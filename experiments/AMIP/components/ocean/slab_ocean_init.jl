using ClimaCore

import ClimaTimeSteppers as CTS
import ClimaCoupler.Interfacer: OceanModelSimulation, get_field, update_field!, name
import ClimaCoupler.FieldExchanger: step!, reinit!
import ClimaCoupler.FluxCalculator: update_turbulent_fluxes_point!

include("../slab_utils.jl")

"""
    SlabOceanSimulation{P, Y, D, I}

Equation:

    (h * ρ * c) dTdt = -(F_turb_energy + F_radiative)

"""
struct SlabOceanSimulation{P, Y, D, I} <: OceanModelSimulation
    params::P
    Y_init::Y
    domain::D
    integrator::I
end
name(::SlabOceanSimulation) = "SlabOceanSimulation"

# ocean parameters
struct OceanSlabParameters{FT <: AbstractFloat}
    h::FT
    ρ::FT
    c::FT
    T_init::FT
    z0m::FT
    z0b::FT
    α::FT
    evolving_switch::FT
end
name(::SlabOceanSimulation) = "SlabOceanSimulation"

"""
    temp_anomaly(coord)

Calculates a an anomaly to be added to the initial condition for temperature.
This default case includes only an anomaly at the tropics.
"""
function temp_anomaly(coord)
    # include tropics anomaly
    anom = FT(29 * exp(-coord.lat^2 / (2 * 26^2)))
    return anom
end

"""
    slab_ocean_space_init(space, params)

Initialize the slab ocean prognostic variable (temperature), including an
anomaly in the tropics by default.
"""
function slab_ocean_space_init(space, params)
    FT = ClimaCore.Spaces.undertype(space)
    coords = ClimaCore.Fields.coordinate_field(space)

    # initial condition
    T_sfc = ClimaCore.Fields.zeros(space) .+ params.T_init # FT(271) close to the average of T_1 in atmos
    @. T_sfc += temp_anomaly(coords)

    # prognostic variable
    Y = ClimaCore.Fields.FieldVector(T_sfc = T_sfc)

    return Y, space
end

# ode
function slab_ocean_rhs!(dY, Y, cache, t)
    p, F_turb_energy, F_radiative, area_fraction = cache
    FT = eltype(Y.T_sfc)
    rhs = @. -(F_turb_energy + F_radiative) / (p.h * p.ρ * p.c)
    @. dY.T_sfc = rhs * Regridder.binary_mask(area_fraction) * p.evolving_switch
    @. cache.q_sfc = TD.q_vap_saturation_generic.(cache.thermo_params, Y.T_sfc, cache.ρ_sfc, TD.Liquid())
end

"""
    ocean_init(::Type{FT}; tspan, dt, saveat, space, area_fraction, stepper = CTS.RK4()) where {FT}

Initializes the `DiffEq` problem, and creates a Simulation-type object containing the necessary information for `step!` in the coupling loop.
"""
function ocean_init(
    ::Type{FT};
    tspan,
    dt,
    saveat,
    space,
    area_fraction,
    thermo_params,
    stepper = CTS.RK4(),
    evolving = true,
) where {FT}

    evolving_switch = evolving ? FT(1) : FT(0)
    params =
        OceanSlabParameters(FT(20), FT(1500.0), FT(800.0), FT(271.0), FT(5e-5), FT(5e-5), FT(0.38), evolving_switch)

    Y, space = slab_ocean_space_init(space, params)
    cache = (
        params = params,
        F_turb_energy = ClimaCore.Fields.zeros(space),
        F_radiative = ClimaCore.Fields.zeros(space),
        q_sfc = ClimaCore.Fields.zeros(space),
        ρ_sfc = ClimaCore.Fields.zeros(space),
        area_fraction = area_fraction,
        thermo_params = thermo_params,
        # add dss_buffer to cache to avoid runtime dss allocation
        dss_buffer = ClimaCore.Spaces.create_dss_buffer(ClimaCore.Fields.zeros(space)),
    )

    ode_algo = CTS.ExplicitAlgorithm(stepper)
    ode_function = CTS.ClimaODEFunction(T_exp! = slab_ocean_rhs!, dss! = weighted_dss_slab!)

    problem = ODEProblem(ode_function, Y, Float64.(tspan), cache)
    integrator = init(problem, ode_algo, dt = Float64(dt), saveat = Float64(saveat), adaptive = false)

    sim = SlabOceanSimulation(params, Y, space, integrator)

    # DSS state to ensure we have continuous fields
    dss_state!(sim)
    return sim
end

# file specific
"""
    clean_sst(SST::FT, _info)
Ensures that the space of the SST struct matches that of the land_fraction, and converts the units to Kelvin (N.B.: this is dataset specific)
"""
clean_sst(SST, _info) = (swap_space!(zeros(axes(_info.land_fraction)), SST) .+ float_type_bcf(_info)(273.15))

# extensions required by Interfacer
get_field(sim::SlabOceanSimulation, ::Val{:surface_temperature}) = sim.integrator.u.T_sfc
get_field(sim::SlabOceanSimulation, ::Val{:surface_humidity}) = sim.integrator.p.q_sfc
get_field(sim::SlabOceanSimulation, ::Val{:roughness_momentum}) = sim.integrator.p.params.z0m
get_field(sim::SlabOceanSimulation, ::Val{:roughness_buoyancy}) = sim.integrator.p.params.z0b
get_field(sim::SlabOceanSimulation, ::Val{:beta}) = convert(eltype(sim.integrator.u), 1.0)
get_field(sim::SlabOceanSimulation, ::Val{:albedo}) = sim.integrator.p.params.α
get_field(sim::SlabOceanSimulation, ::Val{:area_fraction}) = sim.integrator.p.area_fraction
get_field(sim::SlabOceanSimulation, ::Val{:air_density}) = sim.integrator.p.ρ_sfc

function update_field!(sim::SlabOceanSimulation, ::Val{:area_fraction}, field::Fields.Field)
    sim.integrator.p.area_fraction .= field
end

function update_field!(sim::SlabOceanSimulation, ::Val{:turbulent_energy_flux}, field)
    parent(sim.integrator.p.F_turb_energy) .= parent(field)
end
function update_field!(sim::SlabOceanSimulation, ::Val{:radiative_energy_flux}, field)
    parent(sim.integrator.p.F_radiative) .= parent(field)
end
function update_field!(sim::SlabOceanSimulation, ::Val{:air_density}, field)
    parent(sim.integrator.p.ρ_sfc) .= parent(field)
end

# extensions required by FieldExchanger
step!(sim::SlabOceanSimulation, t) = step!(sim.integrator, t - sim.integrator.t, true)

reinit!(sim::SlabOceanSimulation) = reinit!(sim.integrator)

# extensions required by FluxCalculator (partitioned fluxes)
function update_turbulent_fluxes_point!(sim::SlabOceanSimulation, fields::NamedTuple, colidx::Fields.ColumnIndex)
    (; F_turb_energy) = fields
    @. sim.integrator.p.F_turb_energy[colidx] = F_turb_energy
end

"""
    get_model_state_vector(sim::SlabOceanSimulation)

Extension of Checkpointer.get_model_state_vector to get the model state.
"""
function get_model_state_vector(sim::SlabOceanSimulation)
    return sim.integrator.u
end

"""
    get_field(sim::SlabOceanSimulation, ::Val{:energy})

Extension of Interfacer.get_field to get the energy of the ocean.
It multiplies the the slab temperature by the heat capacity, density, and depth.
"""
get_field(sim::SlabOceanSimulation, ::Val{:energy}) =
    sim.integrator.p.params.ρ .* sim.integrator.p.params.c .* sim.integrator.u.T_sfc .* sim.integrator.p.params.h

get_field(sim::SlabOceanSimulation, ::Val{:water}) = nothing

"""
    dss_state!(sim::SlabOceanSimulation)

Perform DSS on the state of a component simulation, intended to be used
before the initial step of a run. This method acts on slab ocean model sims.
"""
function dss_state!(sim::SlabOceanSimulation)
    Y = sim.integrator.u
    p = sim.integrator.p
    for key in propertynames(Y)
        field = getproperty(Y, key)
        buffer = get_dss_buffer(axes(field), p)
        Spaces.weighted_dss!(field, buffer)
    end
end
