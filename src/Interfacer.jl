"""
    Interfacer

This modules contains abstract types, interface templates and model stubs for coupling component models.
"""
module Interfacer

using ClimaCore: Fields
export ComponentModelSimulation,
    AtmosModelSimulation, SurfaceModelSimulation, SurfaceStub, name, get_field, update_field!

"""
    ComponentModelSimulation

An abstract type encompassing all component model (and model stub) simulations.
"""
abstract type ComponentModelSimulation end

"""
    AtmosModelSimulation

An abstract type for an atmospheric model simulation.
"""
abstract type AtmosModelSimulation <: ComponentModelSimulation end

"""
    SurfaceModelSimulation

An abstract type for surface model simulations.
"""
abstract type SurfaceModelSimulation <: ComponentModelSimulation end

"""
    SurfaceStub

On object containing simulation-like info, used as a stub or for prescribed data.
"""
struct SurfaceStub{I} <: SurfaceModelSimulation
    cache::I
end

"""
    get_field(::SurfaceStub, ::Val)

A getter function, that should not allocate. If undefined, it returns a descriptive error.
"""
get_field(sim::SurfaceStub, ::Val{:area_fraction}) = sim.cache.area_fraction
get_field(sim::SurfaceStub, ::Val{:surface_temperature}) = sim.cache.T_sfc
get_field(sim::SurfaceStub, ::Val{:albedo}) = sim.cache.α
get_field(sim::SurfaceStub, ::Val{:roughness_momentum}) = sim.cache.z0m
get_field(sim::SurfaceStub, ::Val{:roughness_buoyancy}) = sim.cache.z0b
get_field(sim::SurfaceStub, ::Val{:beta}) = sim.cache.beta
function get_field(sim::ComponentModelSimulation, val::Val)
    error("undefined field $val for " * name(sim))
end

"""
    get_field(::ComponentModelSimulation, ::Val, colidx::Fields.ColumnIndex)

Extension of `get_field(::ComponentModelSimulation, ::Val)`, indexing into the specified colum index.
"""
function get_field(sim::ComponentModelSimulation, val::Val, colidx::Fields.ColumnIndex)
    if get_field(sim, val) isa AbstractFloat
        get_field(sim, val)
    else
        get_field(sim, val)[colidx]
    end
end

"""
    update_field!(::SurfaceStub, ::Val)

Updates the specified value in the cache of `SurfaceStub`.
"""
function update_field!(sim::SurfaceStub, ::Val{:area_fraction}, field::Fields.Field)
    sim.cache.area_fraction .= field
end
function update_field!(sim::SurfaceStub, ::Val{:surface_temperature}, field::Fields.Field)
    sim.cache.T_sfc .= field
end

"""
    name(::ComponentModelSimulation)

Returns simulation name, if defined, or `Unnamed` if not.
"""
name(::ComponentModelSimulation) = "Unnamed"
name(::SurfaceStub) = "SurfaceStub"

end # module
