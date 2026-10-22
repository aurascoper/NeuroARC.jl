# NeuroARC.jl

**Typed Criterial Causation, Hyphal Grafting, and Epistemic Invariants in Grid Domain Logic**

[![Julia CI](https://github.com/aurascoper/NeuroARC.jl/actions/workflows/julia_ci.yml/badge.svg)](https://github.com/aurascoper/NeuroARC.jl/actions/workflows/julia_ci.yml)
[![Manuscript CI](https://github.com/aurascoper/NeuroARC.jl/actions/workflows/manuscript_ci.yml/badge.svg)](https://github.com/aurascoper/NeuroARC.jl/actions/workflows/manuscript_ci.yml)

`NeuroARC.jl` (`UUID = a3f5a15a-93e1-4bd8-99e6-0563b78be05c`) is a high performance, zero-dependency Julia package for autonomous visual reasoning on discrete grid abstraction benchmarks, including the Abstraction and Reasoning Corpus (ARC).

![NeuroARC.jl Criterial Causation Architecture](manuscript/figures/NeuroARC.svg)

---

## 1. Epistemic Architecture Boundaries

Our research program maintains strict stratification between distinct research tracks:
- **Track 2 (Donald Hoffman Paper Route)**: Kept rigorously minimalist, conservative, and focused exclusively on whether an aesthetic preference relation escapes the 2006 Scrambling Theorem or is carried by a functional bijection. No ARC benchmarks, prompt engineering tokens, or ungrounded algorithmic operators enter Track 2.
- **Track 3 (Antigravity and NeuroARC.jl Track)**: The operational software platform for criterial causation, informational logic gates, pedagogical scaffolding, morphological grid invariants, and psycholinguistic chain-of-thought mediation.

---

## 2. Core Concepts

### 2.1 Tri-Stage Criterial Causation
Following Peter Tse's cognitive theory of criterial causation (Tse, 2013), rule selection operates across three temporal phases:
1. **Stage t1**: Setting acceptance threshold vectors, projection operators, and computing token budgets.
2. **Stage t2**: Gating input candidate representations through criterial logic gates (`ThresholdGate`, `BandpassGate`, `SubtypeGate`, `ConjunctionGate`, `DisjunctionGate`, `KOfNGate`).
3. **Stage t3**: Downward empowerment (`Accepted`) with compute allocation or criterial extinction (`Rejected` / `Incomplete`).

### 2.2 Hyphal Grafting and Deep Composition Contracts
Rule pipelines are composed via verified directed edges:
- **Preflight Compatibility Check**: Evaluates static Julia subtyping `Out(A) <: In(B)` before running, executing zero node functions during validation.
- **Runtime Intermediate Boundary Contract**: Callable wrapper `x -> second(first(x))` enforces `Core.typeassert` at every intermediate node boundary, preventing undeclared types from leaking downstream.
- **Typed Verdicts (No Numeric Inf Sentinels)**: Returns explicit algebraic types (`Accepted`, `Rejected`, `Incomplete`) to prevent optimizer corruption.

---

## 3. Package Architecture & Extension Isolation

`NeuroARC.jl` enforces a zero-dependency core package. The core engine runs exclusively on the standard library.

External acceleration and inference libraries are provided via Julia 1.9+ package extensions:
- **`Metal.jl`** (`ext/NeuroARCMetalExt.jl`): GPU acceleration for Apple Silicon hardware.
- **`JACC.jl`** (`ext/NeuroARCJACCExt.jl`): Performance portability across CPU and GPU hardware.
- **`Turing.jl`** (`ext/NeuroARCTuringExt.jl`): Probabilistic MCMC calibration routines.

---

## 4. Running Tests & Benchmarks

Execute the master package test suite (325 assertions) using Julia's package manager:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Execute the dedicated 67-assertion verification suite covering conditional extensions, C-ABI zero-copy transport, Bayesian GLMM calibration, 4-compartment Kondepudi-Frank chiral percolation, and the adaptive CPU-Metal RL scheduler:

```bash
julia --project=. test/test_turing_ext.jl
```

Run the multi-backend and adaptive CPU-Metal test-time RL benchmarks:

```bash
julia --project=. benchmark_adaptive_rl.jl
julia --project=. benchmark_bandwidth.jl
```

---

## 5. Kaggle Submission, Cryptographic Audit Sealing & Deployment

To execute the test-time RL inference loop, write `submission.json`, seal `task_audit_table.parquet.jls`, and verify the append-only SHA-256 chain hash:

```bash
make submission
make verify
```

To package a clean, self-contained deployment archive (`neuroarc_kaggle_deployment.zip`) for private Kaggle Dataset upload:

```bash
make bundle
```

---

## 6. Compiling the Manuscript

The repository houses the complete academic manuscript in `manuscript/`:

```bash
make manuscript
```

The build script renders Graphviz DOT vector diagrams, compiles `main.tex` to `main.pdf` via Tectonic or XeLaTeX, and verifies text cleanliness against the compiled layout.

---

## 7. Repository Governance & Release Lifecycle

`NeuroARC.jl` is currently initialized as a **private repository**. Releasing the code publicly before formal review exposes provisional architecture as finished work.

Public release is scheduled after:
1. The Donald Hoffman outreach cycle on the six-page draft is complete.
2. The Revision 3 anti-solipsism audit gates and telemetry logs (`task_audit_table.parquet`) have been formally executed and cryptographically sealed.
3. The Kaggle submission notebook (`notebooks/NeuroARC_Submission_v3.ipynb`) has been frozen and scored on the leaderboard.

---

## 8. License

MIT License. See `LICENSE` for details.
