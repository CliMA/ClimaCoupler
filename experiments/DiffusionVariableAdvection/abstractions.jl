#######
# useful concepts for dispatch
#######


abstract type AbstractSimulation end

struct Simulation{𝒜, ℬ, 𝒞, 𝒟, ℰ, ℱ, O, DG,N} <: AbstractSimulation
    model::𝒜
    state::ℬ
    timestepper::𝒞
    initial_conditions::𝒟
    callbacks::ℰ
    simulation_time::ℱ
    odesolver::O
    dgmodel::DG
    name::N
end

function Simulation(;
    model = nothing,
    state = nothing,
    timestepper = nothing,
    initial_conditions = nothing,
    callbacks = nothing,
    simulation_time = nothing,
    odesolver = nothing,
    dgmodel = nothing,
    name = nothing,
)
    # initialize DGModel (rhs)
    dgmodel = DGModel(model) # DGModel --> KernelModel, to be more general? 

    FT = eltype(dgmodel.grid.vgeo)

    # initialize state variables
    if state == nothing
        state = init_ode_state(dgmodel, FT(0); init_on_cpu = true)
    end

    # initialize timestepper
    odesolver = timestepper.method( dgmodel, state; dt = timestepper.timestep, t0 = simulation_time[1] )

    return Simulation(
        model,
        state,
        timestepper,
        initial_conditions,
        callbacks,
        simulation_time,
        odesolver,
        dgmodel,
        name,
    )
end

"""
calculate_dt(grid, wavespeed = nothing, diffusivity = nothing, viscocity = nothing, cfl = 0.1)
"""
function calculate_dt(
    grid;
    wavespeed = nothing,
    diffusivity = nothing,
    viscocity = nothing,
    cfl = 0.001,
    adv_direction = HorizontalDirection(),
    dif_direction = VerticalDirection()
)
    Δx_adv = min_node_distance(grid, adv_direction)
    Δx_dif = min_node_distance(grid, dif_direction)
    Δts = []
    if wavespeed != nothing
        push!(Δts, Δx_adv / wavespeed)
    end
    if diffusivity != nothing
        push!(Δts, Δx_dif^2 / diffusivity)
    end
    if viscocity != nothing
        push!(Δts, Δx_dif^2 / viscocity)
    end
    if Δts == []
        @error("Please provide characteristic speed or diffusivities")
        return nothing
    end
    return cfl * minimum(Δts)
end


