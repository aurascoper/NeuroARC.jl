# src/types.jl
# Core type definitions for NeuroARC candidate verification engine

"""
    ConnectedComponent

Deterministic connected component representation of an ARC grid region.
"""
struct ConnectedComponent
    id::Int
    color::Int8
    cells::Vector{Tuple{Int,Int}}
    bbox::NTuple{4,Int} # (rmin, cmin, rmax, cmax)
    is_border_touching::Bool
    hole_count::Int
end

"""
    GridState

Validated color-grid (colors 0..9, dimensions 1x1 up to 30x30) with cached palette bitmask,
background color, and extracted connected components.
"""
struct GridState
    cells::Matrix{Int8}
    height::Int
    width::Int
    palette::UInt16
    bg_color::Int8
    components::Vector{ConnectedComponent}

    function GridState(cells::Matrix{Int8}, height::Int, width::Int, palette::UInt16, bg_color::Int8, components::Vector{ConnectedComponent})
        if height < 1 || height > 30 || width < 1 || width > 30
            throw(ArgumentError("Grid dimensions must be between 1 and 30 (got $(height)x$(width))"))
        end
        for val in cells
            if val < 0 || val > 9
                throw(ArgumentError("Grid colors must be in 0..9 (got $val)"))
            end
        end
        new(cells, height, width, palette, bg_color, components)
    end
end

Base.:(==)(a::GridState, b::GridState) = (a.cells == b.cells)
Base.hash(g::GridState, h::UInt) = hash(g.cells, h)
Base.size(g::GridState) = (g.height, g.width)
Base.size(g::GridState, d::Integer) = size(g.cells, d)
Base.getindex(g::GridState, r::Integer, c::Integer) = g.cells[r, c]
Base.copy(g::GridState) = GridState(copy(g.cells), g.height, g.width, g.palette, g.bg_color, copy(g.components))

"""
    Demonstration

ARC input-output grid pair.
"""
struct Demonstration
    input::GridState
    output::GridState
end

"""
    ARCTask

ARC task container with train demonstrations and test inputs.
"""
struct ARCTask
    task_id::String
    train::Vector{Demonstration}
    test_inputs::Vector{GridState}
end

"""
    AbstractGridRule

Abstract root for all symbolic grid transformation rules.
"""
abstract type AbstractGridRule end

"""
    RuleNotImplementedError <: Exception

Thrown when an unpromoted or stub rule is invoked.
"""
struct RuleNotImplementedError <: Exception
    rule_type::String
    message::String
end

Base.showerror(io::IO, e::RuleNotImplementedError) = print(io, "RuleNotImplementedError: ", e.message)

"""
    AbstractEvidence

Abstract root for verifier evidence records.
"""
abstract type AbstractEvidence end

"""
    TrainExactEvidence <: AbstractEvidence

Exact categorical replay verification across train demonstrations.
"""
struct TrainExactEvidence <: AbstractEvidence
    pairs_matched::Int
    total_pairs::Int
    max_cell_residual::Float64
end

"""
    InformativeLOOEvidence <: AbstractEvidence

Leave-one-out cross-validation evidence.
Informative only when parameters are refit on N-1 demonstrations.
"""
struct InformativeLOOEvidence <: AbstractEvidence
    is_informative::Bool
    folds_passed::Int
    total_folds::Int
    free_param_count::Int
end

const CANONICAL_D8_TRANSFORMS = Symbol[
    :id, :rot90, :rot180, :rot270,
    :refl_h, :refl_v, :refl_main_diag, :refl_anti_diag
]

const SYMMETRY_GROUP_TRANSFORMS = Dict{Symbol, Vector{Symbol}}(
    :D8                => Symbol[:id, :rot90, :rot180, :rot270, :refl_h, :refl_v, :refl_main_diag, :refl_anti_diag],
    :C4                => Symbol[:id, :rot90, :rot180, :rot270],
    :D2_ortho          => Symbol[:id, :rot180, :refl_h, :refl_v],
    :D2_diag           => Symbol[:id, :rot180, :refl_main_diag, :refl_anti_diag],
    :C2                => Symbol[:id, :rot180],
    :D1_refl_h         => Symbol[:id, :refl_h],
    :D1_refl_v         => Symbol[:id, :refl_v],
    :D1_refl_main_diag => Symbol[:id, :refl_main_diag],
    :D1_refl_anti_diag => Symbol[:id, :refl_anti_diag],
    :C1                => Symbol[:id]
)

const ORDERED_SYMMETRY_SUBGROUPS = Symbol[
    :D8, :C4, :D2_ortho, :D2_diag, :C2,
    :D1_refl_h, :D1_refl_v, :D1_refl_main_diag, :D1_refl_anti_diag, :C1
]

"""
    group_transforms(group::Symbol)::Vector{Symbol}

Returns the canonical list of geometric transformations for the requested symmetry group.
"""
function group_transforms(group::Symbol)::Vector{Symbol}
    haskey(SYMMETRY_GROUP_TRANSFORMS, group) ||
        throw(ArgumentError("Unsupported symmetry group symbol: $group"))
    return copy(SYMMETRY_GROUP_TRANSFORMS[group])
end

"""
    compute_supported_subgroups(passed_transforms::AbstractVector{Symbol})::Vector{Symbol}

Computes all dihedral/rotational/reflection subgroups of `D_8` whose elements are all contained
in `passed_transforms`.
"""
function compute_supported_subgroups(passed_transforms::AbstractVector{Symbol})::Vector{Symbol}
    passed_set = Set{Symbol}(passed_transforms)
    subgroups = Symbol[]
    for sg in ORDERED_SYMMETRY_SUBGROUPS
        req = SYMMETRY_GROUP_TRANSFORMS[sg]
        if all(t -> t in passed_set, req)
            push!(subgroups, sg)
        end
    end
    return subgroups
end

"""
    EquivarianceEvidence <: AbstractEvidence

Equivariance verification evidence recording the requested symmetry claim (`requested_group`),
exact `tested_transforms`, `passed_transforms`, `failed_transforms`, `untestable_transforms`,
and `supported_subgroups`, along with `d8_equivariant`, `color_perm_equivariant`, and
3-valued `status` (`:passed`, `:failed`, or `:untestable` scoped to `requested_group`).
"""
struct EquivarianceEvidence <: AbstractEvidence
    d8_equivariant::Bool
    color_perm_equivariant::Bool
    status::Symbol
    requested_group::Symbol
    tested_transforms::Vector{Symbol}
    passed_transforms::Vector{Symbol}
    failed_transforms::Vector{Symbol}
    untestable_transforms::Vector{Symbol}
    supported_subgroups::Vector{Symbol}
end

function EquivarianceEvidence(
    d8_equivariant::Bool,
    color_perm_equivariant::Bool,
    status::Symbol,
    requested_group::Symbol,
    tested_transforms::Vector{Symbol},
    passed_transforms::Vector{Symbol},
    failed_transforms::Vector{Symbol},
    untestable_transforms::Vector{Symbol}
)
    return EquivarianceEvidence(
        d8_equivariant,
        color_perm_equivariant,
        status,
        requested_group,
        tested_transforms,
        passed_transforms,
        failed_transforms,
        untestable_transforms,
        compute_supported_subgroups(passed_transforms)
    )
end

function EquivarianceEvidence(
    d8_equivariant::Bool,
    color_perm_equivariant::Bool,
    status::Symbol;
    requested_group::Symbol = :D8
)
    tested = group_transforms(requested_group)
    if status === :untestable
        return EquivarianceEvidence(
            d8_equivariant,
            color_perm_equivariant,
            status,
            requested_group,
            tested,
            Symbol[],
            Symbol[],
            copy(tested),
            Symbol[]
        )
    elseif d8_equivariant
        return EquivarianceEvidence(
            d8_equivariant,
            color_perm_equivariant,
            status,
            requested_group,
            tested,
            copy(tested),
            Symbol[],
            Symbol[],
            compute_supported_subgroups(CANONICAL_D8_TRANSFORMS)
        )
    else
        passed = :id in tested ? Symbol[:id] : Symbol[]
        failed = [t for t in tested if t !== :id]
        return EquivarianceEvidence(
            d8_equivariant,
            color_perm_equivariant,
            status,
            requested_group,
            tested,
            passed,
            failed,
            Symbol[],
            compute_supported_subgroups(passed)
        )
    end
end

"""
    ProvenanceReceipt

Audit receipt recording solver family, checkpoint SHA, seed, budget steps, and cross-task firing.
"""
struct ProvenanceReceipt
    solver_family::Symbol
    checkpoint_sha::Union{String, Nothing}
    seed::Union{Int, Nothing}
    budget_steps::Union{Int, Nothing}
    cross_task_firing::Int
end

function ProvenanceReceipt(solver_family::Symbol;
                           checkpoint_sha::Union{String, Nothing}=nothing,
                           seed::Union{Int, Nothing}=nothing,
                           budget_steps::Union{Int, Nothing}=nothing,
                           cross_task_firing::Int=0)
    ProvenanceReceipt(solver_family, checkpoint_sha, seed, budget_steps, cross_task_firing)
end

"""
    Candidate{R<:AbstractGridRule}

A generated rule candidate bundled with predictions, verification evidence, and provenance receipt.
"""
struct Candidate{R<:AbstractGridRule}
    rule::R
    predictions::Vector{GridState}
    evidence::Vector{AbstractEvidence}
    provenance::ProvenanceReceipt
end
