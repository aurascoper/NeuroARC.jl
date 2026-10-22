# ==============================================================================
# NeuroARC.jl Development Makefile (With LaTeX Manuscript & Audit Targets)
# ==============================================================================

JULIA ?= julia
PROJECT_DIR = .
MANUSCRIPT_DIR = manuscript

.PHONY: all instantiate test coverage submission verify bundle manuscript manuscript-clean clean help

all: instantiate test

help:
	@echo "Available Makefile targets:"
	@echo "  make instantiate      - Instantiate and precompile Julia project dependencies"
	@echo "  make test             - Run the master 325-assertion unit test suite"
	@echo "  make coverage         - Run tests with coverage and print line coverage stats"
	@echo "  make submission       - Run generate_submission.jl to build Kaggle outputs & audit ledger"
	@echo "  make verify           - Run verify_audit_seal.jl to check cryptographic ledger chain integrity"
	@echo "  make bundle           - Build clean neuroarc_kaggle_deployment.zip via bundle_kaggle.sh"
	@echo "  make manuscript       - Compile manuscript/main.tex to PDF via build_pdf.sh"
	@echo "  make manuscript-clean - Clean LaTeX auxiliary build files in manuscript/"
	@echo "  make clean            - Remove coverage files, LCOV reports, and local artifacts"

instantiate:
	@echo "--- Instantiating & Precompiling NeuroARC.jl ---"
	$(JULIA) --color=yes --project=$(PROJECT_DIR) -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

test:
	@echo "--- Running Master Unit Test Suite ---"
	$(JULIA) --color=yes --project=$(PROJECT_DIR) -e 'using Pkg; Pkg.test()'

coverage:
	@echo "--- Running Tests with Coverage Reporting ---"
	$(JULIA) --color=yes --project=$(PROJECT_DIR) -e 'using Pkg; Pkg.test(coverage=true)'
	@echo "--- Generating Coverage Summary ---"
	$(JULIA) --color=yes --project=$(PROJECT_DIR) -e 'using Coverage; cov = Coverage.process_folder("src"); sum = Coverage.get_summary(cov); printfmt = round(100.0 * sum.covered / sum.total, digits=2); println("Covered Lines: $(sum.covered) / $(sum.total) ($printfmt%)")'

submission:
	@echo "--- Executing Kaggle Submission & Ledger Sealing Pipeline ---"
	$(JULIA) --color=yes --project=$(PROJECT_DIR) generate_submission.jl

verify:
	@echo "--- Verifying Cryptographic Audit Ledger Seal ---"
	$(JULIA) --color=yes --project=$(PROJECT_DIR) verify_audit_seal.jl task_audit_table.parquet.jls

bundle:
	@echo "--- Building Clean Kaggle Deployment Archive ---"
	./bundle_kaggle.sh

manuscript:
	@echo "--- Compiling LaTeX Manuscript ---"
	$(MAKE) -C $(MANUSCRIPT_DIR) pdf

manuscript-clean:
	@echo "--- Cleaning LaTeX Auxiliary Build Files ---"
	$(MAKE) -C $(MANUSCRIPT_DIR) clean

clean:
	@echo "--- Cleaning Workspace Artifacts ---"
	find . -name "*.cov" -delete
	rm -f lcov.info submission.json task_audit_table.parquet.jls neuroarc_kaggle_deployment.zip
	@echo "Workspace cleanup complete."
