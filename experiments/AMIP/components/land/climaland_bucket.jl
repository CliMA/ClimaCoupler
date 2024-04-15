import Dates
import SciMLBase
import Statistics
import ClimaCore as CC
import ClimaTimeSteppers as CTS
import ClimaParams
import Thermodynamics as TD
import ClimaLand as CL
import ClimaLand.Parameters as LP
import ClimaCoupler: Checkpointer, FluxCalculator, Interfacer

###
### Functions required by ClimaCoupler.jl for a SurfaceModelSimulation
###
"""
    BucketSimulation{M, Y, D, I}

The bucket model simulation object.
"""
struct BucketSimulation{M, Y, D, I, A} <: Interfacer.LandModelSimulation
    model::M
    Y_init::Y
    domain::D
    integrator::I
    area_fraction::A
end
Interfacer.name(::BucketSimulation) = "BucketSimulation"


"""
    bucket_init

Initializes the bucket model variables.
"""
function bucket_init(
    ::Type{FT},
    tspan::Tuple{Float64, Float64},
    config::String,
    albedo_type::String,
    land_temperature_anomaly::String,
    regrid_dirpath::String;
    space,
    dt::Float64,
    saveat::Float64,
    area_fraction,
    stepper = CTS.RK4(),
    date_ref::Dates.DateTime,
    t_start::Float64,
) where {FT}
    if config != "sphere"
        println(
            "Currently only spherical shell domains are supported; single column set-up will be addressed in future PR.",
        )
        @assert config == "sphere"
    end

    α_snow = FT(0.8) # snow albedo
    if albedo_type == "map_static" # Read in albedo from static data file (default type)
        # By default, this uses a file containing bareground albedo without a time component. Snow albedo is specified separately.
        albedo = CL.Bucket.PrescribedBaregroundAlbedo{FT}(α_snow, regrid_dirpath, space)
    elseif albedo_type == "map_temporal" # Read in albedo from data file containing data over time
        # By default, this uses a file containing linearly-interpolated monthly data of total albedo, generated by CESM2's land model (CLM).
        albedo = CL.Bucket.PrescribedSurfaceAlbedo{FT}(regrid_dirpath, date_ref, t_start, space)
    elseif albedo_type == "function" # Use prescribed function of lat/lon for surface albedo
        function α_bareground(coordinate_point)
            (; lat, long) = coordinate_point
            return typeof(lat)(0.38)
        end
        albedo = CL.Bucket.PrescribedBaregroundAlbedo{FT}(α_snow, α_bareground, space)
    else
        error("invalid albedo type $albedo_type")
    end

    d_soil = FT(3.5) # soil depth
    z_0m = FT(1e-3) # roughness length for momentum over smooth bare soil
    z_0b = FT(1e-3) # roughness length for tracers over smooth bare soil
    τc = FT(dt) # This is the timescale on which snow exponentially damps to zero, in the case where all
    # the snow would melt in time `τc`. It prevents us from having to specially time step in cases where
    # all the snow melts in a single timestep.
    σS_c = FT(0.2) # critical snow water equivalent
    W_f = FT(10) # bucket capacity
    κ_soil = FT(0.7) # soil conductivity
    ρc_soil = FT(2e8) # soil volumetric heat capacity

    params = CL.Bucket.BucketModelParameters(FT; albedo, z_0m, z_0b, τc, σS_c, W_f, κ_soil, ρc_soil)

    n_vertical_elements = 7
    # Note that this does not take into account topography of the surface, which is OK for this land model.
    # But it must be taken into account when computing surface fluxes, for Δz.
    domain = make_land_domain(space, (-d_soil, FT(0.0)), n_vertical_elements)
    args = (params, CL.CoupledAtmosphere{FT}(), CL.CoupledRadiativeFluxes{FT}(), domain)
    model = CL.Bucket.BucketModel{FT, typeof.(args)...}(args...)

    # Initial conditions with no moisture
    Y, p, coords = CL.initialize(model)

    # Get temperature anomaly function
    T_functions = Dict("aquaplanet" => temp_anomaly_aquaplanet, "amip" => temp_anomaly_amip)
    haskey(T_functions, land_temperature_anomaly) ||
        error("land temp anomaly function $land_temperature_anomaly not supported")
    temp_anomaly = T_functions[land_temperature_anomaly]

    # Set temperature IC including anomaly, based on atmospheric setup
    T_sfc_0 = FT(271.0)
    @. Y.bucket.T = T_sfc_0 + temp_anomaly(coords.subsurface)

    Y.bucket.W .= 6.5
    Y.bucket.Ws .= 0.0
    Y.bucket.σS .= 0.0

    # Set initial aux variable values
    set_initial_cache! = CL.make_set_initial_cache(model)
    set_initial_cache!(p, Y, tspan[1])

    exp_tendency! = CL.make_exp_tendency(model)
    ode_algo = CTS.ExplicitAlgorithm(stepper)
    bucket_ode_function = CTS.ClimaODEFunction(T_exp! = exp_tendency!, dss! = CL.dss!)
    prob = SciMLBase.ODEProblem(bucket_ode_function, Y, tspan, p)
    integrator = SciMLBase.init(prob, ode_algo; dt = dt, saveat = saveat, adaptive = false)

    sim = BucketSimulation(model, Y, (; domain = domain, soil_depth = d_soil), integrator, area_fraction)

    # DSS state to ensure we have continuous fields
    dss_state!(sim)
    return sim
end

# extensions required by Interfacer
Interfacer.get_field(sim::BucketSimulation, ::Val{:air_density}) = sim.integrator.p.bucket.ρ_sfc
Interfacer.get_field(sim::BucketSimulation, ::Val{:area_fraction}) = sim.area_fraction
Interfacer.get_field(sim::BucketSimulation, ::Val{:beta}) =
    CL.surface_evaporative_scaling(sim.model, sim.integrator.u, sim.integrator.p)
Interfacer.get_field(sim::BucketSimulation, ::Val{:roughness_buoyancy}) = sim.model.parameters.z_0b
Interfacer.get_field(sim::BucketSimulation, ::Val{:roughness_momentum}) = sim.model.parameters.z_0m
Interfacer.get_field(sim::BucketSimulation, ::Val{:surface_direct_albedo}) =
    CL.surface_albedo(sim.model, sim.integrator.u, sim.integrator.p)
Interfacer.get_field(sim::BucketSimulation, ::Val{:surface_diffuse_albedo}) =
    CL.surface_albedo(sim.model, sim.integrator.u, sim.integrator.p)
Interfacer.get_field(sim::BucketSimulation, ::Val{:surface_humidity}) =
    CL.surface_specific_humidity(sim.model, sim.integrator.u, sim.integrator.p, sim.integrator.t)
Interfacer.get_field(sim::BucketSimulation, ::Val{:surface_temperature}) =
    CL.surface_temperature(sim.model, sim.integrator.u, sim.integrator.p, sim.integrator.t)

"""
    Interfacer.get_field(bucket_sim::BucketSimulation, ::Val{:energy})

Extension of Interfacer.get_field that provides the total energy contained in the bucket, including the latent heat due to snow melt.
"""
function Interfacer.get_field(bucket_sim::BucketSimulation, ::Val{:energy})
    # required by ConservationChecker
    e_per_area = zeros(axes(bucket_sim.integrator.u.bucket.W))
    CC.Operators.column_integral_definite!(
        e_per_area,
        bucket_sim.model.parameters.ρc_soil .* bucket_sim.integrator.u.bucket.T,
    )

    e_per_area .+=
        -LP.LH_f0(bucket_sim.model.parameters.earth_param_set) .*
        LP.ρ_cloud_liq(bucket_sim.model.parameters.earth_param_set) .* bucket_sim.integrator.u.bucket.σS

    return e_per_area
end

"""
    Interfacer.get_field(bucket_sim::BucketSimulation, ::Val{:water})

Extension of Interfacer.get_field that provides the total water contained in the bucket, including the liquid water in snow.
"""
function Interfacer.get_field(bucket_sim::BucketSimulation, ::Val{:water})
    ρ_cloud_liq = CL.LP.ρ_cloud_liq(bucket_sim.model.parameters.earth_param_set)
    return
    @. (bucket_sim.integrator.u.bucket.σS + bucket_sim.integrator.u.bucket.W + bucket_sim.integrator.u.bucket.Ws) *
       ρ_cloud_liq  # kg water / m2
end

function Interfacer.update_field!(sim::BucketSimulation, ::Val{:air_density}, field)
    parent(sim.integrator.p.bucket.ρ_sfc) .= parent(field)
end
function Interfacer.update_field!(sim::BucketSimulation, ::Val{:liquid_precipitation}, field)
    ρ_liq = (LP.ρ_cloud_liq(sim.model.parameters.earth_param_set))
    parent(sim.integrator.p.drivers.P_liq) .= parent(field ./ ρ_liq)
end
function Interfacer.update_field!(sim::BucketSimulation, ::Val{:radiative_energy_flux_sfc}, field)
    parent(sim.integrator.p.bucket.R_n) .= parent(field)
end
function Interfacer.update_field!(sim::BucketSimulation, ::Val{:turbulent_energy_flux}, field)
    parent(sim.integrator.p.bucket.turbulent_fluxes.shf) .= parent(field)
end
function Interfacer.update_field!(sim::BucketSimulation, ::Val{:snow_precipitation}, field)
    ρ_ice = (LP.ρ_cloud_ice(sim.model.parameters.earth_param_set))
    parent(sim.integrator.p.drivers.P_snow) .= parent(field ./ ρ_ice)
end
function Interfacer.update_field!(sim::BucketSimulation, ::Val{:turbulent_moisture_flux}, field)
    ρ_liq = (LP.ρ_cloud_liq(sim.model.parameters.earth_param_set))
    parent(sim.integrator.p.bucket.turbulent_fluxes.vapor_flux) .= parent(field ./ ρ_liq) # TODO: account for sublimation
end

# extensions required by FieldExchanger
Interfacer.step!(sim::BucketSimulation, t) = Interfacer.step!(sim.integrator, t - sim.integrator.t, true)
Interfacer.reinit!(sim::BucketSimulation) = Interfacer.reinit!(sim.integrator)

# extensions required by FluxCalculator (partitioned fluxes)
function FluxCalculator.update_turbulent_fluxes_point!(
    sim::BucketSimulation,
    fields::NamedTuple,
    colidx::CC.Fields.ColumnIndex,
)
    (; F_turb_energy, F_turb_moisture) = fields
    turbulent_fluxes = sim.integrator.p.bucket.turbulent_fluxes
    turbulent_fluxes.shf[colidx] .= F_turb_energy
    earth_params = sim.model.parameters.earth_param_set
    turbulent_fluxes.vapor_flux[colidx] .= F_turb_moisture ./ LP.ρ_cloud_liq(earth_params)
    return nothing
end

# extension of FluxCalculator.FluxCalculator.surface_thermo_state, overriding the saturated-surface default
function FluxCalculator.surface_thermo_state(
    sim::BucketSimulation,
    thermo_params::TD.Parameters.ThermodynamicsParameters,
    thermo_state_int,
    colidx::CC.Fields.ColumnIndex,
)

    T_sfc = Interfacer.get_field(sim, Val(:surface_temperature), colidx)
    # Note that the surface air density, ρ_sfc, is computed using the atmospheric state at the first level and making ideal gas
    # and hydrostatic balance assumptions. The land model does not compute the surface air density so this is
    # a reasonable stand-in.
    ρ_sfc = Interfacer.get_field(sim, Val(:air_density), colidx)
    q_sfc = Interfacer.get_field(sim, Val(:surface_humidity), colidx) # already calculated in rhs! (cache)
    @. TD.PhaseEquil_ρTq.(thermo_params, ρ_sfc, T_sfc, q_sfc)
end

"""
    Checkpointer.get_model_prog_state(sim::BucketSimulation)

Extension of Checkpointer.get_model_prog_state to get the model state.
"""
function Checkpointer.get_model_prog_state(sim::BucketSimulation)
    return sim.integrator.u.bucket
end

###
### CL.jl bucket model-specific functions (not explicitly required by ClimaCoupler.jl)
###

# TODO remove this function after ClimaLand v0.8.1 update
function CL.turbulent_fluxes(atmos::CL.CoupledAtmosphere, model::CL.Bucket.BucketModel, Y, p, t)
    # coupler has done its thing behind the scenes already
    model_name = CL.name(model)
    model_cache = getproperty(p, model_name)
    return model_cache.turbulent_fluxes
end


function CL.initialize_drivers(a::CL.CoupledAtmosphere{FT}, coords) where {FT}
    keys = (:P_liq, :P_snow)
    types = ([FT for k in keys]...,)
    domain_names = ([:surface for k in keys]...,)
    model_name = :drivers
    # intialize_vars packages the variables as a Interfacer.named tuple,
    # as part of a Interfacer.named tuple with `model_name` as the key.
    # Here we just want the variable Interfacer.named tuple itself
    vars = CL.initialize_vars(keys, types, domain_names, coords, model_name)
    return vars.drivers
end


"""
    temp_anomaly_aquaplanet(coord)

Introduce a temperature IC anomaly for the aquaplanet case.
The values for this case follow the moist Held-Suarez setup of Thatcher &
Jablonowski (2016, eq. 6), consistent with ClimaAtmos aquaplanet.
"""
temp_anomaly_aquaplanet(coord) = 29 * exp(-coord.lat^2 / (2 * 26^2))

"""
    temp_anomaly_amip(coord)

Introduce a temperature IC anomaly for the AMIP case.
The values used in this case have been tuned to align with observed temperature
and result in stable simulations.
"""
temp_anomaly_amip(coord) = 40 * cosd(coord.lat)^4

"""
    make_land_domain(
        atmos_boundary_space::CC.Spaces.SpectralElementSpace2D,
        zlim::Tuple{FT, FT},
        nelements_vert::Int,) where {FT}

Creates the land model domain from the horizontal space of the atmosphere, and information
about the number of elements and extent of the vertical domain.
"""
function make_land_domain(
    atmos_boundary_space::CC.Spaces.SpectralElementSpace2D,
    zlim::Tuple{FT, FT},
    nelements_vert::Int,
) where {FT}
    @assert zlim[1] < zlim[2]
    depth = zlim[2] - zlim[1]

    mesh = CC.Spaces.topology(atmos_boundary_space).mesh

    radius = mesh.domain.radius
    nelements_horz = mesh.ne
    npolynomial = CC.Spaces.Quadratures.polynomial_degree(CC.Spaces.quadrature_style(atmos_boundary_space))
    nelements = (nelements_horz, nelements_vert)
    vertdomain = CC.Domains.IntervalDomain(
        CC.Geometry.ZPoint(FT(zlim[1])),
        CC.Geometry.ZPoint(FT(zlim[2]));
        boundary_names = (:bottom, :top),
    )

    vertmesh = CC.Meshes.IntervalMesh(vertdomain, CC.Meshes.Uniform(), nelems = nelements[2])
    verttopology = CC.Topologies.IntervalTopology(vertmesh)
    vert_center_space = CC.Spaces.CenterFiniteDifferenceSpace(verttopology)
    subsurface_space = CC.Spaces.ExtrudedFiniteDifferenceSpace(atmos_boundary_space, vert_center_space)
    space = (; surface = atmos_boundary_space, subsurface = subsurface_space)

    return CL.Domains.SphericalShell{FT}(radius, depth, nothing, nelements, npolynomial, space)
end

"""
    get_land_temp_from_state(land_sim, u)
Returns the surface temperature of the earth, computed from the state u.
"""
function get_land_temp_from_state(land_sim, u)
    # required by viz_explorer.jl
    return CL.surface_temperature(land_sim.model, u, land_sim.integrator.p, land_sim.integrator.t)
end

"""
    dss_state!(sim::BucketSimulation)

Perform DSS on the state of a component simulation, intended to be used
before the initial step of a run. This method acts on bucket land simulations.
The `dss!` function of ClimaLand must be called because it uses either the 2D
or 3D dss buffer stored in the cache depending on space of each variable in
`sim.integrator.u`.
"""
function dss_state!(sim::BucketSimulation)
    CL.dss!(sim.integrator.u, sim.integrator.p, sim.integrator.t)
end
