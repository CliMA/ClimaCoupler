########
# Set up parameters
# - ICTH = parameter for Thatcher & Jablonowski initial conditions 
#   (see http://www-personal.umich.edu/~cjablono/DCMIP-2016_TestCaseDocument_10June2016.pdf)
########
parameters = (
    a        = get_planet_parameter(:planet_radius),
    Ω        = get_planet_parameter(:Omega),
    g        = get_planet_parameter(:grav),
    κ        = get_planet_parameter(:kappa_d),
    R_d      = get_planet_parameter(:R_d),
    R_v      = get_planet_parameter(:R_v),
    cv_d     = get_planet_parameter(:cv_d),
    cv_v     = get_planet_parameter(:cv_v),
    cv_l     = get_planet_parameter(:cv_l),
    cv_i     = get_planet_parameter(:cv_i),
    cp_d     = get_planet_parameter(:cp_d), 
    cp_v     = get_planet_parameter(:cp_v), 
    cp_l     = get_planet_parameter(:cp_l),
    cp_i     = get_planet_parameter(:cp_i),
    molmass_ratio = get_planet_parameter(:molmass_dryair)/get_planet_parameter(:molmass_water),
    γ        = get_planet_parameter(:cp_d)/get_planet_parameter(:cv_d),
    pₒ       = get_planet_parameter(:MSLP),
    pₜᵣ      = get_planet_parameter(:press_triple),
    Tₜᵣ      = get_planet_parameter(:T_triple),
    T_0      = get_planet_parameter(:T_0),
    LH_v0    = get_planet_parameter(:LH_v0), 
    e_int_v0 = get_planet_parameter(:e_int_v0),
    e_int_i0 = get_planet_parameter(:e_int_i0),
    H        = 30e3,   # domain height [m]
    k        = 3.0,    # ICTH: power used for temperture field 
    Γ        = 0.005,  # ICTH: lapse rate [K / m]
    T_E      = 300,    # ICTH: surface temperature horizontally averaged [K]
    T_P      = 271.0,  # ICTH: surface temperature at the pole [K]
    b        = 2.0,    # ICTH: half-width parameter
    z_t      = 15e3,   # ICTH: max height of the zonal wind perturbation [m]
    λ_c      = π / 9,  # ICTH: longitude of the zonal wind perturbation centerpoint 
    ϕ_c      = 2π / 9, # ICTH: latitude of the zonal wind perturbation centerpoint
    V_p      = 1.0,    # ICTH: max amplitude of the zonal wind perturbation [m / s]
    ϕ_w      = 2π/9,   # ICTH: specific humidity latitudinal width parameter
    p_w      = 3.4e4,  # ICTH: specific humidity vertical pressure width parameter
    q₀       = 0.018,  # ICTH: max specific humidity amplitude
    qₜ       = 1e-12,  # ICTH: specific humidity above artificial tropopause
    Mᵥ       = 0.608,  # ICTH: constant for virtual temperature conversion
    ΔT       = 29.0,   # equator-pole SST difference: fixed SST runs only
    Tₘᵢₙ     = 271.0,  # polar SST [K]: fixed SST runs only
    Δϕ       = 26π/180.0,  # latitudinal width (standard deviation) of the SST kernel: fixed SST runs only
    day      = 86400,  # length of day [s]
    T_ref    = 255,    # reference temperature [K]
    τ_precip = 100.0,  # precipitation timescale [s]
    p0       = 1e5,    # surface pressure [Pa] 
    Cₑ       = 0.0015, # bulk transfer coefficient for sensible heat
    Cₗ       = 0.0015, # bulk transfer coefficient for latent heat
    c_o = 3.93e3,   # specific heat for ocean  [J / K / kg]
    T_h = 280.0,      # initial temperature of surface ocean layer [K]
    h_o = 100.0,      # depth of the modelled ocean mixed layer [m]
    F_sol = 1361.0,   # incoming solar TOA radiation [W / m^2]
    τ = 0.9,        # atmospheric transmissivity 
    α = 0.5,        # surface albedo    
    σ = 5.67e-8,    # Steffan Boltzmann constant [kg / s^3 / K^4]
    ϵ = 0.98,       # broadband emissivity / absorptivity
    F_a = 0.0,      # LW flux from the atmosphere [W / m^2]
    ρ_o = 1026.0,     # density for ocean [kg / m^3]
    Q_0 = 10.0,       # Q-flux amplitude [W / m^2]
    L_w = 16.0,       # width of the Q-flux region (radians)
    diurnal_period = 24*60*60, # idealized daily cycle period [s]
)

# Mask to pick out the coupled boundary in the MPIStateArrays (here at altitude = 0 m)
epss = sqrt(eps(Float64))
boundary_mask( 𝒫, xc, yc, zc ) = @. abs(( xc^2 + yc^2 + zc^2 )^0.5 - 𝒫.a) < epss

########
# Set up inital conditions
########

# 1. Land (ocean) initial condition 
T_sfc₀(𝒫, x, y, z) = boundary_mask(𝒫, x, y, z ) * 0.5 * (𝒫.T_E + 𝒫.T_P)

# 2. Atmos (single stack) initial conditions
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
    T_ref = hsf.parameters.T_ref

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



