# ==============================================================================
# File: benchmark_bandwidth.jl
# Effective Memory Bandwidth (GB/s) & Roofline Profiler for NeuroARC.jl
# ==============================================================================

using Random
using Printf
using NeuroARC
using NeuroARC.TransjectionCalculus: Accepted
using NeuroARC: AbstractExecutionBackend, CPUBackend, DihedralOp, evaluate_batch_demos!, extension_loaded

const HAS_METAL_BW = Base.find_package("Metal") !== nothing
if HAS_METAL_BW
    try
        @eval using Metal
    catch
    end
end

struct BandwidthProfile
    backend_name::Symbol
    grid_dims::Tuple{Int, Int}
    batch_size_K::Int
    median_time_ms::Float64
    effective_bandwidth_gbs::Float64
    throughput_grids_per_sec::Float64
end

function run_bandwidth_profiler()::Vector{BandwidthProfile}
    profiles = BandwidthProfile[]
    H, W = 30, 30
    batch_sizes = [16, 64, 256, 1024]
    op = DihedralOp(2, false)
    n_trials = 5
    rng = MersenneTwister(2026)

    backends = AbstractExecutionBackend[CPUBackend()]
    if extension_loaded(NeuroARC.MetalBackend())
        push!(backends, NeuroARC.MetalBackend())
    end

    println("=== NeuroARC.jl Memory Bandwidth & Roofline Profiler (30x30 Grids) ===")
    @printf("%-14s | %-10s | %-12s | %-14s | %-18s\n",
            "Backend", "Batch K", "Median Time", "Eff. Bandwidth", "Throughput")
    println("-"^78)

    for K in batch_sizes
        X_batch = rand(rng, UInt8(0):UInt8(9), H, W, K)
        Y_batch = similar(X_batch)
        for k in 1:K
            Y_batch[:, :, k] .= UInt8(9) .- rot180(@view X_batch[:, :, k])
        end
        bytes_moved = Float64(2 * H * W * K)

        for b in backends
            b_name = nameof(typeof(b))
            evaluate_batch_demos!(b, X_batch, Y_batch, op, true)

            times_s = Float64[]
            for _ in 1:n_trials
                t0 = time_ns()
                v = evaluate_batch_demos!(b, X_batch, Y_batch, op, true)
                dt = Float64(time_ns() - t0) / 1e9
                @assert v isa Accepted
                push!(times_s, dt)
            end
            med_s = sort(times_s)[cld(n_trials, 2)]
            med_ms = med_s * 1000.0
            bw_gbs = (bytes_moved / med_s) / 1e9
            gps    = Float64(K) / med_s

            push!(profiles, BandwidthProfile(b_name, (H, W), K, med_ms, bw_gbs, gps))
            @printf("%-14s | %-10d | %9.3f ms | %9.3f GB/s | %12.1f grids/s\n",
                    string(b_name), K, med_ms, bw_gbs, gps)
        end
    end
    println("-"^78)
    return profiles
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_bandwidth_profiler()
end
