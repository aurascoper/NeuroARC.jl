# ==============================================================================
# File: verify_audit_seal.jl
# Post-Submission Cryptographic Audit Ledger Verification Script
# ==============================================================================

using NeuroARC
using NeuroARC: GENESIS_SEAL_HASH, sha256_hex, read_columnar_audit_snapshot

function verify_post_submission_audit(filepath::String)::Bool
    println("=== NeuroARC.jl Post-Submission Audit Ledger Verification ===")
    println("Loading audit snapshot from: ", filepath)

    if !isfile(filepath)
        println("[ERROR] Audit snapshot file not found: ", filepath)
        exit(1)
    end

    # 1. Load columnar snapshot NamedTuple
    snapshot = read_columnar_audit_snapshot(filepath)

    println("Schema Version    : ", snapshot.schema_version)
    println("Git Commit SHA    : ", snapshot.git_commit_hash)
    println("Total Audit Rows  : ", length(snapshot.row_id))
    println("Terminal Head Seal: ", snapshot.head_seal_sha256)
    println("-"^68)

    # 2. Recompute SHA-256 chain hash across all rows
    prev_seal = GENESIS_SEAL_HASH
    n_rows    = length(snapshot.row_id)

    for idx in 1:n_rows
        r_id        = snapshot.row_id[idx]
        t_id        = snapshot.task_id[idx]
        commit      = snapshot.git_commit_hash
        dsl         = snapshot.dsl_operator_ids[idx]
        ast_sha     = snapshot.candidate_ast_sha256[idx]
        v_stat      = snapshot.verdict_status[idx]
        v_rsn       = snapshot.verdict_reason[idx]
        score       = snapshot.score_or_partial[idx]
        resid       = snapshot.train_max_residual[idx]
        n_p         = snapshot.num_free_params[idx]
        loo_inf     = snapshot.loo_is_informative[idx]
        loo_p       = snapshot.loo_folds_passed[idx]
        loo_t       = snapshot.loo_folds_total[idx]
        equiv       = snapshot.equivariance_status[idx]
        mode        = snapshot.wbr_terminal_mode[idx]
        tokens      = snapshot.tokens_consumed[idx]
        q_seal      = snapshot.test_quarantine_sealed[idx]
        stored_seal = snapshot.row_seal_sha256[idx]

        # Reconstruct exact payload string used during append_sealed_row!
        payload = string(
            prev_seal, "|",
            r_id, "|",
            t_id, "|",
            commit, "|",
            join(dsl, ","), "|",
            ast_sha, "|",
            v_stat, "|",
            v_rsn, "|",
            score, "|",
            resid, "|",
            n_p, "|",
            loo_inf, "|",
            loo_p, "|",
            loo_t, "|",
            equiv, "|",
            mode, "|",
            tokens, "|",
            q_seal
        )

        expected_seal = sha256_hex(payload)

        if stored_seal != expected_seal
            println("[TAMPER DETECTED] SHA-256 chain broken at Row $idx (Task ID: $t_id)!")
            println("  Stored Seal   : ", stored_seal)
            println("  Expected Seal : ", expected_seal)
            exit(1)
        else
            println("[OK] Row $idx (Task: $t_id) | Status: $(rpad(string(v_stat), 10)) | Seal: $(stored_seal[1:12])...")
        end

        prev_seal = expected_seal
    end

    if snapshot.head_seal_sha256 != prev_seal
        println("[ERROR] Ledger head SHA-256 does not match terminal row seal!")
        exit(1)
    end

    println("-"^68)
    println("[SUCCESS] Cryptographic audit ledger verification PASSED.")
    println("[SUCCESS] All $n_rows rows are cryptographically sealed and untampered.")
    println("=== Verification Complete ===")
    return true
end

if abspath(PROGRAM_FILE) == @__FILE__
    target_file = length(ARGS) > 0 ? ARGS[1] : "task_audit_table.parquet.jls"
    verify_post_submission_audit(target_file)
end
