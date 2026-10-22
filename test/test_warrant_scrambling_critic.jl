# ==============================================================================
# ARC-AGI-2 Coevolutionary Warrant-Scrambling & Informative LOO Critic
# Implements:
# 1. Color-Bijection Scrambling (pi in S_10) across input and output grids
# 2. Dihedral Spatial Scrambling (g in D_4) with directional-gravity exemption
# 3. In-Grid Instruction Legend Warrant Scrambling (defeating hardcoded color shortcuts)
# 4. Informative Leave-One-Out (LOO) Criterial Gate (Section 4.1 / Section C2)
# Strictly zero em-dashes and zero en-dashes.
# ==============================================================================

using Test

module WarrantScramblingCritic

export dihedral_transform,
       inverse_dihedral_transform,
       permute_colors,
       scramble_in_grid_legend_pair,
       evaluate_warrant_under_scrambling,
       evaluate_arc_agi2_loo_and_warrant_gate

const Grid = Matrix{Int}

"""
    dihedral_transform(grid::Grid, op_id::Int) -> Grid

Applies one of the 8 dihedral group D4 symmetries (0..7).
"""
function dihedral_transform(grid::Grid, op_id::Int)::Grid
    rot_k = mod(op_id, 4)
    g = if rot_k == 0
        copy(grid)
    elseif rot_k == 1
        rotr90(grid)
    elseif rot_k == 2
        rot180(grid)
    else
        rotl90(grid)
    end
    return op_id >= 4 ? reverse(g, dims = 2) : g
end

"""
    inverse_dihedral_transform(grid::Grid, op_id::Int) -> Grid

Exact inverse of `dihedral_transform(grid, op_id)`.
"""
function inverse_dihedral_transform(grid::Grid, op_id::Int)::Grid
    g = op_id >= 4 ? reverse(grid, dims = 2) : copy(grid)
    rot_k = mod(4 - mod(op_id, 4), 4)
    if rot_k == 0
        return g
    elseif rot_k == 1
        return rotr90(g)
    elseif rot_k == 2
        return rot180(g)
    else
        return rotl90(g)
    end
end

"""
    permute_colors(grid::Grid, color_map::Dict{Int,Int}) -> Grid

Applies a bijective color scrambling map simultaneously across `grid`.
"""
function permute_colors(grid::Grid, color_map::Dict{Int,Int})::Grid
    out = similar(grid)
    @inbounds for idx in eachindex(grid)
        c = grid[idx]
        out[idx] = get(color_map, c, c)
    end
    return out
end

"""
    scramble_in_grid_legend_pair(x::Grid, y::Grid, color_a::Int, color_b::Int) -> Tuple{Grid, Grid}

Swaps symbolic colors `color_a <-> color_b` across both the input grid (including its
in-grid instruction legend) and the expected output grid.
"""
function scramble_in_grid_legend_pair(x::Grid, y::Grid, color_a::Int, color_b::Int)::Tuple{Grid,Grid}
    cmap = Dict{Int,Int}(color_a => color_b, color_b => color_a)
    return (permute_colors(x, cmap), permute_colors(y, cmap))
end

"""
    evaluate_warrant_under_scrambling(
        program_fn::Function,
        train_pairs::Vector{Tuple{Grid,Grid}};
        fixed_colors::Set{Int} = Set([0]),
        test_rotations::Bool = true,
        ast_node_count::Int = 1,
        alpha_mdl::Float64 = 0.02
    )
"""
function evaluate_warrant_under_scrambling(
    program_fn::Function,
    train_pairs::Vector{Tuple{Grid,Grid}};
    fixed_colors::Set{Int} = Set([0]),
    test_rotations::Bool = true,
    ast_node_count::Int = 1,
    alpha_mdl::Float64 = 0.02,
)
    exact_matches = 0
    color_set = Set{Int}()
    for (x, y) in train_pairs
        for c in x
             !(c in fixed_colors) && push!(color_set, c)
        end
        for c in y
            !(c in fixed_colors) && push!(color_set, c)
        end
        try
            pred = program_fn(copy(x))
            if size(pred) == size(y) && pred == y
                exact_matches += 1
            end
        catch
        end
    end
    train_acc = exact_matches / max(length(train_pairs), 1)
    active_colors = sort!(collect(color_set))

    color_warrant_trials = 0
    color_warrant_passes = 0
    # Build candidate color bijections:
    # (a) If >= 2 active symbolic colors appear in train_pairs, test cyclic permutation among them.
    # (b) Also test mapping active symbolic colors to an unused palette color in 1..9 \ (fixed_colors U active_colors)
    #     so single-color legend tasks (where all training grids share one target color, e.g. color 2)
    #     cannot pass by hardcoding that single training color.
    candidate_cmaps = Dict{Int,Int}[]
    if length(active_colors) >= 2
        shifted = vcat(active_colors[2:end], active_colors[1:1])
        push!(candidate_cmaps, Dict{Int,Int}(c => s for (c, s) in zip(active_colors, shifted)))
    end
    if !isempty(active_colors)
        unused_colors = [c for c in 1:9 if !(c in fixed_colors) && !(c in color_set)]
        if !isempty(unused_colors)
            alt_map = Dict{Int,Int}()
            for (idx, c) in enumerate(active_colors)
                alt_map[c] = unused_colors[mod1(idx, length(unused_colors))]
            end
            push!(candidate_cmaps, alt_map)
        end
    end

    for cmap in candidate_cmaps
        for (x, y) in train_pairs
            color_warrant_trials += 1
            try
                x_scr = permute_colors(x, cmap)
                y_scr_expected = permute_colors(y, cmap)
                y_scr_pred = program_fn(x_scr)
                if size(y_scr_pred) == size(y_scr_expected) && y_scr_pred == y_scr_expected
                    color_warrant_passes += 1
                end
            catch
            end
        end
    end
    color_warrant = color_warrant_trials > 0 ? (color_warrant_passes / color_warrant_trials) : 1.0

    spatial_warrant_trials = 0
    spatial_warrant_passes = 0
    if test_rotations
        for op_id in (1, 2, 4)
            for (x, y) in train_pairs
                spatial_warrant_trials += 1
                try
                    x_rot = dihedral_transform(x, op_id)
                    y_rot_expected = dihedral_transform(y, op_id)
                    y_rot_pred = program_fn(x_rot)
                    if size(y_rot_pred) == size(y_rot_expected) && y_rot_pred == y_rot_expected
                        spatial_warrant_passes += 1
                    end
                catch
                end
            end
        end
    end
    spatial_warrant = spatial_warrant_trials > 0 ? (spatial_warrant_passes / spatial_warrant_trials) : 1.0

    mdl_score = exp(-alpha_mdl * max(ast_node_count - 1, 0))
    composite_fitness = 0.50 * train_acc + 0.25 * color_warrant + 0.15 * spatial_warrant + 0.10 * mdl_score

    return (
        train_accuracy = train_acc,
        color_scrambling_warrant = color_warrant,
        spatial_scrambling_warrant = spatial_warrant,
        aesthetic_mdl_score = mdl_score,
        composite_fitness = composite_fitness,
        is_warranted_generalizer = (train_acc == 1.0 && color_warrant == 1.0),
    )
end

"""
    evaluate_arc_agi2_loo_and_warrant_gate(
        synthesize_on_subset_fn::Function,
        demo_pairs::Vector{Tuple{Grid,Grid}};
        swappable_colors::Tuple{Int,Int} = (1, 2)
    )

Enforces both:
1. Informative Leave-One-Out (LOO) Criterial Gate (0-pixel residual across all N folds).
2. In-grid Legend Warrant-Scrambling Gate (equivariance under symbolic color swap).
"""
function evaluate_arc_agi2_loo_and_warrant_gate(
    synthesize_on_subset_fn::Function,
    demo_pairs::Vector{Tuple{Grid,Grid}};
    swappable_colors::Tuple{Int,Int} = (1, 2),
)
    n_demos = length(demo_pairs)
    n_demos >= 2 || throw(ArgumentError("Informative LOO gate requires at least 2 demonstration pairs"))

    loo_zero_pixel_folds = 0
    warrant_scramble_passes = 0
    ca, cb = swappable_colors

    for holdout_idx in 1:n_demos
        train_subset = [demo_pairs[i] for i in 1:n_demos if i != holdout_idx]
        x_val, y_val = demo_pairs[holdout_idx]

        candidate_prog = synthesize_on_subset_fn(train_subset)

        y_pred = candidate_prog(copy(x_val))
        if size(y_pred) == size(y_val) && y_pred == y_val
            loo_zero_pixel_folds += 1
        end

        x_scr, y_scr_expected = scramble_in_grid_legend_pair(x_val, y_val, ca, cb)
        y_scr_pred = candidate_prog(x_scr)
        if size(y_scr_pred) == size(y_scr_expected) && y_scr_pred == y_scr_expected
            warrant_scramble_passes += 1
        end
    end

    verdict = (loo_zero_pixel_folds == n_demos && warrant_scramble_passes == n_demos) ?
        :ACCEPTED : :REJECTED_OVERFIT_OR_UNWARRANTED

    return (
        verdict = verdict,
        loo_folds_passed = loo_zero_pixel_folds,
        legend_warrant_folds_passed = warrant_scramble_passes,
        total_folds = n_demos,
    )
end

end # module WarrantScramblingCritic

using .WarrantScramblingCritic

@testset "ARC-AGI-2 Warrant-Scrambling & Informative LOO Critic Tests" begin
    # Construct 3 synthetic ARC-AGI-2 training pairs with an in-grid legend at (1, 1):
    # Cell (1, 1) holds the target color (color 2 in all 3 demos); cells with marker 5
    # in the workspace (rows 2..4, cols 2..4) must be recolored to match legend cell (1, 1).
    demo_pairs = Tuple{Matrix{Int},Matrix{Int}}[]
    for k in 1:3
        x = zeros(Int, 4, 4)
        x[1, 1] = 2 # Legend instruction key: recolor marker 5 -> 2
        x[1 + k, 2 + mod(k, 2)] = 5
        y = copy(x)
        y[y .== 5] .= 2
        push!(demo_pairs, (x, y))
    end

    # 1. Shortcut / Memorizer AST: hardcodes `5 -> most_common_target_color_in_train (2)`
    #    ignoring the legend cell x[1, 1]. Scores 3/3 on naive LOO when all demos use 2,
    #    but FAILS 0/3 on Legend Warrant Scrambling when 2 <-> 1!
    shortcut_synthesizer(train_subset) = begin
        return function (grid::Matrix{Int})
            out = copy(grid)
            out[out .== 5] .= 2 # Hardcoded shortcut!
            return out
        end
    end

    # 2. Relational Legend-Reading AST: reads target color from `grid[1, 1]` and recolors `5 -> grid[1, 1]`
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

    # Verify evaluate_warrant_under_scrambling separates shortcut from relational generalizer
    w_shortcut = evaluate_warrant_under_scrambling(shortcut_synthesizer(demo_pairs), demo_pairs; fixed_colors = Set([0, 5]), test_rotations = false, ast_node_count = 12)
    w_relational = evaluate_warrant_under_scrambling(relational_synthesizer(demo_pairs), demo_pairs; fixed_colors = Set([0, 5]), test_rotations = false, ast_node_count = 4)
    @test w_shortcut.train_accuracy == 1.0
    @test w_shortcut.color_scrambling_warrant == 0.0
    @test !w_shortcut.is_warranted_generalizer
    @test w_relational.train_accuracy == 1.0
    @test w_relational.color_scrambling_warrant == 1.0
    @test w_relational.is_warranted_generalizer
    @test w_relational.composite_fitness > w_shortcut.composite_fitness

    # Verify D4 dihedral invertibility across all 8 group elements (0..7)
    sample_grid = reshape(collect(1:12), 3, 4)
    for op_id in 0:7
        @test inverse_dihedral_transform(dihedral_transform(sample_grid, op_id), op_id) == sample_grid
    end
end
