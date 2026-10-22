# src/verifier/loo.jl
# Leave-one-out cross-validation, train-exact replay, equivariance, and candidate verification

"""
    evaluate_train_exact(rule::AbstractGridRule, task::ARCTask)::TrainExactEvidence

Evaluates categorical replay match of the rule on all train demonstrations.
"""
function evaluate_train_exact(rule::AbstractGridRule, task::ARCTask)::TrainExactEvidence
    total_pairs = length(task.train)
    if total_pairs == 0
        return TrainExactEvidence(0, 0, 0.0)
    end

    matched = 0
    max_res = 0.0

    for demo in task.train
        try
            pred = apply_rule(rule, demo.input)
            if pred == demo.output
                matched += 1
            else
                if pred.height == demo.output.height && pred.width == demo.output.width
                    mismatches = count(pred.cells .!= demo.output.cells)
                    res = mismatches / (pred.height * pred.width)
                    max_res = max(max_res, Float64(res))
                else
                    max_res = 1.0
                end
            end
        catch e
            max_res = 1.0
        end
    end

    return TrainExactEvidence(matched, total_pairs, max_res)
end

"""
    rule_free_param_count(rule::AbstractGridRule)::Int

Returns the number of refittable free parameters for a symbolic grid rule.
"""
rule_free_param_count(::MarkerLineReflectionRule) = 2
rule_free_param_count(::ArcGeyserRule) = 3
rule_free_param_count(::ArcGyrismRule) = 3
rule_free_param_count(::AbstractGridRule) = 1

"""
    rule_excluded_colors(rule::AbstractGridRule)::Set{Int8}

Returns the set of landmark, emitter, beam, barrier, or center colors bound to `rule`
that must be held fixed when permuting non-landmark foreground colors.
"""
function rule_excluded_colors(rule::MarkerLineReflectionRule)::Set{Int8}
    return Set{Int8}([rule.marker_color])
end

function rule_excluded_colors(rule::ArcGeyserRule)::Set{Int8}
    excl = Set{Int8}([rule.emitter_color])
    rule.beam_color >= 0 && push!(excl, rule.beam_color)
    rule.intersection_color >= 0 && push!(excl, rule.intersection_color)
    for bc in rule.barrier_colors
        push!(excl, bc)
    end
    return excl
end

function rule_excluded_colors(rule::ArcGyrismRule)::Set{Int8}
    return rule.center_color >= 0 ? Set{Int8}([rule.center_color]) : Set{Int8}()
end

rule_excluded_colors(::AbstractGridRule)::Set{Int8} = Set{Int8}()

function _score_trial_rule(trial_rule::AbstractGridRule, train_demos::Vector{Demonstration})
    exact_matches = 0
    active_matches = 0
    neg_mismatches = 0
    for d in train_demos
        try
            pred = apply_rule(trial_rule, d.input)
            if pred == d.output
                exact_matches += 1
                if pred != d.input
                    active_matches += 1
                end
            elseif pred.height == d.output.height && pred.width == d.output.width
                neg_mismatches -= count(pred.cells .!= d.output.cells)
            else
                neg_mismatches -= (d.output.height * d.output.width)
            end
        catch
            neg_mismatches -= (d.output.height * d.output.width)
        end
    end
    return (exact_matches, active_matches, neg_mismatches)
end

"""
    evaluate_loo(rule::AbstractGridRule, task::ARCTask;
                 is_informative::Bool=false, free_param_count::Int=0)::InformativeLOOEvidence

Evaluates leave-one-out validation. Parameter-free rules are marked non-informative
unless parameters are genuinely refit on N-1 demonstrations.
"""
function evaluate_loo(rule::AbstractGridRule, task::ARCTask;
                      is_informative::Bool=false,
                      free_param_count::Int=(is_informative ? rule_free_param_count(rule) : 0))::InformativeLOOEvidence
    total_folds = length(task.train)
    if total_folds == 0
        return InformativeLOOEvidence(is_informative, 0, 0, free_param_count)
    end

    if free_param_count == 0 && !is_informative
        # Fixed parameter-free transform: non-informative LOO
        folds_passed = 0
        for demo in task.train
            try
                pred = apply_rule(rule, demo.input)
                if pred == demo.output
                    folds_passed += 1
                end
            catch
            end
        end
        return InformativeLOOEvidence(false, folds_passed, total_folds, 0)
    else
        # Informative LOO refit on N-1 demonstrations
        eff_params = max(free_param_count, 1)
        folds_passed = 0
        for k in 1:total_folds
            train_sub = [task.train[j] for j in 1:total_folds if j != k]
            held_out = task.train[k]

            refit_rule = refit_rule_parameters(rule, train_sub)
            try
                pred = apply_rule(refit_rule, held_out.input)
                if pred == held_out.output
                    folds_passed += 1
                end
            catch
            end
        end
        return InformativeLOOEvidence(true, folds_passed, total_folds, eff_params)
    end
end

"""
    refit_rule_parameters(rule::MarkerLineReflectionRule, train_demos::Vector{Demonstration})::MarkerLineReflectionRule

Refits `marker_color` and `axis_candidate` strictly from `train_demos` (N-1 folds) without
leaking held-out fold parameters when `train_demos` has zero active support for `rule`.
"""
function refit_rule_parameters(rule::MarkerLineReflectionRule, train_demos::Vector{Demonstration})::MarkerLineReflectionRule
    isempty(train_demos) && return rule

    best_color = Int8(0)
    best_axis = :auto
    best_key = (-1, -1, typemin(Int), false, false)

    candidate_colors = collect(Int8(0):Int8(9))
    candidate_axes = Symbol[:auto, :point, :vertical, :horizontal]

    for c in candidate_colors, axis in candidate_axes
        trial_rule = MarkerLineReflectionRule(c, axis, rule.marker_cells)
        exact_m, active_m, neg_err = _score_trial_rule(trial_rule, train_demos)
        is_fg_landmark = (active_m > 0) && all(d -> c != d.input.bg_color && (c in d.input.cells), train_demos)
        is_orig_active = (active_m > 0) && (c == rule.marker_color) && (axis == rule.axis_candidate)
        key = (exact_m, active_m, neg_err, is_fg_landmark, is_orig_active)
        if key > best_key
            best_key = key
            best_color = c
            best_axis = axis
        end
    end

    return MarkerLineReflectionRule(best_color, best_axis, rule.marker_cells)
end

"""
    refit_rule_parameters(rule::ArcGeyserRule, train_demos::Vector{Demonstration})::ArcGeyserRule

Refits `emitter_color`, `beam_color`, and `directions` strictly from `train_demos` (N-1 folds).
"""
function refit_rule_parameters(rule::ArcGeyserRule, train_demos::Vector{Demonstration})::ArcGeyserRule
    isempty(train_demos) && return rule

    input_colors = Int8[]
    output_colors = Int8[-1]
    for d in train_demos
        append!(input_colors, unique(d.input.cells))
        append!(output_colors, unique(d.output.cells))
    end
    cand_emitters = sort(unique(Int8[input_colors; collect(Int8(0):Int8(9))]))
    cand_beams    = sort(unique(output_colors))
    cand_dirs     = Symbol[:cardinal, :diagonal, :all8, :up, :down, :left, :right]

    best_emitter = Int8(0)
    best_beam = Int8(-1)
    best_dir = :cardinal
    best_key = (-1, -1, typemin(Int), false, false, false)

    for e_col in cand_emitters, b_col in cand_beams, dir in cand_dirs
        trial_rule = ArcGeyserRule(
            e_col,
            b_col,
            dir,
            rule.barrier_colors,
            rule.stop_at_barrier,
            rule.intersection_color
        )
        exact_m, active_m, neg_err = _score_trial_rule(trial_rule, train_demos)
        is_fg_landmark = (active_m > 0) && all(d -> e_col != d.input.bg_color && (e_col in d.input.cells), train_demos)
        is_orig_active = (active_m == length(train_demos)) &&
                         (e_col == rule.emitter_color) &&
                         (b_col == rule.beam_color) &&
                         (dir == rule.directions)
        inherit_pref = (b_col == Int8(-1))
        key = (exact_m, active_m, neg_err, is_fg_landmark, is_orig_active, inherit_pref)
        if key > best_key
            best_key = key
            best_emitter = e_col
            best_beam = b_col
            best_dir = dir
        end
    end

    return ArcGeyserRule(
        best_emitter,
        best_beam,
        best_dir,
        rule.barrier_colors,
        rule.stop_at_barrier,
        rule.intersection_color
    )
end

"""
    refit_rule_parameters(rule::ArcGyrismRule, train_demos::Vector{Demonstration})::ArcGyrismRule

Refits `center_color`, `angle_degrees`, and `clockwise` strictly from `train_demos` (N-1 folds).
"""
function refit_rule_parameters(rule::ArcGyrismRule, train_demos::Vector{Demonstration})::ArcGyrismRule
    isempty(train_demos) && return rule

    cand_centers = Int8[collect(Int8(0):Int8(9)); -1]
    cand_angles  = Int[90, 180, 270]
    cand_cw      = Bool[true, false]

    best_center = Int8(-1)
    best_angle  = 90
    best_cw     = true
    best_key    = (-1, -1, typemin(Int), false, false)

    for c_col in cand_centers, ang in cand_angles, cw in cand_cw
        trial_rule = ArcGyrismRule(c_col, ang, cw)
        exact_m, active_m, neg_err = _score_trial_rule(trial_rule, train_demos)
        is_fg_landmark = (active_m > 0) && (c_col >= 0) &&
                         all(d -> c_col != d.input.bg_color && (c_col in d.input.cells), train_demos)
        is_orig_active = (active_m == length(train_demos)) &&
                         (c_col == rule.center_color) &&
                         (ang == rule.angle_degrees) &&
                         (cw == rule.clockwise)
        key = (exact_m, active_m, neg_err, is_fg_landmark, is_orig_active)
        if key > best_key
            best_key = key
            best_center = c_col
            best_angle = ang
            best_cw = cw
        end
    end

    return ArcGyrismRule(best_center, best_angle, best_cw)
end

function refit_rule_parameters(rule::AbstractGridRule, train_demos::Vector{Demonstration})::AbstractGridRule
    return rule
end

# Dihedral group D8 transforms on matrices
function apply_d8_transform(m::Matrix{Int8}, idx::Int)::Matrix{Int8}
    if idx == 1      # Identity (:id)
        return copy(m)
    elseif idx == 2  # rot90 clockwise (:rot90)
        return rotr90(m)
    elseif idx == 3  # rot180 (:rot180)
        return rot180(m)
    elseif idx == 4  # rot270 clockwise (:rot270)
        return rotl90(m)
    elseif idx == 5  # Left-right reflection across vertical axis (:refl_v, reverse columns)
        return reverse(m, dims=2)
    elseif idx == 6  # Top-bottom reflection across horizontal axis (:refl_h, reverse rows)
        return reverse(m, dims=1)
    elseif idx == 7  # Main diagonal reflection (:refl_main_diag, transpose)
        return Matrix{Int8}(m')
    elseif idx == 8  # Anti-diagonal reflection (:refl_anti_diag, anti-transpose)
        return reverse(reverse(Matrix{Int8}(m'), dims=1), dims=2)
    else
        throw(ArgumentError("Invalid D8 transform index: $idx"))
    end
end

function apply_d8_transform(m::Matrix{Int8}, op::Symbol)::Matrix{Int8}
    if op === :id
        return apply_d8_transform(m, 1)
    elseif op === :rot90
        return apply_d8_transform(m, 2)
    elseif op === :rot180
        return apply_d8_transform(m, 3)
    elseif op === :rot270
        return apply_d8_transform(m, 4)
    elseif op === :refl_v
        return apply_d8_transform(m, 5)
    elseif op === :refl_h
        return apply_d8_transform(m, 6)
    elseif op === :refl_main_diag
        return apply_d8_transform(m, 7)
    elseif op === :refl_anti_diag
        return apply_d8_transform(m, 8)
    else
        throw(ArgumentError("Invalid D8 transform symbol: $op"))
    end
end

function _is_untestable_transform_for_rule(rule::AbstractGridRule, op::Symbol)::Bool
    if rule isa MarkerLineReflectionRule
        if !isempty(rule.marker_cells) && op !== :id
            return true
        end
        if rule.axis_candidate in (:vertical, :horizontal) &&
           op in (:rot90, :rot270, :refl_main_diag, :refl_anti_diag)
            return true
        end
    end
    return false
end

"""
    evaluate_equivariance(rule::AbstractGridRule, task::ARCTask;
                          allow_untestable::Bool=true,
                          requested_group::Symbol=:D8)::EquivarianceEvidence

Evaluates equivariance under the requested geometric symmetry group (`requested_group`, defaulting
to `:D8`) and non-landmark foreground color permutations.
Records exact `tested_transforms`, `passed_transforms`, `failed_transforms`, `untestable_transforms`,
and `supported_subgroups`.
"""
function evaluate_equivariance(rule::AbstractGridRule, task::ARCTask;
                              allow_untestable::Bool=true,
                              requested_group::Symbol=:D8)::EquivarianceEvidence
    tested = group_transforms(requested_group)
    if isempty(task.train)
        st = allow_untestable ? :untestable : :failed
        return EquivarianceEvidence(false, false, st, requested_group, tested, Symbol[], Symbol[], copy(tested), Symbol[])
    end

    # Evaluate all 8 canonical D8 transforms so we know both full D8 status and requested_group status
    all_passed = Symbol[]
    all_failed = Symbol[]
    all_untestable = Symbol[]

    for op in CANONICAL_D8_TRANSFORMS
        op_passed = true
        op_untestable = false

        for demo in task.train
            try
                pred_orig = apply_rule(rule, demo.input)
                t_pred_orig = apply_d8_transform(pred_orig.cells, op)

                t_input = GridState(apply_d8_transform(demo.input.cells, op))
                pred_transformed = apply_rule(rule, t_input)

                if t_pred_orig != pred_transformed.cells
                    if _is_untestable_transform_for_rule(rule, op)
                        op_untestable = true
                    else
                        op_passed = false
                    end
                end
            catch
                op_untestable = true
            end
        end

        if op_untestable
            push!(all_untestable, op)
        elseif op_passed
            push!(all_passed, op)
        else
            push!(all_failed, op)
        end
    end

    tested_set = Set{Symbol}(tested)
    passed = [op for op in tested if op in all_passed]
    failed = [op for op in tested if op in all_failed]
    untestable = [op for op in tested if op in all_untestable]
    supported = compute_supported_subgroups(all_passed)
    d8_passed = (:D8 in supported) && isempty(all_failed) && isempty(all_untestable)

    # Test color permutation equivariance (permute non-background, non-landmark foreground colors)
    color_perm_passed = true
    color_perm_testable = true
    excl_colors = rule_excluded_colors(rule)

    for demo in task.train
        bg = demo.input.bg_color
        fg_colors = filter(c -> c != bg && !(c in excl_colors), unique(demo.input.cells))

        if isempty(fg_colors)
            continue
        end

        shift_map = Dict{Int8, Int8}()
        for c in Int8(0):Int8(9)
            shift_map[c] = c
        end

        if length(fg_colors) >= 2
            for i in 1:length(fg_colors)
                next_c = fg_colors[mod1(i + 1, length(fg_colors))]
                shift_map[fg_colors[i]] = next_c
            end
        else
            c_orig = fg_colors[1]
            used = union(Set{Int8}([bg, c_orig]), excl_colors)
            avail = [c for c in Int8(0):Int8(9) if !(c in used)]
            if !isempty(avail)
                c_sub = avail[1]
                shift_map[c_orig] = c_sub
                shift_map[c_sub] = c_orig
            end
        end

        try
            pred_orig = apply_rule(rule, demo.input)
            t_pred_cells = map(c -> get(shift_map, c, c), pred_orig.cells)

            perm_input_cells = map(c -> get(shift_map, c, c), demo.input.cells)
            perm_input = GridState(perm_input_cells)
            pred_perm = apply_rule(rule, perm_input)

            if t_pred_cells != pred_perm.cells
                color_perm_passed = false
            end
        catch
            color_perm_testable = false
        end
    end

    status = if !isempty(failed) || (color_perm_testable && !color_perm_passed)
        :failed
    elseif !isempty(untestable) || !color_perm_testable
        allow_untestable ? :untestable : :failed
    else
        :passed
    end

    return EquivarianceEvidence(
        d8_passed,
        color_perm_passed,
        status,
        requested_group,
        tested,
        passed,
        failed,
        untestable,
        supported
    )
end

"""
    verify_candidate(candidate::Candidate, task::ARCTask;
                     requested_group::Symbol=:D8)::Tuple{Bool, Symbol, Vector{AbstractEvidence}}

Full verification pipeline evaluating:
1. Shape and palette validity
2. Exact train replay gate
3. Informative LOO refit / generalization gate
4. Three-valued equivariance gate (:passed, :failed, :untestable) scoped to `requested_group`
"""
function verify_candidate(candidate::Candidate, task::ARCTask;
                          requested_group::Symbol=:D8)::Tuple{Bool, Symbol, Vector{AbstractEvidence}}
    evidence = AbstractEvidence[]

    # 1. Train-exact replay gate
    train_ev = evaluate_train_exact(candidate.rule, task)
    push!(evidence, train_ev)
    if train_ev.pairs_matched < train_ev.total_pairs
        return (false, :failed, evidence)
    end

    # 2. Informative LOO gate
    is_inf = (candidate.provenance.solver_family != :fixed_macro)
    n_free = is_inf ? rule_free_param_count(candidate.rule) : 0
    loo_ev = evaluate_loo(candidate.rule, task;
                          is_informative=is_inf,
                          free_param_count=n_free)
    push!(evidence, loo_ev)

    if loo_ev.is_informative
        if loo_ev.folds_passed < loo_ev.total_folds
            return (false, :failed, evidence)
        end
    else
        # Parameter-free fixed transforms require cross_task_firing >= 2
        if candidate.provenance.cross_task_firing < 2
            return (false, :failed, evidence)
        end
    end

    # 3. Equivariance gate
    eq_ev = evaluate_equivariance(candidate.rule, task; requested_group=requested_group)
    push!(evidence, eq_ev)

    if eq_ev.status == :failed
        return (false, :failed, evidence)
    elseif eq_ev.status == :untestable
        # Untestable status yields :incomplete rather than false pass or false fail
        return (false, :incomplete, evidence)
    end

    return (true, :passed, evidence)
end

"""
    depolarize_membrane(rule::AbstractGridRule, task::ARCTask;
                        requested_group::Symbol=:D8)::AbstractVerdict

Evaluates the unified criterial verification barrier across the FFI boundary without
numeric `Inf` sentinels:
1. `train_exact_gate`: Exact matrix match on all demonstrations (`max_cell_residual == 0.0`).
2. `informative_loo_gate`: Informative N-1 Leave-One-Out parameter refit consistency.
3. `equivariance_gate`: Commutation with `requested_group` and non-landmark color permutations
   (`:untestable` returns `Incomplete` rather than `Accepted`).
4. `topological_homomorphism_gate`: Component count preservation across demonstrations.
"""
function depolarize_membrane(rule::AbstractGridRule, task::ARCTask;
                             requested_group::Symbol=:D8)::AbstractVerdict
    # 1. Train-exact replay gate
    train_ev = evaluate_train_exact(rule, task)
    if train_ev.total_pairs == 0
        return Incomplete(:empty_training_set, "Cannot verify rule on a task with zero demonstrations.")
    end
    if train_ev.pairs_matched < train_ev.total_pairs || train_ev.max_cell_residual != 0.0
        partial = Float64(train_ev.pairs_matched) / Float64(train_ev.total_pairs)
        return Rejected(
            :train_exact_failed,
            "Train exact gate failed ($(train_ev.pairs_matched)/$(train_ev.total_pairs) pairs matched).",
            [:train_exact_gate],
            partial
        )
    end

    # 2. Informative N-1 LOO refit gate
    loo_ev = evaluate_loo(rule, task; is_informative=true, free_param_count=rule_free_param_count(rule))
    if loo_ev.folds_passed < loo_ev.total_folds
        partial = Float64(loo_ev.folds_passed) / Float64(max(loo_ev.total_folds, 1))
        return Rejected(
            :informative_loo_failed,
            "Informative LOO refit failed ($(loo_ev.folds_passed)/$(loo_ev.total_folds) folds passed).",
            [:informative_loo_gate],
            partial
        )
    end

    # 3. Equivariance Commutator (E_comm)
    eq_ev = evaluate_equivariance(rule, task; requested_group=requested_group)
    if eq_ev.status === :failed
        return Rejected(
            :equivariance_failed,
            "Equivariance gate failed on requested group $(requested_group): failed=$(eq_ev.failed_transforms).",
            [:equivariance_gate],
            0.5
        )
    elseif eq_ev.status === :untestable
        return Incomplete(
            :equivariance_untestable,
            "Equivariance is untestable on requested group $(requested_group): untestable=$(eq_ev.untestable_transforms)."
        )
    end

    # 4. Topological Homomorphism (H_topo)
    for demo in task.train
        try
            pred = apply_rule(rule, demo.input)
            if length(pred.components) != length(demo.output.components)
                return Rejected(
                    :topological_mismatch,
                    "Predicted component count $(length(pred.components)) != expected $(length(demo.output.components)).",
                    [:topological_homomorphism_gate],
                    0.75
                )
            end
        catch e
            return Rejected(
                :topological_execution_error,
                "Rule execution threw exception during topological check: $(sprint(showerror, e))",
                [:topological_homomorphism_gate],
                0.0
            )
        end
    end

    return Accepted(
        (
            rule = rule,
            train_evidence = train_ev,
            loo_evidence = loo_ev,
            equivariance_evidence = eq_ev
        ),
        (:train_exact_verified, :informative_loo_verified, :equivariance_verified, :topological_homomorphism_verified),
        1.0,
        "Membrane depolarized: all verification gates satisfied under $(requested_group)."
    )
end
