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
export GateViolationCertificate, TransjectVerdict, CriterialVerdict, AbstractVerdict
export Accepted, Rejected, Incomplete
export EvidenceStatus, Witness, Refutation, Unresolved
export AbstractCertificate, AbstractProofTerm, AbstractRefutationTerm
export StructuredProofTerm, StructuredRefutationTerm, GateViolationRefutationTerm
export check_proof_term, check_refutation_term
export evaluate_gate, gate_passed, evaluate_gate_constructive
export conjunction_evidence, disjunction_evidence
export verify_evidence_certificate, verdict_from_evidence, evidence_from_verdict
export AchievementLevel, IMPLEMENTED_INTERFACE, VERIFIED_NUMERICAL_COMPONENT
export VALIDATED_PHYSICAL_MODEL, EXPERIMENTALLY_SUPPORTED_CLAIM
export ScientificClaimAudit, audit_scientific_claim_boundary
export transject, compose_transjections
export MorphologicalProfile, compute_morphology, euler_characteristic
export ScaffoldController, update_scaffold_state!

# ------------------------------------------------------------------------------
# 1. Algebraic Verdict Types (No numeric Inf or -1.0 sentinels)
# ------------------------------------------------------------------------------

abstract type TransjectVerdict end
const CriterialVerdict = TransjectVerdict
const AbstractVerdict = TransjectVerdict

struct Accepted{T} <: TransjectVerdict
    value::T
    salient_features::Vector{Float64}
    empowerment_score::Float64
    detail::String
    function Accepted{T}(
        value::T,
        salient_features::AbstractVector{<:Real},
        empowerment_score::Real,
        detail::AbstractString
    ) where {T}
        sc = Float64(empowerment_score)
        if !isfinite(sc) || sc == -1.0
            throw(ArgumentError("Numeric sentinel leakage (Inf/NaN/-1.0) forbidden in Accepted."))
        end
        return new{T}(value, Float64[Float64(v) for v in salient_features], sc, String(detail))
    end
end

function Accepted(
    value::T,
    salient_features::AbstractVector{<:Real},
    empowerment_score::Real,
    detail::AbstractString
) where {T}
    return Accepted{T}(value, salient_features, empowerment_score, detail)
end

function Base.getproperty(v::Accepted, sym::Symbol)
    if sym === :score
        return getfield(v, :empowerment_score)
    end
    return getfield(v, sym)
end

struct GateViolationCertificate
    gate_name::Symbol
    pair_index::Int
    cell_residual::Float64
    violation_coord::Tuple{Int, Int}
    function GateViolationCertificate(
        gate_name::Symbol,
        pair_index::Int,
        cell_residual::Real,
        violation_coord::Tuple{Int, Int} = (0, 0)
    )
        cr = Float64(cell_residual)
        if !isfinite(cr) || cr < 0.0
            throw(ArgumentError("GateViolationCertificate cell_residual must be finite and non-negative."))
        end
        return new(gate_name, pair_index, cr, violation_coord)
    end
end

struct Rejected <: TransjectVerdict
    reason::Symbol
    detail::String
    failed_gate_indices::Vector{Int}
    failed_gates::Vector{Symbol}
    partial_score::Float64
    violation_certificates::Vector{GateViolationCertificate}
    function Rejected(
        reason::Symbol,
        detail::AbstractString,
        failed_gate_indices::Vector{Int},
        failed_gates::Vector{Symbol},
        partial_score::Real = 0.0,
        violation_certificates::Vector{GateViolationCertificate} = GateViolationCertificate[]
    )
        ps = Float64(partial_score)
        if !isfinite(ps) || ps == -1.0
            throw(ArgumentError("Numeric sentinel leakage (Inf/NaN/-1.0) forbidden in Rejected."))
        end
        return new(
            reason,
            String(detail),
            copy(failed_gate_indices),
            copy(failed_gates),
            ps,
            copy(violation_certificates)
        )
    end
end

function Rejected(reason::Symbol, detail::AbstractString, failed_gate_indices::Vector{Int}, partial_score::Real = 0.0)
    return Rejected(reason, detail, failed_gate_indices, Symbol[], partial_score, GateViolationCertificate[])
end

function Rejected(reason::Symbol, detail::AbstractString, failed_gates::Vector{Symbol}, partial_score::Real = 0.0)
    return Rejected(reason, detail, Int[], failed_gates, partial_score, GateViolationCertificate[])
end

function Rejected(
    reason::Symbol,
    detail::AbstractString,
    failed_gates::Vector{Symbol},
    violation_certificates::Vector{GateViolationCertificate},
    partial_score::Real = 0.0
)
    return Rejected(reason, detail, Int[], failed_gates, partial_score, violation_certificates)
end

struct Incomplete <: TransjectVerdict
    reason::Symbol
    detail::String
    missing_prerequisites::Vector{Symbol}
    function Incomplete(
        reason::Symbol,
        detail::AbstractString,
        missing_prerequisites::Vector{Symbol} = Symbol[reason]
    )
        return new(reason, String(detail), copy(missing_prerequisites))
    end
end

# ------------------------------------------------------------------------------
# 1b. Constructive Proof-Certificate Hierarchy (BHK Evidence Calculus)
# ------------------------------------------------------------------------------

@enum AchievementLevel begin
    IMPLEMENTED_INTERFACE = 1
    VERIFIED_NUMERICAL_COMPONENT = 2
    VALIDATED_PHYSICAL_MODEL = 3
    EXPERIMENTALLY_SUPPORTED_CLAIM = 4
end

abstract type EvidenceStatus end

abstract type AbstractCertificate end
abstract type AbstractProofTerm <: AbstractCertificate end
abstract type AbstractRefutationTerm <: AbstractCertificate end

function _freeze_certificate_value(x::AbstractArray)
    if isempty(x)
        return Array{eltype(x), ndims(x)}(undef, size(x))
    end
    frozen_elems = [_freeze_certificate_value(v) for v in x]
    if all(v -> v isa eltype(x), frozen_elems)
        out = Array{eltype(x), ndims(x)}(undef, size(x))
        for (i, v) in enumerate(frozen_elems)
            out[i] = v
        end
        return out
    end
    return reshape(frozen_elems, size(x))
end

function _freeze_certificate_value(x::AbstractDict{K, V}) where {K, V}
    out = Dict{K, V}()
    for (k, v) in x
        out[_freeze_certificate_value(k)] = _freeze_certificate_value(v)
    end
    return out
end

function _freeze_certificate_value(x::AbstractSet{T}) where {T}
    return Set{T}(_freeze_certificate_value(v) for v in x)
end

function _freeze_certificate_value(x::NamedTuple{N}) where {N}
    return NamedTuple{N}(Tuple(_freeze_certificate_value(v) for v in values(x)))
end

_freeze_certificate_value(x::Tuple) = Tuple(_freeze_certificate_value(v) for v in x)
_freeze_certificate_value(x) = x

function _certificate_structural_seal(x::NamedTuple, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    h = hash(:NamedTuple, h)
    for (k, v) in pairs(x)
        h = hash(k, h)
        h = _certificate_structural_seal(v, h)
    end
    return h
end

function _certificate_structural_seal(x::Tuple, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    h = hash(:Tuple, h)
    h = hash(length(x), h)
    for v in x
        h = _certificate_structural_seal(v, h)
    end
    return h
end

function _certificate_structural_seal(x::AbstractArray, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    h = hash(:AbstractArray, h)
    h = hash(typeof(x), h)
    h = hash(size(x), h)
    for v in x
        h = _certificate_structural_seal(v, h)
    end
    return h
end

function _certificate_structural_seal(x::AbstractDict, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    h = hash(:AbstractDict, h)
    h = hash(typeof(x), h)
    h = hash(length(x), h)
    acc = UInt(0)
    for (k, v) in x
        acc ⊻= _certificate_structural_seal(v, _certificate_structural_seal(k, UInt(0x517cc1b727220a95)))
    end
    return hash(acc, h)
end

function _certificate_structural_seal(x::AbstractSet, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    h = hash(:AbstractSet, h)
    h = hash(typeof(x), h)
    h = hash(length(x), h)
    acc = UInt(0)
    for v in x
        acc ⊻= _certificate_structural_seal(v, UInt(0x517cc1b727220a95))
    end
    return hash(acc, h)
end

function _certificate_structural_seal(x::GateViolationCertificate, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    h = hash(:GateViolationCertificate, h)
    h = hash(x.gate_name, h)
    h = hash(x.pair_index, h)
    h = hash(reinterpret(UInt64, x.cell_residual), h)
    h = hash(x.violation_coord, h)
    return h
end

function _certificate_structural_seal(x::AbstractFloat, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    return hash(typeof(x), hash(reinterpret(UInt64, Float64(x)), h))
end

_certificate_structural_seal(x, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt = hash(typeof(x), hash(x, h))

struct StructuredProofTerm{NT <: NamedTuple} <: AbstractProofTerm
    payload::NT
    _seal::UInt
    function StructuredProofTerm{NT}(payload::NamedTuple) where {NT <: NamedTuple}
        if isempty(payload)
            throw(ArgumentError("StructuredProofTerm payload cannot be an empty NamedTuple."))
        end
        frozen = _freeze_certificate_value(payload)
        if !(frozen isa NT)
            throw(ArgumentError("Frozen payload type $(typeof(frozen)) does not match type parameter $(NT)."))
        end
        return new{NT}(frozen, _certificate_structural_seal(frozen))
    end
    function StructuredProofTerm(payload::NamedTuple)
        if isempty(payload)
            throw(ArgumentError("StructuredProofTerm payload cannot be an empty NamedTuple."))
        end
        frozen = _freeze_certificate_value(payload)
        return new{typeof(frozen)}(frozen, _certificate_structural_seal(frozen))
    end
end
StructuredProofTerm(; kwargs...) = StructuredProofTerm((; kwargs...))

Base.getproperty(t::StructuredProofTerm, sym::Symbol) =
    sym === :payload ? _freeze_certificate_value(getfield(t, :payload)) :
    sym === :_seal ? getfield(t, :_seal) :
    _freeze_certificate_value(getproperty(getfield(t, :payload), sym))
Base.propertynames(t::StructuredProofTerm, private::Bool = false) =
    private ? (propertynames(getfield(t, :payload), true)..., :payload, :_seal) : propertynames(getfield(t, :payload), false)
Base.haskey(t::StructuredProofTerm, key::Symbol) = haskey(getfield(t, :payload), key)
Base.get(t::StructuredProofTerm, key::Symbol, default) = _freeze_certificate_value(get(getfield(t, :payload), key, default))
Base.getindex(t::StructuredProofTerm, key::Symbol) = getproperty(t, key)
Base.getindex(t::StructuredProofTerm, i::Integer) = _freeze_certificate_value(getindex(getfield(t, :payload), i))
Base.keys(t::StructuredProofTerm) = keys(getfield(t, :payload))
Base.values(t::StructuredProofTerm) = _freeze_certificate_value(values(getfield(t, :payload)))
Base.isempty(t::StructuredProofTerm) = isempty(getfield(t, :payload))
Base.:(==)(a::StructuredProofTerm, b::StructuredProofTerm) = getfield(a, :payload) == getfield(b, :payload)
Base.:(==)(a::StructuredProofTerm, b::NamedTuple) = getfield(a, :payload) == b
Base.:(==)(a::NamedTuple, b::StructuredProofTerm) = a == getfield(b, :payload)
Base.hash(a::StructuredProofTerm, h::UInt) = hash(getfield(a, :payload), h)

struct StructuredRefutationTerm{NT <: NamedTuple} <: AbstractRefutationTerm
    payload::NT
    _seal::UInt
    function StructuredRefutationTerm{NT}(payload::NamedTuple) where {NT <: NamedTuple}
        if isempty(payload)
            throw(ArgumentError("StructuredRefutationTerm payload cannot be an empty NamedTuple."))
        end
        frozen = _freeze_certificate_value(payload)
        if !(frozen isa NT)
            throw(ArgumentError("Frozen payload type $(typeof(frozen)) does not match type parameter $(NT)."))
        end
        return new{NT}(frozen, _certificate_structural_seal(frozen))
    end
    function StructuredRefutationTerm(payload::NamedTuple)
        if isempty(payload)
            throw(ArgumentError("StructuredRefutationTerm payload cannot be an empty NamedTuple."))
        end
        frozen = _freeze_certificate_value(payload)
        return new{typeof(frozen)}(frozen, _certificate_structural_seal(frozen))
    end
end
StructuredRefutationTerm(; kwargs...) = StructuredRefutationTerm((; kwargs...))

Base.getproperty(t::StructuredRefutationTerm, sym::Symbol) =
    sym === :payload ? _freeze_certificate_value(getfield(t, :payload)) :
    sym === :_seal ? getfield(t, :_seal) :
    _freeze_certificate_value(getproperty(getfield(t, :payload), sym))
Base.propertynames(t::StructuredRefutationTerm, private::Bool = false) =
    private ? (propertynames(getfield(t, :payload), true)..., :payload, :_seal) : propertynames(getfield(t, :payload), false)
Base.haskey(t::StructuredRefutationTerm, key::Symbol) = haskey(getfield(t, :payload), key)
Base.get(t::StructuredRefutationTerm, key::Symbol, default) = _freeze_certificate_value(get(getfield(t, :payload), key, default))
Base.getindex(t::StructuredRefutationTerm, key::Symbol) = getproperty(t, key)
Base.getindex(t::StructuredRefutationTerm, i::Integer) = _freeze_certificate_value(getindex(getfield(t, :payload), i))
Base.keys(t::StructuredRefutationTerm) = keys(getfield(t, :payload))
Base.values(t::StructuredRefutationTerm) = _freeze_certificate_value(values(getfield(t, :payload)))
Base.isempty(t::StructuredRefutationTerm) = isempty(getfield(t, :payload))
Base.:(==)(a::StructuredRefutationTerm, b::StructuredRefutationTerm) = getfield(a, :payload) == getfield(b, :payload)
Base.:(==)(a::StructuredRefutationTerm, b::NamedTuple) = getfield(a, :payload) == b
Base.:(==)(a::NamedTuple, b::StructuredRefutationTerm) = a == getfield(b, :payload)
Base.hash(a::StructuredRefutationTerm, h::UInt) = hash(getfield(a, :payload), h)

struct GateViolationRefutationTerm <: AbstractRefutationTerm
    violation::GateViolationCertificate
end
Base.getproperty(t::GateViolationRefutationTerm, sym::Symbol) =
    sym === :violation ? getfield(t, :violation) : getproperty(getfield(t, :violation), sym)
Base.propertynames(t::GateViolationRefutationTerm, private::Bool = false) =
    propertynames(getfield(t, :violation), private)
Base.haskey(::GateViolationRefutationTerm, key::Symbol) =
    key in (:gate_name, :pair_index, :cell_residual, :violation_coord)
Base.:(==)(a::GateViolationRefutationTerm, b::GateViolationRefutationTerm) =
    getfield(a, :violation) == getfield(b, :violation)
Base.hash(a::GateViolationRefutationTerm, h::UInt) = hash(getfield(a, :violation), h)

struct Witness{T, C <: AbstractProofTerm} <: EvidenceStatus
    proposition::T
    certificate::C
    _proposition_seal::UInt
    function Witness{T, C}(proposition::T, certificate::C) where {T, C <: AbstractProofTerm}
        raw_frozen = _freeze_certificate_value(proposition)
        frozen_prop = raw_frozen isa T ? raw_frozen : proposition
        if !check_proof_term(frozen_prop, certificate)
            throw(ArgumentError("Invalid or mismatched proof term for Witness($(repr(proposition))): certificate failed independent re-derivation."))
        end
        return new{T, C}(frozen_prop, certificate, _certificate_structural_seal(frozen_prop))
    end
end

function Base.getproperty(w::Witness, sym::Symbol)
    if sym === :proposition
        return _freeze_certificate_value(getfield(w, :proposition))
    end
    return getfield(w, sym)
end

Witness(proposition::T, certificate::C) where {T, C <: AbstractProofTerm} =
    Witness{T, C}(proposition, certificate)
Witness{T}(proposition::T, certificate::C) where {T, C <: AbstractProofTerm} =
    Witness{T, C}(proposition, certificate)
function Witness(proposition::T, payload::NamedTuple) where {T}
    term = StructuredProofTerm(payload)
    return Witness{T, typeof(term)}(proposition, term)
end
function Witness{T}(proposition::T, payload::NamedTuple) where {T}
    term = StructuredProofTerm(payload)
    return Witness{T, typeof(term)}(proposition, term)
end
function Witness(proposition, invalid)
    throw(ArgumentError("Witness requires a verifiable AbstractProofTerm that re-derives proposition $(repr(proposition)); got $(typeof(invalid))."))
end
function Witness{T}(proposition::T, invalid) where {T}
    throw(ArgumentError("Witness requires a verifiable AbstractProofTerm that re-derives proposition $(repr(proposition)); got $(typeof(invalid))."))
end

struct Refutation{T, C <: AbstractRefutationTerm} <: EvidenceStatus
    proposition::T
    countercertificate::C
    _proposition_seal::UInt
    function Refutation{T, C}(proposition::T, countercertificate::C) where {T, C <: AbstractRefutationTerm}
        raw_frozen = _freeze_certificate_value(proposition)
        frozen_prop = raw_frozen isa T ? raw_frozen : proposition
        if !check_refutation_term(frozen_prop, countercertificate)
            throw(ArgumentError("Invalid or mismatched refutation term for Refutation($(repr(proposition))): countercertificate failed independent re-derivation."))
        end
        return new{T, C}(frozen_prop, countercertificate, _certificate_structural_seal(frozen_prop))
    end
end

function Base.getproperty(r::Refutation, sym::Symbol)
    if sym === :proposition
        return _freeze_certificate_value(getfield(r, :proposition))
    end
    return getfield(r, sym)
end

Refutation(proposition::T, countercertificate::C) where {T, C <: AbstractRefutationTerm} =
    Refutation{T, C}(proposition, countercertificate)
Refutation{T}(proposition::T, countercertificate::C) where {T, C <: AbstractRefutationTerm} =
    Refutation{T, C}(proposition, countercertificate)
function Refutation(proposition::T, payload::NamedTuple) where {T}
    term = StructuredRefutationTerm(payload)
    return Refutation{T, typeof(term)}(proposition, term)
end
function Refutation{T}(proposition::T, payload::NamedTuple) where {T}
    term = StructuredRefutationTerm(payload)
    return Refutation{T, typeof(term)}(proposition, term)
end
function Refutation(proposition::T, cert::GateViolationCertificate) where {T}
    term = GateViolationRefutationTerm(cert)
    return Refutation{T, GateViolationRefutationTerm}(proposition, term)
end
function Refutation{T}(proposition::T, cert::GateViolationCertificate) where {T}
    term = GateViolationRefutationTerm(cert)
    return Refutation{T, GateViolationRefutationTerm}(proposition, term)
end
function Refutation(proposition, invalid)
    throw(ArgumentError("Refutation requires a verifiable AbstractRefutationTerm that refutes proposition $(repr(proposition)); got $(typeof(invalid))."))
end
function Refutation{T}(proposition::T, invalid) where {T}
    throw(ArgumentError("Refutation requires a verifiable AbstractRefutationTerm that refutes proposition $(repr(proposition)); got $(typeof(invalid))."))
end

struct Unresolved{T} <: EvidenceStatus
    proposition::T
    missing_prerequisites::Vector{Symbol}
    _sealed_prerequisites::Tuple{Vararg{Symbol}}
    _proposition_seal::UInt
    function Unresolved{T}(proposition::T, missing_prerequisites::Vector{Symbol}) where {T}
        if isempty(missing_prerequisites) || any(s -> s === Symbol(""), missing_prerequisites)
            throw(ArgumentError("Unresolved requires at least one non-empty missing prerequisite symbol."))
        end
        raw_frozen = _freeze_certificate_value(proposition)
        frozen_prop = raw_frozen isa T ? raw_frozen : proposition
        cloned = copy(missing_prerequisites)
        return new{T}(frozen_prop, cloned, Tuple(cloned), _certificate_structural_seal(frozen_prop))
    end
end

function Base.getproperty(u::Unresolved, sym::Symbol)
    if sym === :missing_prerequisites
        return Symbol[getfield(u, :_sealed_prerequisites)...]
    elseif sym === :proposition
        return _freeze_certificate_value(getfield(u, :proposition))
    end
    return getfield(u, sym)
end

function Unresolved(proposition::T, missing_prerequisites::Vector{Symbol}) where {T}
    return Unresolved{T}(proposition, missing_prerequisites)
end

function Unresolved(proposition::T, missing_prerequisites::AbstractVector) where {T}
    return Unresolved{T}(proposition, Symbol[Symbol(s) for s in missing_prerequisites])
end

function Unresolved(proposition::T, missing_prerequisite::Symbol) where {T}
    return Unresolved{T}(proposition, Symbol[missing_prerequisite])
end

function _certificate_structural_seal(x::StructuredProofTerm, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    h = hash(:StructuredProofTerm, h)
    h = hash(getfield(x, :_seal), h)
    return _certificate_structural_seal(getfield(x, :payload), h)
end

function _certificate_structural_seal(x::StructuredRefutationTerm, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    h = hash(:StructuredRefutationTerm, h)
    h = hash(getfield(x, :_seal), h)
    return _certificate_structural_seal(getfield(x, :payload), h)
end

function _certificate_structural_seal(x::GateViolationRefutationTerm, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    return _certificate_structural_seal(getfield(x, :violation), hash(:GateViolationRefutationTerm, h))
end

function _certificate_structural_seal(x::Witness, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    h = hash(:Witness, h)
    h = hash(getfield(x, :_proposition_seal), h)
    h = _certificate_structural_seal(getfield(x, :proposition), h)
    return _certificate_structural_seal(getfield(x, :certificate), h)
end

function _certificate_structural_seal(x::Refutation, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    h = hash(:Refutation, h)
    h = hash(getfield(x, :_proposition_seal), h)
    h = _certificate_structural_seal(getfield(x, :proposition), h)
    return _certificate_structural_seal(getfield(x, :countercertificate), h)
end

function _certificate_structural_seal(x::Unresolved, h::UInt = UInt(0x9e3779b97f4a7c15))::UInt
    h = hash(:Unresolved, h)
    h = hash(getfield(x, :_proposition_seal), h)
    h = _certificate_structural_seal(getfield(x, :proposition), h)
    h = _certificate_structural_seal(getfield(x, :missing_prerequisites), h)
    return _certificate_structural_seal(getfield(x, :_sealed_prerequisites), h)
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
# 2b. Constructive Gate Evaluation and BHK Combinators
# ------------------------------------------------------------------------------

function _missing_prerequisites(prerequisites, available_prerequisites)::Vector{Symbol}
    avail_set = Set{Symbol}(Symbol(a) for a in available_prerequisites)
    missing = Symbol[]
    for p in prerequisites
        ps = Symbol(p)
        if !(ps in avail_set) && !(ps in missing)
            push!(missing, ps)
        end
    end
    return missing
end

function evaluate_gate_constructive(
    g::ThresholdGate,
    x;
    prerequisites = Symbol[],
    available_prerequisites = Symbol[],
    proposition = nothing
)::EvidenceStatus
    prop = proposition === nothing ? g.name : proposition
    missing_prereqs = _missing_prerequisites(prerequisites, available_prerequisites)
    if !isempty(missing_prereqs)
        return Unresolved(prop, missing_prereqs)
    end
    if x === missing || x === nothing
        return Unresolved(prop, Symbol[:missing_input])
    end
    raw_val = try
        g.functional(x)
    catch
        return Unresolved(prop, Symbol[:evaluation_exception])
    end
    if raw_val === missing || raw_val === nothing || !(raw_val isa Real)
        return Unresolved(prop, Symbol[:missing_measurement])
    end
    val = Float64(raw_val)
    thresh = Float64(g.threshold)
    if !isfinite(val) || !isfinite(thresh)
        return Unresolved(prop, Symbol[:nonfinite_measurement])
    end
    if val >= thresh
        cert = StructuredProofTerm((
            gate_type = :threshold,
            proposition = prop,
            gate_name = g.name,
            measured_value = val,
            threshold = thresh,
            comparison = :>=,
            margin = val - thresh,
            verified = true
        ))
        return Witness(prop, cert)
    else
        countercert = StructuredRefutationTerm((
            gate_type = :threshold,
            proposition = prop,
            gate_name = g.name,
            measured_value = val,
            threshold = thresh,
            comparison = :<,
            deficit = thresh - val,
            refuted = true
        ))
        return Refutation(prop, countercert)
    end
end

function evaluate_gate_constructive(
    g::BandpassGate,
    x;
    prerequisites = Symbol[],
    available_prerequisites = Symbol[],
    proposition = nothing
)::EvidenceStatus
    prop = proposition === nothing ? g.name : proposition
    missing_prereqs = _missing_prerequisites(prerequisites, available_prerequisites)
    if !isempty(missing_prereqs)
        return Unresolved(prop, missing_prereqs)
    end
    if x === missing || x === nothing
        return Unresolved(prop, Symbol[:missing_input])
    end
    raw_val = try
        g.functional(x)
    catch
        return Unresolved(prop, Symbol[:evaluation_exception])
    end
    if raw_val === missing || raw_val === nothing || !(raw_val isa Real)
        return Unresolved(prop, Symbol[:missing_measurement])
    end
    val = Float64(raw_val)
    lo = Float64(g.low)
    hi = Float64(g.high)
    if !isfinite(val) || !isfinite(lo) || !isfinite(hi)
        return Unresolved(prop, Symbol[:nonfinite_measurement])
    end
    if lo > hi
        return Unresolved(prop, Symbol[:invalid_bandpass_bounds])
    end
    if lo <= val <= hi
        cert = StructuredProofTerm((
            gate_type = :bandpass,
            proposition = prop,
            gate_name = g.name,
            measured_value = val,
            low = lo,
            high = hi,
            margin_low = val - lo,
            margin_high = hi - val,
            verified = true
        ))
        return Witness(prop, cert)
    else
        violation = val < lo ? :below_low : :above_high
        deficit = val < lo ? (lo - val) : (val - hi)
        countercert = StructuredRefutationTerm((
            gate_type = :bandpass,
            proposition = prop,
            gate_name = g.name,
            measured_value = val,
            low = lo,
            high = hi,
            violation = violation,
            deficit = deficit,
            refuted = true
        ))
        return Refutation(prop, countercert)
    end
end

function evaluate_gate_constructive(
    g::SubtypeGate{OutT, InT},
    x = nothing;
    prerequisites = Symbol[],
    available_prerequisites = Symbol[],
    proposition = nothing
)::EvidenceStatus where {OutT, InT}
    prop = proposition === nothing ? g.name : proposition
    missing_prereqs = _missing_prerequisites(prerequisites, available_prerequisites)
    if !isempty(missing_prereqs)
        return Unresolved(prop, missing_prereqs)
    end
    if OutT <: InT
        cert = StructuredProofTerm((
            gate_type = :subtype,
            proposition = prop,
            gate_name = g.name,
            out_type = OutT,
            in_type = InT,
            relation = :(Out <: In),
            verified = true
        ))
        return Witness(prop, cert)
    else
        countercert = StructuredRefutationTerm((
            gate_type = :subtype,
            proposition = prop,
            gate_name = g.name,
            out_type = OutT,
            in_type = InT,
            relation = :(!(Out <: In)),
            refuted = true
        ))
        return Refutation(prop, countercert)
    end
end

function evaluate_gate_constructive(
    g::ConjunctionGate,
    x;
    prerequisites = Symbol[],
    available_prerequisites = Symbol[],
    proposition = nothing
)::EvidenceStatus
    prop = proposition === nothing ? g.name : proposition
    missing_prereqs = _missing_prerequisites(prerequisites, available_prerequisites)
    if !isempty(missing_prereqs)
        return Unresolved(prop, missing_prereqs)
    end
    child_evs = EvidenceStatus[
        evaluate_gate_constructive(
            sub,
            x;
            prerequisites = prerequisites,
            available_prerequisites = available_prerequisites
        ) for sub in g.gates
    ]
    failed_idxs = Int[i for (i, ev) in enumerate(child_evs) if ev isa Refutation]
    if !isempty(failed_idxs)
        countercert = StructuredRefutationTerm((
            gate_type = :conjunction,
            proposition = prop,
            gate_name = g.name,
            child_evidence = child_evs,
            failed_indices = failed_idxs,
            failed_countercertificates = Any[child_evs[i].countercertificate for i in failed_idxs],
            refuted = true
        ))
        return Refutation(prop, countercert)
    end
    unresolved_idxs = Int[i for (i, ev) in enumerate(child_evs) if ev isa Unresolved]
    if !isempty(unresolved_idxs)
        combined_missing = Symbol[]
        for i in unresolved_idxs
            for s in child_evs[i].missing_prerequisites
                if !(s in combined_missing)
                    push!(combined_missing, s)
                end
            end
        end
        return Unresolved(prop, combined_missing)
    end
    cert = StructuredProofTerm((
        gate_type = :conjunction,
        proposition = prop,
        gate_name = g.name,
        child_evidence = child_evs,
        child_certificates = Any[ev.certificate for ev in child_evs],
        verified = true
    ))
    return Witness(prop, cert)
end

function evaluate_gate_constructive(
    g::DisjunctionGate,
    x;
    prerequisites = Symbol[],
    available_prerequisites = Symbol[],
    proposition = nothing
)::EvidenceStatus
    prop = proposition === nothing ? g.name : proposition
    missing_prereqs = _missing_prerequisites(prerequisites, available_prerequisites)
    if !isempty(missing_prereqs)
        return Unresolved(prop, missing_prereqs)
    end
    if isempty(g.gates)
        countercert = StructuredRefutationTerm((
            gate_type = :disjunction,
            proposition = prop,
            gate_name = g.name,
            child_evidence = EvidenceStatus[],
            failed_countercertificates = Any[],
            refuted = true
        ))
        return Refutation(prop, countercert)
    end
    child_evs = EvidenceStatus[
        evaluate_gate_constructive(
            sub,
            x;
            prerequisites = prerequisites,
            available_prerequisites = available_prerequisites
        ) for sub in g.gates
    ]
    witness_idxs = Int[i for (i, ev) in enumerate(child_evs) if ev isa Witness]
    if !isempty(witness_idxs)
        idx = first(witness_idxs)
        inj = idx == 1 ? :left : (idx == 2 ? :right : Symbol("branch_$(idx)"))
        cert = StructuredProofTerm((
            gate_type = :disjunction,
            proposition = prop,
            gate_name = g.name,
            branch_index = idx,
            injection = inj,
            witness_certificate = child_evs[idx].certificate,
            child_evidence = child_evs,
            verified = true
        ))
        return Witness(prop, cert)
    end
    unresolved_idxs = Int[i for (i, ev) in enumerate(child_evs) if ev isa Unresolved]
    if !isempty(unresolved_idxs)
        combined_missing = Symbol[]
        for i in unresolved_idxs
            for s in child_evs[i].missing_prerequisites
                if !(s in combined_missing)
                    push!(combined_missing, s)
                end
            end
        end
        return Unresolved(prop, combined_missing)
    end
    countercert = StructuredRefutationTerm((
        gate_type = :disjunction,
        proposition = prop,
        gate_name = g.name,
        child_evidence = child_evs,
        failed_countercertificates = Any[ev.countercertificate for ev in child_evs],
        refuted = true
    ))
    return Refutation(prop, countercert)
end

function evaluate_gate_constructive(
    g::KOfNGate,
    x;
    prerequisites = Symbol[],
    available_prerequisites = Symbol[],
    proposition = nothing
)::EvidenceStatus
    prop = proposition === nothing ? g.name : proposition
    missing_prereqs = _missing_prerequisites(prerequisites, available_prerequisites)
    if !isempty(missing_prereqs)
        return Unresolved(prop, missing_prereqs)
    end
    if g.k < 0
        return Unresolved(prop, Symbol[:invalid_k_of_n_parameter])
    end
    child_evs = EvidenceStatus[
        evaluate_gate_constructive(
            sub,
            x;
            prerequisites = prerequisites,
            available_prerequisites = available_prerequisites
        ) for sub in g.gates
    ]
    n = length(g.gates)
    w_idxs = Int[i for (i, ev) in enumerate(child_evs) if ev isa Witness]
    r_idxs = Int[i for (i, ev) in enumerate(child_evs) if ev isa Refutation]
    u_idxs = Int[i for (i, ev) in enumerate(child_evs) if ev isa Unresolved]

    if length(w_idxs) >= g.k
        cert = StructuredProofTerm((
            gate_type = :k_of_n,
            proposition = prop,
            gate_name = g.name,
            k = g.k,
            n = n,
            passed_count = length(w_idxs),
            witness_indices = w_idxs,
            witness_certificates = Any[child_evs[i].certificate for i in w_idxs],
            child_evidence = child_evs,
            verified = true
        ))
        return Witness(prop, cert)
    elseif length(w_idxs) + length(u_idxs) < g.k
        countercert = StructuredRefutationTerm((
            gate_type = :k_of_n,
            proposition = prop,
            gate_name = g.name,
            k = g.k,
            n = n,
            passed_count = length(w_idxs),
            refuted_count = length(r_idxs),
            failed_indices = r_idxs,
            failed_countercertificates = Any[child_evs[i].countercertificate for i in r_idxs],
            child_evidence = child_evs,
            refuted = true
        ))
        return Refutation(prop, countercert)
    else
        combined_missing = Symbol[]
        for i in u_idxs
            for s in child_evs[i].missing_prerequisites
                if !(s in combined_missing)
                    push!(combined_missing, s)
                end
            end
        end
        return Unresolved(prop, combined_missing)
    end
end

function evaluate_gate_constructive(
    g::AbstractCriterialGate,
    x;
    prerequisites = Symbol[],
    available_prerequisites = Symbol[],
    proposition = nothing
)::EvidenceStatus
    prop = proposition === nothing ? (hasproperty(g, :name) ? g.name : Symbol(typeof(g))) : proposition
    missing_prereqs = _missing_prerequisites(prerequisites, available_prerequisites)
    if !isempty(missing_prereqs)
        return Unresolved(prop, missing_prereqs)
    end
    if x === missing || x === nothing
        return Unresolved(prop, Symbol[:missing_input])
    end
    eval_res = try
        evaluate_gate(g, x)
    catch
        return Unresolved(prop, Symbol[:evaluation_exception])
    end
    passed, score, msg = eval_res
    sc = Float64(score)
    if !isfinite(sc) || sc == -1.0
        return Unresolved(prop, Symbol[:nonfinite_measurement])
    end
    if passed
        cert = StructuredProofTerm((
            gate_type = :custom,
            proposition = prop,
            gate_name = string(prop),
            measured_value = sc,
            detail = String(msg),
            recheck = () -> first(evaluate_gate(g, x)) === true,
            verified = true
        ))
        return Witness(prop, cert)
    else
        countercert = StructuredRefutationTerm((
            gate_type = :custom,
            proposition = prop,
            gate_name = string(prop),
            measured_value = sc,
            detail = String(msg),
            recheck = () -> first(evaluate_gate(g, x)) === false,
            refuted = true
        ))
        return Refutation(prop, countercert)
    end
end

# Brouwer-Heyting-Kolmogorov (BHK) constructive combinators
function conjunction_evidence(
    e1::EvidenceStatus,
    e2::EvidenceStatus;
    proposition = nothing
)::EvidenceStatus
    prop = proposition === nothing ? (e1.proposition, e2.proposition) : proposition
    if e1 isa Witness && e2 isa Witness
        cert = StructuredProofTerm((
            combinator = :conjunction,
            proposition = prop,
            left = e1.certificate,
            right = e2.certificate,
            left_evidence = e1,
            right_evidence = e2,
            verified = true
        ))
        return Witness(prop, cert)
    elseif e1 isa Refutation && e2 isa Refutation
        countercert = StructuredRefutationTerm((
            combinator = :conjunction,
            proposition = prop,
            failed_branch = :both,
            left = e1.countercertificate,
            right = e2.countercertificate,
            left_evidence = e1,
            right_evidence = e2,
            refuted = true
        ))
        return Refutation(prop, countercert)
    elseif e1 isa Refutation
        countercert = StructuredRefutationTerm((
            combinator = :conjunction,
            proposition = prop,
            failed_branch = :left,
            countercertificate = e1.countercertificate,
            left_evidence = e1,
            right_evidence = e2,
            refuted = true
        ))
        return Refutation(prop, countercert)
    elseif e2 isa Refutation
        countercert = StructuredRefutationTerm((
            combinator = :conjunction,
            proposition = prop,
            failed_branch = :right,
            countercertificate = e2.countercertificate,
            left_evidence = e1,
            right_evidence = e2,
            refuted = true
        ))
        return Refutation(prop, countercert)
    else
        missing_prereqs = Symbol[]
        if e1 isa Unresolved
            for s in e1.missing_prerequisites
                if !(s in missing_prereqs)
                    push!(missing_prereqs, s)
                end
            end
        end
        if e2 isa Unresolved
            for s in e2.missing_prerequisites
                if !(s in missing_prereqs)
                    push!(missing_prereqs, s)
                end
            end
        end
        return Unresolved(prop, missing_prereqs)
    end
end

function conjunction_evidence(
    e1::EvidenceStatus,
    e2::EvidenceStatus,
    rest::EvidenceStatus...
)::EvidenceStatus
    return foldl(conjunction_evidence, (e1, e2, rest...))
end

function disjunction_evidence(
    e1::EvidenceStatus,
    e2::EvidenceStatus;
    proposition = nothing
)::EvidenceStatus
    prop = proposition === nothing ? (e1.proposition, e2.proposition) : proposition
    if e1 isa Witness
        cert = StructuredProofTerm((
            combinator = :disjunction,
            proposition = prop,
            injection = :left,
            certificate = e1.certificate,
            witness_evidence = e1,
            left_evidence = e1,
            right_evidence = e2,
            verified = true
        ))
        return Witness(prop, cert)
    elseif e2 isa Witness
        cert = StructuredProofTerm((
            combinator = :disjunction,
            proposition = prop,
            injection = :right,
            certificate = e2.certificate,
            witness_evidence = e2,
            left_evidence = e1,
            right_evidence = e2,
            verified = true
        ))
        return Witness(prop, cert)
    elseif e1 isa Refutation && e2 isa Refutation
        countercert = StructuredRefutationTerm((
            combinator = :disjunction,
            proposition = prop,
            left = e1.countercertificate,
            right = e2.countercertificate,
            left_evidence = e1,
            right_evidence = e2,
            refuted = true
        ))
        return Refutation(prop, countercert)
    else
        missing_prereqs = Symbol[]
        if e1 isa Unresolved
            for s in e1.missing_prerequisites
                if !(s in missing_prereqs)
                    push!(missing_prereqs, s)
                end
            end
        end
        if e2 isa Unresolved
            for s in e2.missing_prerequisites
                if !(s in missing_prereqs)
                    push!(missing_prereqs, s)
                end
            end
        end
        return Unresolved(prop, missing_prereqs)
    end
end

function disjunction_evidence(
    e1::EvidenceStatus,
    e2::EvidenceStatus,
    rest::EvidenceStatus...
)::EvidenceStatus
    return foldl(disjunction_evidence, (e1, e2, rest...))
end

# Independent proof-term and refutation-term re-derivation checkers
_is_numeric_real(x)::Bool = (x isa Real) && !(x isa Bool) && isfinite(x)
_is_index_int(x)::Bool = (x isa Integer) && !(x isa Bool)

function _proposition_matches(proposition, payload::NamedTuple)::Bool
    if haskey(payload, :proposition) && payload.proposition != proposition
        return false
    end
    if haskey(payload, :claim) && payload.claim != proposition
        return false
    end
    if !haskey(payload, :proposition) && (proposition isa Union{AbstractString, Symbol}) &&
       haskey(payload, :gate_name) && (payload.gate_name isa Union{AbstractString, Symbol})
        gate_str = String(payload.gate_name)
        if !isempty(gate_str) && gate_str != String(proposition)
            return false
        end
    end
    if haskey(payload, :combinator)
        if !haskey(payload, :proposition) && !(proposition isa Tuple && length(proposition) == 2)
            return false
        end
        if proposition isa Tuple && length(proposition) == 2
            if haskey(payload, :left_evidence) && (payload.left_evidence isa EvidenceStatus)
                if payload.left_evidence.proposition != proposition[1]
                    return false
                end
            end
            if haskey(payload, :right_evidence) && (payload.right_evidence isa EvidenceStatus)
                if payload.right_evidence.proposition != proposition[2]
                    return false
                end
            end
            if payload.combinator === :disjunction &&
               haskey(payload, :witness_evidence) && (payload.witness_evidence isa EvidenceStatus)
                inj = get(payload, :injection, nothing)
                if inj === :left && payload.witness_evidence.proposition != proposition[1]
                    return false
                elseif inj === :right && payload.witness_evidence.proposition != proposition[2]
                    return false
                end
            end
        end
    end
    return true
end

function _check_threshold_proof_fields(cert::NamedTuple)::Bool
    if !(haskey(cert, :measured_value) && haskey(cert, :threshold) &&
         _is_numeric_real(cert.measured_value) && _is_numeric_real(cert.threshold) &&
         (cert.measured_value >= cert.threshold))
        return false
    end
    if haskey(cert, :comparison) && !(cert.comparison in (:>=, :>, :(==)))
        return false
    end
    if haskey(cert, :margin)
        if !_is_numeric_real(cert.margin) ||
           !isapprox(Float64(cert.margin), Float64(cert.measured_value) - Float64(cert.threshold); atol = 1e-12)
            return false
        end
    end
    return true
end

function _check_bandpass_proof_fields(cert::NamedTuple)::Bool
    if !(haskey(cert, :measured_value) && haskey(cert, :low) && haskey(cert, :high) &&
         _is_numeric_real(cert.measured_value) && _is_numeric_real(cert.low) && _is_numeric_real(cert.high) &&
         (cert.low <= cert.high) && (cert.low <= cert.measured_value <= cert.high))
        return false
    end
    if haskey(cert, :margin_low)
        if !_is_numeric_real(cert.margin_low) ||
           !isapprox(Float64(cert.margin_low), Float64(cert.measured_value) - Float64(cert.low); atol = 1e-12)
            return false
        end
    end
    if haskey(cert, :margin_high)
        if !_is_numeric_real(cert.margin_high) ||
           !isapprox(Float64(cert.margin_high), Float64(cert.high) - Float64(cert.measured_value); atol = 1e-12)
            return false
        end
    end
    return true
end

function _check_subtype_proof_fields(cert::NamedTuple)::Bool
    if !(haskey(cert, :out_type) && haskey(cert, :in_type) &&
         (cert.out_type isa Type) && (cert.in_type isa Type) &&
         (cert.out_type <: cert.in_type))
        return false
    end
    if haskey(cert, :relation) && cert.relation != :(Out <: In)
        return false
    end
    return true
end

function _check_threshold_refutation_fields(cc::NamedTuple)::Bool
    if !(haskey(cc, :measured_value) && haskey(cc, :threshold) &&
         _is_numeric_real(cc.measured_value) && _is_numeric_real(cc.threshold) &&
         (cc.measured_value < cc.threshold))
        return false
    end
    if haskey(cc, :comparison) && cc.comparison !== :<
        return false
    end
    if haskey(cc, :deficit)
        if !_is_numeric_real(cc.deficit) ||
           !isapprox(Float64(cc.deficit), Float64(cc.threshold) - Float64(cc.measured_value); atol = 1e-12)
            return false
        end
    end
    return true
end

function _check_bandpass_refutation_fields(cc::NamedTuple)::Bool
    if !(haskey(cc, :measured_value) && haskey(cc, :low) && haskey(cc, :high) &&
         _is_numeric_real(cc.measured_value) && _is_numeric_real(cc.low) && _is_numeric_real(cc.high) &&
         (cc.low <= cc.high) && (cc.measured_value < cc.low || cc.measured_value > cc.high))
        return false
    end
    expected_violation = cc.measured_value < cc.low ? :below_low : :above_high
    expected_deficit = cc.measured_value < cc.low ? (Float64(cc.low) - Float64(cc.measured_value)) : (Float64(cc.measured_value) - Float64(cc.high))
    if haskey(cc, :violation) && cc.violation !== expected_violation
        return false
    end
    if haskey(cc, :deficit)
        if !_is_numeric_real(cc.deficit) ||
           !isapprox(Float64(cc.deficit), expected_deficit; atol = 1e-12)
            return false
        end
    end
    return true
end

function _check_subtype_refutation_fields(cc::NamedTuple)::Bool
    if !(haskey(cc, :out_type) && haskey(cc, :in_type) &&
         (cc.out_type isa Type) && (cc.in_type isa Type) &&
         !(cc.out_type <: cc.in_type))
        return false
    end
    if haskey(cc, :relation) && cc.relation != :(!(Out <: In))
        return false
    end
    return true
end

function check_proof_term(proposition, term::StructuredProofTerm)::Bool
    cert = getfield(term, :payload)
    if isempty(cert) || _certificate_structural_seal(cert) != getfield(term, :_seal) || !_proposition_matches(proposition, cert)
        return false
    end
    if haskey(cert, :verified) && cert.verified !== true
        return false
    end
    if haskey(cert, :refuted) && cert.refuted !== false
        return false
    end
    if haskey(cert, :gate_type)
        gt = cert.gate_type
        if gt === :threshold
            return _check_threshold_proof_fields(cert)
        elseif gt === :bandpass
            return _check_bandpass_proof_fields(cert)
        elseif gt === :subtype
            return _check_subtype_proof_fields(cert)
        elseif gt === :conjunction
            if !(haskey(cert, :child_evidence) && (cert.child_evidence isa AbstractVector) &&
                 all(c -> (c isa Witness) && verify_evidence_certificate(c), cert.child_evidence))
                return false
            end
            if haskey(cert, :child_certificates)
                if !(cert.child_certificates isa AbstractVector) ||
                   length(cert.child_certificates) != length(cert.child_evidence) ||
                   !all(i -> cert.child_certificates[i] == cert.child_evidence[i].certificate, eachindex(cert.child_evidence))
                    return false
                end
            end
            return true
        elseif gt === :disjunction
            if !(haskey(cert, :child_evidence) && (cert.child_evidence isa AbstractVector) &&
                 haskey(cert, :branch_index) && _is_index_int(cert.branch_index) &&
                 (1 <= cert.branch_index <= length(cert.child_evidence)) &&
                 all(c -> (c isa EvidenceStatus) && verify_evidence_certificate(c), cert.child_evidence) &&
                 (cert.child_evidence[cert.branch_index] isa Witness))
                return false
            end
            if haskey(cert, :injection)
                expected_inj = cert.branch_index == 1 ? :left : (cert.branch_index == 2 ? :right : Symbol("branch_$(cert.branch_index)"))
                if cert.injection !== expected_inj
                    return false
                end
            end
            if haskey(cert, :witness_certificate) && cert.witness_certificate != cert.child_evidence[cert.branch_index].certificate
                return false
            end
            return true
        elseif gt === :k_of_n
            if !(haskey(cert, :child_evidence) && (cert.child_evidence isa AbstractVector) &&
                 haskey(cert, :witness_indices) && (cert.witness_indices isa AbstractVector) &&
                 all(_is_index_int, cert.witness_indices) &&
                 haskey(cert, :k) && _is_index_int(cert.k) && (cert.k >= 0) &&
                 allunique(cert.witness_indices) &&
                 (length(cert.witness_indices) >= cert.k) &&
                 all(c -> (c isa EvidenceStatus) && verify_evidence_certificate(c), cert.child_evidence) &&
                 all(i -> (1 <= i <= length(cert.child_evidence)) && (cert.child_evidence[i] isa Witness), cert.witness_indices))
                return false
            end
            if haskey(cert, :n) && (!_is_index_int(cert.n) || cert.n != length(cert.child_evidence))
                return false
            end
            if haskey(cert, :passed_count) && (!_is_index_int(cert.passed_count) || cert.passed_count != length(cert.witness_indices))
                return false
            end
            if haskey(cert, :witness_certificates)
                if !(cert.witness_certificates isa AbstractVector) ||
                   length(cert.witness_certificates) != length(cert.witness_indices) ||
                   !all(j -> cert.witness_certificates[j] == cert.child_evidence[cert.witness_indices[j]].certificate, eachindex(cert.witness_indices))
                    return false
                end
            end
            return true
        elseif gt === :custom
            if !(get(cert, :verified, false) === true &&
                 haskey(cert, :measured_value) && _is_numeric_real(cert.measured_value) &&
                 cert.measured_value != -1.0 &&
                 haskey(cert, :detail) && (cert.detail isa AbstractString) && !isempty(cert.detail))
                return false
            end
            if haskey(cert, :recheck) && (cert.recheck isa Function)
                ok = try
                    cert.recheck() === true
                catch
                    false
                end
                if !ok
                    return false
                end
            end
            return true
        else
            return false
        end
    elseif haskey(cert, :combinator)
        comb = cert.combinator
        if comb === :conjunction
            if !(haskey(cert, :left_evidence) && haskey(cert, :right_evidence) &&
                 (cert.left_evidence isa Witness) && (cert.right_evidence isa Witness) &&
                 verify_evidence_certificate(cert.left_evidence) &&
                 verify_evidence_certificate(cert.right_evidence))
                return false
            end
            if haskey(cert, :left) && cert.left != cert.left_evidence.certificate
                return false
            end
            if haskey(cert, :right) && cert.right != cert.right_evidence.certificate
                return false
            end
            return true
        elseif comb === :disjunction
            if !(haskey(cert, :injection) && (cert.injection in (:left, :right)) &&
                 haskey(cert, :witness_evidence) && (cert.witness_evidence isa Witness) &&
                 verify_evidence_certificate(cert.witness_evidence))
                return false
            end
            if haskey(cert, :left_evidence)
                if !(cert.left_evidence isa EvidenceStatus && verify_evidence_certificate(cert.left_evidence))
                    return false
                end
                if cert.injection === :left && (cert.witness_evidence !== cert.left_evidence || !(cert.left_evidence isa Witness))
                    return false
                end
            end
            if haskey(cert, :right_evidence)
                if !(cert.right_evidence isa EvidenceStatus && verify_evidence_certificate(cert.right_evidence))
                    return false
                end
                if cert.injection === :right && (cert.witness_evidence !== cert.right_evidence || !(cert.right_evidence isa Witness))
                    return false
                end
            end
            if haskey(cert, :certificate) && cert.certificate != cert.witness_evidence.certificate
                return false
            end
            return true
        else
            return false
        end
    elseif haskey(cert, :audit_type) && cert.audit_type === :scientific_claim_boundary
        return haskey(cert, :claimed_level) &&
               haskey(cert, :achieved_level) &&
               haskey(cert, :tracked_in_source) &&
               haskey(cert, :reported_in_delivery) &&
               haskey(cert, :independently_verified) &&
               haskey(cert, :underlying_evidence) &&
               (cert.claimed_level isa AchievementLevel) &&
               (cert.achieved_level isa AchievementLevel) &&
               (cert.claimed_level <= cert.achieved_level) &&
               (cert.tracked_in_source === true) &&
               (cert.reported_in_delivery === true) &&
               (cert.independently_verified === true) &&
               (cert.underlying_evidence isa Witness) &&
               verify_evidence_certificate(cert.underlying_evidence)
    elseif haskey(cert, :verdict_bridge)
        return cert.verdict_bridge === :accepted &&
               haskey(cert, :empowerment_score) &&
               _is_numeric_real(cert.empowerment_score) &&
               cert.empowerment_score != -1.0 &&
               haskey(cert, :salient_features) &&
               (cert.salient_features isa AbstractVector) &&
               all(_is_numeric_real, cert.salient_features)
    elseif haskey(cert, :measured_value) && haskey(cert, :threshold)
        return _check_threshold_proof_fields(cert)
    elseif haskey(cert, :measured_value) && haskey(cert, :low) && haskey(cert, :high)
        return _check_bandpass_proof_fields(cert)
    elseif haskey(cert, :out_type) && haskey(cert, :in_type)
        return _check_subtype_proof_fields(cert)
    else
        return false
    end
end

function check_refutation_term(proposition, term::GateViolationRefutationTerm)::Bool
    v = getfield(term, :violation)
    if !(isfinite(v.cell_residual) && v.cell_residual > 0.0)
        return false
    end
    gate_str = String(v.gate_name)
    if (proposition isa Union{AbstractString, Symbol}) && !isempty(gate_str)
        if String(proposition) != gate_str
            return false
        end
    end
    return true
end

function check_refutation_term(proposition, term::StructuredRefutationTerm)::Bool
    cc = getfield(term, :payload)
    if isempty(cc) || _certificate_structural_seal(cc) != getfield(term, :_seal) || !_proposition_matches(proposition, cc)
        return false
    end
    if haskey(cc, :refuted) && cc.refuted !== true
        return false
    end
    if haskey(cc, :verified) && cc.verified !== false
        return false
    end
    if haskey(cc, :gate_type)
        gt = cc.gate_type
        if gt === :threshold
            return _check_threshold_refutation_fields(cc)
        elseif gt === :bandpass
            return _check_bandpass_refutation_fields(cc)
        elseif gt === :subtype
            return _check_subtype_refutation_fields(cc)
        elseif gt === :conjunction
            if !(haskey(cc, :child_evidence) && (cc.child_evidence isa AbstractVector) &&
                 haskey(cc, :failed_indices) && (cc.failed_indices isa AbstractVector) &&
                 all(_is_index_int, cc.failed_indices) &&
                 !isempty(cc.failed_indices) && allunique(cc.failed_indices) &&
                 all(c -> (c isa EvidenceStatus) && verify_evidence_certificate(c), cc.child_evidence) &&
                 all(i -> (1 <= i <= length(cc.child_evidence)) && (cc.child_evidence[i] isa Refutation), cc.failed_indices))
                return false
            end
            if haskey(cc, :failed_countercertificates)
                if !(cc.failed_countercertificates isa AbstractVector) ||
                   length(cc.failed_countercertificates) != length(cc.failed_indices) ||
                   !all(j -> cc.failed_countercertificates[j] == cc.child_evidence[cc.failed_indices[j]].countercertificate, eachindex(cc.failed_indices))
                    return false
                end
            end
            return true
        elseif gt === :disjunction
            if !(haskey(cc, :child_evidence) && (cc.child_evidence isa AbstractVector) &&
                 all(c -> (c isa Refutation) && verify_evidence_certificate(c), cc.child_evidence))
                return false
            end
            if haskey(cc, :failed_countercertificates)
                if !(cc.failed_countercertificates isa AbstractVector) ||
                   length(cc.failed_countercertificates) != length(cc.child_evidence) ||
                   !all(i -> cc.failed_countercertificates[i] == cc.child_evidence[i].countercertificate, eachindex(cc.child_evidence))
                    return false
                end
            end
            return true
        elseif gt === :k_of_n
            if !(haskey(cc, :child_evidence) && (cc.child_evidence isa AbstractVector) &&
                 haskey(cc, :failed_indices) && (cc.failed_indices isa AbstractVector) &&
                 all(_is_index_int, cc.failed_indices) &&
                 haskey(cc, :k) && _is_index_int(cc.k) &&
                 haskey(cc, :n) && _is_index_int(cc.n) &&
                 (cc.n == length(cc.child_evidence)) &&
                 (cc.k > 0) &&
                 allunique(cc.failed_indices) &&
                 (length(cc.failed_indices) > (cc.n - cc.k)) &&
                 all(c -> (c isa EvidenceStatus) && verify_evidence_certificate(c), cc.child_evidence) &&
                 all(i -> (1 <= i <= length(cc.child_evidence)) && (cc.child_evidence[i] isa Refutation), cc.failed_indices))
                return false
            end
            if haskey(cc, :refuted_count) && (!_is_index_int(cc.refuted_count) || cc.refuted_count != length(cc.failed_indices))
                return false
            end
            if haskey(cc, :passed_count) && (!_is_index_int(cc.passed_count) || cc.passed_count != count(c -> c isa Witness, cc.child_evidence))
                return false
            end
            if haskey(cc, :failed_countercertificates)
                if !(cc.failed_countercertificates isa AbstractVector) ||
                   length(cc.failed_countercertificates) != length(cc.failed_indices) ||
                   !all(j -> cc.failed_countercertificates[j] == cc.child_evidence[cc.failed_indices[j]].countercertificate, eachindex(cc.failed_indices))
                    return false
                end
            end
            return true
        elseif gt === :custom
            if !(get(cc, :refuted, false) === true &&
                 haskey(cc, :measured_value) && _is_numeric_real(cc.measured_value) &&
                 cc.measured_value != -1.0 &&
                 haskey(cc, :detail) && (cc.detail isa AbstractString) && !isempty(cc.detail))
                return false
            end
            if haskey(cc, :recheck) && (cc.recheck isa Function)
                ok = try
                    cc.recheck() === true
                catch
                    false
                end
                if !ok
                    return false
                end
            end
            return true
        else
            return false
        end
    elseif haskey(cc, :combinator)
        comb = cc.combinator
        if comb === :conjunction
            if !(haskey(cc, :failed_branch) && haskey(cc, :left_evidence) && haskey(cc, :right_evidence) &&
                 (cc.left_evidence isa EvidenceStatus) && (cc.right_evidence isa EvidenceStatus) &&
                 verify_evidence_certificate(cc.left_evidence) && verify_evidence_certificate(cc.right_evidence))
                return false
            end
            if cc.failed_branch === :left
                return (cc.left_evidence isa Refutation) &&
                       (!haskey(cc, :countercertificate) || cc.countercertificate == cc.left_evidence.countercertificate)
            elseif cc.failed_branch === :right
                return (cc.right_evidence isa Refutation) &&
                       (!haskey(cc, :countercertificate) || cc.countercertificate == cc.right_evidence.countercertificate)
            elseif cc.failed_branch === :both
                return (cc.left_evidence isa Refutation) &&
                       (cc.right_evidence isa Refutation) &&
                       (!haskey(cc, :left) || cc.left == cc.left_evidence.countercertificate) &&
                       (!haskey(cc, :right) || cc.right == cc.right_evidence.countercertificate)
            else
                return false
            end
        elseif comb === :disjunction
            if !(haskey(cc, :left_evidence) && haskey(cc, :right_evidence) &&
                 (cc.left_evidence isa Refutation) && (cc.right_evidence isa Refutation) &&
                 verify_evidence_certificate(cc.left_evidence) && verify_evidence_certificate(cc.right_evidence))
                return false
            end
            if haskey(cc, :left) && cc.left != cc.left_evidence.countercertificate
                return false
            end
            if haskey(cc, :right) && cc.right != cc.right_evidence.countercertificate
                return false
            end
            return true
        else
            return false
        end
    elseif haskey(cc, :audit_type) && cc.audit_type === :scientific_claim_boundary
        if !(haskey(cc, :claimed_level) && haskey(cc, :achieved_level) && haskey(cc, :underlying_evidence) &&
             (cc.claimed_level isa AchievementLevel) && (cc.achieved_level isa AchievementLevel))
            return false
        end
        overclaimed = cc.claimed_level > cc.achieved_level
        refuted_ev = (cc.underlying_evidence isa Refutation) && verify_evidence_certificate(cc.underlying_evidence)
        invalid_wit = (cc.underlying_evidence isa Witness) && !verify_evidence_certificate(cc.underlying_evidence)
        if haskey(cc, :reason)
            if cc.reason === :claim_exceeds_achievement
                overclaimed || return false
            elseif cc.reason === :underlying_evidence_refuted
                refuted_ev || return false
            elseif cc.reason === :invalid_witness_certificate
                invalid_wit || return false
            else
                return false
            end
        end
        if haskey(cc, :countercertificate) && (cc.underlying_evidence isa Refutation)
            if cc.countercertificate != cc.underlying_evidence.countercertificate
                return false
            end
        end
        return overclaimed || refuted_ev || invalid_wit
    elseif haskey(cc, :verdict_bridge)
        return cc.verdict_bridge === :rejected &&
               haskey(cc, :partial_score) &&
               _is_numeric_real(cc.partial_score) &&
               cc.partial_score != -1.0
    elseif haskey(cc, :measured_value) && haskey(cc, :threshold)
        return _check_threshold_refutation_fields(cc)
    elseif haskey(cc, :measured_value) && haskey(cc, :low) && haskey(cc, :high)
        return _check_bandpass_refutation_fields(cc)
    elseif haskey(cc, :out_type) && haskey(cc, :in_type)
        return _check_subtype_refutation_fields(cc)
    else
        return false
    end
end

function check_proof_term(proposition, payload::NamedTuple)::Bool
    isempty(payload) && return false
    return check_proof_term(proposition, StructuredProofTerm(payload))
end
check_proof_term(proposition, term::AbstractRefutationTerm)::Bool = false
check_proof_term(::Any, ::Any)::Bool = false

function check_refutation_term(proposition, payload::NamedTuple)::Bool
    isempty(payload) && return false
    return check_refutation_term(proposition, StructuredRefutationTerm(payload))
end
check_refutation_term(proposition, cert::GateViolationCertificate)::Bool =
    check_refutation_term(proposition, GateViolationRefutationTerm(cert))
check_refutation_term(proposition, term::AbstractProofTerm)::Bool = false
check_refutation_term(::Any, ::Any)::Bool = false

# Independent certificate re-checker on EvidenceStatus and raw candidate payloads
function verify_evidence_certificate(ev::Unresolved)::Bool
    raw_prop = getfield(ev, :proposition)
    raw_prereqs = getfield(ev, :missing_prerequisites)
    sealed_prereqs = getfield(ev, :_sealed_prerequisites)
    return _certificate_structural_seal(raw_prop) == getfield(ev, :_proposition_seal) &&
           !isempty(raw_prereqs) &&
           !isempty(sealed_prereqs) &&
           Tuple(raw_prereqs) === sealed_prereqs &&
           all(s -> s !== Symbol(""), sealed_prereqs)
end

function verify_evidence_certificate(ev::Witness)::Bool
    raw_prop = getfield(ev, :proposition)
    return _certificate_structural_seal(raw_prop) == getfield(ev, :_proposition_seal) &&
           check_proof_term(raw_prop, getfield(ev, :certificate))
end

function verify_evidence_certificate(ev::Refutation)::Bool
    raw_prop = getfield(ev, :proposition)
    return _certificate_structural_seal(raw_prop) == getfield(ev, :_proposition_seal) &&
           check_refutation_term(raw_prop, getfield(ev, :countercertificate))
end

function verify_evidence_certificate(proposition, candidate_cert::AbstractProofTerm)::Bool
    return check_proof_term(proposition, candidate_cert)
end

function verify_evidence_certificate(proposition, candidate_countercert::AbstractRefutationTerm)::Bool
    return check_refutation_term(proposition, candidate_countercert)
end

function verify_evidence_certificate(proposition, candidate_payload::NamedTuple)::Bool
    return check_proof_term(proposition, candidate_payload)
end

verify_evidence_certificate(::Any)::Bool = false
verify_evidence_certificate(::Any, ::Any)::Bool = false

# Bridge between constructive EvidenceStatus and operational CriterialVerdict
function verdict_from_evidence(ev::Witness)::Accepted
    score = 1.0
    feats = Float64[1.0]
    cert = ev.certificate
    if (cert isa NamedTuple || cert isa StructuredProofTerm) && haskey(cert, :measured_value) &&
       (cert.measured_value isa Real) && isfinite(cert.measured_value)
        mv = Float64(cert.measured_value)
        if mv != -1.0
            score = mv
            feats = Float64[mv]
        end
    elseif (cert isa NamedTuple || cert isa StructuredProofTerm) && haskey(cert, :empowerment_score) &&
           (cert.empowerment_score isa Real) && isfinite(cert.empowerment_score)
        es = Float64(cert.empowerment_score)
        if es != -1.0
            score = es
        end
        if haskey(cert, :salient_features) && cert.salient_features isa Vector{Float64}
            feats = copy(cert.salient_features)
        end
    end
    return Accepted(ev.proposition, feats, score, "Constructive witness verified for proposition: $(ev.proposition)")
end

function verdict_from_evidence(ev::Refutation)::Rejected
    failed_idxs = Int[]
    failed_gates = Symbol[]
    pscore = 0.0
    reason = :refuted
    cc = ev.countercertificate
    if cc isa NamedTuple || cc isa StructuredRefutationTerm
        if haskey(cc, :failed_indices) && cc.failed_indices isa AbstractVector
            failed_idxs = Int[Int(i) for i in cc.failed_indices]
        elseif haskey(cc, :failed_gate_indices) && cc.failed_gate_indices isa AbstractVector
            failed_idxs = Int[Int(i) for i in cc.failed_gate_indices]
        end
        if haskey(cc, :gate_name)
            push!(failed_gates, Symbol(cc.gate_name))
        end
        if haskey(cc, :measured_value) && (cc.measured_value isa Real) && isfinite(cc.measured_value) && Float64(cc.measured_value) != -1.0
            pscore = Float64(cc.measured_value)
        elseif haskey(cc, :partial_score) && (cc.partial_score isa Real) && isfinite(cc.partial_score) && Float64(cc.partial_score) != -1.0
            pscore = Float64(cc.partial_score)
        end
        if haskey(cc, :reason) && cc.reason isa Symbol
            reason = cc.reason
        elseif haskey(cc, :gate_type) && cc.gate_type isa Symbol
            reason = Symbol("refuted_", cc.gate_type)
        end
    elseif cc isa GateViolationRefutationTerm
        push!(failed_gates, cc.gate_name)
    end
    return Rejected(reason, "Constructive refutation for proposition: $(ev.proposition)", failed_idxs, failed_gates, pscore)
end

function verdict_from_evidence(ev::Unresolved)::Incomplete
    missing_prereqs = isempty(ev.missing_prerequisites) ? Symbol[:unresolved] : copy(ev.missing_prerequisites)
    reason = first(missing_prereqs)
    detail = "Unresolved proposition $(ev.proposition); missing prerequisites: $(join(missing_prereqs, ", "))"
    return Incomplete(reason, detail, missing_prereqs)
end

function evidence_from_verdict(v::Accepted, proposition = v.value)::Witness
    cert = StructuredProofTerm((
        verdict_bridge = :accepted,
        proposition = proposition,
        value = v.value,
        salient_features = v.salient_features,
        empowerment_score = v.empowerment_score,
        detail = v.detail,
        verified = true
    ))
    return Witness(proposition, cert)
end

function evidence_from_verdict(v::Rejected, proposition = v.reason)::Refutation
    countercert = StructuredRefutationTerm((
        verdict_bridge = :rejected,
        proposition = proposition,
        reason = v.reason,
        detail = v.detail,
        failed_gate_indices = v.failed_gate_indices,
        failed_gates = v.failed_gates,
        partial_score = v.partial_score,
        violation_certificates = v.violation_certificates,
        refuted = true
    ))
    return Refutation(proposition, countercert)
end

function evidence_from_verdict(v::Incomplete, proposition = v.reason)::Unresolved
    missing_prereqs = isempty(v.missing_prerequisites) ? Symbol[v.reason] : copy(v.missing_prerequisites)
    return Unresolved(proposition, missing_prereqs)
end

# ------------------------------------------------------------------------------
# 2c. Four-Level Scientific Achievement Taxonomy and Claim Boundary Auditor
# ------------------------------------------------------------------------------

struct ScientificClaimAudit{T}
    claim::T
    achieved_level::AchievementLevel
    claimed_level::AchievementLevel
    evidence::EvidenceStatus
    tracked_in_source::Bool
    reported_in_delivery::Bool
    independently_verified::Bool
end

function ScientificClaimAudit(
    claim::T,
    achieved_level::AchievementLevel,
    claimed_level::AchievementLevel,
    evidence::EvidenceStatus;
    tracked_in_source::Bool = true,
    reported_in_delivery::Bool = true,
    independently_verified::Bool = true
) where {T}
    return ScientificClaimAudit{T}(
        claim,
        achieved_level,
        claimed_level,
        evidence,
        tracked_in_source,
        reported_in_delivery,
        independently_verified
    )
end

function audit_scientific_claim_boundary(
    audit::ScientificClaimAudit;
    required_prerequisites = Symbol[],
    available_prerequisites = Symbol[]
)::EvidenceStatus
    if audit.claimed_level > audit.achieved_level
        countercert = StructuredRefutationTerm((
            audit_type = :scientific_claim_boundary,
            proposition = audit.claim,
            reason = :claim_exceeds_achievement,
            claim = audit.claim,
            achieved_level = audit.achieved_level,
            claimed_level = audit.claimed_level,
            tracked_in_source = audit.tracked_in_source,
            reported_in_delivery = audit.reported_in_delivery,
            independently_verified = audit.independently_verified,
            underlying_evidence = audit.evidence,
            refuted = true
        ))
        return Refutation(audit.claim, countercert)
    end

    if audit.evidence isa Refutation
        countercert = StructuredRefutationTerm((
            audit_type = :scientific_claim_boundary,
            proposition = audit.claim,
            reason = :underlying_evidence_refuted,
            claim = audit.claim,
            achieved_level = audit.achieved_level,
            claimed_level = audit.claimed_level,
            tracked_in_source = audit.tracked_in_source,
            reported_in_delivery = audit.reported_in_delivery,
            independently_verified = audit.independently_verified,
            underlying_evidence = audit.evidence,
            countercertificate = audit.evidence.countercertificate,
            refuted = true
        ))
        return Refutation(audit.claim, countercert)
    end

    if (audit.evidence isa Witness) && !verify_evidence_certificate(audit.evidence)
        countercert = StructuredRefutationTerm((
            audit_type = :scientific_claim_boundary,
            proposition = audit.claim,
            reason = :invalid_witness_certificate,
            claim = audit.claim,
            achieved_level = audit.achieved_level,
            claimed_level = audit.claimed_level,
            tracked_in_source = audit.tracked_in_source,
            reported_in_delivery = audit.reported_in_delivery,
            independently_verified = audit.independently_verified,
            underlying_evidence = audit.evidence,
            refuted = true
        ))
        return Refutation(audit.claim, countercert)
    end

    missing_prereqs = _missing_prerequisites(required_prerequisites, available_prerequisites)
    if audit.evidence isa Unresolved
        for p in audit.evidence.missing_prerequisites
            if !(p in missing_prereqs)
                push!(missing_prereqs, p)
            end
        end
        if isempty(missing_prereqs)
            push!(missing_prereqs, :unresolved_evidence)
        end
    end
    if !audit.tracked_in_source && !(:tracked_in_source in missing_prereqs)
        push!(missing_prereqs, :tracked_in_source)
    end
    if !audit.reported_in_delivery && !(:reported_in_delivery in missing_prereqs)
        push!(missing_prereqs, :reported_in_delivery)
    end
    if !audit.independently_verified && !(:independently_verified in missing_prereqs)
        push!(missing_prereqs, :independently_verified)
    end
    if !isempty(missing_prereqs)
        return Unresolved(audit.claim, missing_prereqs)
    end

    cert = StructuredProofTerm((
        audit_type = :scientific_claim_boundary,
        proposition = audit.claim,
        claim = audit.claim,
        achieved_level = audit.achieved_level,
        claimed_level = audit.claimed_level,
        tracked_in_source = audit.tracked_in_source,
        reported_in_delivery = audit.reported_in_delivery,
        independently_verified = audit.independently_verified,
        underlying_evidence = audit.evidence,
        verified = true
    ))
    return Witness(audit.claim, cert)
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
