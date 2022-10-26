import ArgParse
function parse_commandline()
    s = ArgParse.ArgParseSettings()
    ArgParse.@add_arg_table s begin
        # ClimaCoupler flags
        "--run_name"
        help = "Name of this run."
        arg_type = String
        default = "run"
        "--dt_cpl"
        help = " Coupling time step in seconds"
        arg_type = Int
        default = 400
        "--anim"
        help = "Boolean flag indicating whether to make animations"
        arg_type = Bool
        default = false
        "--energy_check"
        help = "Boolean flag indicating whether to check energy conservation"
        arg_type = Bool
        default = false
        "--mode_name"
        help = "Mode of coupled simulation. [`amip`, `slabplanet`]"
        arg_type = String
        default = "amip"
        "--mono_surface"
        help = "Boolean flag indicating whether (1st order) monotone and conservative remapping is applied."
        arg_type = Bool
        default = false
        # ClimaAtmos flags
        "--FLOAT_TYPE"
        help = "Float type"
        arg_type = String
        default = "Float32"
        "--t_end"
        help = "Simulation end time. Examples: [`1200days`, `40secs`]"
        arg_type = String
        default = "10days"
        "--dt"
        help = "Simulation time step. Examples: [`10secs`, `1hours`]"
        arg_type = String
        default = "600secs"
        "--dt_save_to_sol"
        help = "Time between saving solution. Examples: [`10days`, `1hours`, `Inf` (do not save)]"
        arg_type = String
        default = "1days"
        "--dt_save_to_disk"
        help = "Time between saving to disk. Examples: [`10secs`, `1hours`, `Inf` (do not save)]"
        arg_type = String
        default = "Inf"
        "--dt_save_restart"
        help = "Time between saving restart files to disk. Examples: [`10secs`, `1hours`, `Inf` (do not save)]"
        arg_type = String
        default = "Inf"
        "--dt_rad"
        help = "Time between calling radiation callback for sphere configurations"
        arg_type = String
        default = "6hours"
        "--config" # TODO: add box
        help = "Spatial configuration [`sphere` (default), `column`]"
        arg_type = String
        default = "sphere"
        "--moist"
        help = "Moisture model [`dry` (default), `equil`, `non_equil`]"
        arg_type = String
        default = "dry"
        "--precip_model"
        help = "Precipitation model [`nothing` (default), `0M`]"
        arg_type = String
        "--microphy"
        help = "Microphysics model [`nothing` (default), `0M`]"
        arg_type = String
        "--forcing"
        help = "Forcing [`nothing` (default), `held_suarez`]"
        arg_type = String
        "--subsidence"
        help = "Subsidence [`nothing` (default), `Bomex`, `LifeCycleTan2018`, `Rico`, `DYCOMS`]"
        arg_type = String
        "--ls_adv"
        help = "Large-scale advection [`nothing` (default), `Bomex`, `LifeCycleTan2018`, `Rico`, `ARM_SGP`, `GATE_III`]"
        arg_type = String
        "--edmf_coriolis"
        help = "EDMF coriolis [`nothing` (default), `Bomex`,`LifeCycleTan2018`,`Rico`,`ARM_SGP`,`DYCOMS_RF01`,`DYCOMS_RF02`,`GABLS`]"
        arg_type = String
        "--vert_diff"
        help = "Vertical diffusion [`false` (default), `true`]"
        arg_type = Bool
        default = false
        "--surface_scheme"
        help = "Surface flux scheme [`nothing` (default), `bulk`, `monin_obukhov`]"
        arg_type = String
        default = "bulk"
        "--C_E"
        help = "Bulk transfer coefficient"
        arg_type = Float64
        default = Float64(0.0044)
        "--coupled"
        help = "Coupled simulation [`false` (default), `true`]"
        arg_type = Bool
        default = false
        "--turbconv"
        help = "Turbulence convection scheme [`nothing` (default), `edmf`]"
        arg_type = String
        "--turbconv_case"
        help = "The case run by Turbulence convection scheme [`Bomex` (default), `Bomex`, `DYCOMS_RF01`, `TRMM_LBA`, `GABLS`]"
        arg_type = String
        "--anelastic_dycore"
        help = "false enables defualt remaining tendency which produces a compressible model, the true option allow the EDMF to use an anelastic dycore (temporary)"
        arg_type = Bool
        default = false
        "--hyperdiff"
        help = "Hyperdiffusion [`true` (default), `false`]"
        arg_type = Bool
        default = true
        "--idealized_insolation"
        help = "Use idealized insolation in radiation model [`false`, `true` (default)]"
        arg_type = Bool
        default = true
        "--idealized_h2o"
        help = "Use idealized H2O in radiation model [`false` (default), `true`]"
        arg_type = Bool
        default = false
        "--idealized_clouds"
        help = "Use idealized clouds in radiation model [`false` (default), `true`]"
        arg_type = Bool
        default = false
        "--rad"
        help = "Radiation model [`nothing` (default), `gray`, `clearsky`, `allsky`, `allskywithclear`]"
        arg_type = String
        "--energy_name"
        help = "Energy variable name [`rhoe` (default), `rhoe_int` , `rhotheta`]"
        arg_type = String
        default = "rhoe"
        "--perturb_initstate"
        help = "Add a perturbation to the initial condition [`false`, `true` (default)]"
        arg_type = Bool
        default = true
        "--energy_upwinding"
        help = "Energy upwinding mode [`none` (default), `first_order` , `third_order`, `boris_book`, `zalesak`]"
        arg_type = Symbol
        default = :none
        "--tracer_upwinding"
        help = "Tracer upwinding mode [`none` (default), `first_order` , `third_order`, `boris_book`, `zalesak`]"
        arg_type = Symbol
        default = :none # TODO: change to :zalesak
        "--ode_algo"
        help = "ODE algorithm [`ARS343` (default), `IMKG343a`, `ODE.Euler`, `ODE.IMEXEuler`, `ODE.Rosenbrock23`, etc.]"
        arg_type = String
        default = "ARS343"
        "--max_newton_iters"
        help = "Maximum number of Newton's method iterations (only for ODE algorithms that use Newton's method)"
        arg_type = Int
        default = 1
        "--use_krylov_method"
        help = "Whether to use a Krylov method to solve the linear system in Newton's method (only for ODE algorithms from ClimaTimeSteppers.jl)"
        arg_type = Bool
        default = false
        "--krylov_forcing"
        help = "Relative tolerance for the Krylov method (only used if `use_krylov_method` is `true`)"
        arg_type = Float64
        default = Float64(0.1)
        "--jvp_step_adjustment"
        help = "Amount by which the step size of the forward difference approximation of the Jacobian-vector product in the Krylov method should be scaled (only used if `use_krylov_method` is `true`)"
        arg_type = Float64
        default = Float64(1)
        "--split_ode"
        help = "Use split of ODE problem. Examples: [`true` (implicit, default), `false` (explicit)]"
        arg_type = Bool
        default = true
        "--regression_test"
        help = "(Bool) perform regression test"
        arg_type = Bool
        default = false
        "--enable_threading"
        help = "Enable multi-threading. Note: Julia must be launched with (e.g.,) `--threads=8`"
        arg_type = Bool
        default = true
        "--output_dir"
        help = "Output directory"
        arg_type = String
        "--job_id"
        help = "Uniquely identifying string for a particular job"
        arg_type = String
        "--trunc_stack_traces"
        help = "Set to `true` to truncate printing of ClimaCore `Field`s"
        arg_type = Bool
        default = true
        "--fps"
        help = "Frames per second for animations"
        arg_type = Int
        default = 5
        "--post_process"
        help = "Post process [`true` (default), `false`]"
        arg_type = Bool
        default = true
        "--h_elem"
        help = "number of elements per edge on a cubed sphere"
        arg_type = Int
        default = 6
        "--z_elem"
        help = "number of vertical elements"
        arg_type = Int
        default = 10
        "--nh_poly"
        help = "Horizontal polynomial degree. Note: The number of quadrature points in 1D within each horizontal element is then Nq = <--nh_poly> + 1"
        arg_type = Int
        default = 3
        "--z_max"
        help = "Model top height. Default: 30km"
        arg_type = Float64
        default = Float64(30e3)
        "--z_stretch"
        help = "Stretch grid in z-direction. [`true` (default), `false`]"
        arg_type = Bool
        default = true
        "--dz_bottom"
        help = "Model bottom grid depth. Default: 500m"
        arg_type = Float64
        default = Float64(500)
        "--dz_top"
        help = "Model top grid depth. Default: 5000m"
        arg_type = Float64
        default = Float64(5000)
        "--kappa_4"
        help = "Hyperdiffusion parameter"
        arg_type = Float64
        default = Float64(2e17)
        "--rayleigh_sponge"
        help = "Rayleigh sponge [`true`, `false` (default)]"
        arg_type = Bool
        default = false
        "--viscous_sponge"
        help = "Viscous sponge [`true`, `false` (default)]"
        arg_type = Bool
        default = false
        "--zd_rayleigh"
        help = "Rayleigh sponge height"
        arg_type = Float64
        default = Float64(15e3)
        "--alpha_rayleigh_uh"
        help = "Rayleigh sponge coefficient for horizontal velocity"
        arg_type = Float64
        default = Float64(1e-4)
        "--alpha_rayleigh_w"
        help = "Rayleigh sponge coefficient for vertical velocity"
        arg_type = Float64
        default = Float64(1)
        "--zd_viscous"
        help = "Viscous sponge height"
        arg_type = Float64
        default = Float64(15e3)
        "--kappa_2_sponge"
        help = "Viscous sponge coefficient"
        arg_type = Float64
        default = Float64(1e6)
        "--apply_moisture_filter"
        help = "Apply filter to moisture"
        arg_type = Bool
        default = false
        "--disable_qt_hyperdiffusion"
        help = "Disable the hyperdiffusion of specific humidity [`true`, `false` (default)] (TODO: reconcile this with ρe_tot or remove if instability fixed with limiters)"
        arg_type = Bool
        default = false
        "--start_date"
        help = "Start date of the simulation"
        arg_type = String
        default = "19790321"
        "--topography"
        help = "Define the surface elevation profile [`NoWarp`,`Earth`,`DCMIP200`]"
        arg_type = String
        default = "NoWarp"
        "--apply_limiter"
        help = "Apply a horizontal limiter to every tracer [`true` (default), `false`]"
        arg_type = Bool
        default = true
        "--debugging_tc"
        help = "Save most of the tc aux state to HDF5 file [`false` (default), `true`]"
        arg_type = Bool
        default = false
        "--non_orographic_gravity_wave"
        help = "Apply parameterization for convective gravity wave forcing on horizontal mean flow"
        arg_type = Bool
        default = false
    end
    parsed_args = ArgParse.parse_args(ARGS, s)
    return (s, parsed_args)
end

function cli_defaults(s::ArgParse.ArgParseSettings)
    defaults = Dict()
    # TODO: Don't use ArgParse internals
    for arg in s.args_table.fields
        defaults[arg.dest_name] = arg.default
    end
    return defaults
end

"""
    job_id_from_parsed_args(
        s::ArgParseSettings,
        parsed_args = ArgParse.parse_args(ARGS, s)
    )
Returns a unique name (`String`) given
 - `s::ArgParse.ArgParseSettings` The arg parse settings
 - `parsed_args` The parse arguments
The `ArgParseSettings` are used for truncating
this string based on the default values.
"""
job_id_from_parsed_args(s, parsed_args = ArgParse.parse_args(ARGS, s)) =
    job_id_from_parsed_args(cli_defaults(s), parsed_args)

function job_id_from_parsed_args(defaults::Dict, parsed_args)
    _parsed_args = deepcopy(parsed_args)
    s = ""
    warn = false
    for k in keys(_parsed_args)
        # Skip defaults to alleviate verbose names
        defaults[k] == _parsed_args[k] && continue

        if _parsed_args[k] isa String
            # We don't need keys if the value is a string
            # (alleviate verbose names)
            s *= _parsed_args[k]
        elseif _parsed_args[k] isa Int
            s *= k * "_" * string(_parsed_args[k])
        elseif _parsed_args[k] isa AbstractFloat
            warn = true
        else
            s *= k * "_" * string(_parsed_args[k])
        end
        s *= "_"
    end
    s = replace(s, "/" => "_")
    s = strip(s, '_')
    warn && @warn "Truncated job ID:$s may not be unique due to use of Real"
    return s
end


"""
    print_repl_script(str::String)
Generate a block of code to run a particular
buildkite job given the `command:` string.
Example:
"""
function print_repl_script(str)
    ib = """"""
    ib *= """\n"""
    ib *= """using Revise; include("examples/hybrid/cli_options.jl");\n"""
    ib *= """\n"""
    ib *= """(s, parsed_args) = parse_commandline();\n"""
    parsed_args = parsed_args_from_command_line_flags(str)
    for (flag, val) in parsed_args
        if val isa AbstractString
            ib *= "parsed_args[\"$flag\"] = \"$val\";\n"
        else
            ib *= "parsed_args[\"$flag\"] = $val;\n"
        end
    end
    ib *= """\n"""
    ib *= """include("examples/hybrid/driver.jl")\n"""
    println(ib)
end

function parsed_args_from_command_line_flags(str, parsed_args = Dict())
    s = str
    s = last(split(s, ".jl"))
    s = strip(s)
    parsed_args_list = split(s, " ")
    @assert iseven(length(parsed_args_list))
    parsed_arg_pairs = map(1:2:(length(parsed_args_list) - 1)) do i
        Pair(parsed_args_list[i], parsed_args_list[i + 1])
    end
    function parse_arg(val)
        for T in (Bool, Int, Float32, Float64)
            try
                return parse(T, val)
            catch
            end
        end
        return val # string
    end
    for (flag, val) in parsed_arg_pairs
        parsed_args[replace(flag, "--" => "")] = parse_arg(val)
    end
    return parsed_args
end

function time_to_seconds(s::String)
    factor = Dict("secs" => 1, "mins" => 60, "hours" => 60 * 60, "days" => 60 * 60 * 24)
    s == "Inf" && return Inf
    if count(occursin.(keys(factor), Ref(s))) != 1
        error("Bad format for flag $s. Examples: [`10secs`, `20mins`, `30hours`, `40days`]")
    end
    for match in keys(factor)
        occursin(match, s) || continue
        return parse(Float64, first(split(s, match))) * factor[match]
    end
    error("Uncaught case in computing time from given string.")
end
