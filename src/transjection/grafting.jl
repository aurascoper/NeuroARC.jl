# src/transjection/grafting.jl
# Paper B Hyphal Grafting & Deep Grafting Reference Contract

module HyphalGraftingContract

export AbstractGridArtifact, AbstractPolyomino,
       ColorMappedGrid, PolyominoGraph, BoundedPolyomino,
       GraftVerdict, Accepted, Rejected, Incomplete,
       GraftNode, in_type, out_type, In, Out,
       can_graft, try_graft, try_deep_graft,
       build_canonical_fixtures,
       generate_figure_b1_dot, generate_figure_b2_dot,
       generate_figure_b1_svg, generate_figure_b2_svg,
       parse_dot_semantics, try_graphviz_render

# ------------------------------------------------------------------------------
# 1. Domain Artifact Hierarchy
# ------------------------------------------------------------------------------

abstract type AbstractGridArtifact end
abstract type AbstractPolyomino <: AbstractGridArtifact end

struct ColorMappedGrid <: AbstractGridArtifact
    grid::Matrix{Int}
end

Base.:(==)(a::ColorMappedGrid, b::ColorMappedGrid) = a.grid == b.grid

struct PolyominoGraph <: AbstractPolyomino
    coords::Vector{Tuple{Int, Int}}
    colors::Vector{Int}
    function PolyominoGraph(coords::Vector{Tuple{Int, Int}}, colors::Vector{Int})
        if length(coords) != length(colors)
            throw(ArgumentError("PolyominoGraph requires length(coords) == length(colors); got $(length(coords)) and $(length(colors))"))
        end
        return new(coords, colors)
    end
end

PolyominoGraph(coords::Vector{Tuple{Int, Int}}) = PolyominoGraph(coords, ones(Int, length(coords)))
Base.:(==)(a::PolyominoGraph, b::PolyominoGraph) = (a.coords == b.coords) && (a.colors == b.colors)

struct BoundedPolyomino <: AbstractPolyomino
    coords::Vector{Tuple{Int, Int}}
    max_span::Int
end

Base.:(==)(a::BoundedPolyomino, b::BoundedPolyomino) = (a.coords == b.coords) && (a.max_span == b.max_span)

# ------------------------------------------------------------------------------
# 2. Typed Verdicts (Replacing Numeric Inf Rejection Sentinels)
# ------------------------------------------------------------------------------

abstract type GraftVerdict end

struct Accepted{T} <: GraftVerdict
    node::T
    reason::Symbol
    detail::String
    edge_pair::Tuple{String, String}
    out_type::Type
    in_type::Type
end

struct Rejected <: GraftVerdict
    reason::Symbol
    detail::String
    edge_pair::Tuple{String, String}
    out_type::Any
    in_type::Any
end

struct Incomplete <: GraftVerdict
    reason::Symbol
    detail::String
end

# ------------------------------------------------------------------------------
# 3. Typed GraftNode Wrapper with Runtime Input Dispatch & Output Typeassert
# ------------------------------------------------------------------------------

struct GraftNode{InType, OutType, F}
    name::String
    label_compose::String
    f::F
    function GraftNode{InType, OutType, F}(name::AbstractString, label_compose::AbstractString, f::F) where {InType, OutType, F}
        (InType isa Type) || throw(ArgumentError("GraftNode InType parameter must be a Type; got $(repr(InType)) of type $(typeof(InType))"))
        (OutType isa Type) || throw(ArgumentError("GraftNode OutType parameter must be a Type; got $(repr(OutType)) of type $(typeof(OutType))"))
        return new{InType, OutType, F}(String(name), String(label_compose), f)
    end
end

function GraftNode{InType, OutType}(name::AbstractString, label_compose::AbstractString, f::F) where {InType, OutType, F}
    return GraftNode{InType, OutType, F}(String(name), String(label_compose), f)
end

function GraftNode{InType, OutType}(label_compose::AbstractString, f::F) where {InType, OutType, F}
    return GraftNode{InType, OutType, F}(String(label_compose), String(label_compose), f)
end

in_type(::GraftNode{InType, OutType}) where {InType, OutType} = InType
out_type(::GraftNode{InType, OutType}) where {InType, OutType} = OutType
In(node::GraftNode) = in_type(node)
Out(node::GraftNode) = out_type(node)

"""
    (node::GraftNode{InType, OutType})(x::InType)

Callable wrapper enforcing:
1. Input type compatibility `x isa InType` via Julia multiple dispatch (`MethodError` on mismatch).
2. Declared output type contract `y isa OutType` via `Core.typeassert(y, OutType)` (`TypeError` on violation,
   without calling `Base.convert`).
"""
function (node::GraftNode{InType, OutType, F})(x::InType) where {InType, OutType, F}
    y = node.f(x)
    return Core.typeassert(y, OutType)
end

# ------------------------------------------------------------------------------
# 4. Preflight Compatibility Check and Composition (`can_graft`, `try_graft`, `try_deep_graft`)
# ------------------------------------------------------------------------------

"""
    can_graft(first::GraftNode, second::GraftNode) -> Bool

Preflight check testing whether `Out(first) <: In(second)`.
Does not execute either node function.
"""
function can_graft(::GraftNode{InA, OutA}, ::GraftNode{InB, OutB})::Bool where {InA, OutA, InB, OutB}
    return OutA <: InB
end

can_graft(::Any, ::Any)::Bool = false

"""
    try_graft(first::GraftNode, second::GraftNode) -> Union{Accepted, Rejected}

Validates `Out(first) <: In(second)` without executing `first` or `second`.
When compatible, constructs a composed `GraftNode{In(first), Out(second)}` whose
callable body is `x -> second(first(x))` so that both nodes' input and output
contracts are enforced at runtime, and labels the composition
`"\$(second.label_compose) ∘ \$(first.label_compose)"`.
"""
function try_graft(first::GraftNode{InA, OutA}, second::GraftNode{InB, OutB}) where {InA, OutA, InB, OutB}
    edge = (first.label_compose, second.label_compose)
    if can_graft(first, second)
        comp_fn = x -> second(first(x))
        comp_label = "$(second.label_compose) ∘ $(first.label_compose)"
        comp_name = "$(second.name) ∘ $(first.name)"
        composed = GraftNode{InA, OutB}(comp_name, comp_label, comp_fn)
        detail = "Out($(first.label_compose)) = $(OutA) <: In($(second.label_compose)) = $(InB)"
        return Accepted(composed, :subtype_compatible, detail, edge, OutA, InB)
    else
        detail = "Declared output type $(OutA) of $(first.label_compose) is not a subtype of declared input type $(InB) of $(second.label_compose)"
        return Rejected(:type_mismatch, detail, edge, OutA, InB)
    end
end

function try_graft(first::Any, second::Any)
    edge = (string(typeof(first)), string(typeof(second)))
    detail = "Both arguments to try_graft must be GraftNode instances; got ($(typeof(first)), $(typeof(second)))"
    return Rejected(:invalid_node_element, detail, edge, typeof(first), typeof(second))
end

"""
    try_deep_graft(chain::AbstractVector) -> Union{Accepted, Rejected, Incomplete}

Folds `try_graft` across an ordered vector of `GraftNode` stages `[N_1, N_2, ..., N_k]`.
Supported collection shape: `AbstractVector` containing `GraftNode` elements.
- If `isempty(chain)`, returns `Incomplete(:empty_chain, ...)`.
- If any element in `chain` is not a `GraftNode`, returns `Rejected(:invalid_node_element, ...)`.
- If `length(chain) == 1`, returns `Accepted(chain[1], :single_node_chain, ...)`.
- For `length(chain) >= 2`, validates each adjacent boundary `(chain[idx-1], chain[idx])`
  in execution order without invoking any node functions, producing `"N_k ∘ ... ∘ N_2 ∘ N_1"`.
"""
function try_deep_graft(chain::AbstractVector)
    if isempty(chain)
        return Incomplete(:empty_chain, "Cannot construct a deep graft from an empty node vector")
    end
    for (idx, elem) in enumerate(chain)
        if !(elem isa GraftNode)
            edge = ("chain[$idx]", string(typeof(elem)))
            detail = "Element at index $idx is of type $(typeof(elem)); expected GraftNode"
            return Rejected(:invalid_node_element, detail, edge, typeof(elem), GraftNode)
        end
    end
    if length(chain) == 1
        only_node = chain[1]::GraftNode
        edge = (only_node.label_compose, only_node.label_compose)
        return Accepted(
            only_node,
            :single_node_chain,
            "Single valid GraftNode $(only_node.label_compose)",
            edge,
            out_type(only_node),
            in_type(only_node)
        )
    end
    acc_node = chain[1]::GraftNode
    last_verdict = nothing
    for idx in 2:length(chain)
        prev_node = chain[idx - 1]::GraftNode
        next_node = chain[idx]::GraftNode
        adj_verdict = try_graft(prev_node, next_node)
        if adj_verdict isa Rejected
            return adj_verdict
        end
        verdict = try_graft(acc_node, next_node)
        last_verdict = verdict::Accepted
        acc_node = last_verdict.node
    end
    return last_verdict::Accepted
end

function try_deep_graft(unsupported::Any)
    return Incomplete(
        :unsupported_chain_collection,
        "try_deep_graft requires an AbstractVector of GraftNode elements; got $(typeof(unsupported))"
    )
end

# ------------------------------------------------------------------------------
# 5. Canonical Fixture Builder (with Optional Call Instrumentation)
# ------------------------------------------------------------------------------

function build_canonical_fixtures(;
    countA::Base.RefValue{Int} = Ref(0),
    countB::Base.RefValue{Int} = Ref(0),
    countC::Base.RefValue{Int} = Ref(0),
    countX::Base.RefValue{Int} = Ref(0)
)
    nodeA = GraftNode{ColorMappedGrid, PolyominoGraph}(
        "Node A: PolyominoExtractor",
        "NodeA",
        function(cmg::ColorMappedGrid)
            countA[] += 1
            coords = Tuple{Int, Int}[]
            colors = Int[]
            for r in axes(cmg.grid, 1), c in axes(cmg.grid, 2)
                val = cmg.grid[r, c]
                if val != 0
                    push!(coords, (r, c))
                    push!(colors, val)
                end
            end
            return PolyominoGraph(coords, colors)
        end
    )

    nodeB = GraftNode{PolyominoGraph, ColorMappedGrid}(
        "Node B: StencilStamper",
        "NodeB",
        function(pg::PolyominoGraph)
            countB[] += 1
            if isempty(pg.coords)
                return ColorMappedGrid(zeros(Int, 1, 1))
            end
            max_r = maximum(first, pg.coords)
            max_c = maximum(last, pg.coords)
            grid = zeros(Int, max_r, max_c)
            for (coord, col) in zip(pg.coords, pg.colors)
                grid[coord[1], coord[2]] = col
            end
            return ColorMappedGrid(grid)
        end
    )

    nodeC = GraftNode{ColorMappedGrid, ColorMappedGrid}(
        "Node C: ColorPermutor",
        "NodeC",
        function(cmg::ColorMappedGrid)
            countC[] += 1
            permuted = map(v -> v == 0 ? 0 : (v % 9) + 1, cmg.grid)
            return ColorMappedGrid(permuted)
        end
    )

    # Fixed Blocking Issue 3: references bp.max_span matching BoundedPolyomino field
    nodeX = GraftNode{BoundedPolyomino, ColorMappedGrid}(
        "Node X: InvalidTransformer",
        "NodeX",
        function(bp::BoundedPolyomino)
            countX[] += 1
            return ColorMappedGrid(fill(bp.max_span, 2, 2))
        end
    )

    return (nodeA = nodeA, nodeB = nodeB, nodeC = nodeC, nodeX = nodeX,
            counts = (A = countA, B = countB, C = countC, X = countX))
end

# ------------------------------------------------------------------------------
# 6. DOT Generation and Semantic Parser for Figure B1 and Figure B2
# ------------------------------------------------------------------------------

function _short_type(t)
    return replace(string(t), r"\b(?:[A-Za-z_][A-Za-z0-9_]*\.)+" => "")
end

"""
    generate_figure_b1_dot(nodes, verdicts) -> String

Generates the Figure B1 Graphviz DOT specification directly from the evaluated
preflight verdicts (`v_ab`, `v_bc`, `v_ax`, `v_abc`).
"""
function generate_figure_b1_dot(nodes, verdicts)::String
    v_ab = verdicts.ab
    v_bc = verdicts.bc
    v_ax = verdicts.ax
    v_abc = verdicts.abc

    ab_label = v_ab.node.label_compose
    abc_label = v_abc.node.label_compose

    io = IOBuffer()
    println(io, "digraph FigureB1_TypedGrafting {")
    println(io, "    rankdir=LR;")
    println(io, "    fontname=\"Helvetica\";")
    println(io, "    fontsize=11;")
    println(io, "    labelloc=\"t\";")
    println(io, "    label=\"Figure B1: Typed Composition and Deep Grafting in NeuroARC.jl (Preflight Out(A) <: In(B) vs Runtime Wrapper Enforcement)\";")
    println(io, "    node [shape=box, fontname=\"Helvetica\", fontsize=10, style=\"rounded,filled\", fillcolor=\"#f9f9f9\"];")
    println(io, "    edge [fontname=\"Helvetica\", fontsize=9];")
    println(io, "")
    println(io, "    // Primitive GraftNode Declarations")
    for (key, fillcol) in [(:nodeA, "#e1f5fe"), (:nodeB, "#e8f5e9"), (:nodeC, "#e8f5e9"), (:nodeX, "#ffebee")]
        nd = getfield(nodes, key)
        in_s = _short_type(in_type(nd))
        out_s = _short_type(out_type(nd))
        println(io, "    $(nd.label_compose) [label=\"$(nd.name)\\nIn: $(in_s)\\nOut: $(out_s)\", fillcolor=\"$(fillcol)\"];")
    end
    println(io, "")
    println(io, "    // Composed Pipeline Nodes (Enforcing x -> second(first(x)))")
    println(io, "    ComposedAB [label=\"Composed: $(ab_label)\\nCallable: x -> nodeB(nodeA(x))\\nIn: $(_short_type(in_type(v_ab.node))) | Out: $(_short_type(out_type(v_ab.node)))\", fillcolor=\"#dcedc8\"];")
    println(io, "    ComposedABC [label=\"Deep Graft: $(abc_label)\\nCallable: x -> nodeC((nodeB ∘ nodeA)(x))\\nIn: $(_short_type(in_type(v_abc.node))) | Out: $(_short_type(out_type(v_abc.node)))\", fillcolor=\"#c8e6c9\"];")
    println(io, "")
    println(io, "    // Verdict-Driven Preflight Edges")
    for v in (v_ab, v_bc, v_ax)
        src, dst = v.edge_pair
        out_s = _short_type(v.out_type)
        in_s = _short_type(v.in_type)
        if v isa Accepted
            println(io, "    $(src) -> $(dst) [label=\"Accepted ($(v.reason))\\nOut($(src)) <: In($(dst))\\n($(out_s) <: $(in_s))\", color=\"#2e7d32\", fontcolor=\"#1b5e20\", style=\"solid\", penwidth=2.0];")
        elseif v isa Rejected
            println(io, "    $(src) -> $(dst) [label=\"Rejected by Preflight ($(v.reason))\\n!(Out($(src)) <: In($(dst)))\\n($(out_s) not <: $(in_s))\\n0 node calls; distinct from runtime MethodError\", color=\"#c62828\", fontcolor=\"#b71c1c\", style=\"dashed\", penwidth=1.5];")
        end
    end
    println(io, "")
    println(io, "    // Composition Construction Lineage")
    println(io, "    NodeB -> ComposedAB [label=\"yields $(ab_label)\", color=\"#1565c0\", style=\"dotted\", penwidth=1.4];")
    println(io, "    ComposedAB -> ComposedABC [label=\"graft with NodeC\\nyields $(abc_label)\", color=\"#1565c0\", style=\"dotted\", penwidth=1.4];")
    println(io, "}")
    return String(take!(io))
end

"""
    generate_figure_b2_dot() -> String

Generates the Figure B2 Graphviz DOT specification depicting the NeuroARC agent
execution and verification flow with explicit epistemological boundaries:
- "Proposed shared-buffer interface" (no unverified zero-copy theorem claim)
- "Independent validation suite" emitting typed `Accepted`, `Rejected`, `Incomplete`
- "Experiment completion criteria" / "Global validation status" (no unverified convergence theorem)
"""
function generate_figure_b2_dot()::String
    return """
digraph FigureB2_AgentExecutionAndVerification {
    rankdir=TB;
    fontname="Helvetica";
    fontsize=11;
    labelloc="t";
    label="Figure B2: NeuroARC Agent Execution and Verification Architecture (Proposed Interface vs Verified Contracts)";
    node [shape=box, fontname="Helvetica", fontsize=10, style="rounded,filled", fillcolor="#f8fafc"];
    edge [fontname="Helvetica", fontsize=9];

    subgraph cluster_presynaptic {
        label="1. Presynaptic Layer (Python Agent Search Strategy)";
        style="rounded,dashed";
        color="#475569";
        AgentState [label="Search Strategy Controller\\nState transitions: Focus -> Frustration -> Panic", fillcolor="#e0f2fe"];
        CandidateGen [label="Candidate Rule & Grid Proposer\\nEmits candidate specification and metadata", fillcolor="#e0f2fe"];
        AgentState -> CandidateGen [label="selects search operator", color="#0284c7", style="solid", penwidth=1.5];
    }

    subgraph cluster_ffi {
        label="2. Cross-Language Transport Boundary";
        style="rounded,dashed";
        color="#d97706";
        SharedBuffer [label="Proposed shared-buffer interface\\n(Python-to-Julia buffer descriptor handoff;\\nownership & concurrency tests required before zero-copy claims)", fillcolor="#fef3c7"];
    }

    subgraph cluster_membrane {
        label="3. Criterial Verification Membrane";
        style="rounded,solid";
        color="#2563eb";
        ValidationSuite [label="Independent validation suite\\n1. Exact demonstration pair reconstruction\\n2. Discrete grid dimension (1..30) & palette (0..9) checks\\n3. Structural & topological invariant predicates", fillcolor="#dbeafe"];
        VerdictAccepted [label="Accepted(artifact, metadata)\\nTyped pass verdict", fillcolor="#dcfce7"];
        VerdictRejected [label="Rejected(reason, detail)\\nTyped diagnostic failure (no numeric Inf sentinel)", fillcolor="#fee2e2"];
        VerdictIncomplete [label="Incomplete(reason, detail)\\nMissing prerequisite or budget exhaustion", fillcolor="#fef9c3"];

        ValidationSuite -> VerdictAccepted [label="all predicates hold", color="#2e7d32", style="solid", penwidth=1.8];
        ValidationSuite -> VerdictRejected [label="predicate violation", color="#c62828", style="dashed", penwidth=1.5];
        ValidationSuite -> VerdictIncomplete [label="unavailable resource", color="#b45309", style="dotted", penwidth=1.5];
    }

    subgraph cluster_julia_core {
        label="4. Julia Core (NeuroARC.jl Typed Composition & Execution)";
        style="rounded,solid";
        color="#15803d";
        TypeGrafting [label="Type-Directed Hyphal Grafting\\nPreflight: Out(A) <: In(B)\\nRuntime wrapper: x -> second(first(x))", fillcolor="#dcfce7"];
        BudgetScheduler [label="Compute Budget Scheduler\\nAllocates evaluation budget across verified compositions", fillcolor="#f0fdf4"];
        CompletionCriteria [label="Global validation status &\\nExperiment completion criteria\\n(Auditable pass/abstain ledger; no unproved convergence claim)", fillcolor="#e2e8f0"];

        TypeGrafting -> BudgetScheduler [label="Accepted(NodeC ∘ NodeB ∘ NodeA)", color="#2e7d32", style="solid", penwidth=1.8];
        BudgetScheduler -> CompletionCriteria [label="records verified task outcome", color="#1e293b", style="solid", penwidth=1.5];
    }

    CandidateGen -> SharedBuffer [label="dispatches candidate payload", color="#d97706", style="solid", penwidth=1.5];
    SharedBuffer -> ValidationSuite [label="presents candidate buffer", color="#2563eb", style="solid", penwidth=1.5];
    VerdictAccepted -> TypeGrafting [label="enters verified pipeline", color="#2e7d32", style="solid", penwidth=2.0];
    VerdictRejected -> AgentState [label="structured rejection reason\\nupdates search state", color="#c62828", style="dashed", penwidth=1.5];
    VerdictIncomplete -> CompletionCriteria [label="logged as INCOMPLETE", color="#b45309", style="dotted", penwidth=1.5];
}
"""
end

"""
    parse_dot_semantics(dot_source::AbstractString)

Lexer-aware structural parser for DOT digraphs used to verify that generated DOT
files have balanced braces outside string literals and comments, valid `digraph`
declarations, node definitions (single-line or multiline, regardless of attribute order),
and edge attributes (including brackets inside quoted strings) that correspond to
the actual `try_graft` and `try_deep_graft` preflight verdicts.
"""
function parse_dot_semantics(dot_source::AbstractString)
    # Strip comments while preserving quoted string literals and tracking brace depth outside strings/comments
    cleaned_io = IOBuffer()
    chars = collect(dot_source)
    n = length(chars)
    i = 1
    in_string = false
    in_line_comment = false
    in_block_comment = false
    depth = 0
    open_braces = 0
    close_braces = 0
    never_negative = true

    while i <= n
        c = chars[i]
        if in_line_comment
            if c == '\n'
                in_line_comment = false
                write(cleaned_io, '\n')
            end
            i += 1
        elseif in_block_comment
            if c == '*' && i < n && chars[i + 1] == '/'
                in_block_comment = false
                i += 2
            else
                i += 1
            end
        elseif in_string
            write(cleaned_io, c)
            if c == '\\' && i < n
                write(cleaned_io, chars[i + 1])
                i += 2
            else
                if c == '"'
                    in_string = false
                end
                i += 1
            end
        else
            if c == '/' && i < n && chars[i + 1] == '/'
                in_line_comment = true
                i += 2
            elseif c == '/' && i < n && chars[i + 1] == '*'
                in_block_comment = true
                i += 2
            else
                if c == '"'
                    in_string = true
                elseif c == '{'
                    open_braces += 1
                    depth += 1
                elseif c == '}'
                    close_braces += 1
                    depth -= 1
                    if depth < 0
                        never_negative = false
                    end
                end
                write(cleaned_io, c)
                i += 1
            end
        end
    end

    cleaned = String(take!(cleaned_io))
    has_digraph = occursin(r"^\s*digraph\s+[A-Za-z0-9_]+\s*\{"m, cleaned)
    balanced_braces = (!in_string) && (!in_block_comment) && never_negative && (open_braces > 0) && (depth == 0)

    edge_re = r"([A-Za-z_][A-Za-z0-9_]*)\s*->\s*([A-Za-z_][A-Za-z0-9_]*)\s*\[((?:[^\"\]\\]|\"(?:[^\"\\]|\\.)*\")*)\]\s*;"
    edges = NamedTuple{(:src, :dst, :attrs), Tuple{String, String, String}}[]
    for m in eachmatch(edge_re, cleaned)
        push!(edges, (src = String(m.captures[1]), dst = String(m.captures[2]), attrs = String(m.captures[3])))
    end

    node_re = r"(?:^|[;\{\}\n])\s*([A-Za-z_][A-Za-z0-9_]*)\s*\[((?:[^\"\]\\]|\"(?:[^\"\\]|\\.)*\")*)\]\s*;"
    nodes = String[]
    for m in eachmatch(node_re, cleaned)
        id = String(m.captures[1])
        attrs = String(m.captures[2])
        if !(id in ("node", "edge", "graph", "digraph", "subgraph")) && occursin(r"\blabel\s*=", attrs)
            push!(nodes, id)
        end
    end

    return (
        valid_syntax = has_digraph && balanced_braces && !isempty(edges) && !isempty(nodes),
        has_digraph = has_digraph,
        balanced_braces = balanced_braces,
        nodes = nodes,
        edges = edges
    )
end

"""
    try_graphviz_render(dot_path::AbstractString, svg_path::AbstractString, pdf_path::AbstractString; dot_bin=Sys.which("dot")) -> GraftVerdict

Checks whether the Graphviz `dot` executable is available.
- If `dot_path` does not exist, returns `Rejected(:missing_dot_file, ...)`.
- If `dot_bin === nothing`, returns `Incomplete(:missing_graphviz_executable, ...)` rather than
  silently treating a missing binary as a passing external render.
- If `dot_bin` is available, executes `dot -Tsvg` and `dot -Tpdf`, returning `Accepted` on success
  or `Rejected(:graphviz_render_failed, ...)` if the external command fails.
"""
function try_graphviz_render(
    dot_path::AbstractString,
    svg_path::AbstractString,
    pdf_path::AbstractString;
    dot_bin::Union{AbstractString, Nothing} = Sys.which("dot")
)
    if !isfile(dot_path)
        return Rejected(
            :missing_dot_file,
            "DOT source file does not exist at $dot_path",
            (basename(dot_path), basename(svg_path)),
            String,
            String
        )
    end
    if dot_bin === nothing
        return Incomplete(
            :missing_graphviz_executable,
            "Graphviz 'dot' executable not found on PATH; external binary rendering skipped and recorded as INCOMPLETE"
        )
    end
    try
        run(`$dot_bin -Tsvg $dot_path -o $svg_path`)
        run(`$dot_bin -Tpdf $dot_path -o $pdf_path`)
    catch err
        return Rejected(
            :graphviz_render_failed,
            "Graphviz execution failed via $dot_bin: $(sprint(showerror, err))",
            (basename(dot_path), basename(svg_path)),
            String,
            String
        )
    end
    if !isfile(svg_path) || !isfile(pdf_path)
        return Rejected(
            :graphviz_output_missing,
            "Graphviz executable $dot_bin returned 0 but did not produce expected SVG/PDF outputs",
            (basename(dot_path), basename(svg_path)),
            String,
            String
        )
    end
    return Accepted(
        (svg = svg_path, pdf = pdf_path),
        :graphviz_rendered,
        "Rendered SVG and PDF via $dot_bin",
        (basename(dot_path), basename(svg_path)),
        String,
        String
    )
end

# ------------------------------------------------------------------------------
# 7. Deterministic Native SVG Renderers for Figure B1 and Figure B2
# ------------------------------------------------------------------------------

function generate_figure_b1_svg(verdicts)::String
    ab_label = verdicts.ab.node.label_compose
    abc_label = verdicts.abc.node.label_compose
    return """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1120 660" width="100%" height="100%">
  <defs>
    <style>
      .bg { fill: #0f172a; }
      .panel { fill: #1e293b; stroke: #334155; stroke-width: 1.5; rx: 10; }
      .node-a { fill: #0c4a6e; stroke: #38bdf8; stroke-width: 2; rx: 8; }
      .node-valid { fill: #064e3b; stroke: #34d399; stroke-width: 2; rx: 8; }
      .node-comp { fill: #14532d; stroke: #4ade80; stroke-width: 2.2; rx: 8; }
      .node-reject { fill: #450a0a; stroke: #f87171; stroke-width: 2; rx: 8; }
      .title { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 18px; font-weight: 700; fill: #f8fafc; }
      .subtitle { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 12px; fill: #94a3b8; }
      .sec-hdr { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 13px; font-weight: 700; fill: #38bdf8; }
      .node-title { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 12.5px; font-weight: 700; fill: #f8fafc; }
      .mono { font-family: 'JetBrains Mono', 'Courier New', monospace; font-size: 10.5px; fill: #e2e8f0; }
      .edge-ok-txt { font-family: 'JetBrains Mono', 'Courier New', monospace; font-size: 10px; font-weight: 700; fill: #4ade80; }
      .edge-err-txt { font-family: 'JetBrains Mono', 'Courier New', monospace; font-size: 10px; font-weight: 700; fill: #f87171; }
      .edge-comp-txt { font-family: 'JetBrains Mono', 'Courier New', monospace; font-size: 10px; font-weight: 700; fill: #60a5fa; }
      .edge-ok { stroke: #22c55e; stroke-width: 2.4; fill: none; marker-end: url(#arrowOk); }
      .edge-err { stroke: #ef4444; stroke-width: 2.0; stroke-dasharray: 7,5; fill: none; marker-end: url(#arrowErr); }
      .edge-comp { stroke: #3b82f6; stroke-width: 1.8; stroke-dasharray: 4,4; fill: none; marker-end: url(#arrowComp); }
    </style>
    <marker id="arrowOk" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#22c55e"/>
    </marker>
    <marker id="arrowErr" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#ef4444"/>
    </marker>
    <marker id="arrowComp" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#3b82f6"/>
    </marker>
  </defs>

  <rect width="1120" height="660" class="bg"/>

  <!-- Header -->
  <text x="30" y="34" class="title">Figure B1: Typed Composition and Deep Grafting in NeuroARC.jl</text>
  <text x="30" y="54" class="subtitle">Preflight Type-Compatibility Verdict (Out(A) &lt;: In(B), Zero Node Calls) Coupled with Runtime Wrapper Enforcement (x -&gt; second(first(x)))</text>

  <!-- Main Graph Panel -->
  <rect x="30" y="72" width="1060" height="390" class="panel"/>
  <text x="48" y="96" class="sec-hdr">1. Typed Transformation Graph &amp; Preflight Compatibility Verdicts</text>

  <!-- Node A -->
  <rect x="52" y="135" width="230" height="90" class="node-a"/>
  <text x="66" y="158" class="node-title">Node A: PolyominoExtractor</text>
  <text x="66" y="178" class="mono">label_compose: "NodeA"</text>
  <text x="66" y="195" class="mono">In:  ColorMappedGrid</text>
  <text x="66" y="212" class="mono">Out: PolyominoGraph</text>

  <!-- Node B -->
  <rect x="440" y="115" width="230" height="90" class="node-valid"/>
  <text x="454" y="138" class="node-title">Node B: StencilStamper</text>
  <text x="454" y="158" class="mono">label_compose: "NodeB"</text>
  <text x="454" y="175" class="mono">In:  PolyominoGraph</text>
  <text x="454" y="192" class="mono">Out: ColorMappedGrid</text>

  <!-- Node C -->
  <rect x="828" y="115" width="235" height="90" class="node-valid"/>
  <text x="842" y="138" class="node-title">Node C: ColorPermutor</text>
  <text x="842" y="158" class="mono">label_compose: "NodeC"</text>
  <text x="842" y="175" class="mono">In:  ColorMappedGrid</text>
  <text x="842" y="192" class="mono">Out: ColorMappedGrid</text>

  <!-- Node X (Rejected Branch) -->
  <rect x="440" y="325" width="230" height="100" class="node-reject"/>
  <text x="454" y="348" class="node-title">Node X: InvalidTransformer</text>
  <text x="454" y="368" class="mono">label_compose: "NodeX"</text>
  <text x="454" y="385" class="mono">In:  BoundedPolyomino (max_span)</text>
  <text x="454" y="402" class="mono">Out: ColorMappedGrid</text>
  <text x="454" y="417" class="edge-ok-txt">Direct call valid on BoundedPolyomino</text>

  <!-- Composed NodeB ∘ NodeA -->
  <rect x="580" y="228" width="230" height="82" class="node-comp"/>
  <text x="594" y="250" class="node-title">Composed: $(ab_label)</text>
  <text x="594" y="268" class="mono">fn: x -&gt; nodeB(nodeA(x))</text>
  <text x="594" y="285" class="mono">In: ColorMappedGrid</text>
  <text x="594" y="300" class="mono">Out: ColorMappedGrid</text>

  <!-- Deep Graft NodeC ∘ NodeB ∘ NodeA -->
  <rect x="828" y="228" width="235" height="82" class="node-comp"/>
  <text x="842" y="250" class="node-title">Deep Graft: $(abc_label)</text>
  <text x="842" y="268" class="mono">fn: x -&gt; nodeC((nodeB ∘ nodeA)(x))</text>
  <text x="842" y="285" class="mono">In: ColorMappedGrid</text>
  <text x="842" y="300" class="mono">Out: ColorMappedGrid</text>

  <!-- Edges -->
  <!-- NodeA -> NodeB -->
  <line x1="282" y1="160" x2="432" y2="160" class="edge-ok"/>
  <text x="292" y="134" class="edge-ok-txt">Accepted (:subtype_compatible)</text>
  <text x="292" y="148" class="mono">Out(NodeA) &lt;: In(NodeB)</text>
  <text x="292" y="176" class="mono">(PolyominoGraph &lt;: PolyominoGraph)</text>

  <!-- NodeB -> NodeC -->
  <line x1="670" y1="160" x2="820" y2="160" class="edge-ok"/>
  <text x="680" y="134" class="edge-ok-txt">Accepted (:subtype_compatible)</text>
  <text x="680" y="148" class="mono">Out(NodeB) &lt;: In(NodeC)</text>
  <text x="680" y="176" class="mono">(ColorMappedGrid &lt;: ColorMappedGrid)</text>

  <!-- NodeA -> NodeX (Rejected) -->
  <path d="M 167 225 L 167 375 L 432 375" class="edge-err"/>
  <text x="180" y="340" class="edge-err-txt">Rejected by Preflight Validator (:type_mismatch)</text>
  <text x="180" y="356" class="mono">!(Out(NodeA) &lt;: In(NodeX)): PolyominoGraph not &lt;: BoundedPolyomino</text>
  <text x="180" y="394" class="mono">0 node executions during preflight (distinct from runtime MethodError)</text>

  <!-- Lineage arrows to composed nodes -->
  <path d="M 555 205 L 555 268 L 572 268" class="edge-comp"/>
  <line x1="810" y1="268" x2="822" y2="268" class="edge-comp"/>

  <!-- Bottom Contract Distinction Panel -->
  <rect x="30" y="478" width="1060" height="156" class="panel"/>
  <text x="48" y="502" class="sec-hdr">2. Contract Separation: Static Preflight Check vs Runtime Boundary Enforcement</text>

  <text x="48" y="526" class="mono">1. Preflight Check (can_graft / try_graft / try_deep_graft): Tests declared subtype relation Out(first) &lt;: In(second) without calling node.f (counter == 0).</text>
  <text x="48" y="546" class="mono">2. Composition Order &amp; Naming: If NodeA runs first and NodeB second, the composed operator is "$(ab_label)", and 3-stage deep graft is "$(abc_label)".</text>
  <text x="48" y="566" class="mono">3. Runtime Wrapper Contract: comp_fn = x -&gt; second(first(x)) invokes each GraftNode wrapper, enforcing input dispatch (MethodError if bypassed)</text>
  <text x="48" y="584" class="mono">   and Core.typeassert(y, OutType) at every intermediate boundary (TypeError if an intermediate node function returns an undeclared runtime type).</text>
  <text x="48" y="604" class="mono">4. Typed Verdicts: Returns Accepted(node, ...), Rejected(reason, ...), or Incomplete(reason, ...) instead of leaking numeric Inf sentinels.</text>
</svg>
"""
end

function generate_figure_b2_svg()::String
    return """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1120 720" width="100%" height="100%">
  <defs>
    <style>
      .bg { fill: #0f172a; }
      .layer-py { fill: #0f172a; stroke: #0284c7; stroke-width: 1.8; stroke-dasharray: 6,4; rx: 10; }
      .layer-ffi { fill: #0f172a; stroke: #d97706; stroke-width: 1.8; stroke-dasharray: 6,4; rx: 10; }
      .layer-mem { fill: #0f172a; stroke: #3b82f6; stroke-width: 2.0; rx: 10; }
      .layer-jl { fill: #0f172a; stroke: #22c55e; stroke-width: 2.0; rx: 10; }
      .box-py { fill: #1e293b; stroke: #38bdf8; stroke-width: 1.5; rx: 8; }
      .box-ffi { fill: #27272a; stroke: #f59e0b; stroke-width: 1.8; rx: 8; }
      .box-mem { fill: #1e293b; stroke: #60a5fa; stroke-width: 1.8; rx: 8; }
      .box-acc { fill: #064e3b; stroke: #34d399; stroke-width: 1.8; rx: 8; }
      .box-rej { fill: #450a0a; stroke: #f87171; stroke-width: 1.8; rx: 8; }
      .box-inc { fill: #422006; stroke: #fbbf24; stroke-width: 1.8; rx: 8; }
      .box-jl { fill: #14532d; stroke: #4ade80; stroke-width: 1.8; rx: 8; }
      .box-status { fill: #1e293b; stroke: #94a3b8; stroke-width: 1.8; rx: 8; }
      .title { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 18px; font-weight: 700; fill: #f8fafc; }
      .subtitle { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 12px; fill: #94a3b8; }
      .layer-hdr { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 13px; font-weight: 700; fill: #f8fafc; }
      .box-hdr { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; font-size: 12px; font-weight: 700; fill: #f8fafc; }
      .mono { font-family: 'JetBrains Mono', 'Courier New', monospace; font-size: 10px; fill: #cbd5e1; }
      .tag-prop { font-family: 'JetBrains Mono', 'Courier New', monospace; font-size: 10px; font-weight: 700; fill: #fbbf24; }
      .tag-ok { font-family: 'JetBrains Mono', 'Courier New', monospace; font-size: 10px; font-weight: 700; fill: #4ade80; }
      .tag-err { font-family: 'JetBrains Mono', 'Courier New', monospace; font-size: 10px; font-weight: 700; fill: #f87171; }
      .arrow-blue { stroke: #38bdf8; stroke-width: 1.8; fill: none; marker-end: url(#arrBlue); }
      .arrow-amber { stroke: #f59e0b; stroke-width: 1.8; fill: none; marker-end: url(#arrAmber); }
      .arrow-green { stroke: #22c55e; stroke-width: 2.2; fill: none; marker-end: url(#arrGreen); }
      .arrow-red { stroke: #ef4444; stroke-width: 1.8; stroke-dasharray: 6,4; fill: none; marker-end: url(#arrRed); }
    </style>
    <marker id="arrBlue" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#38bdf8"/>
    </marker>
    <marker id="arrAmber" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#f59e0b"/>
    </marker>
    <marker id="arrGreen" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#22c55e"/>
    </marker>
    <marker id="arrRed" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#ef4444"/>
    </marker>
  </defs>

  <rect width="1120" height="720" class="bg"/>

  <!-- Header -->
  <text x="30" y="34" class="title">Figure B2: NeuroARC Agent Execution and Verification Architecture</text>
  <text x="30" y="54" class="subtitle">Separating Proposed Architecture, Implementation Contracts, and Auditable Completion Criteria (No Unproved Zero-Copy or Convergence Claims)</text>

  <!-- Layer 1: Presynaptic Layer -->
  <rect x="30" y="74" width="1060" height="112" class="layer-py"/>
  <text x="48" y="96" class="layer-hdr">1. Presynaptic Candidate Layer (Python Search Controller &amp; Rule Proposer)</text>

  <rect x="48" y="108" width="440" height="64" class="box-py"/>
  <text x="64" y="128" class="box-hdr">Search Strategy State Machine</text>
  <text x="64" y="145" class="mono">Mode transitions: Focus -&gt; Frustration -&gt; Panic</text>
  <text x="64" y="160" class="mono">Updates search operator weights from typed rejection reasons</text>

  <rect x="550" y="108" width="510" height="64" class="box-py"/>
  <text x="566" y="128" class="box-hdr">Candidate Transformation &amp; Grid Proposer</text>
  <text x="566" y="145" class="mono">Emits candidate rule specification + demonstration predictions</text>
  <text x="566" y="160" class="tag-prop">[PROPOSED ARCHITECTURE: Heuristic Candidate Generation]</text>

  <line x1="488" y1="140" x2="542" y2="140" class="arrow-blue"/>

  <!-- Layer 2: Cross-Language Transport Boundary -->
  <rect x="30" y="206" width="1060" height="96" class="layer-ffi"/>
  <text x="48" y="228" class="layer-hdr">2. Cross-Language Data Exchange Boundary (Python &lt;-&gt; Julia)</text>

  <rect x="180" y="238" width="760" height="52" class="box-ffi"/>
  <text x="200" y="258" class="box-hdr">Proposed shared-buffer interface</text>
  <text x="200" y="276" class="mono">Passes candidate array descriptors across language boundary (allocation, ownership, and concurrency tests required before zero-copy claims)</text>

  <line x1="805" y1="172" x2="805" y2="232" class="arrow-amber"/>

  <!-- Layer 3: Criterial Verification Membrane -->
  <rect x="30" y="322" width="1060" height="186" class="layer-mem"/>
  <text x="48" y="344" class="layer-hdr">3. Criterial Verification Membrane (Deterministic Gate Prior to Pipeline Integration)</text>

  <rect x="180" y="356" width="760" height="56" class="box-mem"/>
  <text x="200" y="376" class="box-hdr">Independent validation suite</text>
  <text x="200" y="394" class="mono">Predicates: (1) 100% exact demonstration reconstruction, (2) grid bounds 1..30 &amp; palette 0..9, (3) structural invariant checks</text>

  <line x1="560" y1="290" x2="560" y2="350" class="arrow-blue"/>

  <!-- Three Typed Verdict Boxes -->
  <rect x="48" y="430" width="320" height="64" class="box-rej"/>
  <text x="64" y="450" class="box-hdr">Rejected(reason, detail)</text>
  <text x="64" y="467" class="mono">Structured failure diagnostic</text>
  <text x="64" y="482" class="tag-err">No numeric Inf leaked to optimizer</text>

  <rect x="400" y="430" width="320" height="64" class="box-acc"/>
  <text x="416" y="450" class="box-hdr">Accepted(artifact, metadata)</text>
  <text x="416" y="467" class="mono">All demonstration &amp; type predicates pass</text>
  <text x="416" y="482" class="tag-ok">Enters verified Julia composition core</text>

  <rect x="752" y="430" width="318" height="64" class="box-inc"/>
  <text x="768" y="450" class="box-hdr">Incomplete(reason, detail)</text>
  <text x="768" y="467" class="mono">Empty chain, missing tool, or timeout</text>
  <text x="768" y="482" class="tag-prop">Audited explicitly; never silent pass</text>

  <path d="M 320 412 L 208 426" class="arrow-red"/>
  <line x1="560" y1="412" x2="560" y2="424" class="arrow-green"/>
  <path d="M 800 412 L 910 426" class="arrow-amber"/>

  <!-- Feedback loop from Rejected to Search Strategy -->
  <path d="M 48 462 L 18 462 L 18 140 L 42 140" class="arrow-red"/>

  <!-- Layer 4: Julia Core -->
  <rect x="30" y="528" width="1060" height="164" class="layer-jl"/>
  <text x="48" y="550" class="layer-hdr">4. Julia Core (NeuroARC.jl Type-Directed Composition, Scheduling &amp; Experiment Ledger)</text>

  <rect x="48" y="566" width="330" height="106" class="box-jl"/>
  <text x="64" y="588" class="box-hdr">Typed Hyphal &amp; Deep Grafting</text>
  <text x="64" y="606" class="mono">Preflight: Out(A) &lt;: In(B)</text>
  <text x="64" y="622" class="mono">Order: NodeC ∘ NodeB ∘ NodeA</text>
  <text x="64" y="638" class="mono">Wrapper: x -&gt; second(first(x))</text>
  <text x="64" y="654" class="tag-ok">[VERIFIED RUNTIME CONTRACT]</text>

  <rect x="410" y="566" width="300" height="106" class="box-py"/>
  <text x="426" y="588" class="box-hdr">Compute Budget Scheduler</text>
  <text x="426" y="606" class="mono">Allocates evaluation tokens across</text>
  <text x="426" y="622" class="mono">verified candidate pipelines</text>
  <text x="426" y="638" class="mono">Tracks step latency &amp; censoring</text>
  <text x="426" y="654" class="tag-prop">[PROPOSED SCHEDULING POLICY]</text>

  <rect x="742" y="566" width="328" height="106" class="box-status"/>
  <text x="758" y="588" class="box-hdr">Experiment completion criteria</text>
  <text x="758" y="606" class="mono">Global validation status ledger:</text>
  <text x="758" y="622" class="mono">- Verified Exact Match on demos</text>
  <text x="758" y="638" class="mono">- Explicit Abstain / Incomplete</text>
  <text x="758" y="654" class="tag-prop">[REPLACES UNPROVED CONVERGENCE CLAIM]</text>

  <path d="M 560 494 L 560 515 L 213 515 L 213 560" class="arrow-green"/>
  <line x1="378" y1="619" x2="404" y2="619" class="arrow-green"/>
  <line x1="710" y1="619" x2="736" y2="619" class="arrow-blue"/>
  <line x1="910" y1="494" x2="910" y2="560" class="arrow-amber"/>
</svg>
"""
end

end # module HyphalGraftingContract
