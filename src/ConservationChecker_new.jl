"""
    ConservationChecker

This module contains functions that check global conservation of energy and water (and momentum - TODO).
"""
# module ConservationChecker

using ClimaCore: ClimaCore, Geometry, Meshes, Domains, Topologies, Spaces, Fields, InputOutput
using ClimaCore.Utilities: half
using ClimaComms
using NCDatasets
using ClimaCoreTempestRemap
using Dates
using JLD2
using UnPack
using Plots
using ClimaAtmos: RRTMGPI
using ClimaLSM
using ClimaCoupler.Utilities: CoupledSimulation, swap_space!
import ClimaCoupler.Interfacer: SurfaceStub, ComponentModelSimulation, name

#export AbstractCheck, EnergyConservationCheck, WaterConservationCheck, check_conservation!, plot_global_conservation

abstract type AbstractCheck end

"""
    EnergyConservationCheck{A} <: AbstractCheck

Struct of type `AbstractCheck` containing global energy conservation logs.
"""
mutable struct EnergyConservationCheck <: AbstractCheck
    x::NamedTuple
    function EnergyConservationCheck(x)
        all_sims = (;)
        for sim in x
            all_sims = merge(all_sims, [Symbol(name(sim)) => []])
        end
        all_sims = (all_sims..., toa_net_source = [], total = [])
        return new(all_sims)
    end
end


"""
    WaterConservationCheck{A} <: AbstractCheck

Struct of type `AbstractCheck` containing global water mass conservation logs.
"""
mutable struct WaterConservationCheck <: AbstractCheck
    x::NamedTuple
    function WaterConservationCheck(x)
        all_sims = (;)
        for sim in x
            all_sims = merge(all_sims, [Symbol(name(sim)) => []])
        end
        all_sims = (all_sims..., total = [])
        return new(all_sims)
    end
end


"""
    check_conservation!(coupler_sim::CoupledSimulation)

itertes over all specified conservation checks.
"""
check_conservation!(coupler_sim::CoupledSimulation) =
    map(x -> check_conservation!(x, coupler_sim), coupler_sim.conservation_checks)

"""
        check_conservation!(
        cc::EnergyConservationCheck,
        coupler_sim,
        )

computes the total energy, ∫ ρe dV, of the various components
of the coupled simulations, and updates `cc` with the values.

TODO: move `get_slab_energy` and `get_land_energy` to their respective sims upon optimization refactor.
"""
function check_conservation!(
    cc::EnergyConservationCheck,
    coupler_sim::CoupledSimulation,
)

    ccx = cc.x
    @unpack model_sims = coupler_sim

    boundary_space = coupler_sim.boundary_space # thin shell approx (boundary_space[z=0] = boundary_space[z_top])

    FT = eltype(coupler_sim.fields[1])

    total = 0

    # save surfaces
    for sim in model_sims
        sim_name = Symbol(name(sim))
        if sim isa Interfacer.AtmosModelSimulation
            # save radiation source
            parent(coupler_sim.fields.F_radiative_TOA) .= parent(get_field(sim, Val(:F_radiative_TOA)))
            radiation_sources_accum = sum(coupler_sim.fields.F_radiative_TOA) .* coupler_sim.Δt_cpl # ∫ J / m^2 dA
            push!(ccx.toa_net_source, radiation_sources_accum)

            # save atmos
            previous = getproperty(ccx, sim_name)
            current = sum(get_field(sim, Val(:energy))) # # ∫ J / m^3 dV

            push!(previous, current)
            total += current  + radiation_sources_accum

        elseif sim isa Interfacer.SurfaceModelSimulation || sim isa Interfacer.SurfaceStub
            # save surfaces
            area_fraction = Interfacer.get_field(sim, Val(:area_fraction))
            if isnothing(get_field(sim, Val(:energy)))
                previous = getproperty(ccx, sim_name)
                current = FT(0)
            else
                previous = getproperty(ccx, sim_name)
                current =  sum(get_field(sim, Val(:energy)) .* area_fraction) # # ∫ J / m^3 dV
            end
            total += current
        end
        push!(ccx.total, total)

    end

    return total
    # @assert abs((tot[end] - tot[1]) / tot[end]) < 1e-4
end

"""
    check_conservation!(
    cc::WaterConservationCheck,
    coupler_sim,
    get_slab_energy,
    get_land_energy,
    )

computes the total water, ∫ ρq_tot dV, of the various components
of the coupled simulations, and updates `cc` with the values.

Note: in the future this should not use `push!`.
"""
function check_conservation!(
    cc::WaterConservationCheck,
    coupler_sim::CoupledSimulation,
)

    ccx = cc.x
    @unpack model_sims = coupler_sim

    boundary_space = coupler_sim.boundary_space # thin shell approx (boundary_space[z=0] = boundary_space[z_top])

    FT = eltype(coupler_sim.fields[1])

    total = 0

    # net precipitation (for surfaces that don't collect water)
    PE_net = coupler_sim.fields.P_net .+= swap_space!(zeros(boundary_space), surface_water_gain_from_rates(coupler_sim))

    # save surfaces
    for sim in model_sims
        sim_name = Symbol(name(sim))
        if sim isa Interfacer.AtmosModelSimulation

            # save atmos
            previous = getproperty(ccx, sim_name)
            current = sum(get_field(sim, Val(:water))) # kg (∫kg of water / m^3 dV)
            push!(previous, current)

        elseif sim isa Interfacer.SurfaceModelSimulation || sim isa Interfacer.SurfaceStub
            # save surfaces
            area_fraction = Interfacer.get_field(sim, Val(:area_fraction))
            if isnothing(get_field(sim, Val(:water)))
                previous = getproperty(ccx, sim_name)
                current = sum(PE_net .* area_fraction) # kg (∫kg of water / m^3 dV)
                push!(previous, current)
            else
                previous = getproperty(ccx, sim_name)
                current =  sum(get_field(sim, Val(:water)) .* area_fraction) # kg (∫kg of water / m^3 dV)
                push!(previous, current)
            end
        end
        total += current
        push!(ccx.total, total)

    end

    return total
    # @assert abs((tot[end] - tot[1]) / tot[end]) < 1e-2
end

"""
    surface_water_gain_from_rates(cs)

Determines the total water content gain/loss of a surface from the begining of the simulation based on evaporation and precipitation rates.
"""
function surface_water_gain_from_rates(cs::CoupledSimulation)
    evaporation = cs.fields.F_turb_moisture # kg / m^2 / s / layer depth
    precipitation_l = cs.fields.P_liq
    precipitation_s = cs.fields.P_snow
    @. - (evaporation + precipitation_l + precipitation_s) * cs.Δt_cpl # kg / m^2 / layer depth
end

# setup the GKS socket application environment as nul for better performance and to avoid GKS connection errors while plotting
ENV["GKSwstype"] = "nul"

"""
    plot_global_conservation(
        cc::EnergyConservationCheck,
        coupler_sim::CoupledSimulation;
        figname1 = "total_energy.png",
        figname2 = "total_energy_log.png",
    )

Creates two plots of the globally integrated quantity (energy, ``\\rho e``):
1. global quantity of each model component as a function of time,
relative to the initial value;
2. fractional change in the sum of all components over time on a log scale.
"""
function plot_global_conservation(
    cc::EnergyConservationCheck,
    coupler_sim::CoupledSimulation;
    figname1 = "total_energy.png",
    figname2 = "total_energy_log.png",
)

    times = collect(1:length(cc.ρe_tot_atmos)) * coupler_sim.Δt_cpl
    diff_ρe_tot_atmos = (cc.ρe_tot_atmos .- cc.ρe_tot_atmos[1])
    diff_ρe_tot_slab = (cc.ρe_tot_land .- cc.ρe_tot_land[1])
    diff_ρe_tot_slab_seaice = (cc.ρe_tot_seaice .- cc.ρe_tot_seaice[1])
    diff_toa_net_source = (cc.toa_net_source .- cc.toa_net_source[1])
    diff_ρe_tot_slab_ocean = (cc.ρe_tot_ocean .- cc.ρe_tot_ocean[1])

    times_days = times ./ (24 * 60 * 60)
    Plots.plot(times_days, diff_ρe_tot_atmos[1:length(times_days)], label = "atmos")
    Plots.plot!(times_days, diff_ρe_tot_slab[1:length(times_days)], label = "land")
    Plots.plot!(times_days, diff_ρe_tot_slab_seaice[1:length(times_days)], label = "seaice")
    Plots.plot!(times_days, diff_toa_net_source[1:length(times_days)], label = "toa")
    Plots.plot!(times_days, diff_ρe_tot_slab_ocean[1:length(times_days)], label = "ocean")

    tot = @. cc.ρe_tot_atmos + cc.ρe_tot_ocean + cc.ρe_tot_land + cc.ρe_tot_seaice + cc.toa_net_source

    Plots.plot!(
        times_days,
        tot .- tot[1],
        label = "tot",
        xlabel = "time [days]",
        ylabel = "energy(t) - energy(t=0) [J]",
    )
    Plots.savefig(figname1)
    Plots.plot(
        times_days,
        log.(abs.(tot .- tot[1]) / tot[1]),
        label = "tot",
        xlabel = "time [days]",
        ylabel = "log( | e(t) - e(t=0)| / e(t=0))",
    )
    Plots.savefig(figname2)
end

"""
    plot_global_conservation(
        cc::WaterConservationCheck,
        coupler_sim::CoupledSimulation;
        figname1 = "total_energy.png",
        figname2 = "total_energy_log.png",
    )

Creates two plots of the globally integrated quantity (water, ``\\rho q_{tot}``):
1. global quantity of each model component as a function of time,
relative to the initial value;
2. fractional change in the sum of all components over time on a log scale.
"""
function plot_global_conservation(
    cc::WaterConservationCheck,
    coupler_sim::CoupledSimulation{FT};
    figname1 = "total_water.png",
    figname2 = "total_water_log.png",
) where {FT}
    times = collect(1:length(cc.ρq_tot_atmos)) * coupler_sim.Δt_cpl
    diff_ρe_tot_atmos = (cc.ρq_tot_atmos .- cc.ρq_tot_atmos[1])
    diff_ρe_tot_slab = (cc.ρq_tot_land .- cc.ρq_tot_land[1])
    diff_ρe_tot_slab_seaice = (cc.ρq_tot_seaice .- cc.ρq_tot_seaice[1])
    diff_ρe_tot_slab_ocean = (cc.ρq_tot_ocean .- cc.ρq_tot_ocean[1])

    times_days = times ./ (24 * 60 * 60)
    Plots.plot(times_days, diff_ρe_tot_atmos[1:length(times_days)], label = "atmos")
    Plots.plot!(times_days, diff_ρe_tot_slab[1:length(times_days)], label = "land")
    Plots.plot!(times_days, diff_ρe_tot_slab_seaice[1:length(times_days)], label = "seaice")
    Plots.plot!(times_days, diff_ρe_tot_slab_ocean[1:length(times_days)], label = "ocean")

    tot = @. cc.ρq_tot_atmos + cc.ρq_tot_land + cc.ρq_tot_seaice + cc.ρq_tot_ocean

    Plots.plot!(times_days, tot .- tot[1], label = "tot", xlabel = "time [days]", ylabel = "water(t) - water(t=0) [kg]")
    Plots.savefig(figname1)
    Plots.plot(
        times_days,
        log.(abs.(tot .- tot[1]) / tot[1]),
        label = "tot",
        xlabel = "time [days]",
        ylabel = "log( | w(t) - w(t=0)| / w(t=0))",
    )
    Plots.savefig(figname2)
end

# end # module
