# ==============================================================================
# File: verify_audit_seal.jl
# Post-Submission Cryptographic Audit Ledger Verification Script
# ==============================================================================

using NeuroARC
using NeuroARC: GENESIS_SEAL_HASH, SEAL_SCHEMA_VERSION, TaskAuditRow,
    sha256_hex, compute_canonical_row_seal_sha256, read_columnar_audit_snapshot

function verify_post_submission_audit(
    filepath::String;
    exit_on_error::Bool = (abspath(PROGRAM_FILE) == @__FILE__)
)::Bool
    println("=== NeuroARC.jl Post-Submission Audit Ledger Verification ===")
    println("Loading audit snapshot from: ", filepath)

    if !isfile(filepath)
        println("[ERROR] Audit snapshot file not found: ", filepath)
        exit_on_error && exit(1)
        return false
    end

    # 1. Load columnar snapshot NamedTuple
    snapshot = read_columnar_audit_snapshot(filepath)

    println("Schema Version    : ", snapshot.schema_version)
    println("Git Commit SHA    : ", snapshot.git_commit_hash)
    println("Total Audit Rows  : ", length(snapshot.row_id))
    println("Terminal Head Seal: ", snapshot.head_seal_sha256)
    println("-"^68)

    if snapshot.schema_version != SEAL_SCHEMA_VERSION
        println("[TAMPER DETECTED] Snapshot schema_version $(snapshot.schema_version) != $(SEAL_SCHEMA_VERSION)")
        exit_on_error && exit(1)
        return false
    end

    # 2. Recompute versioned canonical SHA-256 chain hash across all rows
    prev_seal = GENESIS_SEAL_HASH
    n_rows    = length(snapshot.row_id)

    for idx in 1:n_rows
        row = TaskAuditRow(
            snapshot.seal_schema_version[idx],
            snapshot.row_id[idx],
            snapshot.task_id[idx],
            snapshot.git_commit_hash_col[idx],
            snapshot.dsl_operator_ids[idx],
            snapshot.candidate_ast_sha256[idx],
            snapshot.ast_expr[idx],
            snapshot.preflight_subtype_ok[idx],
            snapshot.runtime_typeassert_ok[idx],
            snapshot.train_pairs_count[idx],
            snapshot.train_exact_matches[idx],
            snapshot.train_max_residual[idx],
            snapshot.num_free_params[idx],
            snapshot.loo_is_informative[idx],
            snapshot.loo_folds_total[idx],
            snapshot.loo_folds_passed[idx],
            snapshot.equivariance_status[idx],
            snapshot.wbr_terminal_mode[idx],
            snapshot.tokens_consumed[idx],
            snapshot.test_quarantine_sealed[idx],
            snapshot.verdict_status[idx],
            snapshot.verdict_reason[idx],
            snapshot.failed_gates[idx],
            snapshot.partial_score[idx],
            snapshot.wall_time_ns[idx],
            snapshot.memory_bytes[idx],
            snapshot.prev_row_seal_sha256[idx],
            snapshot.row_seal_sha256[idx]
        )

        if hasproperty(snapshot, :rows) && snapshot.rows[idx] != row
            println("[TAMPER DETECTED] Columnar fields diverge from stored TaskAuditRow at Row $idx!")
            exit_on_error && exit(1)
            return false
        end

        if !row.test_quarantine_sealed
            println("[QUARANTINE BREACH] Row $idx (Task ID: $(row.task_id)) has test_quarantine_sealed == false!")
            exit_on_error && exit(1)
            return false
        end

        if row.seal_schema_version != SEAL_SCHEMA_VERSION
            println("[TAMPER DETECTED] Unsupported row seal_schema_version at Row $idx: $(row.seal_schema_version)")
            exit_on_error && exit(1)
            return false
        end

        if row.prev_row_seal_sha256 != prev_seal
            println("[TAMPER DETECTED] Broken prev_row_seal_sha256 link at Row $idx (Task ID: $(row.task_id))!")
            exit_on_error && exit(1)
            return false
        end

        if row.git_commit_hash != snapshot.git_commit_hash
            println("[TAMPER DETECTED] Row git_commit_hash mismatch at Row $idx (Task ID: $(row.task_id))!")
            exit_on_error && exit(1)
            return false
        end

        if row.candidate_ast_sha256 != sha256_hex(row.ast_expr)
            println("[TAMPER DETECTED] AST SHA-256 mismatch at Row $idx (Task ID: $(row.task_id))!")
            exit_on_error && exit(1)
            return false
        end

        expected_seal = compute_canonical_row_seal_sha256(row)
        stored_seal   = row.row_seal_sha256

        if stored_seal != expected_seal
            println("[TAMPER DETECTED] SHA-256 chain broken at Row $idx (Task ID: $(row.task_id))!")
            println("  Stored Seal   : ", stored_seal)
            println("  Expected Seal : ", expected_seal)
            exit_on_error && exit(1)
            return false
        else
            println("[OK] Row $idx (Task: $(row.task_id)) | Status: $(rpad(string(row.verdict_status), 10)) | Seal: $(stored_seal[1:12])...")
        end

        prev_seal = expected_seal
    end

    if snapshot.head_seal_sha256 != prev_seal
        println("[ERROR] Ledger head SHA-256 does not match terminal row seal!")
        exit_on_error && exit(1)
        return false
    end

    println("-"^68)
    println("[SUCCESS] Cryptographic audit ledger verification PASSED.")
    println("[SUCCESS] All $n_rows rows are cryptographically sealed and untampered.")
    println("=== Verification Complete ===")
    return true
end

if abspath(PROGRAM_FILE) == @__FILE__
    target_file = length(ARGS) > 0 ? ARGS[1] : "task_audit_table.parquet.jls"
    verify_post_submission_audit(target_file; exit_on_error = true)
end
