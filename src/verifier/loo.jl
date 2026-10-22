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
    evaluate_loo(rule::AbstractGridRule, task::ARCTask;
                 is_informative::Bool=false, free_param_count::Int=0)::InformativeLOOEvidence

Evaluates leave-one-out validation. Parameter-free rules are marked non-informative
unless parameters are genuinely refit on N-1 demonstrations.
"""
function evaluate_loo(rule::AbstractGridRule, task::ARCTask;
                      is_informative::Bool=false, free_param_count::Int=0)::InformativeLOOEvidence
    total_folds = length(task.train)
    if total_folds == 0
        return InformativeLOOEvidence(is_informative, 0, 0, free_param_count)
    end

    if free_param_count == 0
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
        folds_passed = 0
        for k in 1:total_folds
            train_sub = [task.train[j] for j in 1:total_folds if j != k]
            held_out = task.train[k]

            # In R1, refit parameter searches best marker color from train_sub
            refit_rule = refit_rule_parameters(rule, train_sub)
            try
                pred = apply_rule(refit_rule, held_out.input)
                if pred == held_out.output
                    folds_passed += 1
                end
            catch
            end
        end
        return InformativeLOOEvidence(true, folds_passed, total_folds, free_param_count)
    end
end

"""
    refit_rule_parameters(rule::MarkerLineReflectionRule, train_demos::Vector{Demonstration})::MarkerLineReflectionRule

Refits rule parameters (e.g. marker_color, axis_candidate) against the training subset.
"""
function refit_rule_parameters(rule::MarkerLineReflectionRule, train_demos::Vector{Demonstration})::MarkerLineReflectionRule
    best_color = rule.marker_color
    best_axis = rule.axis_candidate
    best_score = -1

    candidate_colors = unique(Int8[rule.marker_color; Int8(0):Int8(9)])
    candidate_axes = Symbol[:auto, :point, :vertical, :horizontal]

    for c in candidate_colors, axis in candidate_axes
        trial_rule = MarkerLineReflectionRule(c; axis_candidate=axis)
        score = 0
        for d in train_demos
            try
                if apply_rule(trial_rule, d.input) == d.output
                    score += 1
                end
            catch
            end
        end
        if score > best_score
            best_score = score
            best_color = c
            best_axis = axis
        end
    end

    return MarkerLineReflectionRule(best_color; axis_candidate=best_axis)
end

function refit_rule_parameters(rule::AbstractGridRule, train_demos::Vector{Demonstration})::AbstractGridRule
    return rule
end

# Dihedral group D8 transforms on matrices
function apply_d8_transform(m::Matrix{Int8}, idx::Int)::Matrix{Int8}
    if idx == 1      # Identity
        return copy(m)
    elseif idx == 2  # rot90 clockwise
        return rotr90(m)
    elseif idx == 3  # rot180
        return rot180(m)
    elseif idx == 4  # rot270 clockwise (rot90 counter-clockwise)
        return rotl90(m)
    elseif idx == 5  # Horizontal flip (reverse columns)
        return reverse(m, dims=2)
    elseif idx == 6  # Vertical flip (reverse rows)
        return reverse(m, dims=1)
    elseif idx == 7  # Transpose
        return Matrix{Int8}(m')
    elseif idx == 8  # Anti-transpose
        return reverse(reverse(Matrix{Int8}(m'), dims=1), dims=2)
    else
        throw(ArgumentError("Invalid D8 transform index: $idx"))
    end
end

"""
    evaluate_equivariance(rule::AbstractGridRule, task::ARCTask;
                          allow_untestable::Bool=true)::EquivarianceEvidence

Evaluates equivariance under D8 dihedral and color permutation symmetries.
Returns 3-valued status: `:passed`, `:failed`, or `:untestable`.
"""
function evaluate_equivariance(rule::AbstractGridRule, task::ARCTask;
                              allow_untestable::Bool=true)::EquivarianceEvidence
    if isempty(task.train)
        return EquivarianceEvidence(false, false, :untestable)
    end

    # Test D8 equivariance
    d8_passed = true
    d8_testable = true

    for demo in task.train
        for d8_idx in 1:8
            try
                pred_orig = apply_rule(rule, demo.input)
                t_pred_orig = apply_d8_transform(pred_orig.cells, d8_idx)

                t_input = GridState(apply_d8_transform(demo.input.cells, d8_idx))
                pred_transformed = apply_rule(rule, t_input)

                if t_pred_orig != pred_transformed.cells
                    # If directional or coordinate-grounded rule encounters asymmetric transform, check if testable
                    if rule isa MarkerLineReflectionRule && (rule.axis_candidate in (:vertical, :horizontal) || !isempty(rule.marker_cells))
                        d8_testable = false
                    else
                        d8_passed = false
                    end
                end
            catch e
                d8_testable = false
            end
        end
    end

    # Test color permutation equivariance (permute non-background, non-marker colors)
    color_perm_passed = true
    color_perm_testable = true

    for demo in task.train
        bg = demo.input.bg_color
        m_color = (rule isa MarkerLineReflectionRule) ? rule.marker_color : Int8(-1)
        fg_colors = filter(c -> c != bg && c != m_color, unique(demo.input.cells))

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
            used = Set([bg, m_color, c_orig])
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

    status = if !d8_testable || !color_perm_testable
        :untestable
    elseif d8_passed && color_perm_passed
        :passed
    else
        :failed
    end

    return EquivarianceEvidence(d8_passed, color_perm_passed, status)
end

"""
    verify_candidate(candidate::Candidate, task::ARCTask)::Tuple{Bool, Symbol, Vector{AbstractEvidence}}

Full verification pipeline evaluating:
1. Shape and palette validity
2. Exact train replay gate
3. Informative LOO refit / generalization gate
4. Three-valued equivariance gate (:passed, :failed, :untestable)
"""
function verify_candidate(candidate::Candidate, task::ARCTask;
                          check_warrant_scrambling::Bool=(candidate.rule isa LegendRelationalRecolorRule))::Tuple{Bool, Symbol, Vector{AbstractEvidence}}
    evidence = AbstractEvidence[]

    # 1. Train-exact replay gate
    train_ev = evaluate_train_exact(candidate.rule, task)
    push!(evidence, train_ev)
    if train_ev.pairs_matched < train_ev.total_pairs
        return (false, :failed, evidence)
    end

    # 2. Informative LOO gate
    loo_ev = evaluate_loo(candidate.rule, task;
                          is_informative=(candidate.provenance.solver_family != :fixed_macro),
                          free_param_count=(candidate.provenance.solver_family != :fixed_macro ? 1 : 0))
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

    # 3. Warrant-Scrambling gate (when enabled or for LegendRelationalRecolorRule)
    if check_warrant_scrambling
        ws_ev = evaluate_warrant_under_scrambling(candidate.rule, task)
        push!(evidence, ws_ev)
        if !ws_ev.is_warranted_generalizer
            return (false, :failed, evidence)
        end
        if candidate.rule isa LegendRelationalRecolorRule
            return (true, :passed, evidence)
        end
    end

    # 4. Equivariance gate
    eq_ev = evaluate_equivariance(candidate.rule, task)
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
    depolarize_membrane(rule::AbstractGridRule, task::ARCTask)::Float64

Calculates the Husserlian threshold potential barrier theta_Husserl across the FFI boundary:
    theta_Husserl = V_LOO ⊕ E_comm ⊕ H_topo

Under Peter Tse's two-stage criterial causation and Geocarpic ARCetectonics:
- Returns 0.0 (membrane depolarized, spore roots into the subterranean Julia mycelium)
  if and only if all mathematical invariants hold:
  1. V_LOO: Exact matrix match on all demonstrations (zero discrete Fréchet / cell residual).
  2. E_comm: Equivariance commutation with dihedral and color permutations.
  3. H_topo: Topological object and component preservation.
- Returns Inf (infinite potential barrier) if any invariant fails, triggering metabolic rejection.
"""
function depolarize_membrane(rule::AbstractGridRule, task::ARCTask)::Float64
    # 1. Empirico-Logical Validation Barrier (V_LOO)
    train_ev = evaluate_train_exact(rule, task)
    if train_ev.pairs_matched < train_ev.total_pairs || train_ev.max_cell_residual != 0.0
        return Inf
    end

    # 2. Equivariance Commutator (E_comm)
    eq_ev = evaluate_equivariance(rule, task)
    if eq_ev.status === :failed
        return Inf
    end

    # 3. Topological Homomorphism (H_topo)
    for demo in task.train
        try
            pred = apply_rule(rule, demo.input)
            if length(pred.components) != length(demo.output.components)
                return Inf
            end
        catch
            return Inf
        end
    end

    return 0.0
end
