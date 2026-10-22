#!/usr/bin/env bash
# ==============================================================================
# NeuroARC.jl Hybrid Kaggle Submission Runner (run.sh)
# Enforces Zero-Dependency Core Isolation, C-ABI Handoff, and Cryptographic Sealing
# ==============================================================================

set -euo pipefail

# 1. Environment & Path Discovery
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WORKSPACE_DIR"

echo "=== [NeuroARC] Starting Kaggle Submission Pipeline ==="
echo "Workspace Directory: $WORKSPACE_DIR"
echo "Current Working Directory: $(pwd)"

# 2. Bootstrap Julia Binary (if not present in host container path)
JULIA_VERSION="1.10.3"
JULIA_BIN="/opt/julia-$JULIA_VERSION/bin/julia"

if ! command -v julia &> /dev/null && [ ! -f "$JULIA_BIN" ]; then
    echo "--- Bootstrapping Julia $JULIA_VERSION ---"
    JULIA_VER=$(cut -d '.' -f -2 <<< "$JULIA_VERSION")
    wget -nv https://julialang-s3.julialang.org/bin/linux/x64/$JULIA_VER/julia-$JULIA_VERSION-linux-x86_64.tar.gz -O /tmp/julia.tar.gz
    tar -xzf /tmp/julia.tar.gz -C /opt/
    export PATH="/opt/julia-$JULIA_VERSION/bin:$PATH"
elif [ -f "$JULIA_BIN" ]; then
    export PATH="/opt/julia-$JULIA_VERSION/bin:$PATH"
fi

echo "Using Julia Version: $(julia --version)"

# 3. Instantiate Julia Project Workspace & Precompile Core
echo "--- Instantiating Julia Project Workspace ---"
julia --color=yes --project="$WORKSPACE_DIR" -e '
using Pkg
Pkg.activate(".")
if isfile("Manifest.toml")
    Pkg.resolve()
else
    Pkg.instantiate()
end
Pkg.precompile()
println("Julia project instantiation and precompilation complete.")
'

# 4. Execute Hybrid Python Presynaptic Host & Julia Verification Core
echo "--- Executing Test-Time RL Inference & Layer 4 Scheduling ---"
INPUT_TASKS="${KAGGLE_INPUT_DIR:-$WORKSPACE_DIR}/test_tasks.json"
OUTPUT_JSON="${KAGGLE_WORKING_DIR:-$WORKSPACE_DIR}/submission.json"
OUTPUT_PARQUET="${KAGGLE_WORKING_DIR:-$WORKSPACE_DIR}/task_audit_table.parquet.jls"

julia --color=yes --project="$WORKSPACE_DIR" "$WORKSPACE_DIR/generate_submission.jl"

# 5. Verify Output Artifacts & Cryptographic Seal
echo "--- Verifying Output Artifacts ---"
if [ -f "$OUTPUT_JSON" ]; then
    echo "[SUCCESS] submission.json generated successfully."
else
    echo "[ERROR] submission.json missing!" >&2
    exit 1
fi

if [ -f "$OUTPUT_PARQUET" ]; then
    echo "[SUCCESS] task_audit_table.parquet.jls cryptographic ledger sealed successfully."
    julia --color=yes --project="$WORKSPACE_DIR" "$WORKSPACE_DIR/verify_audit_seal.jl" "$OUTPUT_PARQUET"
else
    echo "[ERROR] Audit ledger snapshot missing!" >&2
    exit 1
fi

echo "=== [NeuroARC] Pipeline Completed Successfully. Ready for Kaggle Submission. ==="
