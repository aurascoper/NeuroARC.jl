# ==============================================================================
# File: ext/NeuroARCJACCExt.jl
# Portable multi-backend JACC.jl GPU/CPU acceleration extension for NeuroARC.jl
# ==============================================================================
module NeuroARCJACCExt

using NeuroARC
using NeuroARC.TransjectionCalculus: AbstractVerdict, Accepted, Rejected, Incomplete
using NeuroARC: JACCBackend, DihedralOp
using JACC

# 1. Signal to NeuroARC core that the JACC portable backend extension is loaded
NeuroARC.extension_loaded(::JACCBackend) = true

"""
    NeuroARC.evaluate_batch_demos!(::JACCBackend, X_batch, Y_batch, op, color_inv) -> AbstractVerdict

Executes portable batch demonstration verification via `JACC.Array` and `JACC.parallel_for`.
"""
function NeuroARC.evaluate_batch_demos!(
    ::JACCBackend,
    X_batch::Array{UInt8, 3},
    Y_batch::Array{UInt8, 3},
    op::DihedralOp,
    color_inv::Bool = false
)::AbstractVerdict

    size(X_batch) == size(Y_batch) || return Rejected(
        :batch_dimension_mismatch, "Batch dimensions do not match.", [:batch_dim_gate], 0.0
    )
    H, W, K = size(X_batch)
    if !(1 <= H <= 30 && 1 <= W <= 30 && K >= 1)
        return Rejected(:grid_dimension_violation, "Batch dimensions ($H, $W, $K) out of 1..30 bounds.", [:dim_gate], 0.0)
    end
    if (op.k_rot == 0x01 || op.k_rot == 0x03) && (H != W)
        return Rejected(:aspect_ratio_mismatch, "90/270-deg rotation requires square grid for in-place batch.", [:aspect_gate], 0.0)
    end

    N_total  = H * W * K
    X_jacc   = JACC.Array(vec(X_batch))
    Y_jacc   = JACC.Array(vec(Y_batch))
    res_jacc = JACC.Array(zeros(Int32, N_total))

    H32    = Int32(H)
    W32    = Int32(W)
    HW32   = H32 * W32
    k_rot  = op.k_rot
    flip_b = op.flip ? 0x01 : 0x00
    inv_b  = color_inv ? 0x01 : 0x00

    JACC.parallel_for(N_total, (idx, X_d, Y_d, R_d, h, w, hw, rot, flp, inv) -> begin
        idx0  = Int32(idx - 1)
        k_idx = div(idx0, hw)
        rem0  = rem(idx0, hw)
        c     = div(rem0, h) + Int32(1)
        r     = rem(rem0, h) + Int32(1)

        src_r = r
        src_c = c
        if rot == 0x02
            src_r = h - r + Int32(1)
            src_c = w - c + Int32(1)
        elseif rot == 0x01
            src_r = c
            src_c = h - r + Int32(1)
        elseif rot == 0x03
            src_r = w - c + Int32(1)
            src_c = r
        end

        if flp == 0x01
            src_c = w - src_c + Int32(1)
        end

        src_linear = k_idx * hw + (src_c - Int32(1)) * h + src_r
        val_x = X_d[src_linear]

        if val_x > 0x09
            R_d[idx] = Int32(99)
        else
            pred = (inv == 0x01) ? (UInt8(9) - val_x) : val_x
            diff = Int32(pred) - Int32(Y_d[idx])
            R_d[idx] = ifelse(diff < Int32(0), -diff, diff)
        end
    end, X_jacc, Y_jacc, res_jacc, H32, W32, HW32, k_rot, flip_b, inv_b)

    res_host = reshape(Array(res_jacc), H, W, K)
    any(r -> r == Int32(99), res_host) && return Rejected(
        :palette_token_violation, "JACC kernel detected palette token > 9.", [:membrane_palette_gate], 0.0
    )

    worst_residual = Float64(maximum(res_host))
    passed_pairs   = count(k -> maximum(@view res_host[:, :, k]) == Int32(0), 1:K)

    if worst_residual == 0.0
        return Accepted(
            (backend = :JACC, K_verified = K, max_residual = 0.0),
            (:jacc_portable_verified, :exact_reconstruction),
            1.0,
            "JACC portable backend verified all $K/$K demonstration grids with 0.0 residual."
        )
    else
        partial = clamp(Float64(passed_pairs) / Float64(K), 0.0, 0.99)
        return Rejected(
            :train_reconstruction_residual,
            "JACC batch failed exact reconstruction: $passed_pairs/$K matched (max residual = $worst_residual).",
            [:train_exact_reconstruction_gate],
            partial
        )
    end
end

end # module NeuroARCJACCExt
