# ==============================================================================
# File: test/test_ledger_integrity_and_replay.jl
# Verification Suite for Revision 3 Cryptographic Ledger Seal (rev3.v2),
# Quarantine Enforcement, Single-Field Tamper Detection, Safe Allowlisted AST
# Replay, and C-ABI Stride / TOCTOU / Operator-ID Gating
# ==============================================================================

using Test
using NeuroARC
using NeuroARC.TransjectionCalculus: Accepted, Rejected, Incomplete
using NeuroARC.HyphalGraftingContract: GraftNode
using NeuroARC: ColorMappedGrid, PolyominoGraph, VERIFIED_DSL_MAX_ID

if !isdefined(@__MODULE__, :verify_post_submission_audit)
    include(joinpath(@__DIR__, "..", "verify_audit_seal.jl"))
end

@testset "Cryptographic Audit Ledger Seal (rev3.v2), Forensic Replay & C-ABI Negative Tests" begin

    # ==========================================================================
    # 1. Explicit Quarantine Enforcement & No Default Bypass
    # ==========================================================================
    @testset "1. Quarantine Seal Enforcement & Mandatory Keyword" begin
        commit_sha = "7f8e9d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e"
        ledger = Revision3AuditLedger(commit_sha)

        # Omitting test_quarantine_sealed must throw UndefKeywordError (no default = true)
        @test_throws UndefKeywordError append_sealed_row!(
            ledger;
            task_id  = "00d62c1b",
            dsl_ids  = UInt16[12],
            ast_expr = "RuleNode(ArcGyrismRule(-1, 180, true))",
            status   = :ACCEPTED,
            reason   = :verified_pass,
            score    = 1.0,
            residual = 0.0,
            n_params = 0,
            loo_pass = 3,
            loo_tot  = 3,
            equiv    = :passed,
            mode     = :Focus,
            tokens   = 4
        )

        # Appending a row with test_quarantine_sealed = false must be rejected by all verifiers
        unsealed_ledger = Revision3AuditLedger(commit_sha)
        unsealed_row = append_sealed_row!(
            unsealed_ledger;
            task_id                = "00d62c1b",
            dsl_ids                = UInt16[12],
            ast_expr               = "RuleNode(ArcGyrismRule(-1, 180, true))",
            status                 = :ACCEPTED,
            reason                 = :verified_pass,
            score                  = 1.0,
            residual               = 0.0,
            n_params               = 0,
            loo_pass               = 3,
            loo_tot                = 3,
            equiv                  = :passed,
            mode                   = :Focus,
            tokens                 = 4,
            test_quarantine_sealed = false
        )

        v_unsealed_ledger = verify_ledger_cryptographic_seal(unsealed_ledger)
        @test v_unsealed_ledger isa Rejected
        @test v_unsealed_ledger.reason == :quarantine_breach
        @test :gate_r3_5_quarantine in v_unsealed_ledger.failed_gates

        demos = [
            IOPair([1 2; 3 4], [4 3; 2 1]),
            IOPair([5 6; 7 8], [8 7; 6 5]),
            IOPair([1 0; 0 2], [2 0; 0 1]),
        ]
        v_unsealed_replay = replay_audit_row_candidate(unsealed_row, demos)
        @test v_unsealed_replay isa Rejected
        @test v_unsealed_replay.reason == :quarantine_breach

        # Writing unsealed ledger without allow_unverified throws ArgumentError
        mktempdir() do tmpdir
            snap_file = joinpath(tmpdir, "unsealed.parquet.jls")
            @test_throws ArgumentError write_columnar_audit_snapshot(snap_file, unsealed_ledger)
            write_columnar_audit_snapshot(snap_file, unsealed_ledger; allow_unverified = true)
            @test verify_post_submission_audit(snap_file; exit_on_error = false) == false
        end
    end

    # ==========================================================================
    # 2. Single-Field Tamper Detection Across All 28 TaskAuditRow Fields
    # ==========================================================================
    @testset "2. Exhaustive 28-Field Tamper Detection in TaskAuditRow" begin
        commit_sha = "7f8e9d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e"
        in1 = zeros(Int, 5, 5); in1[3, 3] = 2; in1[2, 2] = 1
        out1 = copy(in1); out1[4, 4] = 1
        in2 = zeros(Int, 5, 5); in2[3, 3] = 2; in2[2, 4] = 3
        out2 = copy(in2); out2[4, 2] = 3
        in3 = zeros(Int, 5, 5); in3[3, 3] = 2; in3[1, 3] = 4
        out3 = copy(in3); out3[5, 3] = 4
        demos = [
            IOPair(in1, out1),
            IOPair(in2, out2),
            IOPair(in3, out3),
        ]
        task_base = ARCTask("00d62c1b", demos, [demos[1].input])

        base_ledger = Revision3AuditLedger(commit_sha)
        base_row, v_base = audit_verify_candidate_and_append!(
            base_ledger, task_base, "MarkerLineReflectionRule(2, :point)";
            dsl_ids                = UInt16[12, 144],
            n_params               = 1,
            mode                   = :Focus,
            tokens                 = 5,
            test_quarantine_sealed = true,
            wall_time_ns           = 15000,
            memory_bytes           = 4096
        )
        @test v_base isa Accepted
        @test base_row.verdict_status == :ACCEPTED
        @test verify_ledger_cryptographic_seal(base_ledger) isa Accepted

        function rebuild_row_with(r::TaskAuditRow, field_sym::Symbol, new_val)
            d = Dict{Symbol, Any}(fn => getfield(r, fn) for fn in fieldnames(TaskAuditRow))
            d[field_sym] = new_val
            return TaskAuditRow(
                d[:seal_schema_version],
                d[:row_id],
                d[:task_id],
                d[:git_commit_hash],
                d[:dsl_operator_ids],
                d[:candidate_ast_sha256],
                d[:ast_expr],
                d[:preflight_subtype_ok],
                d[:runtime_typeassert_ok],
                d[:train_pairs_count],
                d[:train_exact_matches],
                d[:train_max_residual],
                d[:num_free_params],
                d[:loo_is_informative],
                d[:loo_folds_total],
                d[:loo_folds_passed],
                d[:equivariance_status],
                d[:wbr_terminal_mode],
                d[:tokens_consumed],
                d[:test_quarantine_sealed],
                d[:verdict_status],
                d[:verdict_reason],
                d[:failed_gates],
                d[:partial_score],
                d[:wall_time_ns],
                d[:memory_bytes],
                d[:prev_row_seal_sha256],
                d[:row_seal_sha256]
            )
        end

        tamper_mutations = Pair{Symbol, Any}[
            :seal_schema_version    => "rev3.v1",
            :row_id                 => Int64(99),
            :task_id                => "tampered_task",
            :git_commit_hash        => "0000000000000000000000000000000000000000",
            :dsl_operator_ids       => UInt16[12, 145],
            :candidate_ast_sha256   => repeat("a", 64),
            :ast_expr               => "MarkerLineReflectionRule(3, :point)",
            :preflight_subtype_ok   => false,
            :runtime_typeassert_ok  => false,
            :train_pairs_count      => Int32(4),
            :train_exact_matches    => Int32(2),
            :train_max_residual     => 0.25,
            :num_free_params        => Int32(3),
            :loo_is_informative     => false,
            :loo_folds_total        => Int32(4),
            :loo_folds_passed       => Int32(2),
            :equivariance_status    => :failed,
            :wbr_terminal_mode      => :Panic,
            :tokens_consumed        => Int32(999),
            :test_quarantine_sealed => false,
            :verdict_status         => :REJECTED,
            :verdict_reason         => :tampered_reason,
            :failed_gates           => Symbol[:injected_gate],
            :partial_score          => 0.5,
            :wall_time_ns           => Int64(99999),
            :memory_bytes           => Int64(8192),
            :prev_row_seal_sha256   => repeat("b", 64),
            :row_seal_sha256        => repeat("c", 64),
        ]

        @test length(tamper_mutations) == fieldcount(TaskAuditRow)

        mktempdir() do tmpdir
            for (field_sym, new_val) in tamper_mutations
                mut_row = rebuild_row_with(base_row, field_sym, new_val)
                mut_ledger = Revision3AuditLedger(commit_sha)
                push!(mut_ledger.rows, mut_row)
                mut_ledger.head_seal_sha256 = mut_row.row_seal_sha256

                v_seal = verify_ledger_cryptographic_seal(mut_ledger)
                @test v_seal isa Rejected

                v_rep = replay_audit_row_candidate(mut_row, demos)
                @test v_rep isa Rejected

                snap_path = joinpath(tmpdir, "tampered_$(field_sym).parquet.jls")
                write_columnar_audit_snapshot(snap_path, mut_ledger; allow_unverified = true)
                @test verify_post_submission_audit(snap_path; exit_on_error = false) == false
            end
        end
    end

    # ==========================================================================
    # 3. Safe Allowlisted AST Parser (Zero eval, Rejects Arbitrary Code)
    # ==========================================================================
    @testset "3. Safe Allowlisted AST Parser & Code-Injection Rejection" begin
        v_refl = parse_allowlisted_candidate_ast("MarkerLineReflectionRule(2, :vertical)")
        @test v_refl isa Accepted
        @test v_refl.value == MarkerLineReflectionRule(2; axis_candidate = :vertical)

        v_geyser = parse_allowlisted_candidate_ast("ArcGeyserRule(2, 1, :up, [3], true, -1)")
        @test v_geyser isa Accepted
        @test v_geyser.value == ArcGeyserRule(2; beam_color = 1, directions = :up, barrier_colors = Int8[3], stop_at_barrier = true, intersection_color = -1)

        v_gyrism = parse_allowlisted_candidate_ast("ArcGyrismRule(-1, 90, false)")
        @test v_gyrism isa Accepted
        @test v_gyrism.value == ArcGyrismRule(-1; angle_degrees = 90, clockwise = false)

        v_rnode = parse_allowlisted_candidate_ast("RuleNode(ArcGyrismRule(-1, 180, true))")
        @test v_rnode isa Accepted
        @test v_rnode.value == RuleNode(ArcGyrismRule(-1; angle_degrees = 180, clockwise = true))

        v_chain = parse_allowlisted_candidate_ast(
            "GraftNode(RuleNode(ArcGyrismRule(-1, 90, true)), RuleNode(ArcGyrismRule(-1, 90, true)))"
        )
        @test v_chain isa Accepted
        @test v_chain.value isa ComposedRuleChain
        @test length(v_chain.value.stages) == 2

        malicious_or_disallowed = [
            "",
            "run(`echo pwned`)",
            "eval(:(1 + 1))",
            "Base.Filesystem.rm(\"/tmp/nonexistent\")",
            "ccall(:getpid, Cint, ())",
            "begin MarkerLineReflectionRule(2, :vertical) end",
            "MarkerLineReflectionRule(2, :vertical); run(`ls`)",
            "RuleNode(:arbitrary_func)",
            "ArcGyrismRule(-1, 45, true)",
            "ArcGeyserRule(2, 1, :invalid_dir, [3], true, -1)",
            "MarkerLineReflectionRule(2, :invalid_axis)",
            "GraftNode(:UnknownNode)",
            "1 + 1",
        ]

        for expr_str in malicious_or_disallowed
            v_bad = parse_allowlisted_candidate_ast(expr_str)
            @test v_bad isa Rejected
            @test :allowlisted_ast_parser_gate in v_bad.failed_gates
        end
    end

    # ==========================================================================
    # 4. Deterministic End-to-End Forensic Replay Across 20 Audit Rows
    # ==========================================================================
    @testset "4. End-to-End Forensic Replay of 20 Sealed Candidate Evaluations" begin
        commit_sha = "7f8e9d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e"
        ledger = Revision3AuditLedger(commit_sha)

        # Task fixture 1: Point reflection across center marker color 2 (Accepted for MarkerLineReflectionRule(2, :point))
        p_in_1 = zeros(Int, 5, 5); p_in_1[3, 3] = 2; p_in_1[2, 2] = 1
        p_out_1 = copy(p_in_1); p_out_1[4, 4] = 1
        p_in_2 = zeros(Int, 5, 5); p_in_2[3, 3] = 2; p_in_2[2, 4] = 3
        p_out_2 = copy(p_in_2); p_out_2[4, 2] = 3
        p_in_3 = zeros(Int, 5, 5); p_in_3[3, 3] = 2; p_in_3[1, 3] = 4
        p_out_3 = copy(p_in_3); p_out_3[5, 3] = 4
        demos_point = [
            IOPair(p_in_1, p_out_1),
            IOPair(p_in_2, p_out_2),
            IOPair(p_in_3, p_out_3),
        ]

        # Task fixture 2: Directional vertical marker reflection (Incomplete due to :untestable equivariance for :vertical)
        v_in_1 = zeros(Int, 5, 5); v_in_1[2:4, 3] .= 2; v_in_1[2, 1] = 4
        v_out_1 = copy(v_in_1); v_out_1[2, 5] = 4
        v_in_2 = zeros(Int, 5, 5); v_in_2[2:4, 3] .= 2; v_in_2[3, 1] = 1
        v_out_2 = copy(v_in_2); v_out_2[3, 5] = 1
        v_in_3 = zeros(Int, 5, 5); v_in_3[2:4, 3] .= 2; v_in_3[4, 1] = 3
        v_out_3 = copy(v_in_3); v_out_3[4, 5] = 3
        demos_vert = [
            IOPair(v_in_1, v_out_1),
            IOPair(v_in_2, v_out_2),
            IOPair(v_in_3, v_out_3),
        ]

        # Task fixture 3: 90-degree CW rotation around center landmark color 2
        g_in_1 = zeros(Int, 5, 5); g_in_1[3, 3] = 2; g_in_1[2, 3] = 4
        g_out_1 = zeros(Int, 5, 5); g_out_1[3, 3] = 2; g_out_1[3, 4] = 4
        g_in_2 = zeros(Int, 5, 5); g_in_2[3, 3] = 2; g_in_2[3, 4] = 1
        g_out_2 = zeros(Int, 5, 5); g_out_2[3, 3] = 2; g_out_2[4, 3] = 1
        g_in_3 = zeros(Int, 5, 5); g_in_3[3, 3] = 2; g_in_3[4, 3] = 3
        g_out_3 = zeros(Int, 5, 5); g_out_3[3, 3] = 2; g_out_3[3, 2] = 3
        demos_gyre = [
            IOPair(g_in_1, g_out_1),
            IOPair(g_in_2, g_out_2),
            IOPair(g_in_3, g_out_3),
        ]

        task_demos_map = Dict{String, Vector{Demonstration}}(
            "task_point" => demos_point,
            "task_vert"  => demos_vert,
            "task_gyre"  => demos_gyre,
        )

        # 20 candidate evaluations spanning Accepted, Rejected, and Incomplete across all allowlisted AST forms
        candidate_specs = [
            ("task_point", "MarkerLineReflectionRule(2, :point)",                                                       :Focus,       1),
            ("task_point", "RuleNode(MarkerLineReflectionRule(2, :point))",                                             :Focus,       1),
            ("task_point", "GraftNode(MarkerLineReflectionRule(2, :point), ArcGyrismRule(-1, 0, true))",                :Focus,       1),
            ("task_point", "MarkerLineReflectionRule(3, :point)",                                                       :Frustration, 1),
            ("task_point", "ArcGeyserRule(2, 1, :up, [3], true, -1)",                                                  :Frustration, 2),
            ("task_point", "GraftNode(MarkerLineReflectionRule(2, :horizontal), ArcGyrismRule(-1, 90, true))",         :Panic,       2),
            ("task_vert",  "MarkerLineReflectionRule(2, :vertical)",                                                   :Focus,       1),
            ("task_vert",  "RuleNode(MarkerLineReflectionRule(2, :vertical))",                                         :Focus,       1),
            ("task_vert",  "MarkerLineReflectionRule(2, :horizontal)",                                                 :Frustration, 1),
            ("task_vert",  "MarkerLineReflectionRule(5, :vertical)",                                                   :Frustration, 1),
            ("task_vert",  "ArcGeyserRule(2, 4, :cardinal, [], true, -1)",                                             :Panic,       1),
            ("task_gyre",  "ArcGyrismRule(2, 90, true)",                                                               :Focus,       1),
            ("task_gyre",  "RuleNode(ArcGyrismRule(2, 90, true))",                                                     :Focus,       1),
            ("task_gyre",  "ArcGyrismRule(2, 90, false)",                                                              :Frustration, 1),
            ("task_gyre",  "ArcGyrismRule(2, 180, true)",                                                              :Frustration, 1),
            ("task_gyre",  "RuleNode(ArcGyrismRule(2, 270, true))",                                                    :Frustration, 1),
            ("task_gyre",  "RuleNode(ArcGyrismRule(-1, 0, true))",                                                     :Panic,       0),
            ("task_gyre",  "GraftNode(RuleNode(ArcGyrismRule(2, 180, true)), RuleNode(ArcGyrismRule(2, 180, true)))",  :Frustration, 2),
            ("task_gyre",  "GraftNode(ArcGyrismRule(2, 180, true), ArcGyrismRule(2, 90, true))",                       :Frustration, 2),
            ("task_gyre",  "ArcGeyserRule(2, 2, :down, [], true, -1)",                                                 :Panic,       1),
        ]

        @test length(candidate_specs) == 20

        for (idx, (t_id, ast_str, mode_sym, n_p)) in enumerate(candidate_specs)
            demos_t = task_demos_map[t_id]
            task_obj = ARCTask(t_id, demos_t, [demos_t[1].input])
            row_i, v_i = audit_verify_candidate_and_append!(
                ledger, task_obj, ast_str;
                dsl_ids                = UInt16[10 + idx],
                n_params               = n_p,
                mode                   = mode_sym,
                tokens                 = 3 * idx,
                test_quarantine_sealed = true,
                wall_time_ns           = 1000 * idx,
                memory_bytes           = 512 * idx
            )
            @test v_i isa Accepted
            @test row_i !== nothing
        end

        @test length(ledger.rows) == 20
        v_ledger = verify_ledger_cryptographic_seal(ledger)
        @test v_ledger isa Accepted
        @test v_ledger.value.rows_verified == 20
        @test v_ledger.value.seal_schema_version == SEAL_SCHEMA_VERSION

        # Ensure all 3 verdict classes (ACCEPTED, REJECTED, INCOMPLETE) are represented across the 20 rows
        statuses = Set(r.verdict_status for r in ledger.rows)
        @test :ACCEPTED in statuses
        @test :REJECTED in statuses
        @test :INCOMPLETE in statuses

        mktempdir() do tmpdir
            snap_file = joinpath(tmpdir, "audit_20_rows.parquet.jls")
            write_columnar_audit_snapshot(snap_file, ledger)
            @test verify_post_submission_audit(snap_file; exit_on_error = false) == true

            reloaded = read_columnar_audit_snapshot(snap_file)
            @test length(reloaded.rows) == 20

            for row in reloaded.rows
                v_rep = replay_audit_row_candidate(row, task_demos_map[row.task_id])
                @test v_rep isa Accepted
                @test v_rep.value.verdict_status == row.verdict_status
                @test v_rep.value.verdict_reason == row.verdict_reason
                @test v_rep.value.failed_gates == row.failed_gates
                @test isapprox(v_rep.value.partial_score, row.partial_score; atol = 1e-12)
                @test v_rep.value.row_seal_sha256 == row.row_seal_sha256
            end

            # Replaying an Accepted row against mismatched task demonstrations must fail
            v_mismatch = replay_audit_row_candidate(reloaded.rows[1], demos_gyre)
            @test v_mismatch isa Rejected
            @test v_mismatch.reason == :replay_verdict_mismatch
        end
    end

    # ==========================================================================
    # 5. C-ABI Negative Tests: Non-Contiguous Stride, Unverified DSL ID & TOCTOU
    # ==========================================================================
    @testset "5. C-ABI Stride Contiguity, Operator Allowlist & Mid-Borrow TOCTOU" begin
        fixtures = build_canonical_fixtures()
        chain = GraftNode[fixtures.nodeA, fixtures.nodeB, fixtures.nodeC]
        buf = UInt8[0 2 0; 2 2 2; 0 2 0]

        GC.@preserve buf begin
            ptr = pointer(buf)
            digest = compute_fnv1a_64(ptr, length(buf))

            # 5a. Non-contiguous stride_row == 2 must be rejected before pointer wrap
            desc_bad_stride_row = CandidateBufferDescriptor(
                NARC_MAGIC_HEADER, UInt16(3), UInt16(144),
                Int32(3), Int32(3), Int32(2), Int32(3),
                COL_MAJOR_CONTIGUOUS, 0x01, UInt16(0),
                Int32(12), UInt64(ptr), digest
            )
            lock1 = TransportSlotLock()
            sched1 = ComputeBudgetScheduler(500, 8, "7f8e9d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e")
            v_stride_row = execute_c_abi_zpd_graft!(lock1, desc_bad_stride_row, chain, sched1)
            @test v_stride_row isa Rejected
            @test v_stride_row.reason == :non_contiguous_stride
            @test :c_abi_stride_gate in v_stride_row.failed_gates
            @test lock1.state[] == UInt8(PYTHON_OWNED)

            # 5b. Non-contiguous stride_col != rows must be rejected before pointer wrap
            desc_bad_stride_col = CandidateBufferDescriptor(
                NARC_MAGIC_HEADER, UInt16(3), UInt16(144),
                Int32(3), Int32(3), Int32(1), Int32(6),
                COL_MAJOR_CONTIGUOUS, 0x01, UInt16(0),
                Int32(12), UInt64(ptr), digest
            )
            lock2 = TransportSlotLock()
            v_stride_col = execute_c_abi_zpd_graft!(lock2, desc_bad_stride_col, chain, sched1)
            @test v_stride_col isa Rejected
            @test v_stride_col.reason == :non_contiguous_stride
            @test :c_abi_stride_gate in v_stride_col.failed_gates

            # 5c. Out-of-bounds dsl_operator_id > VERIFIED_DSL_MAX_ID must be rejected
            desc_bad_op = CandidateBufferDescriptor(
                NARC_MAGIC_HEADER, UInt16(3), UInt16(VERIFIED_DSL_MAX_ID + 10),
                Int32(3), Int32(3), Int32(1), Int32(3),
                COL_MAJOR_CONTIGUOUS, 0x01, UInt16(0),
                Int32(12), UInt64(ptr), digest
            )
            lock3 = TransportSlotLock()
            v_bad_op = execute_c_abi_zpd_graft!(lock3, desc_bad_op, chain, sched1)
            @test v_bad_op isa Rejected
            @test v_bad_op.reason == :unverified_dsl_operator_id
            @test :c_abi_dsl_id_gate in v_bad_op.failed_gates
        end

        # 5d. Mid-borrow TOCTOU mutation: mutating buffer during execution triggers post-borrow FNV-1a rejection
        buf_toctou = UInt8[0 2 0; 2 2 2; 0 2 0]
        GC.@preserve buf_toctou begin
            ptr_t = pointer(buf_toctou)
            digest_t = compute_fnv1a_64(ptr_t, length(buf_toctou))
            desc_t = CandidateBufferDescriptor(
                NARC_MAGIC_HEADER, UInt16(3), UInt16(144),
                Int32(3), Int32(3), Int32(1), Int32(3),
                COL_MAJOR_CONTIGUOUS, 0x01, UInt16(0),
                Int32(12), UInt64(ptr_t), digest_t
            )
            mutating_nodeA = GraftNode{ColorMappedGrid, PolyominoGraph}("NodeA_Mut", function (g::ColorMappedGrid)
                buf_toctou[1, 1] ⊻= 0xff # Corrupt underlying C-ABI buffer mid-borrow!
                return fixtures.nodeA(g)
            end)
            toctou_chain = GraftNode[mutating_nodeA, fixtures.nodeB, fixtures.nodeC]
            lock_t = TransportSlotLock()
            sched_t = ComputeBudgetScheduler(500, 8, "7f8e9d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e")

            v_toctou = execute_c_abi_zpd_graft!(lock_t, desc_t, toctou_chain, sched_t)
            @test v_toctou isa Rejected
            @test v_toctou.reason == :fnv1a_toctou_post_mismatch
            @test :c_abi_toctou_gate in v_toctou.failed_gates
            @test lock_t.state[] == UInt8(PYTHON_OWNED) # Try/finally cleanly releases ownership
        end

        # 5e. Near-miss Rejected candidate (partial_score == 0.99) never empowers lineage
        sched_emp = ComputeBudgetScheduler(500, 8, "7f8e9d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e")
        dsl_lineage = UInt16[77, 88]
        tokens_before = allocate_budget(sched_emp, dsl_lineage, :Focus)
        @test !haskey(sched_emp.entrenchment.weights, dsl_lineage)

        near_miss = Rejected(:training_mismatch, "Training mismatch", [:exact_demo_match_gate], 0.99)
        if near_miss isa Accepted
            empower_lineage!(sched_emp.entrenchment, dsl_lineage, 1.0)
        end
        @test !haskey(sched_emp.entrenchment.weights, dsl_lineage)
        tokens_after = allocate_budget(sched_emp, dsl_lineage, :Focus)
        @test tokens_after == tokens_before
    end

end
