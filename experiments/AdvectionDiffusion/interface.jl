# using Domains

using ClimateMachine, MPI
using ClimateMachine.Mesh.Grids
using ClimateMachine.Mesh.Topologies
using ClimateMachine.MPIStateArrays

using MPI

import ClimateMachine.Mesh.Grids: DiscontinuousSpectralElementGrid
import ClimateMachine.Mesh.Topologies: StackedBrickTopology

"""
function DiscontinuousSpectralElementGrid(Ω::ProductDomain; elements = nothing, polynomialorder = nothing)
# Description 
Computes a DiscontinuousSpectralElementGrid as specified by a product domain
# Arguments
-`Ω`: A product domain object
# Keyword Arguments TODO: Add brickrange and topology as keyword arguments
-`elements`: A tuple of integers ordered by (Nx, Ny, Nz) for number of elements
-`polynomialorder`: A tupe of integers ordered by (npx, npy, npz) for polynomial order
-`FT`: floattype, assumed Float64 unless otherwise specified
-`mpicomm`: default = MPI.COMM_WORLD
-`array`: default = Array, but should generally be ArrayType
# Return 
A DiscontinuousSpectralElementGrid object
"""
function DiscontinuousSpectralElementGrid(
    Ω::ProductDomain{FT},
    elements,
    polynomialorder,
    mpicomm = MPI.COMM_WORLD,
    boundary = (1, 2),
    array = Array,
) where {FT}
    if elements == nothing
        error_message = "Please specify the number of elements as a tuple whose size is commensurate with the domain,"
        error_message = "e.g., a 3 dimensional domain would need a specification like elements = (10,10,10)."
        @error(error_message)
        return nothing
    end

    if polynomialorder == nothing
        error_message = "Please specify the polynomial order as a tuple whose size is commensurate with the domain,"
        error_message = "e.g., a 3 dimensional domain would need a specification like polynomialorder = (3,3,3)."
        @error(error_message)
        return nothing
    end

    dimension = ndims(Ω)

    if (dimension < 2) || (dimension > 3)
        error_message = "SpectralElementGrid only works with dimensions 2 or 3. "
        error_message *= "The current dimension is " * string(ndims(Ω))
        println("The domain is ", Ω)
        @error(error_message)
        return nothing
    end

    if ndims(Ω) != length(elements)
        @error("Specified too many elements for the dimension of the domain")
        return nothing
    end

    if ndims(Ω) != length(polynomialorder)
        @error("Specified too many polynomialorders for the dimension of the domain")
        return nothing
    end

    periodicity = periodicityof(Ω)
    tuple_ranges = []

    for i in 1:dimension
        push!(
            tuple_ranges,
            range(FT(Ω[i].min); length = elements[i] + 1, stop = FT(Ω[i].max)),
        )
    end

    brickrange = Tuple(tuple_ranges)
    if boundary == nothing
        boundary = (ntuple(j -> (1, 2), dimension - 1)..., (3, 4))
    end

    topology = StackedBrickTopology(
        mpicomm,
        brickrange;
        periodicity = periodicity,
        boundary = boundary,
    )

    grid = DiscontinuousSpectralElementGrid(
        topology,
        FloatType = FT,
        DeviceArray = array,
        polynomialorder = polynomialorder,
    )
    return grid
end

```
for CubedSphere
```
# using CLIMAParameters
# using CLIMAParameters.Planet: MSLP, R_d, day, grav, Omega, planet_radius
# struct EarthParameterSet <: AbstractEarthParameterSet end
# const param_set = EarthParameterSet()
# _a::Float64 = planet_radius(param_set)
# atmos_height::Float64 = 30e3

# ```
# grid = DiscontinuousSpectralElementGrid(Ω=, elements=, polynomialorder=)
# ```

function DiscontinuousSpectralElementGrid(
    Ω::AtmosDomain{FT},
    elements,
    polynomialorder,
    mpicomm = MPI.COMM_WORLD,
    boundary = (1, 2),
    array = Array,
) where {FT}
    Rrange = grid1d(Ω.radius, Ω.radius + Ω.height, nelem = elements.vertical)

    topl = StackedCubedSphereTopology(
        mpicomm,
        elements.horizontal,
        Rrange,
        boundary = boundary, 
    )

    grid = DiscontinuousSpectralElementGrid(
        topl,
        FloatType = FT,
        DeviceArray = array,
        polynomialorder = (polynomialorder.horizontal, polynomialorder.vertical),
        meshwarp = ClimateMachine.Mesh.Topologies.equiangular_cubed_sphere_warp,
    )
    return grid
end
function DiscontinuousSpectralElementGrid(
    Ω::OceanDomain{FT},
    elements,
    polynomialorder,
    mpicomm = MPI.COMM_WORLD,
    boundary = (1, 2),
    array = Array,
) where {FT}
    Rrange = grid1d(Ω.radius + Ω.depth, Ω.radius, nelem = elements.vertical)

    topl = StackedCubedSphereTopology(
        mpicomm,
        elements.horizontal,
        Rrange,
        boundary = boundary, 
    )

    grid = DiscontinuousSpectralElementGrid(
        topl,
        FloatType = FT,
        DeviceArray = array,
        polynomialorder = (polynomialorder.horizontal, polynomialorder.vertical),
        meshwarp = ClimateMachine.Mesh.Topologies.equiangular_cubed_sphere_warp,
    )
    return grid
end
