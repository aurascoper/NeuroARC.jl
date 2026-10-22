#!/usr/bin/env bash
# ==============================================================================
# File: bundle_kaggle.sh
# Clean Deployment Archive Builder for Private Kaggle Dataset Upload
# ==============================================================================

set -euo pipefail

ARCHIVE_NAME="neuroarc_kaggle_deployment.zip"

echo "=== [1/3] Cleaning local temporary artifacts ==="
make clean

echo "=== [2/3] Packaging clean workspace into $ARCHIVE_NAME ==="
rm -f "$ARCHIVE_NAME"
zip -q -r "$ARCHIVE_NAME" . \
    -x ".git/*" \
    -x ".github/*" \
    -x "*.cov" \
    -x "*.info" \
    -x "lcov.info" \
    -x "submission.json" \
    -x "task_audit_table.parquet.jls" \
    -x "*.jls" \
    -x "*.DS_Store" \
    -x "$ARCHIVE_NAME"

echo "=== [3/3] Verifying archive manifest ==="
unzip -l "$ARCHIVE_NAME" | grep -E "(src/NeuroARC\.jl|src/gyrism\.jl|src/transport_boundary\.jl|src/budget_scheduler\.jl|src/audit_telemetry\.jl|generate_submission\.jl|verify_audit_seal\.jl|run\.sh)"
echo "[SUCCESS] Deployment archive created: $(pwd)/$ARCHIVE_NAME"
