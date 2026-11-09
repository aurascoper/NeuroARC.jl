module TestCore

using Test
using NeuroARC

@testset "NeuroARC Test Suite" begin

    @testset "1. Core Types & GridState Validation" begin
        # Valid grid
        cells = Int8[0 1 2; 0 3 0; 0 0 0]
        g = GridState(cells)
        @test g.height == 3
        @test g.width == 3
        @test g.bg_color == Int8(0)
        # Palette bitmask: 0, 1, 2, 3 -> (1<<0) | (1<<1) | (1<<2) | (1<<3) = 1 + 2 + 4 + 8 = 15
        @test g.palette == UInt16(15)
        @test size(g) == (3, 3)
        @test size(g, 1) == 3
        @test size(g, 2) == 3
        @test g[1, 2] == Int8(1)

        # Equality & hash
        g_copy = copy(g)
        @test g == g_copy
        @test hash(g) == hash(g_copy)

        # Dimension constraints (1..30)
        @test_throws ArgumentError GridState(zeros(Int8, 0, 0))
        @test_throws ArgumentError GridState(zeros(Int8, 31, 5))
        @test_throws ArgumentError GridState(zeros(Int8, 5, 31))

        # Color constraints (0..9)
        @test_throws ArgumentError GridState(Int8[-1 0; 0 0])
        @test_throws ArgumentError GridState(Int8[10 0; 0 0])

        # Background tie-breaking: lowest color integer wins
        # 1 and 2 each appear twice
        tie_cells = Int8[1 2; 1 2]
        g_tie = GridState(tie_cells)
        @test g_tie.bg_color == Int8(1)

        # Uniform grid
        uniform_cells = fill(Int8(5), 4, 4)
        g_uni = GridState(uniform_cells)
        @test g_uni.bg_color == Int8(5)
        @test isempty(g_uni.components)
        @test g_uni.palette == (UInt16(1) << 5)
    end

    @testset "2. Connected Components & Hole Counting" begin
        # 5x5 grid with a ring of color 3 enclosing a hole of color 0
        # Background is 0
        ring_cells = Int8[
            0 0 0 0 0
            0 3 3 3 0
            0 3 0 3 0
            0 3 3 3 0
            0 0 0 0 0
        ]
        g_ring = GridState(ring_cells)
        @test length(g_ring.components) == 1
        comp = g_ring.components[1]
        @test comp.color == Int8(3)
        @test comp.bbox == (2, 2, 4, 4)
        @test comp.is_border_touching == false
        @test comp.hole_count == 1

        # Border touching component
        border_cells = Int8[
            1 1 0
            0 0 0
            0 0 0
        ]
        g_border = GridState(border_cells)
        @test length(g_border.components) == 1
        @test g_border.components[1].is_border_touching == true
        @test g_border.components[1].hole_count == 0
    end

    @testset "3. MarkerLineReflectionRule Semantics" begin
        # Edge Case 1: No marker cells -> returns exact copy
        no_marker = Int8[
            0 1 0
            0 0 0
            0 0 0
        ]
        res1 = reflect_through_marker(no_marker; marker_color=2)
        @test res1.cells == no_marker

        # Edge Case 2: Markers but no foreground objects -> returns exact copy
        only_marker = Int8[
            0 2 0
            0 0 0
            0 0 0
        ]
        res2 = reflect_through_marker(only_marker; marker_color=2)
        @test res2.cells == only_marker

        # Edge Case 4: Single marker point reflection
        # Marker at (3, 3). Foreground object (color 1) at (2, 2).
        # Reflected coordinate: nr = 2*3 - 2 = 4, nc = 2*3 - 2 = 4.
        pt_grid = zeros(Int8, 5, 5)
        pt_grid[3, 3] = Int8(2) # marker
        pt_grid[2, 2] = Int8(1) # foreground
        res_pt = reflect_through_marker(pt_grid; marker_color=2)
        @test res_pt[4, 4] == Int8(1)
        @test res_pt[2, 2] == Int8(1) # original preserved
        @test res_pt[3, 3] == Int8(2) # marker preserved

        # Edge Case 5: Vertical line of markers -> Horizontal axis reflection
        # Vertical marker at column 3, rows 2:4.
        # Foreground object at (2, 1) of color 4.
        # Reflected coordinate: nr = 2, nc = 2*3 - 1 = 5.
        vert_grid = zeros(Int8, 5, 5)
        vert_grid[2:4, 3] .= Int8(2) # vertical line at col 3
        vert_grid[2, 1] = Int8(4)
        res_vert = reflect_through_marker(vert_grid; marker_color=2)
        @test res_vert[2, 5] == Int8(4)
        @test res_vert[2, 1] == Int8(4)

        # Edge Case 6: Horizontal line of markers -> Vertical axis reflection
        # Horizontal marker at row 3, cols 2:4.
        # Foreground object at (1, 3) of color 5.
        # Reflected coordinate: nr = 2*3 - 1 = 5, nc = 3.
        horiz_grid = zeros(Int8, 5, 5)
        horiz_grid[3, 2:4] .= Int8(2)
        horiz_grid[1, 3] = Int8(5)
        res_horiz = reflect_through_marker(horiz_grid; marker_color=2)
        @test res_horiz[5, 3] == Int8(5)
        @test res_horiz[1, 3] == Int8(5)

        # Edge Case 3: Out of bounds clipping
        # Marker at (1, 1). Object at (2, 2).
        # nr = 2*1 - 2 = 0 (< 1). Should be clipped without bounds exception!
        clip_grid = zeros(Int8, 4, 4)
        clip_grid[1, 1] = Int8(2)
        clip_grid[2, 2] = Int8(6)
        res_clip = reflect_through_marker(clip_grid; marker_color=2)
        @test res_clip[2, 2] == Int8(6)

        # Edge Case 8: Nearest object association with scan order tie-break
        # Marker at (3, 3). Two objects at equal Manhattan distance: (2, 3) and (3, 2).
        # Object at (2, 3) encountered first in scan order.
        assoc_grid = zeros(Int8, 5, 5)
        assoc_grid[3, 3] = Int8(2)
        assoc_grid[2, 3] = Int8(7) # dist = 1, encountered at r=2
        assoc_grid[3, 2] = Int8(8) # dist = 1, encountered at r=3
        res_assoc = reflect_through_marker(assoc_grid; marker_color=2)
        # Point reflection of (2, 3) through (3, 3) is (4, 3)
        @test res_assoc[4, 3] == Int8(7)

        # Edge Case 7: Non-collinear marker cluster (H > W reflects horizontally across cmin)
        cluster_grid = zeros(Int8, 6, 6)
        # 4-connected cluster: (2,3), (3,3), (4,3), (4,4) -> H=3, W=2 -> H > W
        cluster_grid[2, 3] = Int8(2)
        cluster_grid[3, 3] = Int8(2)
        cluster_grid[4, 3] = Int8(2)
        cluster_grid[4, 4] = Int8(2)
        cluster_grid[2, 2] = Int8(9)
        res_cluster = reflect_through_marker(cluster_grid; marker_color=2)
        # cmin = 3 -> reflects (2, 2) to nr = 2, nc = 2*3 - 2 = 4
        @test res_cluster[2, 4] == Int8(9)

        # Edge Case 9: Multi-marker grids with overlapping reflection footprint
        # Marker A at (4, 4) reflects (3, 4) [color 7] -> (5, 4)
        # Marker B at (5, 5) reflects (5, 6) [color 8] -> (5, 4)
        # Marker B is visited second in scan order; its reflection footprint overwrites Marker A at (5, 4)
        multi_grid = zeros(Int8, 7, 7)
        multi_grid[3, 4] = Int8(7)
        multi_grid[4, 4] = Int8(2) # Marker A
        multi_grid[5, 5] = Int8(2) # Marker B
        multi_grid[5, 6] = Int8(8)
        res_multi = reflect_through_marker(multi_grid; marker_color=2)
        @test res_multi[5, 4] == Int8(8)
        @test res_multi[3, 4] == Int8(7)
        @test res_multi[5, 6] == Int8(8)

        # Edge Case 10: Non-zero background field
        # Background is 3, marker is 2, foreground object is 7
        bg_grid = fill(Int8(3), 5, 5)
        bg_grid[3, 3] = Int8(2)
        bg_grid[2, 3] = Int8(7)
        res_bg = reflect_through_marker(bg_grid; marker_color=2)
        @test res_bg[4, 3] == Int8(7)
        @test res_bg[1, 1] == Int8(3)
        @test res_bg.bg_color == Int8(3)

        # Functor and Matrix dispatch
        rule_pt = MarkerLineReflectionRule(2; axis_candidate=:point)
        @test rule_pt(pt_grid) == res_pt
        @test apply_rule(rule_pt, pt_grid) == res_pt
        @test rule_pt(GridState(pt_grid)) == res_pt
    end

    @testset "4. Typed Extension Points & Loud Rejection" begin
        dummy_grid = GridState(zeros(Int8, 3, 3))

        stubs = [
            (GeodesicBarrierFloodRule(), "GeodesicBarrierFloodRule"),
            (CorridorWireTraceRule(), "CorridorWireTraceRule"),
            (PeriodicStampWithPriorityRule(), "PeriodicStampWithPriorityRule"),
            (ExactCoverPolyominoRule(), "ExactCoverPolyominoRule"),
        ]

        for (stub_rule, rule_name) in stubs
            err = try
                apply_rule(stub_rule, dummy_grid)
                nothing
            catch e
                e
            end
            @test err isa RuleNotImplementedError
            @test err.rule_type == rule_name
            @test occursin("proposal-only: parameter contract and executor are not implemented in R1", err.message)
        end
    end

    @testset "5. Candidate Verification Pipeline (LOO, Train Exact, Equivariance)" begin
        # Construct a synthetic task matching MarkerLineReflectionRule
        # Demo 1:
        in1 = zeros(Int8, 5, 5)
        in1[3, 3] = Int8(2)
        in1[2, 2] = Int8(1)
        out1 = copy(in1)
        out1[4, 4] = Int8(1)

        # Demo 2:
        in2 = zeros(Int8, 5, 5)
        in2[3, 3] = Int8(2)
        in2[2, 4] = Int8(3)
        out2 = copy(in2)
        out2[4, 2] = Int8(3)

        task = ARCTask("test_task_marker", [
            Demonstration(GridState(in1), GridState(out1)),
            Demonstration(GridState(in2), GridState(out2)),
        ], [GridState(in1)])

        rule = MarkerLineReflectionRule(2; axis_candidate=:point)

        # 5.1 Train Exact
        train_ev = evaluate_train_exact(rule, task)
        @test train_ev.pairs_matched == 2
        @test train_ev.total_pairs == 2
        @test train_ev.max_cell_residual == 0.0

        # Mismatched rule
        wrong_rule = MarkerLineReflectionRule(5; axis_candidate=:point)
        train_ev_wrong = evaluate_train_exact(wrong_rule, task)
        @test train_ev_wrong.pairs_matched == 0

        # 5.2 LOO Evidence
        # Parameter-free transform (free_param_count = 0) -> is_informative = false
        loo_fixed = evaluate_loo(rule, task; free_param_count=0)
        @test loo_fixed.is_informative == false
        @test loo_fixed.folds_passed == 2
        @test loo_fixed.total_folds == 2

        # Parameter refit (free_param_count = 1) -> is_informative = true
        loo_refit = evaluate_loo(rule, task; is_informative=true, free_param_count=1)
        @test loo_refit.is_informative == true
        @test loo_refit.folds_passed == 2
        @test loo_refit.total_folds == 2

        # 5.3 Equivariance Evidence
        eq_ev = evaluate_equivariance(rule, task)
        @test eq_ev.status in (:passed, :untestable)

        # 5.4 verify_candidate with verified candidate
        receipt_good = ProvenanceReceipt(:qwen_ttt_beam;
                                         checkpoint_sha="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                                         seed=42, budget_steps=128, cross_task_firing=3)
        cand_good = Candidate(rule, [GridState(out1)], AbstractEvidence[], receipt_good)
        is_ver, verdict, evs = verify_candidate(cand_good, task)
        @test is_ver == true
        @test verdict == :passed

        # Parameter-free fixed macro with cross_task_firing < 2 fails gate
        receipt_low_firing = ProvenanceReceipt(:fixed_macro; cross_task_firing=1)
        cand_low = Candidate(rule, [GridState(out1)], AbstractEvidence[], receipt_low_firing)
        is_ver_low, verdict_low, _ = verify_candidate(cand_low, task)
        @test is_ver_low == false
        @test verdict_low == :failed

        # Edge Case 14: Directional axis rule on asymmetric rotation yields :untestable -> :incomplete
        dir_rule = MarkerLineReflectionRule(2; axis_candidate=:vertical)
        eq_dir = evaluate_equivariance(dir_rule, task)
        @test eq_dir.status == :untestable
        cand_dir = Candidate(dir_rule, [GridState(out1)], AbstractEvidence[], receipt_good)
        # Even if train-exact matches or is evaluated, :untestable equivariance yields :incomplete
        # Create a task where vertical reflection matches train
        in_v = zeros(Int8, 5, 5); in_v[2:4, 3] .= Int8(2); in_v[2, 1] = Int8(4)
        out_v = copy(in_v); out_v[2, 5] = Int8(4)
        task_v = ARCTask("task_v", [Demonstration(GridState(in_v), GridState(out_v))], [GridState(in_v)])
        cand_v = Candidate(dir_rule, [GridState(out_v)], AbstractEvidence[], receipt_good)
        is_ver_v, verdict_v, _ = verify_candidate(cand_v, task_v)
        @test is_ver_v == false
        @test verdict_v == :incomplete

        # Edge Case 15: Coordinate-grounded marker hypotheses yield :untestable equivariance -> :incomplete
        coord_rule = MarkerLineReflectionRule(2; axis_candidate=:auto, marker_cells=[(2, 3)])
        cand_coord = Candidate(coord_rule, [GridState(out_v)], AbstractEvidence[], receipt_good)
        is_ver_c, verdict_c, evs_c = verify_candidate(cand_coord, task_v)
        @test is_ver_c == false
        @test verdict_c == :incomplete
        @test evs_c[3].status == :untestable

        # Edge Case 16: Non-zero background color permutation equivariance test
        in_bg = fill(Int8(4), 5, 5); in_bg[3, 3] = Int8(2); in_bg[2, 3] = Int8(0)
        out_bg = copy(in_bg); out_bg[4, 3] = Int8(0)
        task_bg = ARCTask("task_bg", [Demonstration(GridState(in_bg), GridState(out_bg))], [GridState(in_bg)])
        rule_bg = MarkerLineReflectionRule(2; axis_candidate=:point)
        eq_bg = evaluate_equivariance(rule_bg, task_bg)
        @test eq_bg.color_perm_equivariant == true
        @test eq_bg.status in (:passed, :untestable)
    end

    @testset "6. Proposal JSON Bridge & Compiler" begin
        proposal_path = joinpath(@__DIR__, "..", "schema", "examples", "marker-line-reflection.proposal.json")
        @test isfile(proposal_path)

        # Parse JSON
        parsed = parse_json_file(proposal_path)
        @test parsed["schema_version"] == 1
        @test parsed["rule_type"] == "MarkerLineReflectionRule"
        @test length(parsed["parameter_hypotheses"]) == 3

        # Compile Rule
        compiled = compile_rule(parsed)
        @test compiled isa MarkerLineReflectionRule
        @test compiled.marker_color == Int8(4)
        @test compiled.axis_candidate == :vertical
        # Coordinates in proposal: (1, 3), (2, 3) 0-based -> (2, 4), (3, 4) 1-based
        @test compiled.marker_cells == [(2, 4), (3, 4)]

        # Execute compiled rule on a sample grid
        sample_grid = zeros(Int8, 6, 6)
        # Put markers at (2, 4) and (3, 4) with color 4
        sample_grid[2, 4] = Int8(4)
        sample_grid[3, 4] = Int8(4)
        # Foreground object at (2, 2) with color 7
        sample_grid[2, 2] = Int8(7)

        res = apply_rule(compiled, GridState(sample_grid))
        # Vertical marker axis at column 4: nr = 2, nc = 2*4 - 2 = 6
        @test res[2, 6] == Int8(7)
        @test res[2, 2] == Int8(7)
    end

    @testset "7. ArcGeyserRule & ArcGyrismRule Execution" begin
        # Geyser ray casting test
        g_in = zeros(Int8, 5, 5)
        g_in[3, 3] = Int8(1) # Emitter color 1
        g_in[3, 5] = Int8(8) # Barrier color 8

        rule_geyser = ArcGeyserRule(1; beam_color=3, directions=:cardinal, barrier_colors=[8])
        res_geyser = apply_rule(rule_geyser, GridState(g_in))

        # Emitter preserved
        @test res_geyser[3, 3] == Int8(1)
        # Vertical beams
        @test res_geyser[1, 3] == Int8(3)
        @test res_geyser[2, 3] == Int8(3)
        @test res_geyser[4, 3] == Int8(3)
        @test res_geyser[5, 3] == Int8(3)
        # Left horizontal beam
        @test res_geyser[3, 1] == Int8(3)
        @test res_geyser[3, 2] == Int8(3)
        # Right horizontal beam reaches (3, 4) but stops at barrier (3, 5)
        @test res_geyser[3, 4] == Int8(3)
        @test res_geyser[3, 5] == Int8(8) # Barrier untouched

        # Gyrism rotational circulation test
        gyre_in = zeros(Int8, 5, 5)
        gyre_in[3, 3] = Int8(2) # Center landmark color 2
        gyre_in[2, 3] = Int8(4) # Foreground cell north of center

        rule_gyre = ArcGyrismRule(2; angle_degrees=90, clockwise=true)
        res_gyre = apply_rule(rule_gyre, GridState(gyre_in))

        # Center preserved
        @test res_gyre[3, 3] == Int8(2)
        # 90 deg CW rotation: (2, 3) moves to east (3, 4)
        @test res_gyre[3, 4] == Int8(4)
        @test res_gyre[2, 3] == Int8(0)

        # Geyser parallax ray intersection test (two emitters triangulation)
        p_in = zeros(Int8, 5, 5)
        p_in[1, 3] = Int8(1) # Geyser 1 at top
        p_in[3, 1] = Int8(1) # Geyser 2 at left

        rule_parallax = ArcGeyserRule(1; beam_color=3, directions=:cardinal, intersection_color=4)
        res_parallax = apply_rule(rule_parallax, GridState(p_in))

        # Emitters preserved
        @test res_parallax[1, 3] == Int8(1)
        @test res_parallax[3, 1] == Int8(1)
        # Non-intersecting beam segments
        @test res_parallax[2, 3] == Int8(3)
        @test res_parallax[3, 2] == Int8(3)
        # Parallax intersection node at (3, 3) where horizontal and vertical rays cross
        @test res_parallax[3, 3] == Int8(4)

        # 8. Unimplemented rule stubs propagate RuleNotImplementedError and yield :incomplete
        t_in = zeros(Int8, 5, 5); t_in[3, 3] = Int8(2); t_in[2, 3] = Int8(1)
        t_out = copy(t_in); t_out[4, 3] = Int8(1)
        task_stub = ARCTask("stub_task", [Demonstration(GridState(t_in), GridState(t_out))], [GridState(t_in)])
        stub_prov = ProvenanceReceipt(:symbolic_dsl, "stub_cand", 0, 100, 2)

        for stub_rule in (
            GeodesicBarrierFloodRule(),
            CorridorWireTraceRule(),
            PeriodicStampWithPriorityRule(),
            ExactCoverPolyominoRule()
        )
            @test_throws RuleNotImplementedError evaluate_train_exact(stub_rule, task_stub)
            @test_throws RuleNotImplementedError evaluate_loo(stub_rule, task_stub)
            passed_stub, status_stub, ev_stub = verify_candidate(Candidate(stub_rule, GridState[], AbstractEvidence[], stub_prov), task_stub)
            @test passed_stub == false
            @test status_stub == :incomplete
            @test isempty(ev_stub)
        end
    end

end


end # module TestCore
