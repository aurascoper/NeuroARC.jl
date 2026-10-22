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

"""
    EquivarianceEvidence <: AbstractEvidence

Equivariance verification evidence under D8 dihedral and color permutations.
Status is `:passed`, `:failed`, or `:untestable`.
"""
struct EquivarianceEvidence <: AbstractEvidence
    d8_equivariant::Bool
    color_perm_equivariant::Bool
    status::Symbol
end

"""
    WarrantScramblingEvidence <: AbstractEvidence

Coevolutionary Warrant-Scrambling and MDL Aesthetic verification evidence for ARC-AGI-2:
- `train_accuracy`: Exact replay match fraction across training pairs.
- `color_scrambling_warrant`: Commutation fraction under cyclic + out-of-train palette bijections `pi in S_10`.
- `spatial_scrambling_warrant`: Commutation fraction under dihedral `D_4` transforms.
- `legend_scrambling_warrant`: Commutation fraction under in-grid instruction legend swaps.
- `aesthetic_mdl_score`: Minimum Description Length prior `exp(-alpha_mdl * max(ast_node_count - 1, 0))`.
- `composite_fitness`: Weighted fitness `0.50*train + 0.25*color + 0.15*spatial + 0.10*mdl`.
- `is_warranted_generalizer`: True iff `train_accuracy == 1.0 && color_scrambling_warrant == 1.0 && legend_scrambling_warrant == 1.0`.
- `status`: `:passed`, `:failed`, or `:untestable`.
"""
struct WarrantScramblingEvidence <: AbstractEvidence
    train_accuracy::Float64
    color_scrambling_warrant::Float64
    spatial_scrambling_warrant::Float64
    legend_scrambling_warrant::Float64
    aesthetic_mdl_score::Float64
    composite_fitness::Float64
    is_warranted_generalizer::Bool
    status::Symbol
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
