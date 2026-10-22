# ==============================================================================
# NeuroARC.jl - Calculus and Logic Gates of Transjection
# ==============================================================================
# Operational mathematical formalization of criterial causation, informational
# gating, and empowerment operators across pedagogical, developmental, and
# morphological scales.
#
# Epistemic Invariants:
# 1. Zero Em-Dash (\u2014) and Zero En-Dash (\u2013) policy enforced strictly.
# 2. Sourced foundations (Tse 2013, Wimsatt 1986, Wood et al. 1976, Vygotsky 1978)
#    are distinguished from proposed computational formalisms and implementations.
# 3. No vacuous boolean gates: operators define explicit algebraic projections,
#    resource empowerment, and typed diagnostic outcomes.
# ==============================================================================

module TransjectionCalculus

export AbstractCriterialGate, ThresholdGate, BandpassGate, SubtypeGate
export ConjunctionGate, DisjunctionGate, KOfNGate, KofNGate
export EmpowermentOperator, TransjectionOperator
export TransjectVerdict, AbstractVerdict, Accepted, Rejected, Incomplete
export evaluate_gate, gate_passed, transject, compose_transjections
export MorphologicalProfile, compute_morphology, euler_characteristic
export ScaffoldController, update_scaffold_state!

# ------------------------------------------------------------------------------
# 1. Algebraic Verdict Types (No numeric Inf or -1.0 sentinels)
# ------------------------------------------------------------------------------

abstract type TransjectVerdict end
const AbstractVerdict = TransjectVerdict

struct Accepted{T, F} <: TransjectVerdict
    value::T
    salient_features::F
    empowerment_score::Float64
    detail::String
    function Accepted(value::T, salient_features::F, empowerment_score::Real, detail::AbstractString) where {T, F}
        sc = Float64(empowerment_score)
        if !isfinite(sc) || sc == -1.0
            throw(ArgumentError("Numeric sentinel leakage (Inf/NaN/-1.0) forbidden in Accepted."))
        end
        return new{T, F}(value, salient_features, sc, String(detail))
    end
end

function Base.getproperty(v::Accepted, sym::Symbol)
    if sym === :score
        return getfield(v, :empowerment_score)
    end
    return getfield(v, sym)
end

struct Rejected <: TransjectVerdict
    reason::Symbol
    detail::String
    failed_gate_indices::Vector{Int}
    failed_gates::Vector{Symbol}
    partial_score::Float64
    function Rejected(
        reason::Symbol,
        detail::AbstractString,
        failed_gate_indices::Vector{Int},
        failed_gates::Vector{Symbol},
        partial_score::Real = 0.0
    )
        ps = Float64(partial_score)
        if !isfinite(ps) || ps == -1.0
            throw(ArgumentError("Numeric sentinel leakage (Inf/NaN/-1.0) forbidden in Rejected."))
        end
        return new(reason, String(detail), failed_gate_indices, failed_gates, ps)
    end
end

function Rejected(reason::Symbol, detail::AbstractString, failed_gate_indices::Vector{Int}, partial_score::Real = 0.0)
    return Rejected(reason, detail, failed_gate_indices, Symbol[], partial_score)
end

function Rejected(reason::Symbol, detail::AbstractString, failed_gates::Vector{Symbol}, partial_score::Real = 0.0)
    return Rejected(reason, detail, Int[], failed_gates, partial_score)
end

struct Incomplete <: TransjectVerdict
    reason::Symbol
    detail::String
end

# ------------------------------------------------------------------------------
# 2. Criterial Logic Gates (Temporal Stage t2: Informational Coincidence Detection)
# ------------------------------------------------------------------------------

abstract type AbstractCriterialGate end

# Threshold Gate: f(x) >= tau
struct ThresholdGate{F, T <: Real} <: AbstractCriterialGate
    name::String
    functional::F
    threshold::T
end
ThresholdGate(name::Symbol, functional::F, threshold::T) where {F, T <: Real} =
    ThresholdGate{F, T}(String(name), functional, threshold)

# Bandpass Gate: low <= f(x) <= high
struct BandpassGate{F, T <: Real} <: AbstractCriterialGate
    name::String
    functional::F
    low::T
    high::T
end
BandpassGate(name::Symbol, functional::F, low::T, high::T) where {F, T <: Real} =
    BandpassGate{F, T}(String(name), functional, low, high)

# Subtyping Gate: Out(A) <: In(B)
struct SubtypeGate{OutT, InT} <: AbstractCriterialGate
    name::String
    out_type::Type{OutT}
    in_type::Type{InT}
end
SubtypeGate(name::Symbol, ::Type{OutT}, ::Type{InT}) where {OutT, InT} =
    SubtypeGate{OutT, InT}(String(name), OutT, InT)

# Conjunction Gate: AND over a collection of gates
struct ConjunctionGate <: AbstractCriterialGate
    name::String
    gates::Vector{AbstractCriterialGate}
end
ConjunctionGate(name::Symbol, gates::Vector{<:AbstractCriterialGate}) =
    ConjunctionGate(String(name), AbstractCriterialGate[g for g in gates])
ConjunctionGate(name::Union{String, Symbol}, gates::Tuple) =
    ConjunctionGate(String(name), AbstractCriterialGate[g for g in gates])

# Disjunction Gate: OR over a collection of gates
struct DisjunctionGate <: AbstractCriterialGate
    name::String
    gates::Vector{AbstractCriterialGate}
end
DisjunctionGate(name::Symbol, gates::Vector{<:AbstractCriterialGate}) =
    DisjunctionGate(String(name), AbstractCriterialGate[g for g in gates])
DisjunctionGate(name::Union{String, Symbol}, gates::Tuple) =
    DisjunctionGate(String(name), AbstractCriterialGate[g for g in gates])

# K-of-N Gate: at least k of N gates must pass
struct KOfNGate <: AbstractCriterialGate
    name::String
    gates::Vector{AbstractCriterialGate}
    k::Int
end
const KofNGate = KOfNGate
KOfNGate(name::Symbol, gates::Vector{<:AbstractCriterialGate}, k::Int) =
    KOfNGate(String(name), AbstractCriterialGate[g for g in gates], k)
KOfNGate(name::Union{String, Symbol}, k::Int, gates::Union{Tuple, AbstractVector}) =
    KOfNGate(String(name), AbstractCriterialGate[g for g in gates], k)

gate_passed(g::AbstractCriterialGate, x)::Bool = first(evaluate_gate(g, x))

# Gate evaluation methods returning (passed::Bool, score::Float64, message::String)
function evaluate_gate(g::ThresholdGate, x)::Tuple{Bool, Float64, String}
    val = Float64(g.functional(x))
    passed = val >= Float64(g.threshold)
    msg = passed ? "$(g.name): Passed threshold $(g.threshold)" : "$(g.name): Failed ($(val) < $(g.threshold))"
    return (passed, val, msg)
end

function evaluate_gate(g::BandpassGate, x)::Tuple{Bool, Float64, String}
    val = Float64(g.functional(x))
    passed = (val >= Float64(g.low)) && (val <= Float64(g.high))
    msg = passed ? "$(g.name): Within band [$(g.low), $(g.high)]" : "$(g.name): Out of band ($(val) not in [$(g.low), $(g.high)])"
    return (passed, val, msg)
end

function evaluate_gate(g::SubtypeGate{OutT, InT}, x)::Tuple{Bool, Float64, String} where {OutT, InT}
    passed = OutT <: InT
    score = passed ? 1.0 : 0.0
    msg = passed ? "$(g.name): $(OutT) <: $(InT) confirmed" : "$(g.name): $(OutT) not a subtype of $(InT)"
    return (passed, score, msg)
end

function evaluate_gate(g::ConjunctionGate, x)::Tuple{Bool, Float64, String}
    all_passed = true
    sum_score = 0.0
    failed_names = String[]
    for sub in g.gates
        p, s, m = evaluate_gate(sub, x)
        sum_score += s
        if !p
            all_passed = false
            push!(failed_names, "$(sub.name): $(m)")
        end
    end
    mean_score = isempty(g.gates) ? 0.0 : sum_score / length(g.gates)
    msg = all_passed ? "All conjunction criteria satisfied" : "Failed conjunction: " * join(failed_names, "; ")
    return (all_passed, mean_score, msg)
end

function evaluate_gate(g::DisjunctionGate, x)::Tuple{Bool, Float64, String}
    any_passed = false
    max_score = -Inf
    for sub in g.gates
        p, s, _ = evaluate_gate(sub, x)
        max_score = max(max_score, s)
        if p
            any_passed = true
        end
    end
    msg = any_passed ? "Disjunctive criterion satisfied" : "All disjunctive branches failed"
    return (any_passed, any_passed ? max_score : 0.0, msg)
end

function evaluate_gate(g::KOfNGate, x)::Tuple{Bool, Float64, String}
    pass_count = 0
    total_score = 0.0
    for sub in g.gates
        p, s, _ = evaluate_gate(sub, x)
        total_score += s
        if p
            pass_count += 1
        end
    end
    passed = pass_count >= g.k
    msg = "$(pass_count) of $(length(g.gates)) gates satisfied (required: $(g.k))"
    return (passed, total_score / max(1, length(g.gates)), msg)
end

# ------------------------------------------------------------------------------
# 3. Empowerment Operator (Temporal Stage t3: Synaptic / Resource Downward Weighting)
# ------------------------------------------------------------------------------

struct EmpowermentOperator
    weights::Vector{Float64}
    projection_basis::Matrix{Float64}
    base_budget_tokens::Int
end

function empower(op::EmpowermentOperator, features::Vector{Float64})::Tuple{Vector{Float64}, Float64}
    d_feat = length(features)
    d_proj, d_in = size(op.projection_basis)
    if d_feat != d_in
        # Fallback identity scaling if dimensions differ
        return (features .* op.weights[1:min(d_feat, length(op.weights))], sum(features))
    end
    projected = op.projection_basis * features
    weighted = projected .* op.weights[1:min(length(projected), length(op.weights))]
    score = sum(abs.(weighted)) + Float64(op.base_budget_tokens)
    return (weighted, score)
end

# ------------------------------------------------------------------------------
# 4. Transjection Operator: Tri-Stage Dynamic Processing
# ------------------------------------------------------------------------------

struct TransjectionOperator{G <: AbstractCriterialGate}
    criterial_gate::G
    empowerment::EmpowermentOperator
    feature_extractor::Function
    generative_entrenchment_level::Int
end

function transject(op::TransjectionOperator, x)::TransjectVerdict
    # Stage t2: Evaluate criterial coincidence
    passed, raw_score, msg = evaluate_gate(op.criterial_gate, x)
    
    if !passed
        return Rejected(:criteria_failed, msg, Int[], raw_score)
    end
    
    # Extract structural features and apply Stage t3 empowerment
    feats = op.feature_extractor(x)
    salient, final_score = empower(op.empowerment, feats)
    
    return Accepted(x, salient, final_score, "Transjection succeeded: " * msg)
end

function compose_transjections(op2::TransjectionOperator, op1::TransjectionOperator)
    # Composed transjection: evaluates op1 first, then op2 on accepted inputs
    return x -> begin
        v1 = transject(op1, x)
        if !(v1 isa Accepted)
            return v1
        end
        return transject(op2, v1.value)
    end
end

# ------------------------------------------------------------------------------
# 5. Morphological Operators: Topological and Geometric Invariants
# ------------------------------------------------------------------------------

struct MorphologicalProfile
    height::Int
    width::Int
    area::Int
    perimeter::Int
    num_components::Int
    euler_characteristic::Int
    color_palette::Vector{Int}
end

function compute_morphology(grid::Matrix{Int})::MorphologicalProfile
    H, W = size(grid)
    colors = sort(unique(vec(grid)))
    
    # Binarize foreground (color != 0)
    fg = grid .!= 0
    area = count(fg)
    
    # Perimeter: count edges adjacent to 0 or boundary
    perim = 0
    for r in 1:H, c in 1:W
        if fg[r, c]
            if r == 1 || !fg[r-1, c]; perim += 1; end
            if r == H || !fg[r+1, c]; perim += 1; end
            if c == 1 || !fg[r, c-1]; perim += 1; end
            if c == W || !fg[r, c+1]; perim += 1; end
        end
    end
    
    # Connected components (4-connected) using breadth-first search
    visited = falses(H, W)
    components = 0
    for r in 1:H, c in 1:W
        if fg[r, c] && !visited[r, c]
            components += 1
            queue = [(r, c)]
            visited[r, c] = true
            while !isempty(queue)
                curr_r, curr_c = popfirst!(queue)
                for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)]
                    nr, nc = curr_r + dr, curr_c + dc
                    if 1 <= nr <= H && 1 <= nc <= W && fg[nr, nc] && !visited[nr, nc]
                        visited[nr, nc] = true
                        push!(queue, (nr, nc))
                    end
                end
            end
        end
    end
    
    # Planar Euler Characteristic chi = V - E + F
    # For a digital grid representation:
    # V = number of foreground pixels (vertices)
    # E = number of 4-connected adjacent pairs (edges)
    # F = number of 2x2 solid foreground squares (faces)
    V = area
    E = 0
    for r in 1:H, c in 1:W
        if fg[r, c]
            if r < H && fg[r+1, c]; E += 1; end
            if c < W && fg[r, c+1]; E += 1; end
        end
    end
    F = 0
    for r in 1:H-1, c in 1:W-1
        if fg[r, c] && fg[r+1, c] && fg[r, c+1] && fg[r+1, c+1]
            F += 1
        end
    end
    chi = V - E + F
    
    return MorphologicalProfile(H, W, area, perim, components, chi, colors)
end

function euler_characteristic(profile::MorphologicalProfile)::Int
    return profile.euler_characteristic
end

# ------------------------------------------------------------------------------
# 6. Pedagogical Scaffolding Controller (Wood-Bruner-Ross 6-Function Architecture)
# ------------------------------------------------------------------------------

@enum SearchState Focus Frustration Panic

mutable struct ScaffoldController
    state::SearchState
    frustration_counter::Int
    frustration_threshold::Int
    panic_threshold::Int
    active_tolerance::Float64
    budget_allocated::Int
end

function ScaffoldController(budget::Int = 1000)
    return ScaffoldController(Focus, 0, 5, 12, 1.0, budget)
end

function update_scaffold_state!(sc::ScaffoldController, consecutive_rejections::Int)
    sc.frustration_counter = consecutive_rejections
    if consecutive_rejections >= sc.panic_threshold
        sc.state = Panic
        # In Panic, relax non-essential geometric tolerances
        sc.active_tolerance = 2.5
    elseif consecutive_rejections >= sc.frustration_threshold
        sc.state = Frustration
        # In Frustration, moderately expand search horizon
        sc.active_tolerance = 1.5
    else
        sc.state = Focus
        sc.active_tolerance = 1.0
    end
    return sc.state
end

end # module TransjectionCalculus
