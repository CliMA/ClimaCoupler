# slab_rhs!
using ClimaCore

struct ThermalSlabParameters# <: CLIMAParameters.AbstractEarthParameterSet{F} 
    h::FT
    ρ::FT
    c::FT
    T_init::FT
end

# domain
function ShellDomain(; radius = 6371e3, Nel = 8, Nq = 2)
    domain = ClimaCore.Domains.SphereDomain(radius)
    mesh = ClimaCore.Meshes.EquiangularCubedSphere(domain, Nel)
    topology = ClimaCore.Topologies.Topology2D(mesh)
    quad = ClimaCore.Spaces.Quadratures.GLL{Nq}()
    space = ClimaCore.Spaces.SpectralElementSpace2D(topology, quad)
end

# init simulation
function slab_space_init(::Type{FT}, space, params) where {FT}

    coords = ClimaCore.Fields.coordinate_field(space)

    # initial condition
    T_sfc = map(coords) do coord
        T_sfc_0 = params.T_init
        anom_ampl = FT(2)
        radlat = coord.lat / FT(180) * pi
        lat_0 = FT(60) / FT(180) * pi
        lon_0 = FT(-90) / FT(180) * pi
        radlon = coord.long / FT(180) * pi
        stdev = FT(5) / FT(180) * pi
        anom = anom_ampl * exp(-((radlat - lat_0)^2 / 2stdev^2 + (radlon - lon_0)^2 / 2stdev^2))
        T_sfc = T_sfc_0 + anom
    end

    # prognostic variable
    Y = ClimaCore.Fields.FieldVector(T_sfc = T_sfc)

    return Y, space
end

# ode
function slab_rhs!(dY, Y, Ya, t)
    """
    Slab ocean:
    ∂_t T_sfc = F_sfc + G
    """
    p, F_sfc = Ya

    @. dY.T_sfc = (F_sfc) / (p.h * p.ρ * p.c)
end

struct SlabSimulation{P, Y, D, I}
    params::P
    Y_init::Y
    domain::D
    integrator::I
end

function slab_init(
    ::Type{FT},
    tspan;
    stepper = Euler(),
    nelements = 6,
    npolynomial = 4,
    dt = 0.02,
    saveat = 1.0e10,
    space = nothing,
) where {FT}

    params = ThermalSlabParameters(FT(0.5), FT(1500.0), FT(800.0), FT(281.0))

    Y, space = slab_space_init(FT, space, params)
    Ya = (params = params, F_sfc = ClimaCore.Fields.zeros(space)) #auxiliary
    problem = OrdinaryDiffEq.ODEProblem(slab_rhs!, Y, tspan, Ya)
    integrator = OrdinaryDiffEq.init(problem, stepper, dt = dt, saveat = saveat)

    SlabSimulation(params, Y, space, integrator)
end

get_slab_energy(slab_sim, T_sfc) = slab_sim.params.ρ .* slab_sim.params.c .* T_sfc .* slab_sim.params.h
