# ==============================================================================
# File: benchmark_arc2.jl
# Multi-Backend ARC-AGI-2 Throughput Benchmark Suite
# ==============================================================================

using Random
using Printf
using NeuroARC
using NeuroARC.TransjectionCalculus: Accepted
using NeuroARC: AbstractExecutionBackend, CPUBackend, DihedralOp, evaluate_batch_demos!, extension_loaded

const HAS_METAL = Base.find_package("Metal") !== nothing
if HAS_METAL
    try
        @eval using Metal
    catch
    end
end

const HAS_JACC = Base.find_package("JACC") !== nothing
if HAS_JACC
    try
        @eval using JACC
    catch
    end
end

struct BenchmarkResult
    backend_name::Symbol
    batch_size::Int
    grid_dims::Tuple{Int, Int}
    elapsed_seconds::Float64
    bytes_allocated::Int
    status::Symbol
end

function run_arc2_benchmark_suite()::Vector{BenchmarkResult}
    results = BenchmarkResult[]

    grid_configs = [(10, 10), (20, 20), (30, 30)]
    batch_sizes  = [16, 64, 256, 1024]
    op           = DihedralOp(2, false) # 180-deg rotation

    active_backends = AbstractExecutionBackend[CPUBackend()]
    if extension_loaded(NeuroARC.MetalBackend())
        push!(active_backends, NeuroARC.MetalBackend())
    end
    if extension_loaded(NeuroARC.JACCBackend())
        push!(active_backends, NeuroARC.JACCBackend())
    end

    println("=== NeuroARC.jl Multi-Backend ARC-AGI-2 Benchmark Suite ===")
    println(rpad("Backend", 14), rpad("Grid (HxW)", 14), rpad("Batch (K)", 12), rpad("Time (ms)", 14), rpad("Throughput (grids/s)", 24), "Status")
    println("-"^88)

    rng = MersenneTwister(42)

    for (H, W) in grid_configs
        for K in batch_sizes
            X_batch = rand(rng, UInt8(0):UInt8(9), H, W, K)
            Y_batch = similar(X_batch)
            for k in 1:K
                Y_batch[:, :, k] .= UInt8(9) .- rot180(@view X_batch[:, :, k])
            end

            for backend in active_backends
                b_name = nameof(typeof(backend))
                evaluate_batch_demos!(backend, X_batch, Y_batch, op, true)

                t_start = time_ns()
                allocs = @allocated begin
                    verdict = evaluate_batch_demos!(backend, X_batch, Y_batch, op, true)
                end
                t_elapsed = Float64(time_ns() - t_start) / 1e9

                status_sym = verdict isa Accepted ? :VERIFIED : :FAILED
                throughput = round(K / max(t_elapsed, 1e-9), digits = 1)
                time_ms    = round(t_elapsed * 1000.0, digits = 3)

                push!(results, BenchmarkResult(b_name, K, (H, W), t_elapsed, allocs, status_sym))
                println(
                    rpad(string(b_name), 14),
                    rpad("$(H)x$(W)", 14),
                    rpad(string(K), 12),
                    rpad("$time_ms ms", 14),
                    rpad("$throughput /s", 24),
                    status_sym
                )
            end
        end
    end
    println("-"^88)
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_arc2_benchmark_suite()
end
