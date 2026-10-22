# ==============================================================================
# File: ext/NeuroARCTuringExt.jl
# Conditional Package Extension for Bayesian MCMC Calibration via Turing.jl
# ==============================================================================
module NeuroARCTuringExt

using NeuroARC
using NeuroARC.TransjectionCalculus: AbstractVerdict, Accepted, Rejected, Incomplete
using NeuroARC: ThresholdGate, BandpassGate, ConjunctionGate, gate_passed
using NeuroARC: TuringGLMMBackend, GLMMCalibrationConfig, GLMMPosteriorSummary
using NeuroARC: Revision3AuditLedger, verify_ledger_cryptographic_seal
using NeuroARC: GLMMCalibrationSpec, TopologicalPriorToken, build_ns_covariance, compute_chain_rhat_and_ess
using Random
using LinearAlgebra
using Turing

export loglink_neutron_glmm_model, neuroarc_audit_loglink_glmm

# 1. Signal to NeuroARC core that NeuroARCTuringExt is loaded and active
NeuroARC.extension_loaded(::TuringGLMMBackend) = true

# ============================================================================
# 2. Turing.jl Hierarchical Log-Link Poisson GLMM over Revision 3 Audit Ledger
# ============================================================================
@model function neuroarc_audit_loglink_glmm(
    y_tokens::Vector{Int},
    is_frust::Vector{Float64},
    is_panic::Vector{Float64},
    n_params::Vector{Float64},
    task_idx::Vector{Int},
    n_tasks::Int
)
    beta_0      ~ Normal(log(4.0), 1.0)
    beta_frust  ~ Normal(0.0, 0.75)
    beta_panic  ~ Normal(0.0, 0.75)
    beta_params ~ Normal(0.0, 0.75)

    sigma_task  ~ Exponential(1.0)
    z_task      ~ filldist(Normal(0.0, 1.0), n_tasks)

    N = length(y_tokens)
    for i in 1:N
        u_j = sigma_task * z_task[task_idx[i]]
        eta_i = beta_0 +
                beta_frust  * is_frust[i] +
                beta_panic  * is_panic[i] +
                beta_params * n_params[i] +
                u_j
        lambda_i = exp(clamp(eta_i, -10.0, 10.0))
        y_tokens[i] ~ Poisson(lambda_i)
    end
end

# ============================================================================
# 3. Turing.jl Compartmental Navier-Stokes Precision-Coupled Neutron GLMM
# ============================================================================
@model function loglink_neutron_glmm_model(
    Y::AbstractMatrix{<:Integer},
    log_flux::AbstractVector{<:Real},
    tau_res::AbstractVector{<:Real},
    L_NS::AbstractMatrix{<:Real},
    lambda_decay::Real,
    alpha_spatial::Real
)
    M, R = size(Y)
    tau_prec ~ Gamma(2.0, 1.0)
    beta_0   ~ Normal(4.0, 1.5)
    beta_1   ~ LogNormal(0.0, 0.35)

    Sigma_NS = Symmetric(build_ns_covariance(L_NS, tau_prec, alpha_spatial))
    b ~ MvNormal(zeros(Float64, M), Sigma_NS)

    for i in 1:M
        sat_i = max(1.0 - exp(-Float64(lambda_decay) * Float64(tau_res[i])), eps(Float64))
        eta_i = beta_0 + Float64(log_flux[i]) + beta_1 * log(sat_i) + b[i]
        mu_i  = exp(clamp(eta_i, -20.0, 20.0))
        for j in 1:R
            Y[i, j] ~ Poisson(mu_i)
        end
    end
end

# ============================================================================
# 4. Stage t_1 -> t_2 -> t_3 Criterial GLMM Calibration Engine
# ============================================================================
function NeuroARC.calibrate_audit_glmm!(
    ::TuringGLMMBackend,
    ledger::Revision3AuditLedger,
    cfg::GLMMCalibrationConfig = GLMMCalibrationConfig()
)::AbstractVerdict

    v_seal = verify_ledger_cryptographic_seal(ledger)
    if !(v_seal isa Accepted)
        return Rejected(
            :unsealed_audit_ledger,
            "Refusing GLMM calibration: Revision 3 cryptographic seal verification failed!",
            [:gate_r3_5_cryptographic_seal],
            0.0
        )
    end

    N = length(ledger.rows)
    if N < 4
        return Incomplete(
            :insufficient_audit_rows,
            "Bayesian GLMM calibration requires at least 4 audited task rows; got N=$N."
        )
    end

    unique_tasks = unique([r.task_id for r in ledger.rows])
    J = length(unique_tasks)
    if J < 2
        return Incomplete(
            :insufficient_task_clusters,
            "Random-intercept GLMM (1 | task_id) requires at least J >= 2 distinct tasks; got J=$J."
        )
    end
    task_to_idx = Dict(tid => idx for (idx, tid) in enumerate(unique_tasks))

    y_tokens = Int[Int(r.tokens_consumed) for r in ledger.rows]
    is_frust = Float64[r.wbr_terminal_mode == :Frustration ? 1.0 : 0.0 for r in ledger.rows]
    is_panic = Float64[r.wbr_terminal_mode == :Panic       ? 1.0 : 0.0 for r in ledger.rows]
    n_params = Float64[Float64(r.num_free_params) for r in ledger.rows]
    task_idx = Int[task_to_idx[r.task_id] for r in ledger.rows]

    model = neuroarc_audit_loglink_glmm(y_tokens, is_frust, is_panic, n_params, task_idx, J)

    sampler = NUTS(cfg.n_adapts, cfg.target_accept)
    chains_list = [
        sample(
            MersenneTwister(cfg.rng_seed + UInt64(c)),
            model,
            sampler,
            cfg.n_samples;
            progress = false
        )
        for c in 1:cfg.n_chains
    ]

    core_params = (:beta_0, :beta_frust, :beta_panic, :beta_params, :sigma_task)
    param_means = Dict{Symbol, Float64}()
    worst_rhat  = 1.0
    min_ess     = Inf

    for p in core_params
        mat = hcat([ vec(Array(ch[p])) for ch in chains_list ]...)
        if !all(isfinite, mat)
            return Rejected(
                :mcmc_nonfinite_samples,
                "Non-finite MCMC sample detected in parameter $p.",
                [:mcmc_finite_sentinel_gate],
                0.0
            )
        end
        param_means[p] = sum(mat) / Float64(length(mat))
        rhat_p, ess_p  = compute_chain_rhat_and_ess(mat)
        worst_rhat     = max(worst_rhat, rhat_p)
        min_ess        = min(min_ess, ess_p)
    end

    task_re_dict = Dict{String, Float64}()
    for (j, tid) in enumerate(unique_tasks)
        z_sym = Symbol("z_task[$j]")
        z_mat = hcat([ vec(Array(ch[z_sym])) for ch in chains_list ]...)
        z_mean = sum(z_mat) / Float64(length(z_mat))
        task_re_dict[tid] = param_means[:sigma_task] * z_mean
    end

    g_rhat = ThresholdGate(:glmm_rhat_gate, m -> cfg.max_rhat - m.rhat, 0.0)
    g_ess  = ThresholdGate(:glmm_ess_gate,  m -> m.ess, cfg.min_ess)
    conv_gate = ConjunctionGate(:glmm_mcmc_convergence_gate, (g_rhat, g_ess))

    diag_metrics = (rhat = worst_rhat, ess = min_ess)

    if !gate_passed(conv_gate, diag_metrics)
        failed = Symbol[]
        !gate_passed(g_rhat, diag_metrics) && push!(failed, :glmm_rhat_gate)
        !gate_passed(g_ess,  diag_metrics) && push!(failed, :glmm_ess_gate)

        rhat_score = clamp(cfg.max_rhat / max(worst_rhat, 1.0), 0.0, 1.0)
        ess_score  = clamp(min_ess / max(cfg.min_ess, 1.0), 0.0, 1.0)
        partial    = clamp(0.5 * (rhat_score + ess_score), 0.0, 0.99)

        return Rejected(
            :mcmc_convergence_failure,
            "GLMM NUTS chains failed convergence gates (worst R-hat=$(round(worst_rhat, digits=3)), min ESS=$(round(min_ess, digits=1))).",
            failed,
            partial
        )
    end

    summary = GLMMPosteriorSummary(
        param_means[:beta_0],
        param_means[:beta_frust],
        param_means[:beta_panic],
        param_means[:beta_params],
        param_means[:sigma_task],
        task_re_dict,
        worst_rhat,
        min_ess,
        ledger.head_seal_sha256
    )

    conf_score = clamp(1.0 / (1.0 + max(worst_rhat - 1.0, 0.0)), 0.01, 1.0)

    return Accepted(
        summary,
        (:turing_glmm_converged, :rhat_verified, :ess_verified, :seal_bound),
        conf_score,
        "Bayesian log-link Poisson GLMM converged (worst R-hat=$(round(worst_rhat, digits=3)), min ESS=$(round(min_ess, digits=1)))."
    )
end

end # module NeuroARCTuringExt
