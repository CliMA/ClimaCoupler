#!/usr/bin/env julia --project
include("../interface/utilities/boilerplate.jl")
include("../interface/numerics/timestepper_abstractions.jl")
include("")

########
# Set up domain
########
domain = SphericalShell(
    radius = parameters.a,
    height = parameters.H,
)
grid = DiscretizedDomain(
    domain;
    elements = (vertical = 10, horizontal = 32),
    polynomial_order = (vertical = 2, horizontal = 2),
    overintegration_order = (vertical = 0, horizontal = 0),
)

########
# Set up inital condition
########
# additional initial condition parameters
T₀(𝒫)   = 0.5 * (𝒫.T_E + 𝒫.T_P)
A(𝒫)    = 1.0 / 𝒫.Γ
B(𝒫)    = (T₀(𝒫) - 𝒫.T_P) / T₀(𝒫) / 𝒫.T_P
C(𝒫)    = 0.5 * (𝒫.k + 2) * (𝒫.T_E - 𝒫.T_P) / 𝒫.T_E / 𝒫.T_P
H(𝒫)    = 𝒫.R_d * T₀(𝒫) / 𝒫.g
d_0(𝒫)  = 𝒫.a / 6

# convenience functions that only depend on height
τ_z_1(𝒫,r)   = exp(𝒫.Γ * (r - 𝒫.a) / T₀(𝒫))
τ_z_2(𝒫,r)   = 1 - 2 * ((r - 𝒫.a) / 𝒫.b / H(𝒫))^2
τ_z_3(𝒫,r)   = exp(-((r - 𝒫.a) / 𝒫.b / H(𝒫))^2)
τ_1(𝒫,r)     = 1 / T₀(𝒫) * τ_z_1(𝒫,r) + B(𝒫) * τ_z_2(𝒫,r) * τ_z_3(𝒫,r)
τ_2(𝒫,r)     = C(𝒫) * τ_z_2(𝒫,r) * τ_z_3(𝒫,r)
τ_int_1(𝒫,r) = A(𝒫) * (τ_z_1(𝒫,r) - 1) + B(𝒫) * (r - 𝒫.a) * τ_z_3(𝒫,r)
τ_int_2(𝒫,r) = C(𝒫) * (r - 𝒫.a) * τ_z_3(𝒫,r)
F_z(𝒫,r)     = (1 - 3 * ((r - 𝒫.a) / 𝒫.z_t)^2 + 2 * ((r - 𝒫.a) / 𝒫.z_t)^3) * ((r - 𝒫.a) ≤ 𝒫.z_t)

# convenience functions that only depend on longitude and latitude
d(𝒫,λ,ϕ)     = 𝒫.a * acos(sin(ϕ) * sin(𝒫.ϕ_c) + cos(ϕ) * cos(𝒫.ϕ_c) * cos(λ - 𝒫.λ_c))
c3(𝒫,λ,ϕ)    = cos(π * d(𝒫,λ,ϕ) / 2 / d_0(𝒫))^3
s1(𝒫,λ,ϕ)    = sin(π * d(𝒫,λ,ϕ) / 2 / d_0(𝒫))
cond(𝒫,λ,ϕ)  = (0 < d(𝒫,λ,ϕ) < d_0(𝒫)) * (d(𝒫,λ,ϕ) != 𝒫.a * π)

# base-state thermodynamic variables
I_T(𝒫,ϕ,r)   = (cos(ϕ) * r / 𝒫.a)^𝒫.k - 𝒫.k / (𝒫.k + 2) * (cos(ϕ) * r / 𝒫.a)^(𝒫.k + 2)
Tᵥ(𝒫,ϕ,r)    = (τ_1(𝒫,r) - τ_2(𝒫,r) * I_T(𝒫,ϕ,r))^(-1) * (𝒫.a/r)^2
p(𝒫,ϕ,r)     = 𝒫.pₒ * exp(-𝒫.g / 𝒫.R_d * (τ_int_1(𝒫,r) - τ_int_2(𝒫,r) * I_T(𝒫,ϕ,r)))
q(𝒫,ϕ,r)     = (p(𝒫,ϕ,r) > 𝒫.p_w) ? 𝒫.q₀ * exp(-(ϕ / 𝒫.ϕ_w)^4) * exp(-((p(𝒫,ϕ,r) - 𝒫.pₒ) / 𝒫.p_w)^2) : 𝒫.qₜ

# base-state velocity variables
U(𝒫,ϕ,r)  = 𝒫.g * 𝒫.k / 𝒫.a * τ_int_2(𝒫,r) * Tᵥ(𝒫,ϕ,r) * ((cos(ϕ) * r / 𝒫.a)^(𝒫.k - 1) - (cos(ϕ) * r / 𝒫.a)^(𝒫.k + 1))
u(𝒫,ϕ,r)  = -𝒫.Ω * r * cos(ϕ) + sqrt((𝒫.Ω * r * cos(ϕ))^2 + r * cos(ϕ) * U(𝒫,ϕ,r))
v(𝒫,ϕ,r)  = 0.0
w(𝒫,ϕ,r)  = 0.0

# velocity perturbations
δu(𝒫,λ,ϕ,r)  = -16 * 𝒫.V_p / 3 / sqrt(3) * F_z(𝒫,r) * c3(𝒫,λ,ϕ) * s1(𝒫,λ,ϕ) * (-sin(𝒫.ϕ_c) * cos(ϕ) + cos(𝒫.ϕ_c) * sin(ϕ) * cos(λ - 𝒫.λ_c)) / sin(d(𝒫,λ,ϕ) / 𝒫.a) * cond(𝒫,λ,ϕ)
δv(𝒫,λ,ϕ,r)  = 16 * 𝒫.V_p / 3 / sqrt(3) * F_z(𝒫,r) * c3(𝒫,λ,ϕ) * s1(𝒫,λ,ϕ) * cos(𝒫.ϕ_c) * sin(λ - 𝒫.λ_c) / sin(d(𝒫,λ,ϕ) / 𝒫.a) * cond(𝒫,λ,ϕ)
δw(𝒫,λ,ϕ,r)  = 0.0

# CliMA prognostic variables
# compute the total energy
uˡᵒⁿ(𝒫,λ,ϕ,r)   = u(𝒫,ϕ,r) + δu(𝒫,λ,ϕ,r)
uˡᵃᵗ(𝒫,λ,ϕ,r)   = v(𝒫,ϕ,r) + δv(𝒫,λ,ϕ,r)
uʳᵃᵈ(𝒫,λ,ϕ,r)   = w(𝒫,ϕ,r) + δw(𝒫,λ,ϕ,r)

# cv_m and R_m for moist experiment
cv_m(𝒫,ϕ,r)  = 𝒫.cv_d + (𝒫.cv_v - 𝒫.cv_d) * q(𝒫,ϕ,r)
R_m(𝒫,ϕ,r) = 𝒫.R_d * (1 + (𝒫.molmass_ratio - 1) * q(𝒫,ϕ,r))

T(𝒫,ϕ,r) = Tᵥ(𝒫,ϕ,r) / (1 + 𝒫.Mᵥ * q(𝒫,ϕ,r)) 
e_int(𝒫,λ,ϕ,r)  = cv_m(𝒫,ϕ,r) * (T(𝒫,ϕ,r) - 𝒫.T_0) + q(𝒫,ϕ,r) * 𝒫.e_int_v0
e_kin(𝒫,λ,ϕ,r)  = 0.5 * ( uˡᵒⁿ(𝒫,λ,ϕ,r)^2 + uˡᵃᵗ(𝒫,λ,ϕ,r)^2 + uʳᵃᵈ(𝒫,λ,ϕ,r)^2 )
e_pot(𝒫,λ,ϕ,r)  = 𝒫.g * r

ρ₀(𝒫,λ,ϕ,r)    = p(𝒫,ϕ,r) / R_m(𝒫,ϕ,r) / T(𝒫,ϕ,r)
ρuˡᵒⁿ(𝒫,λ,ϕ,r) = ρ₀(𝒫,λ,ϕ,r) * uˡᵒⁿ(𝒫,λ,ϕ,r)
ρuˡᵃᵗ(𝒫,λ,ϕ,r) = ρ₀(𝒫,λ,ϕ,r) * uˡᵃᵗ(𝒫,λ,ϕ,r)
ρuʳᵃᵈ(𝒫,λ,ϕ,r) = ρ₀(𝒫,λ,ϕ,r) * uʳᵃᵈ(𝒫,λ,ϕ,r)
ρe(𝒫,λ,ϕ,r) = ρ₀(𝒫,λ,ϕ,r) * (e_int(𝒫,λ,ϕ,r) + e_kin(𝒫,λ,ϕ,r) + e_pot(𝒫,λ,ϕ,r))
ρq(𝒫,λ,ϕ,r) = ρ₀(𝒫,λ,ϕ,r) * q(𝒫,ϕ,r)

# Cartesian Representation (boiler plate really)
ρ₀ᶜᵃʳᵗ(𝒫, x...)  = ρ₀(𝒫, lon(x...), lat(x...), rad(x...))
ρu⃗₀ᶜᵃʳᵗ(𝒫, x...) = (   ρuʳᵃᵈ(𝒫, lon(x...), lat(x...), rad(x...)) * r̂(x...)
                     + ρuˡᵃᵗ(𝒫, lon(x...), lat(x...), rad(x...)) * ϕ̂(x...)
                     + ρuˡᵒⁿ(𝒫, lon(x...), lat(x...), rad(x...)) * λ̂(x...) )
ρeᶜᵃʳᵗ(𝒫, x...) = ρe(𝒫, lon(x...), lat(x...), rad(x...))
ρqᶜᵃʳᵗ(𝒫, x...) = ρq(𝒫, lon(x...), lat(x...), rad(x...))

########
# Set up lower boundary condition
########
T_sfc(𝒫, ϕ) = 𝒫.ΔT * exp(-ϕ^2 / 2 / 𝒫.Δϕ^2) + 𝒫.Tₘᵢₙ
FixedSST = BulkFormulaTemperature(
    drag_coef_temperature = (params, ϕ) -> params.Cₑ,
    drag_coef_moisture = (params, ϕ) -> params.Cₗ,
    surface_temperature = T_sfc,
)

#####
# Held-Suarez Forcing
#####
struct HeldSuarezForcing{S} <: AbstractPhysicsComponent
    parameters::S
end

FT = Float64
day = 86400
held_suarez_parameters = (;
    k_a = FT(1 / (40 * day)),
    k_f = FT(1 / day),
    k_s = FT(1 / (4 * day)),
    ΔT_y = FT(65),
    Δθ_z = FT(10),
    T_equator = FT(294),
    T_min = FT(200),
    σ_b = FT(7 / 10),
    R_d  = parameters.R_d,
    day  = parameters.day,
    grav = parameters.g,
    cp_d = parameters.cp_d,
    cv_d = parameters.cv_d,
    MSLP = parameters.p0,  
)

######
# Modified Held-Suarez Forcing
######
function calc_component!(
    source,
    hsf::HeldSuarezForcing,
    state,
    aux,
    physics,
)
    FT = eltype(state)
    
    _R_d  = hsf.parameters.R_d
    _day  = hsf.parameters.day
    _grav = hsf.parameters.grav
    _cp_d = hsf.parameters.cp_d
    _cv_d = hsf.parameters.cv_d
    _p0   = hsf.parameters.MSLP  

    # Parameters
    T_ref = FT(255)

    # Extract the state
    ρ = state.ρ
    ρu = state.ρu
    ρe = state.ρe
    Φ = aux.Φ
    
    x = aux.x
    y = aux.y
    z = aux.z
    coord = @SVector[x,y,z]

    p = calc_pressure(physics.eos, state, aux, physics.parameters)
    T = p / (ρ * _R_d)

    # Held-Suarez parameters
    k_a  = hsf.parameters.k_a
    k_f  = hsf.parameters.k_f
    k_s  = hsf.parameters.k_s
    ΔT_y = hsf.parameters.ΔT_y
    Δθ_z = hsf.parameters.Δθ_z
    T_equator = hsf.parameters.T_equator
    T_min = hsf.parameters.T_min
    σ_b = hsf.parameters.σ_b

    # Held-Suarez forcing
    φ = @inbounds asin(coord[3] / norm(coord, 2))

    #TODO: replace _p0 with dynamic surfce pressure in Δσ calculations to account
    #for topography, but leave unchanged for calculations of σ involved in T_equil
    σ = p / _p0
    exner_p = σ^(_R_d / _cp_d)
    Δσ = (σ - σ_b) / (1 - σ_b)
    height_factor = max(0, Δσ)
    T_equil = (T_equator - ΔT_y * sin(φ)^2 - Δθ_z * log(σ) * cos(φ)^2) * exner_p
    T_equil = max(T_min, T_equil)
    k_T = k_a + (k_s - k_a) * height_factor * cos(φ)^4
    k_v = k_f * height_factor

    # horizontal projection
    k = coord / norm(coord)
    P = I - k * k'

    # Apply Held-Suarez forcing
    source.ρu -= k_v * P * ρu
    source.ρe -= k_T * ρ * _cv_d * (T - T_equil)
    return nothing
end

########
# Set up model physics
########
FT = Float64

ref_state = DryReferenceState(
  DecayingTemperatureProfile{FT}(parameters, FT(290), FT(220), FT(8e3))
)
physics = Physics(
    orientation = SphericalOrientation(),
    ref_state   = ref_state,
    eos         = MoistIdealGas(),
    lhs         = (
        NonlinearAdvection{(:ρ, :ρu, :ρe)}(),
        PressureDivergence(),
    ),
    sources     = (
        DeepShellCoriolis(),
        FluctuationGravity(),
        ZeroMomentMicrophysics(),
        HeldSuarezForcing(held_suarez_parameters),
    ),
    parameters = parameters,
)

linear_physics = Physics(
    orientation = physics.orientation,
    ref_state   = physics.ref_state,
    eos         = physics.eos,
    lhs         = (
        LinearAdvection{(:ρ, :ρu, :ρe)}(),
        LinearPressureDivergence(),
    ),
    sources     = (
        FluctuationGravity(),
    ),
    parameters = parameters,
)

########
# Set up model
########
model = DryAtmosModel(
    physics = physics,
    boundary_conditions = (DefaultBC(), FixedSST),
    initial_conditions = (ρ = ρ₀ᶜᵃʳᵗ, ρu = ρu⃗₀ᶜᵃʳᵗ, ρe = ρeᶜᵃʳᵗ, ρq = ρqᶜᵃʳᵗ),
    numerics = (flux = LMARSNumericalFlux(),),
)

linear_model = DryAtmosModel(
    physics = linear_physics,
    boundary_conditions = (DefaultBC(), DefaultBC()),
    initial_conditions = model.initial_conditions,
    numerics = (flux = RefanovFlux(),),
)

########
# Set up time steppers (could be done automatically in simulation)
########
dx = min_node_distance(grid.numerical)
cfl = 5 # 13 for 10 days, 7.5 for 200+ days
Δt = cfl * dx / 330.0
start_time = 0
end_time = 1200 * 24 * 3600
method = IMEX() 
callbacks = (
  Info(),
  CFL(),
  VTKState(
    iteration = Int(floor(24*3600/Δt)), 
    #filepath = "/central/scratch/bischtob/benchmark_moist_held_suarez/"),
    filepath = "./out/"),  
  TMARCallback(),
)

########
# Set up simulation
########
simulation = Simulation(
    (Explicit(model), Implicit(linear_model),);
    grid = grid,
    timestepper = (method = method, timestep = Δt),
    time        = (start = start_time, finish = end_time),
    callbacks   = callbacks,
);

evolve!(simulation)

nothing