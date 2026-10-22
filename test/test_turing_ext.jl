# ==============================================================================
# File: test/test_turing_ext.jl
# Dedicated Verification Suite for Conditional Extensions (Metal, JACC, Turing),
# C-ABI Transport, Revision 3 Cryptographic Audit, and 4-Compartment Chiral Percolation
# ==============================================================================

using Test
using Random
using NeuroARC
using NeuroARC.TransjectionCalculus: Accepted, Rejected, Incomplete
using NeuroARC.HyphalGraftingContract: GraftNode, try_graft, try_deep_graft

@testset "NeuroARC Extensions, C-ABI Transport, GLMM & Chiral Percolation Suite" begin

    # ========================================================================
    # 1. Conditional GPU Extensions: CPUBackend, MetalBackend, JACCBackend
    # ========================================================================
    @testset "1. Conditional GPU Extensions & Batch Dihedral Verification" begin
        X_batch = zeros(UInt8, 4, 4, 3)
        Y_batch = zeros(UInt8, 4, 4, 3)

        for k in 1:3
            grid_k = UInt8[
                mod(k, 9)     mod(k+1, 9)   mod(k+2, 9)   mod(k+3, 9);
                mod(k+4, 9)   0x00          0x05          mod(k+5, 9);
                0x01          0x02          0x03          0x04;
                0x06          0x07          0x08          0x09
            ]
            X_batch[:, :, k] .= grid_k
            Y_batch[:, :, k] .= UInt8(9) .- rot180(grid_k)
        end

        op_target = DihedralOp(2, false)

        v_cpu_pass = evaluate_batch_demos!(CPUBackend(), X_batch, Y_batch, op_target, true)
        @test v_cpu_pass isa Accepted
        @test v_cpu_pass.value.backend == :CPU
        @test v_cpu_pass.value.K_verified == 3
        @test v_cpu_pass.score == 1.0

        Y_corrupt = copy(Y_batch)
        Y_corrupt[1, 1, 3] = mod(Y_corrupt[1, 1, 3] + 0x01, 0x09)
        v_cpu_rej = evaluate_batch_demos!(CPUBackend(), X_batch, Y_corrupt, op_target, true)
        @test v_cpu_rej isa Rejected
        @test isapprox(v_cpu_rej.partial_score, 2.0 / 3.0; atol = 1e-6)

        if !extension_loaded(MetalBackend())
            v_no_metal = evaluate_batch_demos!(MetalBackend(), X_batch, Y_batch, op_target, true)
            @test v_no_metal isa Incomplete
            @test v_no_metal.reason == :backend_extension_not_loaded
        end

        if !extension_loaded(JACCBackend())
            v_no_jacc = evaluate_batch_demos!(JACCBackend(), X_batch, Y_batch, op_target, true)
            @test v_no_jacc isa Incomplete
            @test v_no_jacc.reason == :backend_extension_not_loaded
        end
    end

    # ========================================================================
    # 2. C-ABI Zero-Copy Ownership Lock & Revision 3 Cryptographic Audit Seal
    # ========================================================================
    @testset "2. C-ABI Zero-Copy Slot Lock & Revision 3 Audit Chain" begin
        @test sizeof(CandidateBufferDescriptor) == 48
        slot_lock = TransportSlotLock()
        @test verify_zero_copy_eligibility(slot_lock) == true
        @test slot_lock.zero_copy_certified[] == true

        # Verify pure-Base SHA-256 against NIST FIPS 180-4 test vectors
        @test sha256_hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        @test sha256_hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

        commit_sha = "7f8e9d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e"
        ledger = Revision3AuditLedger(commit_sha)

        synthetic_audit_data = [
            ("00d62c1b", :Focus,       0,  4, :ACCEPTED,   1.00),
            ("00d62c1b", :Frustration, 2,  9, :REJECTED,   0.75),
            ("00d62c1b", :Panic,       2, 16, :REJECTED,   0.00),
            ("0520fde7", :Focus,       1,  5, :ACCEPTED,   1.00),
            ("0520fde7", :Frustration, 2, 11, :REJECTED,   0.50),
            ("0520fde7", :Panic,       2, 19, :INCOMPLETE, 0.00),
            ("1c786137", :Focus,       0,  3, :ACCEPTED,   1.00),
            ("1c786137", :Frustration, 2,  8, :REJECTED,   0.67),
            ("1c786137", :Panic,       3, 18, :REJECTED,   0.00),
            ("25d8a9c8", :Focus,       1,  5, :ACCEPTED,   1.00),
            ("25d8a9c8", :Frustration, 2, 10, :REJECTED,   0.75),
            ("25d8a9c8", :Panic,       3, 21, :INCOMPLETE, 0.00),
        ]

        for (tid, mode, n_p, tok, st, sc) in synthetic_audit_data
            append_sealed_row!(
                ledger;
                task_id  = tid,
                dsl_ids  = UInt16[12, 144],
                ast_expr = "GraftNode(:rule_$(tid)_$(mode))",
                status   = st,
                reason   = st == :ACCEPTED ? :verified_pass : :gate_miss,
                score    = sc,
                residual = 0.0,
                n_params = n_p,
                loo_pass = st == :ACCEPTED ? 3 : 2,
                loo_tot  = 3,
                equiv    = :VERIFIED_D8_COLOR,
                mode     = mode,
                tokens   = tok
            )
        end

        v_seal = verify_ledger_cryptographic_seal(ledger)
        @test v_seal isa Accepted
        @test v_seal.value.rows_verified == 12

        if !extension_loaded(TuringGLMMBackend())
            v_unloaded = calibrate_audit_glmm!(TuringGLMMBackend(), ledger)
            @test v_unloaded isa Incomplete
            @test v_unloaded.reason == :turing_extension_not_loaded
        end

        # Verify multi-chain R-hat and ESS diagnostic calculation
        rng = MersenneTwister(1234)
        converged_chains = 1.5 .+ 0.1 .* randn(rng, 200, 2)
        rhat_ok, ess_ok = compute_chain_rhat_and_ess(converged_chains)
        @test 1.0 <= rhat_ok <= 1.05
        @test ess_ok >= 100.0

        # Tamper detection check
        saved_seal = ledger.head_seal_sha256
        ledger.head_seal_sha256 = repeat("f", 64)
        v_tampered = verify_ledger_cryptographic_seal(ledger)
        @test v_tampered isa Rejected
        @test v_tampered.reason == :sha256_head_mismatch
        ledger.head_seal_sha256 = saved_seal
    end

    # ========================================================================
    # 3. Navier-Stokes Precision Matrix & Compartmental GLMM Calibration
    # ========================================================================
    @testset "3. Hydrodynamic Precision Matrix Q_NS & GLMM Criterial Gating" begin
        M = 4
        L_NS = Float32[
            -0.30   0.10   0.05   0.00;
             0.20  -0.35   0.10   0.05;
             0.10   0.15  -0.25   0.10;
             0.00   0.10   0.10  -0.15
        ]
        log_flux = Float32[2.5, 2.2, 1.9, 1.5]
        tau_res  = Float32[9.8, 5.4, 3.1, 1.4]

        Y_obs = Int[
            830 845 820 855 840;
            510 525 505 530 515;
            305 318 299 315 310;
            142 155 148 150 145
        ]

        Sigma_coupled   = build_ns_covariance(L_NS, 2.0, 0.8)
        Sigma_uncoupled = build_ns_covariance(L_NS, 2.0, 0.0)
        @test Sigma_coupled == transpose(Sigma_coupled)
        @test abs(Sigma_coupled[1, 2]) > 1e-3
        @test isapprox(Sigma_uncoupled[1, 2], 0.0; atol = 1e-7)

        spec = GLMMCalibrationSpec{Float32}(0.15f0, 2.0f0, 1.0f0, 0.5f0, 0.99, 1.05, 100.0, 40, 1)
        spec_tiny = GLMMCalibrationSpec{Float32}(0.15f0, 2.0f0, 1.0f0, 0.5f0, 0.99, 1.05, 100.0, 4, 1)

        v_inc = calibrate_glmm_posterior(Y_obs, log_flux, tau_res, L_NS, 1.0f0, spec_tiny)
        @test v_inc isa Incomplete
        @test v_inc.reason == :insufficient_mcmc_budget

        v_rej = calibrate_glmm_posterior(
            Y_obs, log_flux, tau_res, L_NS, 1.0f0, spec;
            diagnostics_override = (max_rhat = 1.22, min_ess = 85.0)
        )
        @test v_rej isa Rejected
        @test v_rej.reason == :mcmc_convergence_failure
        @test :rhat_bandpass_gate in v_rej.failed_gates
        @test :ess_threshold_gate in v_rej.failed_gates

        v_acc = calibrate_glmm_posterior(
            Y_obs, log_flux, tau_res, L_NS, 1.0f0, spec;
            diagnostics_override = (max_rhat = 1.01, min_ess = 250.0)
        )
        @test v_acc isa Accepted
        @test v_acc.value.prior_token isa TopologicalPriorToken{4}
        @test v_acc.value.prior_token.helicity_sign == Int8(+1)
        @test v_acc.value.prior_token.hopf_linking_number == Int32(2)
        @test v_acc.value.prior_token.compartment_rank_order == (1, 2, 3, 4)
    end

    # ========================================================================
    # 4. 4-Compartment Kondepudi-Frank SDEs & Two-Tier KOfNGate Percolation
    # ========================================================================
    @testset "4. Relativistic Z^5 Scaling & Two-Tier KOfNGate Chiral Percolation" begin
        tau_compartments = [9.8, 5.4, 3.1, 1.4]
        L_NS = [
            -0.08   0.04   0.02   0.00;
             0.05  -0.10   0.03   0.01;
             0.03   0.04  -0.09   0.02;
             0.00   0.02   0.04  -0.08
        ]
        hydro = CompartmentHydroState(tau_compartments, L_NS)

        make_spec(Z_eff::Int; twistor_s::Float64 = +1.0, n_steps::Int = 400) = ChiralReactorSpec(
            Z_eff, 25, twistor_s, 1.0, 0.85, 0.05, 0.46, 1.0e22, 2.0, 25.0, 3.0, 0.02, n_steps
        )

        snr_C  = compute_compartment_snr(make_spec(6),  hydro.tau_res[1])
        snr_P  = compute_compartment_snr(make_spec(15), hydro.tau_res[1])
        snr_S  = compute_compartment_snr(make_spec(16), hydro.tau_res[1])
        snr_Fe = compute_compartment_snr(make_spec(26), hydro.tau_res[1])

        @test snr_C  < 0.01
        @test 0.40 < snr_P < 0.70
        @test 0.55 < snr_S < 0.90
        @test snr_Fe > 8.0
        @test homochiral_probability(snr_Fe) > 0.999999

        # Pure Carbon (Z=6) fails Chiral SNR ThresholdGate
        v_carbon = run_gated_kondepudi_frank!(hydro, make_spec(6); target_compartment = 1)
        @test v_carbon isa Rejected
        @test v_carbon.failed_gates == [:chiral_snr_threshold]

        # Effluent Boundary Omega_4 (tau_4 = 1.4s < 2.0s) fails BandpassGate
        v_washout = run_gated_kondepudi_frank!(hydro, make_spec(26); target_compartment = 4)
        @test v_washout isa Rejected
        @test :residence_time_bandpass in v_washout.failed_gates

        # Two-Tier KOfNGate Advective Percolation:
        make_perc_spec(Z_eff::Int, kappa::Float64; twistor_s::Float64 = +1.0) = PercolationReactorSpec(
            Z_eff, 25, twistor_s, 1.0, 0.85, 0.05, 0.46, 1.0e22,
            kappa, 2.0, 25.0, 3.0, 0.35, 2, 4, 0.02, 500
        )

        # Phase A Failure: Pure Carbon (Z=6) fails 2-of-4 Core Ignition KOfNGate
        v_perc_carbon = verify_advective_percolation!(hydro, make_perc_spec(6, 5.0))
        @test v_perc_carbon isa Rejected
        @test v_perc_carbon.reason == :core_ignition_failure

        # Phase B Failure: Fe-S (Z=26) with uncoupled flow (kappa_adv = 0.0) passes 2-of-4 Core Ignition
        # but fails 4-of-4 Network Percolation in washout compartment Omega_4
        v_perc_uncoupled = verify_advective_percolation!(hydro, make_perc_spec(26, 0.0); rng = MersenneTwister(42))
        @test v_perc_uncoupled isa Rejected
        @test v_perc_uncoupled.reason == :percolation_incomplete
        @test :ee_lock_gate_4 in v_perc_uncoupled.failed_gates

        # Supercritical Percolation (kappa_adv = 6.5 >= kappa_crit): All 4 compartments lock!
        v_perc_matter = verify_advective_percolation!(hydro, make_perc_spec(26, 6.5; twistor_s = +1.0); rng = MersenneTwister(42))
        @test v_perc_matter isa Accepted
        @test v_perc_matter.value.prior_token.compartment_rank_order == (1, 1, 1, 1)

        v_perc_anti = verify_advective_percolation!(hydro, make_perc_spec(26, 6.5; twistor_s = -1.0); rng = MersenneTwister(42))
        @test v_perc_anti isa Accepted
        @test v_perc_anti.value.prior_token.compartment_rank_order == (-1, -1, -1, -1)
    end

    # ========================================================================
    # 5. Adaptive Scheduler & Test-Time Criterial RL Inference Loop
    # ========================================================================
    @testset "5. Adaptive CPU-Metal Scheduler & Test-Time Criterial RL Loop" begin
        tau_vec = [9.8, 5.4, 3.1, 1.4]
        op_target = DihedralOp(2, false)

        m_in = UInt8[1 2 3; 4 5 6; 7 8 9]
        m_out = apply_dihedral(op_target, m_in)

        # Small batch (K = 8 < 32): AdaptiveScheduler routes to CPUBackend
        small_pairs = Tuple{Vector{Float64}, ARCGrid{UInt8}, ARCGrid{UInt8}}[
            (tau_vec, ARCGrid(m_in), ARCGrid(m_out)) for _ in 1:8
        ]
        agent_small = AdaptiveCRLAgent(12; force_cpu_only = false, simulate_metal_unified = true)
        v_small = run_adaptive_test_time_rl!(agent_small, small_pairs)
        @test v_small isa Accepted
        @test v_small.value.Z_eff == 26
        @test v_small.value.kappa_adv == 4.5
        @test v_small.value.k_rot == 2
        @test agent_small.scheduler.cpu_stats.dispatches == 6
        @test agent_small.scheduler.metal_stats.dispatches == 0

        # Large batch (K = 64 >= 32): AdaptiveScheduler routes to MetalBackend
        large_pairs = Tuple{Vector{Float64}, ARCGrid{UInt8}, ARCGrid{UInt8}}[
            (tau_vec, ARCGrid(m_in), ARCGrid(m_out)) for _ in 1:64
        ]
        agent_large = AdaptiveCRLAgent(12; force_cpu_only = false, simulate_metal_unified = true)
        v_large = run_adaptive_test_time_rl!(agent_large, large_pairs)
        @test v_large isa Accepted
        @test v_large.value.Z_eff == 26
        @test v_large.value.kappa_adv == 4.5
        @test v_large.value.k_rot == 2
        @test agent_large.scheduler.metal_stats.dispatches == 6

        # Queue saturation overflow: when Metal active_tasks is high, routes back to CPUBackend
        agent_large.scheduler.metal_stats.active_tasks = 8
        @test select_optimal_backend(agent_large.scheduler, 64) isa CPUBackend
    end

    # ========================================================================
    # 6. Rhizomatic ZPD Middle-Hyphal Graft & Persistent C-ABI Borrow Window
    # ========================================================================
    @testset "6. Rhizomatic ZPD Middle-Hyphal Graft & Persistent C-ABI Borrow" begin
        countA = Ref(0)
        countB = Ref(0)
        countC = Ref(0)
        countX = Ref(0)
        fixtures = build_canonical_fixtures(countA = countA, countB = countB, countC = countC, countX = countX)

        # Direct 2-stage graft NodeA (ColorMappedGrid -> PolyominoGraph) -> NodeC (ColorMappedGrid -> ColorMappedGrid)
        # fails preflight subtyping because Out(NodeA) == PolyominoGraph is not <: In(NodeC) == ColorMappedGrid
        v_direct = try_graft(fixtures.nodeA, fixtures.nodeC)
        @test v_direct isa HyphalGraftingContract.Rejected
        @test countA[] == 0 && countB[] == 0 && countC[] == 0

        # Synthesize middle ZPD bridging hypha (NodeB: PolyominoGraph -> ColorMappedGrid)
        scaffold = ScaffoldController()
        zpd_pool = GraftNode[fixtures.nodeX, fixtures.nodeB]
        v_zpd = synthesize_zpd_mid_graft!(fixtures.nodeA, fixtures.nodeC, zpd_pool, scaffold)
        @test v_zpd isa HyphalGraftingContract.Accepted
        @test v_zpd.node.label_compose == "NodeC ∘ NodeB ∘ NodeA"
        @test countA[] == 0 && countB[] == 0 && countC[] == 0 # Zero node executions during ZPD synthesis

        # Execute the synthesized 3-stage ZPD graft over a pinned C-ABI zero-copy buffer
        buf = UInt8[0 2 0; 2 2 2; 0 2 0]
        GC.@preserve buf begin
            ptr = pointer(buf)
            digest = compute_fnv1a_64(ptr, length(buf))
            desc = CandidateBufferDescriptor(
                NARC_MAGIC_HEADER, UInt16(3), UInt16(144),
                Int32(3), Int32(3), Int32(1), Int32(3),
                COL_MAJOR_CONTIGUOUS, 0x01, UInt16(0),
                Int32(12), UInt64(ptr), digest
            )
            slot_lock = TransportSlotLock()
            sched = ComputeBudgetScheduler(500, 8, "7f8e9d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e")

            v_exec = execute_c_abi_zpd_graft!(
                slot_lock, desc,
                GraftNode[fixtures.nodeA, fixtures.nodeB, fixtures.nodeC],
                sched
            )
            @test v_exec isa Accepted
            @test v_exec.value.composed_label == "NodeC ∘ NodeB ∘ NodeA"
            @test slot_lock.state[] == UInt8(PYTHON_OWNED) # Lock cleanly returned to PYTHON_OWNED
            @test countA[] == 1 && countB[] == 1 && countC[] == 1
        end
    end

    # ========================================================================
    # 7. Clean-Room 8-Fold D8 Conjugate Consensus Weave & Split-Color Overlay Weave
    # ========================================================================
    @testset "7. Clean-Room 8-Fold D8 Conjugate Consensus Weave & Split-Color Overlay" begin
        g_rect = [1 2 3; 4 5 6]
        for k in 0:3, fl in (false, true)
            op = DihedralOp(k, fl)
            @test invert_dihedral(apply_dihedral(g_rect, op), op) == g_rect
        end

        # Split-color overlay weave: shift each non-zero color layer down by 1 row if possible
        shift_down_fn = function (layer::Matrix{Int})
            H, W = size(layer)
            out = zeros(Int, H, W)
            for j in 1:W, i in 1:(H - 1)
                if layer[i, j] != 0
                    out[i + 1, j] = layer[i, j]
                end
            end
            return out
        end

        g_multi = [1 0 2; 0 3 0; 0 0 0]
        weaved = execute_split_overlay_weave(shift_down_fn, g_multi; bg_color = 0)
        @test weaved == [0 0 0; 1 0 2; 0 3 0]

        # 8-Fold D8 Conjugate Consensus Weave:
        # Suppose we only have a canonical "shift_down_fn", but the task actually shifts RIGHT!
        # Folding by DihedralOp(k_rot, flip) synthesizes shift_right via g^-1 o shift_down_fn o g!
        train_shift_right = Tuple{Matrix{Int}, Matrix{Int}}[
            ([1 0 0; 0 2 0; 0 0 0], [0 1 0; 0 0 2; 0 0 0]),
            ([0 4 0; 5 0 0; 0 0 0], [0 0 4; 0 5 0; 0 0 0]),
            ([7 0 0; 0 0 0; 8 0 0], [0 7 0; 0 0 0; 0 8 0]),
        ]
        test_shift_right = [3 0 0; 0 6 0; 9 0 0]
        v_weave = execute_d8_fold_consensus_weave([("shift_down", shift_down_fn)], train_shift_right, test_shift_right)
        @test v_weave isa Accepted
        @test v_weave.value.attempt_1 == [0 3 0; 0 0 6; 0 9 0]
        @test v_weave.value.votes >= 2
    end
end
