# most of these functions are temporary helpers until upstream issues are resolved

# TODO: unify with coupler interface
struct CouplerSimulation{I, F, B, T, M}
    Δt::I
    t::F
    boundary_space::B
    FT::T
    mask::M
end


function swap_space!(field, new_space)
    field_out = zeros(new_space)
    parent(field_out) .= parent(field)
    return field_out
end

heaviside(var) = var < 0 ? 0 : var