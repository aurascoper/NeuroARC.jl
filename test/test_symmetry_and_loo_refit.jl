module TestSymmetryAndLOORefit

using Test
using NeuroARC
using NeuroARC.TransjectionCalculus: Accepted, Rejected, Incomplete

@testset "Symmetry Metadata, Gyre Scan-Order Fix & N-1 LOO Parameter Refit Suite" begin

    @testset "1. EquivarianceEvidence Backward Compatibility & Subgroup Lattice" begin
        ev_pass = EquivarianceEvidence(true, true, :passed)
        @test ev_pass.d8_equivariant == true
        @test ev_pass.color_perm_equivariant == true
        @test ev_pass.status == :passed
        @test ev_pass.requested_group == :D8
        @test ev_pass.tested_transforms == CANONICAL_D8_TRANSFORMS
        @test ev_pass.passed_transforms == CANONICAL_D8_TRANSFORMS
        @test isempty(ev_pass.failed_transforms)
        @test isempty(ev_pass.untestable_transforms)
        @test :D8 in ev_pass.supported_subgroups
        @test :C4 in ev_pass.supported_subgroups

        ev_untest = EquivarianceEvidence(false, true, :untestable)
        @test ev_untest.status == :untestable
        @test ev_untest.untestable_transforms == CANONICAL_D8_TRANSFORMS
        @test isempty(ev_untest.supported_subgroups)

        ev_fail = EquivarianceEvidence(false, true, :failed)
        @test ev_fail.status == :failed
        @test ev_fail.passed_transforms == [:id]
        @test ev_fail.supported_subgroups == [:C1]

        @test_throws ArgumentError group_transforms(:InvalidGroup)
    end

    @testset "2. circulate_gyre Multi-Pixel Polyomino Scan-Order Preservation" begin
        # L-polyomino around center (4, 4) where pixels rotate into adjacent cells occupied
        # by same-color foreground cells later in row-major scan order
        grid_l = zeros(Int8, 7, 7)
        grid_l[4, 4] = Int8(2) # Center marker
        # Place 4-cell L-shape of color 5 at (3, 4), (3, 5), (4, 5), (2, 4)
        # Under 90 deg CW around (4, 4):
        # (3, 4) [dr=-1, dc=0] -> (4, 5) [new_dr=0, new_dc=1] which is occupied by (4, 5)!
        # In old code, processing (3, 4) wrote 5 to (4, 5), and then processing (4, 5) erased (4, 5) to 0!
        grid_l[2, 4] = Int8(5)
        grid_l[3, 4] = Int8(5)
        grid_l[3, 5] = Int8(5)
        grid_l[4, 5] = Int8(5)

        orig_fg_count = count(==(Int8(5)), grid_l)
        @test orig_fg_count == 4

        for ang in (90, 180, 270), cw in (true, false)
            rot_state = circulate_gyre(GridState(grid_l); center_color = 2, angle_degrees = ang, clockwise = cw)
            @test count(==(Int8(5)), rot_state.cells) == orig_fg_count
            @test rot_state[4, 4] == Int8(2)
        end

        # Verify exact 90 deg CW coordinates for the L-polyomino:
        # (2, 4) [-2, 0] -> (4, 6) [0, 2]
        # (3, 4) [-1, 0] -> (4, 5) [0, 1]
        # (3, 5) [-1, 1] -> (5, 5) [1, 1]
        # (4, 5) [ 0, 1] -> (5, 4) [1, 0]
        rot90_cw = circulate_gyre(GridState(grid_l); center_color = 2, angle_degrees = 90, clockwise = true)
        @test rot90_cw[4, 6] == Int8(5)
        @test rot90_cw[4, 5] == Int8(5)
        @test rot90_cw[5, 5] == Int8(5)
        @test rot90_cw[5, 4] == Int8(5)
        @test rot90_cw[2, 4] == Int8(0)
        @test rot90_cw[3, 4] == Int8(0)
        @test rot90_cw[3, 5] == Int8(0)

        # 4 consecutive 90-degree rotations return exact original grid
        g_iter = GridState(grid_l)
        for _ in 1:4
            g_iter = circulate_gyre(g_iter; center_color = 2, angle_degrees = 90, clockwise = true)
        end
        @test g_iter == GridState(grid_l)
    end

    @testset "3. Symmetry Classification Across Full D8, Chiral C4, and Directional Subgroups" begin
        # 3A. Full D8 + Color Permutation Equivariant Geyser Rule (with non-landmark spectator pixels)
        g1 = zeros(Int8, 5, 5); g1[3, 3] = Int8(1); g1[1, 1] = Int8(6)
        g2 = zeros(Int8, 5, 5); g2[2, 2] = Int8(1); g2[5, 5] = Int8(7)
        rule_card = ArcGeyserRule(1; beam_color = 3, directions = :cardinal)
        task_card = ARCTask("task_card", [
            Demonstration(GridState(g1), apply_rule(rule_card, GridState(g1))),
            Demonstration(GridState(g2), apply_rule(rule_card, GridState(g2)))
        ], [GridState(g1)])

        ev_card = evaluate_equivariance(rule_card, task_card; requested_group = :D8)
        @test ev_card.status == :passed
        @test ev_card.d8_equivariant == true
        @test ev_card.color_perm_equivariant == true
        @test ev_card.passed_transforms == CANONICAL_D8_TRANSFORMS
        @test isempty(ev_card.failed_transforms)
        @test isempty(ev_card.untestable_transforms)
        @test :D8 in ev_card.supported_subgroups

        rule_all8 = ArcGeyserRule(1; beam_color = -1, directions = :all8)
        task_all8 = ARCTask("task_all8", [
            Demonstration(GridState(g1), apply_rule(rule_all8, GridState(g1))),
            Demonstration(GridState(g2), apply_rule(rule_all8, GridState(g2)))
        ], [GridState(g1)])
        ev_all8 = evaluate_equivariance(rule_all8, task_all8; requested_group = :D8)
        @test ev_all8.status == :passed
        @test ev_all8.d8_equivariant == true
        @test ev_all8.color_perm_equivariant == true

        # 3B. Chiral C4 Rotational Rule (ArcGyrismRule 90 & 270 deg CW)
        gyre_in1 = zeros(Int8, 7, 7)
        gyre_in1[4, 4] = Int8(2)
        gyre_in1[2, 4] = Int8(5); gyre_in1[3, 4] = Int8(5); gyre_in1[3, 5] = Int8(5); gyre_in1[4, 5] = Int8(5)

        gyre_in2 = zeros(Int8, 7, 7)
        gyre_in2[4, 4] = Int8(2)
        gyre_in2[4, 2] = Int8(6); gyre_in2[4, 3] = Int8(6); gyre_in2[3, 3] = Int8(6)

        for ang in (90, 270)
            rule_gyre = ArcGyrismRule(2; angle_degrees = ang, clockwise = true)
            task_gyre = ARCTask("task_gyre_$ang", [
                Demonstration(GridState(gyre_in1), apply_rule(rule_gyre, GridState(gyre_in1))),
                Demonstration(GridState(gyre_in2), apply_rule(rule_gyre, GridState(gyre_in2)))
            ], [GridState(gyre_in1)])

            # Under requested_group = :C4, passes all 4 rotations
            ev_c4 = evaluate_equivariance(rule_gyre, task_gyre; requested_group = :C4)
            @test ev_c4.status == :passed
            @test ev_c4.d8_equivariant == false
            @test ev_c4.color_perm_equivariant == true
            @test ev_c4.tested_transforms == [:id, :rot90, :rot180, :rot270]
            @test ev_c4.passed_transforms == [:id, :rot90, :rot180, :rot270]
            @test isempty(ev_c4.failed_transforms)
            @test isempty(ev_c4.untestable_transforms)
            @test :C4 in ev_c4.supported_subgroups

            # Under requested_group = :D8, reflections are recorded in failed_transforms (NOT untestable)
            ev_d8 = evaluate_equivariance(rule_gyre, task_gyre; requested_group = :D8)
            @test ev_d8.status == :failed
            @test ev_d8.d8_equivariant == false
            @test ev_d8.color_perm_equivariant == true
            @test ev_d8.passed_transforms == [:id, :rot90, :rot180, :rot270]
            @test ev_d8.failed_transforms == [:refl_h, :refl_v, :refl_main_diag, :refl_anti_diag]
            @test isempty(ev_d8.untestable_transforms)
            @test :C4 in ev_d8.supported_subgroups
            @test !(:D8 in ev_d8.supported_subgroups)
        end

        # 3C. Directional Geyser Rule (:down preserves left-right reflection :refl_v)
        rule_down = ArcGeyserRule(1; beam_color = 3, directions = :down)
        task_down = ARCTask("task_down", [
            Demonstration(GridState(g1), apply_rule(rule_down, GridState(g1))),
            Demonstration(GridState(g2), apply_rule(rule_down, GridState(g2)))
        ], [GridState(g1)])

        ev_down_d8 = evaluate_equivariance(rule_down, task_down; requested_group = :D8)
        @test ev_down_d8.status == :failed
        @test ev_down_d8.passed_transforms == [:id, :refl_v]
        @test ev_down_d8.failed_transforms == [:rot90, :rot180, :rot270, :refl_h, :refl_main_diag, :refl_anti_diag]
        @test isempty(ev_down_d8.untestable_transforms)
        @test ev_down_d8.supported_subgroups == [:D1_refl_v, :C1]

        ev_down_refl_v = evaluate_equivariance(rule_down, task_down; requested_group = :D1_refl_v)
        @test ev_down_refl_v.status == :passed
        @test ev_down_refl_v.passed_transforms == [:id, :refl_v]
        @test isempty(ev_down_refl_v.failed_transforms)

        # Directional :right preserves top-bottom reflection :refl_h
        rule_right = ArcGeyserRule(1; beam_color = 3, directions = :right)
        task_right = ARCTask("task_right", [
            Demonstration(GridState(g1), apply_rule(rule_right, GridState(g1))),
            Demonstration(GridState(g2), apply_rule(rule_right, GridState(g2)))
        ], [GridState(g1)])
        ev_right_d8 = evaluate_equivariance(rule_right, task_right; requested_group = :D8)
        @test ev_right_d8.status == :failed
        @test ev_right_d8.passed_transforms == [:id, :refl_h]
        @test ev_right_d8.supported_subgroups == [:D1_refl_h, :C1]
        @test evaluate_equivariance(rule_right, task_right; requested_group = :D1_refl_h).status == :passed
    end

    @testset "4. Genuine N-1 LOO Parameter Refitting & Overfit Falsification" begin
        # 4A. ArcGeyserRule parameter inference from N-1 demos
        in1 = zeros(Int8, 5, 5); in1[3, 3] = Int8(4)
        in2 = zeros(Int8, 5, 5); in2[2, 4] = Int8(4)
        true_geyser = ArcGeyserRule(4; beam_color = 7, directions = :cardinal)
        demos_geyser = [
            Demonstration(GridState(in1), apply_rule(true_geyser, GridState(in1))),
            Demonstration(GridState(in2), apply_rule(true_geyser, GridState(in2)))
        ]
        # Refit starting from wrong initial parameters
        seed_geyser = ArcGeyserRule(1; beam_color = 2, directions = :up)
        refitted_g = refit_rule_parameters(seed_geyser, demos_geyser)
        @test refitted_g.emitter_color == Int8(4)
        @test refitted_g.beam_color == Int8(7)
        @test refitted_g.directions == :cardinal

        # Overfitted Geyser falsification:
        # Demos 1 and 2 have no color-9 emitter (identity output), while Demo 3 has color-9 emitter!
        # A rule ArcGeyserRule(9; beam_color=7, directions=:cardinal) matches all 3 training pairs
        # (vacuously on Demos 1 & 2, actively on Demo 3), so evaluate_train_exact passes 3/3!
        # However, on Holdout Fold 3 (training on Demos 1 & 2 only), color 9 has zero active support,
        # so refit_rule_parameters does NOT recover emitter_color=9, and Fold 3 FAILS informative LOO!
        id1 = zeros(Int8, 5, 5); id1[2, 2] = Int8(1)
        id2 = zeros(Int8, 5, 5); id2[4, 4] = Int8(2)
        in3 = zeros(Int8, 5, 5); in3[3, 3] = Int8(9)
        overfit_geyser = ArcGeyserRule(9; beam_color = 7, directions = :cardinal)
        task_overfit_geyser = ARCTask("overfit_geyser", [
            Demonstration(GridState(id1), GridState(id1)),
            Demonstration(GridState(id2), GridState(id2)),
            Demonstration(GridState(in3), apply_rule(overfit_geyser, GridState(in3)))
        ], [GridState(in3)])

        @test evaluate_train_exact(overfit_geyser, task_overfit_geyser).pairs_matched == 3
        loo_overfit_g = evaluate_loo(overfit_geyser, task_overfit_geyser; is_informative = true)
        @test loo_overfit_g.is_informative == true
        @test loo_overfit_g.folds_passed < loo_overfit_g.total_folds

        v_mem_overfit = depolarize_membrane(overfit_geyser, task_overfit_geyser)
        @test v_mem_overfit isa Rejected
        @test v_mem_overfit.reason == :informative_loo_failed
        @test :informative_loo_gate in v_mem_overfit.failed_gates

        # 4B. ArcGyrismRule parameter inference & overfit falsification
        gy1 = zeros(Int8, 5, 5); gy1[3, 3] = Int8(2); gy1[2, 3] = Int8(5); gy1[2, 4] = Int8(5)
        gy2 = zeros(Int8, 5, 5); gy2[3, 3] = Int8(2); gy2[4, 3] = Int8(6); gy2[4, 2] = Int8(6)
        true_gyre = ArcGyrismRule(2; angle_degrees = 90, clockwise = true)
        demos_gyre = [
            Demonstration(GridState(gy1), apply_rule(true_gyre, GridState(gy1))),
            Demonstration(GridState(gy2), apply_rule(true_gyre, GridState(gy2)))
        ]
        refitted_gy = refit_rule_parameters(ArcGyrismRule(-1; angle_degrees = 180, clockwise = false), demos_gyre)
        @test refitted_gy.center_color == Int8(2)
        @test apply_rule(refitted_gy, GridState(gy1)) == apply_rule(true_gyre, GridState(gy1))

        # Overfitted Gyre on fold 3 where folds 1 & 2 are rotationally invariant single center pixels
        gy_vac1 = zeros(Int8, 5, 5); gy_vac1[3, 3] = Int8(2)
        gy_vac2 = zeros(Int8, 5, 5); gy_vac2[3, 3] = Int8(2)
        overfit_gyre = ArcGyrismRule(2; angle_degrees = 270, clockwise = true)
        task_overfit_gyre = ARCTask("overfit_gyre", [
            Demonstration(GridState(gy_vac1), GridState(gy_vac1)),
            Demonstration(GridState(gy_vac2), GridState(gy_vac2)),
            Demonstration(GridState(gy1), apply_rule(overfit_gyre, GridState(gy1)))
        ], [GridState(gy1)])
        @test evaluate_train_exact(overfit_gyre, task_overfit_gyre).pairs_matched == 3
        loo_overfit_gy = evaluate_loo(overfit_gyre, task_overfit_gyre; is_informative = true)
        @test loo_overfit_gy.folds_passed < loo_overfit_gy.total_folds

        # 4C. Fold-Weaving N-1 Parameter Refitting inside execute_d8_fold_consensus_weave
        overfit_pairs = Tuple{Matrix{Int}, Matrix{Int}}[
            (Matrix{Int}(id1), Matrix{Int}(id1)),
            (Matrix{Int}(id2), Matrix{Int}(id2)),
            (Matrix{Int}(in3), Matrix{Int}(apply_rule(overfit_geyser, GridState(in3)).cells))
        ]
        v_weave_overfit = execute_d8_fold_consensus_weave(
            [("overfit_geyser", overfit_geyser)],
            overfit_pairs,
            Matrix{Int}(in3)
        )
        @test v_weave_overfit isa Rejected
        @test v_weave_overfit.reason == :no_d8_fold_consensus

        # Consistent Geyser rule across all folds is Accepted by execute_d8_fold_consensus_weave
        consistent_pairs = Tuple{Matrix{Int}, Matrix{Int}}[
            (Matrix{Int}(in1), Matrix{Int}(apply_rule(true_geyser, GridState(in1)).cells)),
            (Matrix{Int}(in2), Matrix{Int}(apply_rule(true_geyser, GridState(in2)).cells))
        ]
        v_weave_ok = execute_d8_fold_consensus_weave(
            [("true_geyser", true_geyser)],
            consistent_pairs,
            Matrix{Int}(in1)
        )
        @test v_weave_ok isa Accepted
        @test v_weave_ok.value.attempt_1 == Matrix{Int}(apply_rule(true_geyser, GridState(in1)).cells)
    end

    @testset "5. depolarize_membrane Unified Gate Enforcement (No Inf Sentinels)" begin
        in_v = zeros(Int8, 5, 5); in_v[2:4, 3] .= Int8(2); in_v[2, 1] = Int8(4)
        out_v = copy(in_v); out_v[2, 5] = Int8(4)
        in_v2 = zeros(Int8, 5, 5); in_v2[2:4, 3] .= Int8(2); in_v2[4, 2] = Int8(4)
        out_v2 = copy(in_v2); out_v2[4, 4] = Int8(4)
        task_v = ARCTask("task_v_mem", [
            Demonstration(GridState(in_v), GridState(out_v)),
            Demonstration(GridState(in_v2), GridState(out_v2))
        ], [GridState(in_v)])

        dir_rule = MarkerLineReflectionRule(2; axis_candidate = :vertical)
        # Under default :D8, untestable equivariance returns Incomplete (NOT Accepted and NOT Inf)
        v_inc = depolarize_membrane(dir_rule, task_v)
        @test v_inc isa Incomplete
        @test v_inc.reason == :equivariance_untestable

        # Under :D2_ortho, all 4 orthogonal transforms are testable and pass -> Accepted
        v_ortho = depolarize_membrane(dir_rule, task_v; requested_group = :D2_ortho)
        @test v_ortho isa Accepted
        @test v_ortho.empowerment_score == 1.0
    end

end

end # module TestSymmetryAndLOORefit
