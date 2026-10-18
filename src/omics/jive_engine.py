"""
Numerically stabilized Joint and Individual Variation Explained (JIVE) solver.

This module provides a robust decomposition of multi-block omics data into
joint variation (shared across all data modalities) and individual variation
(unique to each data modality), with machine-precision subspace orthogonality.

Key numerical stability and weighting safeguards:
1. Explicit block-weighting strategies to prevent high-dimensional blocks
   (e.g., 20,000 RNA features) from dominating low-dimensional blocks
   (e.g., 50 metabolites) in concatenated SVD:
   - "frobenius_total" (default): Scales each block by its total Frobenius norm
     ||X_k||_F so every block has unit total energy (||X_tilde_k||_F = 1.0).
   - "spectral": Scales by top singular value sigma_1(X_k) (MFA-style).
   - "rms_entry": Scales by ||X_k||_F / sqrt(N * P_k) to equalize entry variance.
   - "none": Unweighted raw matrices.
   - User-supplied block_weights for custom priority profiles.
2. Thin QR projection avoiding explicit matrix inversion and rank inflation.
3. Machine-precision orthogonality verification between joint and individual subspaces.
"""

from dataclasses import dataclass
from typing import List, Optional, Tuple
import numpy as np


@dataclass
class JIVEResult:
    """
    Container for JIVE decomposition output.
    
    Attributes:
        joint_blocks: List of joint matrices J_k of shape (N, P_k).
        indiv_blocks: List of individual matrices I_k of shape (N, P_k).
        residual_blocks: List of residual matrices E_k of shape (N, P_k).
        joint_scores: Joint score matrix Z of shape (N, r_joint).
        indiv_scores: List of individual score matrices W_k of shape (N, r_indiv[k]).
        indiv_loadings: List of individual loading matrices V_k of shape (P_k, r_indiv[k]).
        scale_factors: Scaling factor applied to each block prior to weighting.
        effective_weights: Effective weighting factor applied to each block.
        weighting_strategy: Name of the weighting strategy applied.
        var_explained_joint: Proportion of Frobenius variance explained by joint structure.
        var_explained_indiv: List of variance proportions explained by individual structure.
        max_orthogonality_error: Maximum absolute inner product between joint and indiv subspaces.
    """
    joint_blocks: List[np.ndarray]
    indiv_blocks: List[np.ndarray]
    residual_blocks: List[np.ndarray]
    joint_scores: np.ndarray
    indiv_scores: List[np.ndarray]
    indiv_loadings: List[np.ndarray]
    scale_factors: List[float]
    effective_weights: List[float]
    weighting_strategy: str
    var_explained_joint: List[float]
    var_explained_indiv: List[float]
    max_orthogonality_error: float


class JIVE:
    """
    Robust JIVE solver with configurable block weighting and QR-based projection.
    """

    VALID_WEIGHTING_STRATEGIES = {"frobenius_total", "spectral", "rms_entry", "none"}

    def __init__(
        self,
        r_joint: int = 1,
        r_indiv: Optional[List[int]] = None,
        max_iter: int = 25,
        tol: float = 1e-8,
        center: bool = True,
        weighting_strategy: str = "frobenius_total",
        block_weights: Optional[List[float]] = None
    ):
        """
        Initialize JIVE solver.
        
        Args:
            r_joint: Number of joint ranks to extract.
            r_indiv: List of individual ranks for each block.
            max_iter: Maximum number of alternating projection iterations.
            tol: Convergence tolerance for score subspace delta.
            center: Whether to center features (columns) to mean zero.
            weighting_strategy: Method for equalizing block contributions in concatenated SVD:
                - 'frobenius_total': ||X_k||_F = 1.0 for all k (equal total energy).
                - 'spectral': sigma_1(X_k) = 1.0 for all k (equal top directional variance).
                - 'rms_entry': Entry variance = 1.0 (energy proportional to feature dimension).
                - 'none': Raw unweighted blocks.
            block_weights: Optional explicit multiplier applied to each block after scaling.
        """
        if weighting_strategy not in self.VALID_WEIGHTING_STRATEGIES:
            raise ValueError(
                f"Unknown weighting_strategy '{weighting_strategy}'. "
                f"Must be one of {sorted(self.VALID_WEIGHTING_STRATEGIES)}"
            )

        self.r_joint = r_joint
        self.r_indiv = r_indiv
        self.max_iter = max_iter
        self.tol = tol
        self.center = center
        self.weighting_strategy = weighting_strategy
        self.block_weights = block_weights

    def fit_transform(self, blocks: List[np.ndarray]) -> JIVEResult:
        """
        Fit JIVE decomposition on a list of data blocks.
        
        Args:
            blocks: List of K matrices, each of shape (N, P_k), with identical sample count N.
            
        Returns:
            JIVEResult containing reconstructed components and diagnostic metrics.
        """
        if not blocks:
            raise ValueError("Input blocks list cannot be empty.")
            
        k_blocks = len(blocks)
        n_samples = blocks[0].shape[0]
        
        for idx, block in enumerate(blocks):
            if block.shape[0] != n_samples:
                raise ValueError(
                    f"Sample mismatch: Block 0 has {n_samples} samples, "
                    f"but block {idx} has {block.shape[0]} samples."
                )
                
        if self.r_indiv is None:
            r_indiv = [1] * k_blocks
        else:
            if len(self.r_indiv) != k_blocks:
                raise ValueError("Length of r_indiv must match number of blocks.")
            r_indiv = self.r_indiv

        if self.block_weights is not None:
            if len(self.block_weights) != k_blocks:
                raise ValueError("Length of block_weights must match number of blocks.")
            user_weights = [float(w) for w in self.block_weights]
        else:
            user_weights = [1.0] * k_blocks

        # Step 1: Optional feature centering
        centered_blocks = []
        for blk in blocks:
            if self.center:
                centered_blocks.append(blk - np.mean(blk, axis=0, keepdims=True))
            else:
                centered_blocks.append(blk.copy())

        # Step 2: Block scaling according to weighting_strategy
        scale_factors = []
        effective_weights = []
        normalized_blocks = []

        for k, blk in enumerate(centered_blocks):
            f_norm = float(np.linalg.norm(blk, "fro"))
            n_p = float(np.sqrt(blk.shape[0] * blk.shape[1]))

            if self.weighting_strategy == "frobenius_total":
                # Total Frobenius norm normalization: ||X_tilde_k||_F = 1.0
                # Every block contributes identical total energy to the concatenated SVD.
                base_scale = f_norm if f_norm > 1e-12 else 1.0
            elif self.weighting_strategy == "spectral":
                # First singular value normalization
                _, s_vals, _ = np.linalg.svd(blk, full_matrices=False)
                top_s = float(s_vals[0]) if len(s_vals) > 0 else 1.0
                base_scale = top_s if top_s > 1e-12 else 1.0
            elif self.weighting_strategy == "rms_entry":
                # Entry-wise variance normalization
                base_scale = (f_norm / n_p) if f_norm > 1e-12 else 1.0
            elif self.weighting_strategy == "none":
                base_scale = 1.0
            else:
                base_scale = 1.0

            w_k = user_weights[k]
            # Total divisor to obtain normalized block:
            # normalized_block = blk / (base_scale / w_k)
            eff_divisor = base_scale / w_k if w_k > 1e-12 else base_scale
            scale_factors.append(base_scale)
            effective_weights.append(eff_divisor)
            normalized_blocks.append(blk / eff_divisor)

        # Initialize individual structures to zeros
        indiv_norm = [np.zeros_like(b) for b in normalized_blocks]
        q_joint = np.zeros((n_samples, self.r_joint))

        # Step 3: Alternating projection loop with QR orthogonalization
        for iteration in range(self.max_iter):
            # Compute joint candidate from (X_k - I_k)
            joint_inputs = [normalized_blocks[k] - indiv_norm[k] for k in range(k_blocks)]
            concat_joint_input = np.concatenate(joint_inputs, axis=1)

            # SVD on concatenated joint input
            u_j, s_j, vt_j = np.linalg.svd(concat_joint_input, full_matrices=False)
            
            # Select top r_joint left singular vectors
            actual_r_joint = min(self.r_joint, u_j.shape[1])
            z_new = u_j[:, :actual_r_joint]
            
            # Compute thin QR decomposition to guarantee exact orthonormal basis
            q_joint_new, _ = np.linalg.qr(z_new, mode="reduced")

            # Check convergence via subspace projection distance
            subspace_delta = np.linalg.norm(q_joint_new @ q_joint_new.T - q_joint @ q_joint.T, "fro")
            q_joint = q_joint_new

            # Update individual structures by projecting onto orthogonal complement of Q_joint
            # P_perp = I - Q_joint @ Q_joint.T
            # R_k = P_perp @ X_k = X_k - Q_joint @ (Q_joint.T @ X_k)
            for k in range(k_blocks):
                x_k = normalized_blocks[k]
                r_k = x_k - q_joint @ (q_joint.T @ x_k)

                actual_r_indiv = min(r_indiv[k], min(r_k.shape))
                if actual_r_indiv > 0:
                    u_i, s_i, vt_i = np.linalg.svd(r_k, full_matrices=False)
                    indiv_norm[k] = (u_i[:, :actual_r_indiv] * s_i[:actual_r_indiv]) @ vt_i[:actual_r_indiv, :]
                else:
                    indiv_norm[k] = np.zeros_like(r_k)

            if subspace_delta < self.tol and iteration > 0:
                break

        # Step 4: Final extraction of joint and individual components
        joint_blocks = []
        indiv_blocks = []
        residual_blocks = []
        indiv_scores = []
        indiv_loadings = []
        var_explained_joint = []
        var_explained_indiv = []

        max_orthogonality_error = 0.0

        for k in range(k_blocks):
            # Form final joint estimate: projection of normalized block onto Q_joint
            j_k_norm = q_joint @ (q_joint.T @ normalized_blocks[k])
            
            # Form final individual candidate from orthogonal residual
            r_k = normalized_blocks[k] - j_k_norm
            actual_r_indiv = min(r_indiv[k], min(r_k.shape))

            if actual_r_indiv > 0:
                u_i, s_i, vt_i = np.linalg.svd(r_k, full_matrices=False)
                w_k = u_i[:, :actual_r_indiv]
                v_k = vt_i[:actual_r_indiv, :].T
                i_k_norm = (w_k * s_i[:actual_r_indiv]) @ v_k.T
            else:
                w_k = np.zeros((n_samples, 0))
                v_k = np.zeros((normalized_blocks[k].shape[1], 0))
                i_k_norm = np.zeros_like(normalized_blocks[k])

            # Rescale back to original measurement units using effective_weights
            eff_s = effective_weights[k]
            j_k = j_k_norm * eff_s
            i_k = i_k_norm * eff_s
            e_k = centered_blocks[k] - j_k - i_k

            # Measure subspace orthogonality error: ||Q_joint.T @ W_k||
            if w_k.shape[1] > 0:
                ortho_err = float(np.linalg.norm(q_joint.T @ w_k, "fro"))
                if ortho_err > max_orthogonality_error:
                    max_orthogonality_error = ortho_err

            # Variance explained calculation in original centered units
            total_var = float(np.linalg.norm(centered_blocks[k], "fro") ** 2)
            if total_var > 1e-12:
                v_j = float(np.linalg.norm(j_k, "fro") ** 2) / total_var
                v_i = float(np.linalg.norm(i_k, "fro") ** 2) / total_var
            else:
                v_j = 0.0
                v_i = 0.0

            joint_blocks.append(j_k)
            indiv_blocks.append(i_k)
            residual_blocks.append(e_k)
            indiv_scores.append(w_k)
            indiv_loadings.append(v_k)
            var_explained_joint.append(v_j)
            var_explained_indiv.append(v_i)

        return JIVEResult(
            joint_blocks=joint_blocks,
            indiv_blocks=indiv_blocks,
            residual_blocks=residual_blocks,
            joint_scores=q_joint,
            indiv_scores=indiv_scores,
            indiv_loadings=indiv_loadings,
            scale_factors=scale_factors,
            effective_weights=effective_weights,
            weighting_strategy=self.weighting_strategy,
            var_explained_joint=var_explained_joint,
            var_explained_indiv=var_explained_indiv,
            max_orthogonality_error=max_orthogonality_error,
        )
