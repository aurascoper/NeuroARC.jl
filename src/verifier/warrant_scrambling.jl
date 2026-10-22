# src/verifier/warrant_scrambling.jl
# Coevolutionary Warrant-Scrambling Critic, In-Grid Legend Scrambling, Informative LOO Gate,
# and Homoiconic S-Expression / AST Intron Pruning for NeuroARC.jl
# Strictly zero em-dashes and zero en-dashes.

"""
    LegendRelationalRecolorRule <: AbstractGridRule

ARC-AGI-2 rule family for tasks with an in-grid instruction header/legend cell:
- If `use_relational_legend == true`, reads the target replacement color dynamically from
  `grid.cells[legend_row, legend_col]` and recolors all workspace cells matching `marker_color`.
- If `use_relational_legend == false`, uses a hardcoded `hardcoded_target_color` (representing
  an unwarranted shortcut memorizer that overfits constant training legends).
"""
struct LegendRelationalRecolorRule <: AbstractGridRule
    marker_color::Int8
    legend_row::Int
    legend_col::Int
    use_relational_legend::Bool
    hardcoded_target_color::Int8
    ast_node_count::Int

    function LegendRelationalRecolorRule(
        marker_color::Integer;
        legend_row::Integer = 1,
        legend_col::Integer = 1,
        use_relational_legend::Bool = true,
        hardcoded_target_color::Integer = 2,
        ast_node_count::Integer = (use_relational_legend ? 4 : 12),
    )
        new(
            Int8(marker_color),
            Int(legend_row),
            Int(legend_col),
            use_relational_legend,
            Int8(hardcoded_target_color),
            Int(ast_node_count),
        )
    end
end

function apply_rule(rule::LegendRelationalRecolorRule, grid::GridState)::GridState
    out_cells = copy(grid.cells)
    target_c = if rule.use_relational_legend
        (1 <= rule.legend_row <= grid.height && 1 <= rule.legend_col <= grid.width) ||
            throw(BoundsError(grid.cells, (rule.legend_row, rule.legend_col)))
        grid.cells[rule.legend_row, rule.legend_col]
    else
        rule.hardcoded_target_color
    end
    @inbounds for idx in eachindex(out_cells)
        if out_cells[idx] == rule.marker_color
            out_cells[idx] = target_c
        end
    end
    return GridState(out_cells)
end

function refit_rule_parameters(
    rule::LegendRelationalRecolorRule,
    train_demos::Vector{Demonstration},
)::LegendRelationalRecolorRule
    isempty(train_demos) && return rule
    if !rule.use_relational_legend
        # Shortcut memorizer fits the constant target color seen in the N-1 training subset
        d1 = train_demos[1]
        inferred_target = rule.hardcoded_target_color
        @inbounds for idx in eachindex(d1.input.cells)
            if d1.input.cells[idx] == rule.marker_color
                inferred_target = d1.output.cells[idx]
                break
            end
        end
        return LegendRelationalRecolorRule(
            rule.marker_color;
            legend_row = rule.legend_row,
            legend_col = rule.legend_col,
            use_relational_legend = false,
            hardcoded_target_color = inferred_target,
            ast_node_count = rule.ast_node_count,
        )
    end
    return rule
end

"""
    dihedral_transform(grid::AbstractMatrix{T}, op_id::Int) -> Matrix{T}

Applies one of the 8 dihedral group D4 symmetries (`0..7`).
"""
function dihedral_transform(grid::AbstractMatrix{T}, op_id::Int)::Matrix{T} where {T<:Integer}
    rot_k = mod(op_id, 4)
    g = if rot_k == 0
        Matrix{T}(grid)
    elseif rot_k == 1
        rotr90(grid)
    elseif rot_k == 2
        rot180(grid)
    else
        rotl90(grid)
    end
    return op_id >= 4 ? reverse(g, dims = 2) : g
end

dihedral_transform(grid::GridState, op_id::Int)::GridState =
    GridState(dihedral_transform(grid.cells, op_id))

"""
    inverse_dihedral_transform(grid::AbstractMatrix{T}, op_id::Int) -> Matrix{T}

Exact inverse of `dihedral_transform(grid, op_id)`.
"""
function inverse_dihedral_transform(grid::AbstractMatrix{T}, op_id::Int)::Matrix{T} where {T<:Integer}
    g = op_id >= 4 ? reverse(Matrix{T}(grid), dims = 2) : Matrix{T}(grid)
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

inverse_dihedral_transform(grid::GridState, op_id::Int)::GridState =
    GridState(inverse_dihedral_transform(grid.cells, op_id))

"""
    permute_colors(grid::AbstractMatrix{T}, color_map::AbstractDict) -> Matrix{T}

Applies a bijective color scrambling map simultaneously across `grid`.
"""
function permute_colors(grid::AbstractMatrix{T}, color_map::AbstractDict)::Matrix{T} where {T<:Integer}
    out = similar(grid, T)
    @inbounds for idx in eachindex(grid)
        c = grid[idx]
        mapped = get(color_map, c, get(color_map, Int(c), c))
        out[idx] = T(mapped)
    end
    return out
end

permute_colors(grid::GridState, color_map::AbstractDict)::GridState =
    GridState(permute_colors(grid.cells, color_map))

"""
    scramble_in_grid_legend_pair(x, y, color_a::Integer, color_b::Integer)

Swaps symbolic colors `color_a <-> color_b` across both input and output grids.
"""
function scramble_in_grid_legend_pair(
    x::AbstractMatrix{T},
    y::AbstractMatrix{T},
    color_a::Integer,
    color_b::Integer,
)::Tuple{Matrix{T},Matrix{T}} where {T<:Integer}
    cmap = Dict{T,T}(T(color_a) => T(color_b), T(color_b) => T(color_a))
    return (permute_colors(x, cmap), permute_colors(y, cmap))
end

function scramble_in_grid_legend_pair(
    demo::Demonstration,
    color_a::Integer,
    color_b::Integer,
)::Demonstration
    x_scr, y_scr = scramble_in_grid_legend_pair(demo.input.cells, demo.output.cells, color_a, color_b)
    return Demonstration(GridState(x_scr), GridState(y_scr))
end

"""
    count_ast_nodes(expr) -> Int

Counts total symbolic nodes in a homoiconic Julia `Expr` / S-expression AST.
"""
function count_ast_nodes(expr)::Int
    if expr isa Expr
        total = 1
        for arg in expr.args
            if !(arg isa LineNumberNode)
                total += count_ast_nodes(arg)
            end
        end
        return total
    else
        return 1
    end
end

"""
    prune_unwarranted_ast_introns(expr::Expr, is_equivalent_fn::Function) -> Tuple{Expr, Int}

Homoiconic Lisp/Expr subtree ablation (Internal Warrant Gate):
Tests whether wrapping or chaining sub-expressions in `:block` or unary call chains
contains redundant evolutionary hitchhikers (introns) whose removal leaves training
behavior strictly invariant, returning `(pruned_expr, removed_node_count)`.
"""
function prune_unwarranted_ast_introns(expr::Expr, is_equivalent_fn::Function)::Tuple{Expr,Int}
    orig_nodes = count_ast_nodes(expr)
    best_expr = expr
    if expr.head === :block
        kept_args = Any[]
        for (idx, arg) in enumerate(expr.args)
            if arg isa LineNumberNode
                continue
            end
            trial_args = [a for (j, a) in enumerate(expr.args) if j != idx && !(a isa LineNumberNode)]
            if !isempty(trial_args)
                trial_expr = Expr(:block, trial_args...)
                if is_equivalent_fn(trial_expr)
                    return prune_unwarranted_ast_introns(trial_expr, is_equivalent_fn)
                end
            end
            push!(kept_args, arg)
        end
    elseif expr.head === :call && length(expr.args) == 2
        # Check if outer unary combinator `f(inner)` is an identity intron on all training pairs
        inner = expr.args[2]
        if inner isa Expr && is_equivalent_fn(inner)
            best_expr, _ = prune_unwarranted_ast_introns(inner, is_equivalent_fn)
        end
    end
    pruned_nodes = count_ast_nodes(best_expr)
    return (best_expr, max(0, orig_nodes - pruned_nodes))
end

"""
    evaluate_warrant_under_scrambling(
        program_fn::Function,
        train_pairs::AbstractVector{<:Tuple{AbstractMatrix{<:Integer},AbstractMatrix{<:Integer}}};
        fixed_colors::Set{Int} = Set([0]),
        test_rotations::Bool = true,
        ast_node_count::Int = 1,
        alpha_mdl::Float64 = 0.02
    )
"""
function evaluate_warrant_under_scrambling(
    program_fn::Function,
    train_pairs::AbstractVector{<:Tuple{AbstractMatrix{<:Integer},AbstractMatrix{<:Integer}}};
    fixed_colors::Set{Int} = Set([0]),
    test_rotations::Bool = true,
    ast_node_count::Int = 1,
    alpha_mdl::Float64 = 0.02,
)
    exact_matches = 0
    color_set = Set{Int}()
    for (x, y) in train_pairs
        for c in x
            !(Int(c) in fixed_colors) && push!(color_set, Int(c))
        end
        for c in y
            !(Int(c) in fixed_colors) && push!(color_set, Int(c))
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
    evaluate_warrant_under_scrambling(
        rule::AbstractGridRule,
        task::ARCTask;
        fixed_colors::Union{Nothing,Set{Int}} = nothing,
        test_rotations::Union{Nothing,Bool} = nothing,
        ast_node_count::Int = 1,
        alpha_mdl::Float64 = 0.02
    )::WarrantScramblingEvidence

Evaluates an `AbstractGridRule` on an `ARCTask` and returns a `WarrantScramblingEvidence` record.
"""
function evaluate_warrant_under_scrambling(
    rule::AbstractGridRule,
    task::ARCTask;
    fixed_colors::Union{Nothing,Set{Int}} = nothing,
    test_rotations::Union{Nothing,Bool} = nothing,
    ast_node_count::Int = (rule isa LegendRelationalRecolorRule ? rule.ast_node_count : 1),
    alpha_mdl::Float64 = 0.02,
)::WarrantScramblingEvidence
    if isempty(task.train)
        return WarrantScramblingEvidence(0.0, 0.0, 0.0, 0.0, 1.0, 0.0, false, :untestable)
    end

    inferred_fixed = if fixed_colors !== nothing
        fixed_colors
    else
        s = Set{Int}([Int(task.train[1].input.bg_color)])
        if rule isa MarkerLineReflectionRule
            push!(s, Int(rule.marker_color))
        elseif rule isa LegendRelationalRecolorRule
            push!(s, Int(rule.marker_color))
        elseif rule isa ArcGeyserRule
            push!(s, Int(rule.cap_color))
            push!(s, Int(rule.flow_color))
        end
        s
    end

    rot_flag = if test_rotations !== nothing
        test_rotations
    elseif rule isa LegendRelationalRecolorRule || rule isa ArcGeyserRule
        false
    elseif rule isa MarkerLineReflectionRule && (rule.axis_candidate in (:vertical, :horizontal) || !isempty(rule.marker_cells))
        false
    else
        true
    end

    matrix_pairs = Tuple{Matrix{Int},Matrix{Int}}[
        (Matrix{Int}(d.input.cells), Matrix{Int}(d.output.cells)) for d in task.train
    ]
    prog_fn = (m::Matrix{Int}) -> Matrix{Int}(apply_rule(rule, GridState(Matrix{Int8}(m))).cells)

    res = evaluate_warrant_under_scrambling(
        prog_fn,
        matrix_pairs;
        fixed_colors = inferred_fixed,
        test_rotations = rot_flag,
        ast_node_count = ast_node_count,
        alpha_mdl = alpha_mdl,
    )

    legend_warrant = res.color_scrambling_warrant
    is_warranted = (res.train_accuracy == 1.0 && res.color_scrambling_warrant == 1.0 && legend_warrant == 1.0)
    status = is_warranted ? :passed : :failed

    return WarrantScramblingEvidence(
        res.train_accuracy,
        res.color_scrambling_warrant,
        res.spatial_scrambling_warrant,
        legend_warrant,
        res.aesthetic_mdl_score,
        res.composite_fitness,
        is_warranted,
        status,
    )
end

"""
    evaluate_arc_agi2_loo_and_warrant_gate(
        synthesize_on_subset_fn::Function,
        demo_pairs::AbstractVector{<:Tuple{AbstractMatrix{<:Integer},AbstractMatrix{<:Integer}}};
        swappable_colors::Tuple{Int,Int} = (1, 2)
    )
"""
function evaluate_arc_agi2_loo_and_warrant_gate(
    synthesize_on_subset_fn::Function,
    demo_pairs::AbstractVector{<:Tuple{AbstractMatrix{<:Integer},AbstractMatrix{<:Integer}}};
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

function evaluate_arc_agi2_loo_and_warrant_gate(
    rule::AbstractGridRule,
    task::ARCTask;
    swappable_colors::Tuple{Int,Int} = (1, 2),
)
    n_demos = length(task.train)
    n_demos >= 2 || throw(ArgumentError("Informative LOO gate requires at least 2 demonstration pairs"))

    loo_zero_pixel_folds = 0
    warrant_scramble_passes = 0
    ca, cb = swappable_colors

    for holdout_idx in 1:n_demos
        train_sub = [task.train[i] for i in 1:n_demos if i != holdout_idx]
        held_out = task.train[holdout_idx]
        refit_r = refit_rule_parameters(rule, train_sub)

        try
            pred = apply_rule(refit_r, held_out.input)
            if pred == held_out.output
                loo_zero_pixel_folds += 1
            end
        catch
        end

        try
            scr_demo = scramble_in_grid_legend_pair(held_out, ca, cb)
            scr_pred = apply_rule(refit_r, scr_demo.input)
            if scr_pred == scr_demo.output
                warrant_scramble_passes += 1
            end
        catch
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
