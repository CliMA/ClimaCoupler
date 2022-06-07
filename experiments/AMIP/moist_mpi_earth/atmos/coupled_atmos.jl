using ClimaCore.Geometry: ⊗

# These functions are copied from the ClimaAtmos driver and modified for the coupler (TODO: update when interface is stable)
function vertical_diffusion_boundary_layer_coupled_tendency!(Yₜ, Y, p, t)
    ᶜρ = Y.c.ρ
    (; ᶜp, ᶠv_a, ᶠz_a, ᶠK_E) = p # assume ᶜts and ᶜp have been updated
    (; dif_flux_energy, dif_flux_ρq_tot, dif_flux_uₕ) = p
    ᶠgradᵥ = Operators.GradientC2F() # apply BCs to ᶜdivᵥ, which wraps ᶠgradᵥ

    Fields.field_values(ᶠv_a) .= Fields.field_values(Spaces.level(Y.c.uₕ, 1)) .* one.(Fields.field_values(ᶠz_a)) # TODO: fix VIJFH copyto! to remove this
    @. ᶠK_E = eddy_diffusivity_coefficient(norm(ᶠv_a), ᶠz_a, ᶠinterp(ᶜp)) #* FT(0)

    # Total Energy
    if :ρe in propertynames(Y.c)
        ᶜdivᵥ = Operators.DivergenceF2C(
            top = Operators.SetValue(Geometry.WVector(FT(0))),
            bottom = Operators.SetValue(.-dif_flux_energy),
        )
        @. Yₜ.c.ρe += ᶜdivᵥ(ᶠK_E * ᶠinterp(ᶜρ) * ᶠgradᵥ((Y.c.ρe + ᶜp) / ᶜρ))
    end

    # Liquid Mass and Total Mass
    if :ρq_tot in propertynames(Y.c)
        ᶜdivᵥ = Operators.DivergenceF2C(
            top = Operators.SetValue(Geometry.WVector(FT(0))),
            bottom = Operators.SetValue(.-dif_flux_ρq_tot),
        )
        @. Yₜ.c.ρq_tot += ᶜdivᵥ(ᶠK_E * ᶠinterp(ᶜρ) * ᶠgradᵥ(Y.c.ρq_tot / ᶜρ))
        @. Yₜ.c.ρ += ᶜdivᵥ(ᶠK_E * ᶠinterp(ᶜρ) * ᶠgradᵥ(Y.c.ρq_tot / ᶜρ))
    end

    # Momentum
    if :uₕ in propertynames(Y.c)
        ᶜdivᵥ = Operators.DivergenceF2C(
            top = Operators.SetValue(Geometry.Contravariant3Vector(FT(0)) ⊗ Geometry.Covariant12Vector(FT(0), FT(0))),
            bottom = Operators.SetValue(.-dif_flux_uₕ),
        )

        @. Yₜ.c.uₕ += ᶜdivᵥ(ᶠK_E * ᶠgradᵥ(Y.c.uₕ))
    end

end

function vertical_diffusion_boundary_layer_coupled_cache(Y; Cd = FT(0.0014), Ch = FT(0.0014))
    ᶠz_a = similar(Y.f, FT)
    z_bottom = Spaces.level(Fields.coordinate_field(Y.c).z, 1)
    Fields.field_values(ᶠz_a) .= Fields.field_values(z_bottom) .* one.(Fields.field_values(ᶠz_a))
    # TODO: fix VIJFH copyto! to remove the one.(...)

    if :ρq_tot in propertynames(Y.c)
        dif_flux_ρq_tot = similar(z_bottom, Geometry.WVector{FT}) #ones(axes(z_bottom))
    else
        dif_flux_ρq_tot = Ref(Geometry.WVector(FT(0)))
    end

    dif_flux_uₕ =
        Geometry.Contravariant3Vector.(zeros(axes(z_bottom))) .⊗
        Geometry.Covariant12Vector.(zeros(axes(z_bottom)), zeros(axes(z_bottom)))

    if (:ρq_liq in propertynames(Y.c) && :ρq_ice in propertynames(Y.c) && :ρq_tot in propertynames(Y.c))
        ts_type = TD.PhaseNonEquil{FT}
    elseif :ρq_tot in propertynames(Y.c)
        ts_type = TD.PhaseEquil{FT}
    else
        ts_type = TD.PhaseDry{FT}
    end
    coef_type = SF.Coefficients{
        FT,
        SF.InteriorValues{FT, Tuple{FT, FT}, ts_type},
        SF.SurfaceValues{FT, Tuple{FT, FT}, TD.PhaseEquil{FT}},
    }

    return (;
        ᶠv_a = similar(Y.f, eltype(Y.c.uₕ)),
        ᶠz_a,
        ᶠK_E = similar(Y.f, FT),
        flux_coefficients = similar(z_bottom, coef_type),
        dif_flux_energy = similar(z_bottom, Geometry.WVector{FT}),
        dif_flux_ρq_tot,
        dif_flux_uₕ,
        ∂F_aero∂T_sfc = zeros(axes(z_bottom)),
        Cd,
        Ch,
    )
end

additional_cache(Y, params, dt; use_tempest_mode = false) = merge(
    hyperdiffusion_cache(Y; κ₄ = FT(2e17), use_tempest_mode),
    sponge ? rayleigh_sponge_cache(Y, dt) : NamedTuple(),
    isnothing(microphy) ? NamedTuple() : zero_moment_microphysics_cache(Y),
    isnothing(forcing) ? NamedTuple() : held_suarez_cache(Y),
    isnothing(rad) ? NamedTuple() : rrtmgp_model_cache(Y, params; radiation_mode, idealized_h2o),
    vert_diff ? vertical_diffusion_boundary_layer_coupled_cache(Y) : NamedTuple(),
    (;
        tendency_knobs = (;
            hs_forcing = forcing == "held_suarez",
            microphy_0M = microphy == "0M",
            rad_flux = !isnothing(rad),
            vert_diff,
            hyperdiff,
        )
    ),
)

additional_tendency!(Yₜ, Y, p, t) = begin
    (; rad_flux, vert_diff, hs_forcing) = p.tendency_knobs
    (; microphy_0M, hyperdiff) = p.tendency_knobs
    hyperdiff && hyperdiffusion_tendency!(Yₜ, Y, p, t)
    sponge && rayleigh_sponge_tendency!(Yₜ, Y, p, t)
    hs_forcing && held_suarez_tendency!(Yₜ, Y, p, t)
    vert_diff && vertical_diffusion_boundary_layer_coupled_tendency!(Yₜ, Y, p, t)
    microphy_0M && zero_moment_microphysics_tendency!(Yₜ, Y, p, t)
    rad_flux && rrtmgp_model_tendency!(Yₜ, Y, p, t)
end

# switch on required additional tendencies / parameterizations
parsed_args["microphy"] = "0M"
parsed_args["forcing"] = nothing
parsed_args["idealized_h2o"] = false
parsed_args["vert_diff"] = true
parsed_args["rad"] = "gray"
parsed_args["hyperdiff"] = true
parsed_args["config"] = "sphere"
parsed_args["moist"] = "equil"

function array2field(array, space) # reversing the RRTMGP function field2array (TODO: this now exists in ClimaAtmos)
    FT = eltype(array)
    Nq = Spaces.Quadratures.polynomial_degree(space.horizontal_space.quadrature_style) + 1
    ne = space.horizontal_space.topology.mesh.ne
    return Fields.Field(VIJFH{FT, Nq}(reshape(array, size(array, 1), Nq, Nq, 1, ne*ne*6)), space)
end