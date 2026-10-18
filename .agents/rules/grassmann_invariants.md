# Grassmann Invariants and Dependency Guardrails for NeuroARC.jl

## 1. Mathematical Foundation and Semantic Disambiguation
Grassmann.jl, GrassmannSymbolics.jl, and GrassmannTensorNetworks.jl sit over the same exterior-algebra foundation, since Grassmann variables are the exterior algebra's generators. However, they are different tools over the same algebra, not drop-in replacements. What differs is their API, dependency graph, and intended application domain:

1. **Grassmann.jl** (`chakravala/Grassmann.jl`):
   - Scope: Geometric algebra, Clifford algebras, exterior calculus, Hodge duality, and multivector algebra.
   - Foundation: Computes over multivectors, grade projections, and geometric products.
   - Role: Geometric transforms, spatial rotations, and exterior forms on spatial grid manifolds.

2. **GrassmannSymbolics.jl** (`Harrykjg-physics/GrassmannSymbolics.jl`):
   - Scope: Symbolic derivation of Grassmann tensors for fermionic models in condensed-matter and statistical physics.
   - Foundation: Anticommuting symbolic generators and parity-preserving expressions over Symbolics.jl / SymbolicUtils.jl.
   - Role: Exact algebraic simplification and symbolic verification of parity-preserving criterial logic gates.

3. **GrassmannTensorNetworks.jl** (`Harrykjg-physics/GrassmannTensorNetworks.jl`):
   - Scope: Numerical tensor network states and contractions with fermionic swap gates and sign tracking.
   - Foundation: Tensor network states using TensorOperations.jl and Strided.jl.
   - Role: Many-body tensor contractions and network partition problems.

Never conflate their APIs or assume functions from one exist in another.

## 2. Dependency Boundary Invariant (Zero-Dependency Core)
To ensure instant load times, clean CI runs, and lightweight compatibility with Kaggle submission environments:
- **Mandatory Empty `[deps]`**: The core `NeuroARC.jl` package must maintain ZERO external runtime dependencies in `[deps]`.
- **Package Extensions Only**: Any integration with `Grassmann.jl`, `GrassmannSymbolics.jl`, or `GrassmannTensorNetworks.jl` must reside exclusively in `[weakdeps]` and `[extensions]` (requiring Julia 1.9+).
- **No Direct Transitive Pollution**: Never add heavy CAS or tensor libraries (`Symbolics.jl`, `SciMLBase`, `TensorOperations.jl`, `HDF5`) directly to `NeuroARC.jl/Project.toml`.

## 3. Symbolic Derivation versus Numerical Acceleration
- Exact symbolic simplifications generated via `GrassmannSymbolics` must remain strictly decoupled from numerical floating-point operations.
- GPU acceleration backends (`Metal.jl`, `CUDA.jl`, `JACC.jl`) must never be assumed to execute raw symbolic expressions. Symbolic derivations must lower to concrete numeric matrices or deterministic arrays before dispatch to accelerated kernels.
