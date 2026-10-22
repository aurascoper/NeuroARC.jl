# ==============================================================================
# File: ext/NeuroARCMetalExt.jl
# Apple Silicon Metal.jl GPU acceleration extension for NeuroARC.jl
# ==============================================================================
module NeuroARCMetalExt

using NeuroARC
using NeuroARC.TransjectionCalculus: AbstractVerdict, Accepted, Rejected, Incomplete
using NeuroARC: MetalBackend, DihedralOp
using Metal

# 1. Signal to NeuroARC core that the Metal extension is loaded and functional
NeuroARC.extension_loaded(::MetalBackend) = Metal.functional()

"""
    metal_dihedral_residual_kernel!(residuals, X_dev, Y_dev, H, W, K, k_rot, flip_flag, inv_flag)

3D Metal compute kernel evaluating dihedral transformation (k_rot in {0, 1, 2, 3},
horizontal flip, and color complement) and computing per-cell absolute residuals
|Y_hat[r,c,k] - Y_dev[r,c,k]| entirely in integer GPU registers (strictly avoiding
Float64 on Apple Silicon GPUs).
"""
function metal_dihedral_residual_kernel!(
    residuals::MtlDeviceArray{Int32, 3},
    X_dev::MtlDeviceArray{UInt8, 3},
    Y_dev::MtlDeviceArray{UInt8, 3},
    H::Int32,
    W::Int32,
    K::Int32,
    k_rot::UInt8,
    flip_flag::UInt8,
    inv_flag::UInt8
)
    pos = thread_position_in_grid_3d()
    r = Int32(pos.x)
    c = Int32(pos.y)
    k = Int32(pos.z)

    if r <= H && c <= W && k <= K
        src_r = r
        src_c = c

        if k_rot == 0x02 # 180-degree rotation
            src_r = H - r + Int32(1)
            src_c = W - c + Int32(1)
        elseif k_rot == 0x01 && H == W # 90-degree CCW on square grid
            src_r = c
            src_c = H - r + Int32(1)
        elseif k_rot == 0x03 && H == W # 270-degree CCW on square grid
            src_r = W - c + Int32(1)
            src_c = r
        end

        if flip_flag == 0x01
            src_c = W - src_c + Int32(1)
        end

        val_x = X_dev[src_r, src_c, k]
        # Guard palette invariant in kernel: token > 9 maps to sentinel residual 99
        if val_x > 0x09
            residuals[r, c, k] = Int32(99)
        else
            pred = (inv_flag == 0x01) ? (UInt8(9) - val_x) : val_x
            target = Y_dev[r, c, k]
            diff = Int32(pred) - Int32(target)
            residuals[r, c, k] = ifelse(diff < Int32(0), -diff, diff)
        end
    end
    return nothing
end

"""
    NeuroARC.evaluate_batch_demos!(::MetalBackend, X_batch, Y_batch, op, color_inv) -> AbstractVerdict

Offloads batch demonstration verification to the Apple Silicon Metal GPU.
Emits `Incomplete(:metal_device_unavailable, ...)` if no functional Metal device is present.
"""
function NeuroARC.evaluate_batch_demos!(
    ::MetalBackend,
    X_batch::Array{UInt8, 3},
    Y_batch::Array{UInt8, 3},
    op::DihedralOp,
    color_inv::Bool = false
)::AbstractVerdict

    if !Metal.functional()
        return Incomplete(
            :metal_device_unavailable,
            "Metal.jl is loaded, but no functional Apple Silicon Metal GPU device is available."
        )
    end

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

    X_dev   = MtlArray(X_batch)
    Y_dev   = MtlArray(Y_batch)
    res_dev = Metal.zeros(Int32, H, W, K)

    threads_per_group = (min(H, 8), min(W, 8), min(K, 4))
    num_groups = (
        cld(H, threads_per_group[1]),
        cld(W, threads_per_group[2]),
        cld(K, threads_per_group[3])
    )

    flip_byte = op.flip ? 0x01 : 0x00
    inv_byte  = color_inv ? 0x01 : 0x00

    @metal threads=threads_per_group groups=num_groups metal_dihedral_residual_kernel!(
        res_dev, X_dev, Y_dev, Int32(H), Int32(W), Int32(K), op.k_rot, flip_byte, inv_byte
    )
    Metal.synchronize()

    res_host = Array(res_dev)
    any(r -> r == Int32(99), res_host) && return Rejected(
        :palette_token_violation, "Metal kernel detected palette token > 9.", [:membrane_palette_gate], 0.0
    )

    worst_residual = Float64(maximum(res_host))
    passed_pairs   = count(k -> maximum(@view res_host[:, :, k]) == Int32(0), 1:K)

    if worst_residual == 0.0
        return Accepted(
            (backend = :Metal, K_verified = K, max_residual = 0.0),
            (:metal_gpu_verified, :exact_reconstruction, :int32_kernel_clean),
            1.0,
            "Apple Silicon Metal GPU verified all $K/$K demonstration grids with 0.0 residual."
        )
    else
        partial = clamp(Float64(passed_pairs) / Float64(K), 0.0, 0.99)
        return Rejected(
            :train_reconstruction_residual,
            "Metal GPU batch failed exact reconstruction: $passed_pairs/$K matched (max residual = $worst_residual).",
            [:train_exact_reconstruction_gate],
            partial
        )
    end
end

end # module NeuroARCMetalExt
