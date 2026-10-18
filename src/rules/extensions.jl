# src/rules/extensions.jl
# Typed extension points for unpromoted / proposal-only rule families

"""
    GeodesicBarrierFloodRule <: AbstractGridRule

Typed extension point for multi-source barrier-aware flood fill.
Proposal-only in R1.
"""
struct GeodesicBarrierFloodRule <: AbstractGridRule end

function apply_rule(rule::GeodesicBarrierFloodRule, input::GridState)::GridState
    throw(RuleNotImplementedError("GeodesicBarrierFloodRule",
        "GeodesicBarrierFloodRule is proposal-only: parameter contract and executor are not implemented in R1"))
end

"""
    CorridorWireTraceRule <: AbstractGridRule

Typed extension point for wire tracing through crossings and stations.
Proposal-only in R1.
"""
struct CorridorWireTraceRule <: AbstractGridRule end

function apply_rule(rule::CorridorWireTraceRule, input::GridState)::GridState
    throw(RuleNotImplementedError("CorridorWireTraceRule",
        "CorridorWireTraceRule is proposal-only: parameter contract and executor are not implemented in R1"))
end

"""
    PeriodicStampWithPriorityRule <: AbstractGridRule

Typed extension point for count-encoded period + layered overdraw priority.
Proposal-only in R1.
"""
struct PeriodicStampWithPriorityRule <: AbstractGridRule end

function apply_rule(rule::PeriodicStampWithPriorityRule, input::GridState)::GridState
    throw(RuleNotImplementedError("PeriodicStampWithPriorityRule",
        "PeriodicStampWithPriorityRule is proposal-only: parameter contract and executor are not implemented in R1"))
end

"""
    ExactCoverPolyominoRule <: AbstractGridRule

Typed extension point for exact cover polyomino tiling with perimeter tie-breaking.
Proposal-only in R1.
"""
struct ExactCoverPolyominoRule <: AbstractGridRule end

function apply_rule(rule::ExactCoverPolyominoRule, input::GridState)::GridState
    throw(RuleNotImplementedError("ExactCoverPolyominoRule",
        "ExactCoverPolyominoRule is proposal-only: parameter contract and executor are not implemented in R1"))
end
