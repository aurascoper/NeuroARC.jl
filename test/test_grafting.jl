module TestGrafting

# test/test_grafting.jl
# Test Execution & Artifact Generation Suite
# ==============================================================================

using Test
using NeuroARC
using NeuroARC.HyphalGraftingContract

const SCRATCH_DIR = mktempdir()
const FIGURES_DIR = normpath(joinpath(@__DIR__, "..", "manuscript", "figures"))

atexit(() -> rm(SCRATCH_DIR; force = true, recursive = true))

mkpath(FIGURES_DIR)

println("======================================================================")
println("Running Paper B Hyphal Grafting Contract Verification Suite")
println("Julia Version: ", VERSION)
println("Scratch Directory: ", SCRATCH_DIR)
println("======================================================================")

@testset verbose=true "Paper B Hyphal Grafting & Deep Grafting Contract Suite" begin

    # --------------------------------------------------------------------------
    # Testset 1: Direct Execution of Every Valid Node & Fixed nodeX Fixture
    # (Resolves Blocking Issue 3 & Acceptance Criterion 1, 2)
    # --------------------------------------------------------------------------
    @testset "1. Direct Node Execution & Fixed nodeX Fixture (bp.max_span)" begin
        fx = build_canonical_fixtures()
        sample_grid = ColorMappedGrid([1 0 2; 0 3 0])

        # Direct call to nodeA
        pg = fx.nodeA(sample_grid)
        @test pg isa PolyominoGraph
        @test pg.coords == [(1, 1), (1, 3), (2, 2)]
        @test pg.colors == [1, 2, 3]
        @test fx.counts.A[] == 1

        # Direct call to nodeB
        stamped = fx.nodeB(pg)
        @test stamped isa ColorMappedGrid
        @test stamped == sample_grid
        @test fx.counts.B[] == 1

        # Direct call to nodeC
        permuted = fx.nodeC(stamped)
        @test permuted isa ColorMappedGrid
        @test permuted == ColorMappedGrid([2 0 3; 0 4 0])
        @test fx.counts.C[] == 1

        # Direct call to nodeX with valid BoundedPolyomino input (Blocking Issue 3)
        bp = BoundedPolyomino([(1, 1)], 5)
        @test bp.max_span == 5
        x_out = fx.nodeX(bp)
        @test x_out isa ColorMappedGrid
        @test x_out == ColorMappedGrid([5 5; 5 5])
        @test fx.counts.X[] == 1

        # Constructor invariant checks: PolyominoGraph length mismatch and GraftNode non-Type parameters
        @test_throws ArgumentError PolyominoGraph([(1, 1), (1, 2)], [5])
        @test_throws ArgumentError GraftNode{:not_a_type, Int}("BadIn", "BadIn", identity)
        @test_throws ArgumentError GraftNode{Int, 42}("BadOut", "BadOut", identity)
    end

    # --------------------------------------------------------------------------
    # Testset 2: Zero Node Execution During Preflight vs Runtime MethodError
    # (Resolves Blocking Issue 4 & Acceptance Criterion 2)
    # --------------------------------------------------------------------------
    @testset "2. Zero Execution During Preflight vs Runtime MethodError" begin
        fx = build_canonical_fixtures()

        # Boolean preflight checks execute zero node functions
        @test can_graft(fx.nodeA, fx.nodeB) == true
        @test can_graft(fx.nodeB, fx.nodeC) == true
        @test can_graft(fx.nodeA, fx.nodeX) == false
        @test can_graft(fx.nodeX, fx.nodeC) == true
        @test can_graft("not_a_node", fx.nodeB) == false
        @test fx.counts.A[] == 0
        @test fx.counts.B[] == 0
        @test fx.counts.C[] == 0
        @test fx.counts.X[] == 0

        # Pairwise try_graft (both Accepted and Rejected) executes zero node functions
        v_ab = try_graft(fx.nodeA, fx.nodeB)
        v_bc = try_graft(fx.nodeB, fx.nodeC)
        v_ax = try_graft(fx.nodeA, fx.nodeX)

        @test v_ab isa Accepted
        @test v_ab.reason == :subtype_compatible
        @test v_bc isa Accepted
        @test v_bc.reason == :subtype_compatible
        @test v_ax isa Rejected
        @test v_ax.reason == :type_mismatch
        @test v_ax.edge_pair == ("NodeA", "NodeX")
        @test v_ax.out_type == PolyominoGraph
        @test v_ax.in_type == BoundedPolyomino

        # Assert all instrumentation counters are STILL zero after preflight
        @test fx.counts.A[] == 0
        @test fx.counts.B[] == 0
        @test fx.counts.C[] == 0
        @test fx.counts.X[] == 0

        # Deep preflight checks (both Accepted and Rejected at idx=2 and idx=3) execute zero node functions
        v_abc = try_deep_graft([fx.nodeA, fx.nodeB, fx.nodeC])
        v_axc = try_deep_graft([fx.nodeA, fx.nodeX, fx.nodeC])
        v_abx = try_deep_graft([fx.nodeA, fx.nodeB, fx.nodeX])
        @test v_abc isa Accepted
        @test v_axc isa Rejected
        @test v_axc.reason == :type_mismatch
        @test v_axc.edge_pair == ("NodeA", "NodeX")
        @test v_abx isa Rejected
        @test v_abx.reason == :type_mismatch
        @test v_abx.edge_pair == ("NodeB", "NodeX")
        @test v_abx.out_type == ColorMappedGrid
        @test v_abx.in_type == BoundedPolyomino
        @test fx.counts.A[] == 0
        @test fx.counts.B[] == 0
        @test fx.counts.C[] == 0
        @test fx.counts.X[] == 0

        # Separate runtime test: bypassing preflight and calling nodeX with PolyominoGraph
        # raises MethodError at runtime without executing nodeX's body (counts.X[] == 0)
        sample_grid = ColorMappedGrid([1 2; 0 4])
        pg_out = fx.nodeA(sample_grid)
        @test fx.counts.A[] == 1
        @test_throws MethodError fx.nodeX(pg_out)
        @test fx.counts.X[] == 0
    end

    # --------------------------------------------------------------------------
    # Testset 3: Composition Labels, Order, and Intermediate Runtime Boundary TypeError
    # (Resolves Blocking Issues 1 & 2, Acceptance Criteria 1 & 3)
    # --------------------------------------------------------------------------
    @testset "3. Composition Labels, Order & Intermediate Boundary Runtime Contract" begin
        fx = build_canonical_fixtures()

        v_ab = try_graft(fx.nodeA, fx.nodeB)
        @test v_ab isa Accepted
        @test v_ab.node.label_compose == "NodeB ∘ NodeA"
        @test in_type(v_ab.node) == ColorMappedGrid
        @test out_type(v_ab.node) == ColorMappedGrid

        v_abc = try_deep_graft([fx.nodeA, fx.nodeB, fx.nodeC])
        @test v_abc isa Accepted
        @test v_abc.node.label_compose == "NodeC ∘ NodeB ∘ NodeA"
        @test in_type(v_abc.node) == ColorMappedGrid
        @test out_type(v_abc.node) == ColorMappedGrid

        # Execute composed pipeline and verify order: C(B(A(grid)))
        input_grid = ColorMappedGrid([1 0; 0 9])
        result_grid = v_abc.node(input_grid)
        @test result_grid == ColorMappedGrid([2 0; 0 1])
        @test fx.counts.A[] == 1
        @test fx.counts.B[] == 1
        @test fx.counts.C[] == 1
        @test fx.counts.X[] == 0

        # Intermediate runtime boundary contract violation test:
        # Dishonest intermediate node declares Out = PolyominoGraph (so preflight accepts it),
        # but its runtime function returns a BoundedPolyomino (wrong runtime type).
        # Even when paired with a downstream node accepting `Any`, `comp_fn = x -> second(first(x))`
        # must catch the wrong return type at `first(x)` via `Core.typeassert` and throw `TypeError`
        # before `second` ever runs!
        downstream_counter = Ref(0)
        dishonest_first = GraftNode{ColorMappedGrid, PolyominoGraph}(
            "DishonestExtractor",
            "DishonestA",
            cmg -> BoundedPolyomino([(1, 1)], 99) # Violates declared Out = PolyominoGraph!
        )
        lenient_second = GraftNode{Any, ColorMappedGrid}(
            "LenientStamper",
            "LenientB",
            function(any_val)
                downstream_counter[] += 1
                return ColorMappedGrid(zeros(Int, 2, 2))
            end
        )

        # Preflight succeeds because Out(dishonest_first) == PolyominoGraph <: Any == In(lenient_second)
        v_dishonest = try_graft(dishonest_first, lenient_second)
        @test v_dishonest isa Accepted
        @test v_dishonest.node.label_compose == "LenientB ∘ DishonestA"
        @test downstream_counter[] == 0

        # Runtime execution of the composed pipeline throws TypeError at the intermediate boundary
        # and prevents lenient_second from executing!
        @test_throws TypeError v_dishonest.node(input_grid)
        @test downstream_counter[] == 0

        # Same check inside a 3-stage deep graft where the middle node violates its return type
        mid_bad_counter = Ref(0)
        bad_middle = GraftNode{PolyominoGraph, ColorMappedGrid}(
            "BadMiddle",
            "BadMid",
            pg -> (mid_bad_counter[] += 1; "not_a_grid") # Returns String instead of ColorMappedGrid
        )
        c_counter = Ref(0)
        tracked_C = GraftNode{ColorMappedGrid, ColorMappedGrid}(
            "TrackedC",
            "NodeC",
            cmg -> (c_counter[] += 1; cmg)
        )
        v_deep_bad_mid = try_deep_graft([fx.nodeA, bad_middle, tracked_C])
        @test v_deep_bad_mid isa Accepted
        @test v_deep_bad_mid.node.label_compose == "NodeC ∘ BadMid ∘ NodeA"
        @test_throws TypeError v_deep_bad_mid.node(input_grid)
        @test mid_bad_counter[] == 1
        @test c_counter[] == 0
    end

    # --------------------------------------------------------------------------
    # Testset 4: Strict Subtyping, Parametric UnionAll/Covariance/Invariance
    # & Edge Cases for Empty/Invalid Chains
    # --------------------------------------------------------------------------
    @testset "4. Strict Subtyping, Parametric Types & Chain Edge Cases" begin
        fx = build_canonical_fixtures()

        # Strict subtype test: PolyominoGraph <: AbstractPolyomino and BoundedPolyomino <: AbstractPolyomino
        poly_consumer = GraftNode{AbstractPolyomino, ColorMappedGrid}(
            "Node P: AbstractPolyominoConsumer",
            "NodeP",
            ap -> ColorMappedGrid(fill(length(ap.coords), 2, 2))
        )
        @test Out(fx.nodeA) != In(poly_consumer)
        @test Out(fx.nodeA) <: In(poly_consumer)

        v_ap = try_graft(fx.nodeA, poly_consumer)
        @test v_ap isa Accepted
        @test v_ap.node.label_compose == "NodeP ∘ NodeA"
        @test v_ap.node(ColorMappedGrid([1 2; 0 3])) == ColorMappedGrid([3 3; 3 3])

        # Parametric invariance vs UnionAll vs Tuple covariance
        vec_int_producer = GraftNode{Int, Vector{Int}}("VecIntProd", "VecIntProd", n -> [n, n + 1])
        vec_real_invariant = GraftNode{Vector{Real}, Int}("VecRealInv", "VecRealInv", v -> length(v))
        vec_real_unionall = GraftNode{Vector{<:Real}, Int}("VecRealCov", "VecRealCov", v -> sum(v))
        tuple_producer = GraftNode{Int, Tuple{Int, Float64}}("TupProd", "TupProd", n -> (n, Float64(n)))
        tuple_consumer = GraftNode{Tuple{Real, Real}, Float64}("TupCons", "TupCons", t -> Float64(t[1] + t[2]))

        # Vector{Int} is NOT a subtype of invariant Vector{Real}, but IS a subtype of UnionAll Vector{<:Real}
        @test try_graft(vec_int_producer, vec_real_invariant) isa Rejected
        v_unionall = try_graft(vec_int_producer, vec_real_unionall)
        @test v_unionall isa Accepted
        @test v_unionall.node(5) == 11

        # Covariant Tuple{Int, Float64} <: Tuple{Real, Real}
        v_cov_tuple = try_graft(tuple_producer, tuple_consumer)
        @test v_cov_tuple isa Accepted
        @test v_cov_tuple.node(3) == 6.0

        # Multi-parameter UnionAll type bounds: Dict{String, Int} <: Dict{<:AbstractString, <:Integer}
        dict_producer = GraftNode{Int, Dict{String, Int}}("DictProd", "DictProd", n -> Dict("size" => n))
        dict_consumer = GraftNode{Dict{<:AbstractString, <:Integer}, Int}("DictCons", "DictCons", d -> length(d))
        dict_bad_consumer = GraftNode{Dict{String, Float64}, Int}("DictBadCons", "DictBadCons", d -> length(d))

        v_dict_ok = try_graft(dict_producer, dict_consumer)
        @test v_dict_ok isa Accepted
        @test v_dict_ok.node(99) == 1

        v_dict_bad = try_graft(dict_producer, dict_bad_consumer)
        @test v_dict_bad isa Rejected
        @test v_dict_bad.reason == :type_mismatch

        # Empty chain -> Incomplete(:empty_chain, ...)
        v_empty = try_deep_graft(GraftNode[])
        @test v_empty isa Incomplete
        @test v_empty.reason == :empty_chain

        # Unsupported collection shape (e.g., Tuple or nothing) -> Incomplete(:unsupported_chain_collection, ...)
        v_tuple = try_deep_graft((fx.nodeA, fx.nodeB))
        @test v_tuple isa Incomplete
        @test v_tuple.reason == :unsupported_chain_collection

        v_nil = try_deep_graft(nothing)
        @test v_nil isa Incomplete
        @test v_nil.reason == :unsupported_chain_collection

        # Single-element valid chain -> Accepted(:single_node_chain, ...)
        v_single = try_deep_graft([fx.nodeA])
        @test v_single isa Accepted
        @test v_single.reason == :single_node_chain
        @test v_single.node === fx.nodeA

        # Non-GraftNode element in chain -> Rejected(:invalid_node_element, ...)
        v_bad_elem = try_deep_graft([fx.nodeA, :not_a_node, fx.nodeC])
        @test v_bad_elem isa Rejected
        @test v_bad_elem.reason == :invalid_node_element
        @test v_bad_elem.edge_pair == ("chain[2]", "Symbol")

        # Non-GraftNode arguments to try_graft -> Rejected(:invalid_node_element, ...)
        v_bad_pair = try_graft(fx.nodeA, 42)
        @test v_bad_pair isa Rejected
        @test v_bad_pair.reason == :invalid_node_element
    end

    # --------------------------------------------------------------------------
    # Testset 5: DOT & SVG Generation, Semantic Validation & Graphviz Binary Check
    # (Resolves Acceptance Criterion 4)
    # --------------------------------------------------------------------------
    @testset "5. Figure B1 & B2 DOT/SVG Generation and Semantic Validation" begin
        fx = build_canonical_fixtures()
        verdicts = (
            ab = try_graft(fx.nodeA, fx.nodeB),
            bc = try_graft(fx.nodeB, fx.nodeC),
            ax = try_graft(fx.nodeA, fx.nodeX),
            abc = try_deep_graft([fx.nodeA, fx.nodeB, fx.nodeC])
        )

        # Verify _short_type preserves parametric type structure while stripping module prefixes
        @test HyphalGraftingContract._short_type(Tuple{Base.RefValue{Int}, Int}) == "Tuple{RefValue{$Int}, $Int}"

        dot_b1 = generate_figure_b1_dot(fx, verdicts)
        dot_b2 = generate_figure_b2_dot()

        dot_b1_path = joinpath(SCRATCH_DIR, "figure_b1_typed_grafting.dot")
        dot_b2_path = joinpath(SCRATCH_DIR, "figure_b2_agent_execution.dot")
        write(dot_b1_path, dot_b1)
        write(dot_b2_path, dot_b2)

        # Parse and validate Figure B1 DOT semantics against actual preflight verdicts
        parsed_b1 = parse_dot_semantics(dot_b1)
        @test parsed_b1.valid_syntax
        @test "NodeA" in parsed_b1.nodes
        @test "NodeB" in parsed_b1.nodes
        @test "NodeC" in parsed_b1.nodes
        @test "NodeX" in parsed_b1.nodes
        @test occursin("NodeB ∘ NodeA", dot_b1)
        @test occursin("NodeC ∘ NodeB ∘ NodeA", dot_b1)
        @test !occursin("∘Node", dot_b1) # No missing space after composition operator

        # Confirm Accepted and Rejected edges in DOT correspond to actual verdicts
        edge_ab = only(filter(e -> e.src == "NodeA" && e.dst == "NodeB", parsed_b1.edges))
        edge_bc = only(filter(e -> e.src == "NodeB" && e.dst == "NodeC", parsed_b1.edges))
        edge_ax = only(filter(e -> e.src == "NodeA" && e.dst == "NodeX", parsed_b1.edges))

        @test occursin("Accepted (subtype_compatible)", edge_ab.attrs)
        @test occursin("color=\"#2e7d32\"", edge_ab.attrs)
        @test occursin("style=\"solid\"", edge_ab.attrs)

        @test occursin("Accepted (subtype_compatible)", edge_bc.attrs)
        @test occursin("color=\"#2e7d32\"", edge_bc.attrs)

        @test occursin("Rejected by Preflight (type_mismatch)", edge_ax.attrs)
        @test occursin("color=\"#c62828\"", edge_ax.attrs)
        @test occursin("style=\"dashed\"", edge_ax.attrs)

        # Parse and validate Figure B2 DOT semantics
        parsed_b2 = parse_dot_semantics(dot_b2)
        @test parsed_b2.valid_syntax
        @test occursin("Proposed shared-buffer interface", dot_b2)
        @test occursin("Independent validation suite", dot_b2)
        @test occursin("Experiment completion criteria", dot_b2)
        @test occursin("Global validation status", dot_b2)
        @test occursin("Accepted(artifact, metadata)", dot_b2)
        @test occursin("Rejected(reason, detail)", dot_b2)
        @test occursin("Incomplete(reason, detail)", dot_b2)

        # Adversarial DOT parser tests: unclosed digraph with } in string literal, multiline attributes, and ] in label
        broken_dot = "digraph Broken {\n    NodeA [label=\"brace } inside string\"];\n    NodeA -> NodeB [label=\"ok\"];\n"
        @test !parse_dot_semantics(broken_dot).balanced_braces
        @test !parse_dot_semantics(broken_dot).valid_syntax

        multiline_bracket_dot = """
        digraph MultilineValid {
            NodeA [fillcolor="#e1f5fe", label="Node A"];
            NodeB [
                label="Node B",
                fillcolor="#e8f5e9"
            ];
            NodeA -> NodeB [
                label="range [1..30] & brace {x}",
                color="#2e7d32"
            ];
        }
        """
        parsed_ml = parse_dot_semantics(multiline_bracket_dot)
        @test parsed_ml.valid_syntax
        @test parsed_ml.nodes == ["NodeA", "NodeB"]
        @test length(parsed_ml.edges) == 1
        @test parsed_ml.edges[1].src == "NodeA" && parsed_ml.edges[1].dst == "NodeB"

        # Generate deterministic native SVGs in scratch and copy to brain figures dir
        svg_b1 = generate_figure_b1_svg(verdicts)
        svg_b2 = generate_figure_b2_svg()

        svg_b1_scratch = joinpath(SCRATCH_DIR, "figure_b1_typed_grafting.svg")
        svg_b2_scratch = joinpath(SCRATCH_DIR, "figure_b2_agent_execution.svg")
        write(svg_b1_scratch, svg_b1)
        write(svg_b2_scratch, svg_b2)

        if get(ENV, "UPDATE_FIGURES", "0") == "1"
            cp(svg_b1_scratch, joinpath(FIGURES_DIR, "figure_b1_typed_grafting.svg"); force = true)
            cp(svg_b2_scratch, joinpath(FIGURES_DIR, "figure_b2_agent_execution.svg"); force = true)
        end

        @test isfile(svg_b1_scratch)
        @test isfile(svg_b2_scratch)
        @test isfile(joinpath(FIGURES_DIR, "figure_b1_typed_grafting.svg"))
        @test isfile(joinpath(FIGURES_DIR, "figure_b2_agent_execution.svg"))

        # Check Graphviz binary rendering verdict on host (Accepted if `dot` is installed, Incomplete if missing)
        gv_b1 = try_graphviz_render(
            dot_b1_path,
            joinpath(SCRATCH_DIR, "figure_b1_graphviz.svg"),
            joinpath(SCRATCH_DIR, "figure_b1_graphviz.pdf")
        )
        if Sys.which("dot") === nothing
            @test gv_b1 isa Incomplete
            @test gv_b1.reason == :missing_graphviz_executable
            println("Graphviz binary check: INCOMPLETE (", gv_b1.detail, ")")
        else
            @test gv_b1 isa Accepted
            println("Graphviz binary check: ACCEPTED (", gv_b1.detail, ")")
        end

        # Verify try_graphviz_render error/success branches deterministically in a temp directory
        mktempdir() do tmpd
            missing_dot = try_graphviz_render(
                joinpath(tmpd, "nonexistent.dot"),
                joinpath(tmpd, "out.svg"),
                joinpath(tmpd, "out.pdf")
            )
            @test missing_dot isa Rejected
            @test missing_dot.reason == :missing_dot_file

            failed_exec = try_graphviz_render(
                dot_b1_path,
                joinpath(tmpd, "out.svg"),
                joinpath(tmpd, "out.pdf");
                dot_bin = "/usr/bin/false"
            )
            @test failed_exec isa Rejected
            @test failed_exec.reason == :graphviz_render_failed

            mock_dot = joinpath(tmpd, "mock_dot.sh")
            write(mock_dot, "#!/bin/sh\n# Writes output file after -o flag\nwhile [ \$# -gt 0 ]; do\n  if [ \"\$1\" = \"-o\" ]; then\n    echo \"mock_render\" > \"\$2\"\n    shift 2\n  else\n    shift\n  fi\ndone\n")
            chmod(mock_dot, 0o755)
            mock_svg = joinpath(tmpd, "mock.svg")
            mock_pdf = joinpath(tmpd, "mock.pdf")
            ok_exec = try_graphviz_render(dot_b1_path, mock_svg, mock_pdf; dot_bin = mock_dot)
            @test ok_exec isa Accepted
            @test ok_exec.reason == :graphviz_rendered
            @test isfile(mock_svg) && isfile(mock_pdf)
        end

        # Zero em-dash (\u2014) and zero en-dash (\u2013) check on all generated artifacts
        quarantined_needle = "free-will" * " " * "octane"
        for fpath in (dot_b1_path, dot_b2_path, svg_b1_scratch, svg_b2_scratch, @__FILE__)
            content = read(fpath, String)
            @test !occursin('\u2014', content)
            @test !occursin('\u2013', content)
            @test !occursin(quarantined_needle, lowercase(content))
        end
    end
end


end # module TestGrafting
