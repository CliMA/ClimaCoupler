using ClimaComms
using Logging
using ClimaAtmos

# redirect_stderr(IOContext(stderr, :stacktrace_types_limited => Ref(false)))
# import ClimaAtmos as CA
# import Random
# Random.seed!(1234)

# if !(@isdefined config)
#     config = CA.AtmosConfig()
# end
# simulation = CA.get_simulation(config)
# (; integrator) = simulation
# sol_res = CA.solve_atmos!(simulation)


# ___
(; atmos, params) = integrator.p
(; p) = integrator

import ClimaCore
import ClimaCore: Topologies, Quadratures, Spaces
import ClimaAtmos.InitialConditions as ICs
using Statistics: mean
import ClimaAtmos.Parameters as CAP
import Thermodynamics as TD
import ClimaComms
using SciMLBase
using PrettyTables
using JLD2
using NCDatasets
using ClimaTimeSteppers
import JSON
using Test
import Tar
import Base.Filesystem: rm
import OrderedCollections
using ClimaCoreTempestRemap
using ClimaCorePlots
using ClimaCoreMakie, CairoMakie
include(joinpath(pkgdir(CA), "post_processing", "ci_plots.jl"))

ref_job_id = config.parsed_args["reference_job_id"]
reference_job_id = isnothing(ref_job_id) ? simulation.job_id : ref_job_id

# if sol_res.ret_code == :simulation_crashed
#     error(
#         "The ClimaAtmos simulation has crashed. See the stack trace for details.",
#     )
# end
# # Simulation did not crash
# (; sol, walltime) = sol_res

# # we gracefully exited, so we won't have reached t_end
# if !isempty(integrator.tstops)
#     @assert last(sol.t) == simulation.t_end
# end
# CA.verify_callbacks(sol.t)

# # Scaling check
# if CA.is_distributed(config.comms_ctx)
#     nprocs = ClimaComms.nprocs(config.comms_ctx)
#     comms_ctx = config.comms_ctx
#     output_dir = simulation.output_dir
#     # replace sol.u on the root processor with the global sol.u
#     if ClimaComms.iamroot(comms_ctx)
#         Y = sol.u[1]
#         center_space = axes(Y.c)
#         horz_space = Spaces.horizontal_space(center_space)
#         horz_topology = Spaces.topology(horz_space)
#         quadrature_style = Spaces.quadrature_style(horz_space)
#         Nq = Quadratures.degrees_of_freedom(quadrature_style)
#         nlocalelems = Topologies.nlocalelems(horz_topology)
#         ncols_per_process = nlocalelems * Nq * Nq
#         scaling_file =
#             joinpath(output_dir, "scaling_data_$(nprocs)_processes.jld2")
#         @info(
#             "Writing scaling data",
#             "walltime (seconds)" = walltime,
#             scaling_file
#         )
#         JLD2.jldsave(scaling_file; nprocs, ncols_per_process, walltime)
#     end
# end

# # Check if selected output has changed from the previous recorded output (bit-wise comparison)
# include(joinpath(@__DIR__, "..", "..", "regression_tests", "mse_tables.jl"))
# if config.parsed_args["regression_test"]
#     # Test results against main branch
#     include(
#         joinpath(
#             @__DIR__,
#             "..",
#             "..",
#             "regression_tests",
#             "regression_tests.jl",
#         ),
#     )
#     @testset "Test regression table entries" begin
#         mse_keys = sort(collect(keys(all_best_mse[simulation.job_id])))
#         pcs = collect(Fields.property_chains(sol.u[end]))
#         for prop_chain in mse_keys
#             @test prop_chain in pcs
#         end
#     end
#     perform_regression_tests(
#         simulation.job_id,
#         sol.u[end],
#         all_best_mse,
#         simulation.output_dir,
#     )
# end

# @info "Callback verification, n_expected_calls: $(CA.n_expected_calls(integrator))"
# @info "Callback verification, n_measured_calls: $(CA.n_measured_calls(integrator))"

# # Conservation checks
# if config.parsed_args["check_conservation"]
#     @info "Checking conservation"
#     FT = Spaces.undertype(axes(sol.u[end].c.ρ))

#     # energy
#     energy_total = sum(sol.u[end].c.ρe_tot)
#     energy_atmos_change = sum(sol.u[end].c.ρe_tot) - sum(sol.u[1].c.ρe_tot)
#     sfc = p.atmos.surface_model
#     if sfc isa CA.PrognosticSurfaceTemperature
#         sfc_cρh = sfc.ρ_ocean * sfc.cp_ocean * sfc.depth_ocean
#         energy_total +=
#             CA.horizontal_integral_at_boundary(sol.u[end].sfc.T .* sfc_cρh)
#         energy_surface_change =
#             CA.horizontal_integral_at_boundary(
#                 sol.u[end].sfc.T .- sol.u[1].sfc.T,
#             ) * sfc_cρh
#     else
#         energy_surface_change = -p.net_energy_flux_sfc[][]
#     end
#     energy_radiation_input = -p.net_energy_flux_toa[][]

#     energy_net =
#         abs(
#             energy_atmos_change + energy_surface_change -
#             energy_radiation_input,
#         ) / energy_total
#     @info "    Net energy change: $energy_net"
#     @test (energy_net / energy_total) ≈ 0 atol = sqrt(eps(FT))

#     if p.atmos.moisture_model isa CA.DryModel
#         # density
#         @test sum(sol.u[1].c.ρ) ≈ sum(sol.u[end].c.ρ) rtol = 50 * eps(FT)
#     else
#         if sfc isa CA.PrognosticSurfaceTemperature
#             # water
#             water_total = sum(sol.u[end].c.ρq_tot)
#             water_atmos_change =
#                 sum(sol.u[end].c.ρq_tot) - sum(sol.u[1].c.ρq_tot)
#             water_surface_change = CA.horizontal_integral_at_boundary(
#                 sol.u[end].sfc.water .- sol.u[1].sfc.water,
#             )

#             water_net =
#                 abs(water_atmos_change + water_surface_change) / water_total
#             @info "    Net water change: $water_net"
#             @test water_net ≈ 0 atol = 100 * sqrt(eps(FT))
#         end
#     end
# end

# # Precipitation characteristic checks
# if config.parsed_args["check_precipitation"]
#     # run some simple tests based on the output
#     FT = Spaces.undertype(axes(sol.u[end].c.ρ))
#     Yₜ = similar(sol.u[end])
#     @. Yₜ = 0

#     Yₜ_ρ = similar(Yₜ.c.ρq_rai)
#     Yₜ_ρqₚ = similar(Yₜ.c.ρq_rai)
#     Yₜ_ρqₜ = similar(Yₜ.c.ρq_rai)


#     ClimaCore.Fields.bycolumn(axes(sol.u[end].c.ρ)) do colidx
#         CA.precipitation_tendency!(
#             Yₜ,
#             sol.u[end],
#             sol.prob.p,
#             sol.t[end],
#             colidx,
#             sol.prob.p.atmos.precip_model,
#         )

#         @. Yₜ_ρqₚ[colidx] = -Yₜ.c.ρq_rai[colidx] - Yₜ.c.ρq_sno[colidx]
#         @. Yₜ_ρqₜ[colidx] = Yₜ.c.ρq_tot[colidx]
#         @. Yₜ_ρ[colidx] = Yₜ.c.ρ[colidx]

#         # no nans
#         @assert !any(isnan, Yₜ.c.ρ[colidx])
#         @assert !any(isnan, Yₜ.c.ρq_tot[colidx])
#         @assert !any(isnan, Yₜ.c.ρe_tot[colidx])
#         @assert !any(isnan, Yₜ.c.ρq_rai[colidx])
#         @assert !any(isnan, Yₜ.c.ρq_sno[colidx])
#         @assert !any(isnan, sol.prob.p.precomputed.ᶜwᵣ[colidx])
#         @assert !any(isnan, sol.prob.p.precomputed.ᶜwₛ[colidx])

#         # treminal velocity is positive
#         @test minimum(sol.prob.p.precomputed.ᶜwᵣ[colidx]) >= FT(0)
#         @test minimum(sol.prob.p.precomputed.ᶜwₛ[colidx]) >= FT(0)

#         # checking for water budget conservation
#         # in the presence of precipitation sinks
#         # (This test only works without surface flux of q_tot)
#         @test all(
#             ClimaCore.isapprox(
#                 Yₜ_ρqₜ[colidx],
#                 Yₜ_ρqₚ[colidx],
#                 rtol = 1e2 * eps(FT),
#             ),
#         )

#         # mass budget consistency
#         @test all(
#             ClimaCore.isapprox(Yₜ_ρ[colidx], Yₜ_ρqₜ[colidx], rtol = eps(FT)),
#         )

#         # cloud fraction diagnostics
#         @assert !any(isnan, sol.prob.p.precomputed.ᶜcloud_fraction[colidx])
#         @test minimum(sol.prob.p.precomputed.ᶜcloud_fraction[colidx]) >= FT(0)
#         @test maximum(sol.prob.p.precomputed.ᶜcloud_fraction[colidx]) <= FT(1)
#     end
# end

# Visualize the solution
if ClimaComms.iamroot(config.comms_ctx)
    include(
        joinpath(pkgdir(CA), "regression_tests", "self_reference_or_path.jl"),
    )
    @info "Plotting"
    path = self_reference_or_path() # __build__ path (not job path)
    if path == :self_reference
        make_plots(Val(Symbol(reference_job_id)), simulation.output_dir)
    else
        main_job_path = joinpath(path, reference_job_id)
        nc_dir = joinpath(main_job_path, "nc_files")
        if ispath(nc_dir)
            @info "nc_dir exists"
        else
            mkpath(nc_dir)
            # Try to extract nc files from tarball:
            @info "Comparing against $(readdir(nc_dir))"
        end
        if isempty(readdir(nc_dir))
            if isfile(joinpath(main_job_path, "nc_files.tar"))
                Tar.extract(joinpath(main_job_path, "nc_files.tar"), nc_dir)
            else
                @warn "No nc_files found"
            end
        else
            @info "Files already extracted"
        end

        paths = if isempty(readdir(nc_dir))
            simulation.output_dir
        else
            [nc_dir, simulation.output_dir]
        end
        make_plots(::Val{Symbol(reference_job_id)}, paths) = make_plots(
            Val(:longrun_aquaplanet_rhoe_equil_55km_nz63_clearsky_tvinsol_0M_slabocean),
            paths,
        )
        make_plots(Val(Symbol(reference_job_id)), paths)
    end
    @info "Plotting done"

    @info "Creating tarballs"
    # These NC files are used by our reproducibility tests,
    # and need to be found later when comparing against the
    # main branch. If "nc_files.tar" is renamed, then please
    # search for "nc_files.tar" globally and rename it in the
    # reproducibility test folder.
    Tar.create(
        f -> endswith(f, ".nc"),
        simulation.output_dir,
        joinpath(simulation.output_dir, "nc_files.tar"),
    )
    Tar.create(
        f -> endswith(f, r"hdf5|h5"),
        simulation.output_dir,
        joinpath(simulation.output_dir, "hdf5_files.tar"),
    )

    foreach(readdir(simulation.output_dir)) do f
        endswith(f, r"nc|hdf5|h5") && rm(joinpath(simulation.output_dir, f))
    end
    @info "Tarballs created"
end
