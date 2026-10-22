# test/test_warrant_scrambling_critic.jl
# Tests for NeuroARC's directly wired Coevolutionary Warrant-Scrambling Critic,
# LegendRelationalRecolorRule, WarrantScramblingEvidence, Informative LOO Gate,
# and Homoiconic S-Expression / AST Intron Pruning.
# Strictly zero em-dashes and zero en-dashes.

using Test
using NeuroARC

@testset "ARC-AGI-2 Warrant-Scrambling & Informative LOO Critic Tests" begin
    # Construct 3 synthetic ARC-AGI-2 training pairs with an in-grid legend at (1, 1):
    # Cell (1, 1) holds the target color (color 2 in all 3 demos); cells with marker 5
    # in the workspace (rows 2..4, cols 2..4) must be recolored to match legend cell (1, 1).
    demo_pairs = Tuple{Matrix{Int},Matrix{Int}}[]
    arc_demos = Demonstration[]
    for k in 1:3
        x = zeros(Int, 4, 4)
        x[1, 1] = 2 # Legend instruction key: recolor marker 5 -> 2
        x[1 + k, 2 + mod(k, 2)] = 5
        y = copy(x)
        y[y .== 5] .= 2
        push!(demo_pairs, (x, y))
        push!(arc_demos, Demonstration(GridState(Matrix{Int8}(x)), GridState(Matrix{Int8}(y))))
    end

    # Held-out test grid specifies color 1 (Blue) in legend cell (1, 1) instead of color 2!
    x_test = zeros(Int8, 4, 4)
    x_test[1, 1] = Int8(1)
    x_test[3, 3] = Int8(5)
    task = ARCTask("legend_warrant_test_01", arc_demos, [GridState(x_test)])

    # 1. Function-level synthesizers
    shortcut_synthesizer(train_subset) = begin
        return function (grid::Matrix{Int})
            out = copy(grid)
            out[out .== 5] .= 2
            return out
        end
    end

    relational_synthesizer(train_subset) = begin
        return function (grid::Matrix{Int})
            target_color = grid[1, 1]
            out = copy(grid)
            out[out .== 5] .= target_color
            return out
        end
    end

    res_shortcut = evaluate_arc_agi2_loo_and_warrant_gate(shortcut_synthesizer, demo_pairs; swappable_colors = (1, 2))
    @test res_shortcut.loo_folds_passed == 3
    @test res_shortcut.legend_warrant_folds_passed == 0
    @test res_shortcut.verdict == :REJECTED_OVERFIT_OR_UNWARRANTED

    res_relational = evaluate_arc_agi2_loo_and_warrant_gate(relational_synthesizer, demo_pairs; swappable_colors = (1, 2))
    @test res_relational.loo_folds_passed == 3
    @test res_relational.legend_warrant_folds_passed == 3
    @test res_relational.verdict == :ACCEPTED

    # 2. Verify evaluate_warrant_under_scrambling separates shortcut from relational generalizer
    w_shortcut = evaluate_warrant_under_scrambling(
        shortcut_synthesizer(demo_pairs),
        demo_pairs;
        fixed_colors = Set([0, 5]),
        test_rotations = false,
        ast_node_count = 12,
    )
    w_relational = evaluate_warrant_under_scrambling(
        relational_synthesizer(demo_pairs),
        demo_pairs;
        fixed_colors = Set([0, 5]),
        test_rotations = false,
        ast_node_count = 4,
    )
    @test w_shortcut.train_accuracy == 1.0
    @test w_shortcut.color_scrambling_warrant == 0.0
    @test !w_shortcut.is_warranted_generalizer
    @test w_relational.train_accuracy == 1.0
    @test w_relational.color_scrambling_warrant == 1.0
    @test w_relational.is_warranted_generalizer
    @test w_relational.composite_fitness > w_shortcut.composite_fitness

    # 3. Direct NeuroARC AbstractGridRule + verify_candidate integration
    rule_shortcut = LegendRelationalRecolorRule(5; legend_row = 1, legend_col = 1, use_relational_legend = false, hardcoded_target_color = 2)
    rule_relational = LegendRelationalRecolorRule(5; legend_row = 1, legend_col = 1, use_relational_legend = true)

    cand_shortcut = Candidate(
        rule_shortcut,
        [apply_rule(rule_shortcut, task.test_inputs[1])],
        AbstractEvidence[],
        ProvenanceReceipt(:evolutionary_ast; cross_task_firing = 1),
    )
    cand_relational = Candidate(
        rule_relational,
        [apply_rule(rule_relational, task.test_inputs[1])],
        AbstractEvidence[],
        ProvenanceReceipt(:evolutionary_ast; cross_task_firing = 3),
    )

    ok_short, status_short, ev_short = verify_candidate(cand_shortcut, task)
    @test !ok_short
    @test status_short == :failed
    @test any(e -> e isa WarrantScramblingEvidence && !e.is_warranted_generalizer, ev_short)

    ok_rel, status_rel, ev_rel = verify_candidate(cand_relational, task)
    @test ok_rel
    @test status_rel == :passed
    @test any(e -> e isa WarrantScramblingEvidence && e.is_warranted_generalizer, ev_rel)
    @test cand_relational.predictions[1].cells[3, 3] == Int8(1)
    @test cand_shortcut.predictions[1].cells[3, 3] == Int8(2)

    # 4. Homoiconic Lisp/Expr AST Intron Ablation (Greenspun / S-expression MDL gate)
    bloated_expr = :(identity(recolor_from_legend(grid, (1, 1), 5)))
    clean_expr = :(recolor_from_legend(grid, (1, 1), 5))
    @test count_ast_nodes(bloated_expr) > count_ast_nodes(clean_expr)
    pruned_expr, removed_nodes = prune_unwarranted_ast_introns(bloated_expr, ex -> ex == clean_expr)
    @test pruned_expr == clean_expr
    @test removed_nodes == 2

    # 5. Verify D4 dihedral invertibility across all 8 group elements (0..7)
    sample_grid = reshape(collect(1:12), 3, 4)
    for op_id in 0:7
        @test inverse_dihedral_transform(dihedral_transform(sample_grid, op_id), op_id) == sample_grid
    end
end
