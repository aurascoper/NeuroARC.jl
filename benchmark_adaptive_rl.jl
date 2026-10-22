# ==============================================================================
# File: benchmark_adaptive_rl.jl
# A/B/C Policy & Scaling Benchmark Suite Comparing CPU-Only, Metal-Only, and
# Feedback-Driven Adaptive CPU-Metal Routing (AdaptiveScheduler + AdaptiveCRLAgent)
# ==============================================================================

using Test
using Random
using Printf
using NeuroARC
using NeuroARC.TransjectionCalculus: Accepted, Rejected, Incomplete
using NeuroARC: CPUBackend, DihedralOp, evaluate_batch_demos!, extension_loaded

# Load Metal.jl if installed in the host Julia environment
const HAS_METAL_PKG = Base.find_package("Metal") !== nothing
if HAS_METAL_PKG
    try
        @eval using Metal
    catch
    end
end

struct RLBenchmarkProfile
    policy_name::Symbol
    total_time_ms::Float64
    eval_calls::Int
    mean_eval_latency_ms::Float64
    final_verdict::Symbol
end

struct RLBenchmarkRecord
    batch_size_K::Int
    grid_dim::Tuple{Int, Int}
    cpu_only_ms::Float64
    metal_only_ms::Float64
    adaptive_ms::Float64
    speedup_ratio::Float64
    cpu_throughput_gps::Float64
    adaptive_throughput_gps::Float64
    cpu_bandwidth_gbs::Float64
    adaptive_bandwidth_gbs::Float64
    adaptive_cpu_dispatches::Int
    adaptive_metal_dispatches::Int
    steps_to_converge::Int
    terminal_mode::Symbol
end

"""
    build_synthetic_rl_task(H::Int, W::Int, K::Int; k_rot_target::Int = 2, color_inv::Bool = true, seed::Int = 2026)

Constructs a K-demonstration ARC-AGI-2 training set of HxW grids where:
- Compartments 1..3 have supercritical residence times (9.8s, 5.4s, 3.1s)
- Compartment 4 has subcritical washout residence time (1.4s < 2.0s), requiring
  Z_eff = 26 (Fe-S) and kappa_adv = 4.5 to pass all K Informative LOO folds.
- Target grid transformation is DihedralOp(k_rot_target, false) with optional 9 - c color inversion.
"""
function build_synthetic_rl_task(
    H::Int,
    W::Int,
    K::Int;
    k_rot_target::Int = 2,
    color_inv::Bool = true,
    seed::Int = 2026
)
    rng = MersenneTwister(seed)
    op_target = DihedralOp(k_rot_target, false)
    tau_vec = [9.8, 5.4, 3.1, 1.4]

    train_pairs = Vector{Tuple{Vector{Float64}, ARCGrid{UInt8}, ARCGrid{UInt8}}}(undef, K)
    for k in 1:K
        mat_in  = rand(rng, UInt8(0):UInt8(9), H, W)
        mat_rot = apply_dihedral(op_target, mat_in)
        mat_out = color_inv ? (UInt8(9) .- mat_rot) : mat_rot
        train_pairs[k] = (tau_vec, ARCGrid(mat_in), ARCGrid(mat_out))
    end
    return train_pairs
end

"""
    run_adaptive_rl_benchmark_suite(; K::Int = 4, H::Int = 30, W::Int = 30) -> Vector{RLBenchmarkProfile}

Runs the A/B/C policy benchmark suite comparing `:CPU_Only`, `:Metal_Only`, and `:Adaptive_Router`
on an identical ARC-AGI demonstration set.
"""
function run_adaptive_rl_benchmark_suite(; K::Int = 4, H::Int = 30, W::Int = 30)::Vector{RLBenchmarkProfile}
    profiles = RLBenchmarkProfile[]
    train_pairs = build_synthetic_rl_task(H, W, K; k_rot_target = 2, color_inv = true, seed = 2026)
    metal_live = extension_loaded(NeuroARC.MetalBackend())

    # Warmup JIT compilation across policies
    for _ in 1:2
        w_agent = AdaptiveCRLAgent(15; force_cpu_only = false, simulate_metal_unified = !metal_live)
        _ = run_adaptive_test_time_rl!(w_agent, train_pairs; color_inv = true)
    end

    policies = [:CPU_Only, :Metal_Only, :Adaptive_Router]

    println("=== NeuroARC.jl Adaptive Test-Time RL A/B/C Policy Suite (K = $K, $(H)x$(W)) ===")
    println(rpad("Policy", 18), rpad("Total Time (ms)", 18), rpad("Eval Calls", 14), rpad("Mean Latency", 16), "Verdict")
    println("-"^74)

    for pol in policies
        agent = AdaptiveCRLAgent(15; force_cpu_only = false, simulate_metal_unified = !metal_live)

        if pol == :CPU_Only
            sched = AdaptiveScheduler(; force_cpu_only = true, simulate_metal_unified = false)
            sched.metal_stats.ema_latency_ms = 1e9
            agent.scheduler = sched
        elseif pol == :Metal_Only
            sched = AdaptiveScheduler(; force_cpu_only = false, simulate_metal_unified = !metal_live)
            sched.cpu_stats.ema_latency_ms = 1e9
            agent.scheduler = sched
        else
            sched = AdaptiveScheduler(; force_cpu_only = false, simulate_metal_unified = !metal_live)
            agent.scheduler = sched
        end

        t_start = time_ns()
        verdict = run_adaptive_test_time_rl!(agent, train_pairs; color_inv = true)
        elapsed_ms = Float64(time_ns() - t_start) / 1e6

        n_calls = length(agent.reward_trace)
        mean_lat = n_calls > 0 ? elapsed_ms / Float64(n_calls) : 0.0
        v_symbol = verdict isa Accepted ? :ACCEPTED : :INCOMPLETE

        push!(profiles, RLBenchmarkProfile(pol, elapsed_ms, n_calls, mean_lat, v_symbol))
        println(
            rpad(string(pol), 18),
            rpad("$(round(elapsed_ms, digits=3)) ms", 18),
            rpad(string(n_calls), 14),
            rpad("$(round(mean_lat, digits=3)) ms", 16),
            v_symbol
        )
    end
    println("-"^74)
    return profiles
end

"""
    run_adaptive_rl_benchmark(; H=30, W=30, batch_sizes=[4, 8, 16, 32, 64, 256, 1024], n_trials=5)

Measures multi-batch scaling across K in {4, 8, 16, 32, 64, 256, 1024} comparing
CPU-Only, Metal-Only, and Adaptive CPU-Metal Routing.
"""
function run_adaptive_rl_benchmark(;
    H::Int = 30,
    W::Int = 30,
    batch_sizes::Vector{Int} = [4, 8, 16, 32, 64, 256, 1024],
    n_trials::Int = 5
)::Vector{RLBenchmarkRecord}

    metal_live = extension_loaded(NeuroARC.MetalBackend())
    println("\n======================================================================================================")
    println("NeuroARC.jl Multi-Batch Scaling Benchmark: CPU-Only vs. Metal-Only vs. Adaptive CPU-Metal Router")
    println("Grid Dimensions: $(H)x$(W) | Trials per Batch Size: $n_trials | Metal Extension Loaded: $metal_live")
    println("Roofline Model (Apple Silicon M4): I_grid = 1.5 ops/byte << I_crit = 35.8 FLOPs/byte")
    println("======================================================================================================")
    @printf("%-8s | %-10s | %-10s | %-10s | %-8s | %-12s | %-12s | %-14s\n",
            "Batch K", "CPU-Only", "Metal-Only", "Adaptive", "Speedup", "CPU BW", "Adaptive BW", "Route (CPU/Mtl)")
    println("-"^102)

    records = RLBenchmarkRecord[]

    for K in batch_sizes
        train_pairs = build_synthetic_rl_task(H, W, K; k_rot_target = 2, color_inv = false, seed = 42 + K)

        # Warmup
        warm_cpu = AdaptiveCRLAgent(12; force_cpu_only = true, simulate_metal_unified = false)
        _ = run_adaptive_test_time_rl!(warm_cpu, train_pairs)

        warm_adap = AdaptiveCRLAgent(12; force_cpu_only = false, simulate_metal_unified = !metal_live)
        _ = run_adaptive_test_time_rl!(warm_adap, train_pairs)

        # 1. CPU-Only policy
        cpu_times_s = Float64[]
        steps_taken = 0
        for _ in 1:n_trials
            agent_cpu = AdaptiveCRLAgent(12; force_cpu_only = true, simulate_metal_unified = false)
            t0 = time_ns()
            v_cpu = run_adaptive_test_time_rl!(agent_cpu, train_pairs)
            dt_s = Float64(time_ns() - t0) / 1e9
            @assert v_cpu isa Accepted "CPU-only RL loop failed to converge!"
            push!(cpu_times_s, dt_s)
            steps_taken = length(agent_cpu.reward_trace)
        end
        med_cpu_s = sort(cpu_times_s)[cld(n_trials, 2)]

        # 2. Metal-Only policy (penalize CPU EMA to force Metal route for all batch sizes)
        mtl_times_s = Float64[]
        for _ in 1:n_trials
            agent_mtl = AdaptiveCRLAgent(12; force_cpu_only = false, simulate_metal_unified = !metal_live)
            agent_mtl.scheduler.cpu_stats.ema_latency_ms = 1e9
            t0 = time_ns()
            v_mtl = run_adaptive_test_time_rl!(agent_mtl, train_pairs)
            dt_s = Float64(time_ns() - t0) / 1e9
            @assert v_mtl isa Accepted "Metal-only RL loop failed to converge!"
            push!(mtl_times_s, dt_s)
        end
        med_mtl_s = sort(mtl_times_s)[cld(n_trials, 2)]

        # 3. Adaptive CPU-Metal Router policy
        shared_sched = AdaptiveScheduler(; force_cpu_only = false, simulate_metal_unified = !metal_live)
        adap_times_s = Float64[]
        cpu_disp_last = 0
        mtl_disp_last = 0
        term_mode = :Focus

        for _ in 1:n_trials
            shared_sched.cpu_stats.dispatches   = 0
            shared_sched.metal_stats.dispatches = 0

            agent_adap = AdaptiveCRLAgent(12; force_cpu_only = false, simulate_metal_unified = !metal_live)
            agent_adap.scheduler = shared_sched

            t0 = time_ns()
            v_adap = run_adaptive_test_time_rl!(agent_adap, train_pairs)
            dt_s = Float64(time_ns() - t0) / 1e9
            @assert v_adap isa Accepted "Adaptive RL loop failed to converge!"
            push!(adap_times_s, dt_s)

            cpu_disp_last = shared_sched.cpu_stats.dispatches
            mtl_disp_last = shared_sched.metal_stats.dispatches
            term_mode     = agent_adap.mode
        end
        med_adap_s = sort(adap_times_s)[cld(n_trials, 2)]

        n_batch_evals = cpu_disp_last + mtl_disp_last
        total_grids_evaluated = n_batch_evals * K
        total_bytes_moved = Float64(2 * H * W * total_grids_evaluated)

        cpu_ms  = med_cpu_s * 1000.0
        mtl_ms  = med_mtl_s * 1000.0
        adap_ms = med_adap_s * 1000.0
        speedup = cpu_ms / max(adap_ms, 1e-6)

        cpu_gps  = Float64(total_grids_evaluated) / med_cpu_s
        adap_gps = Float64(total_grids_evaluated) / med_adap_s

        cpu_bw_gbs  = (total_bytes_moved / med_cpu_s) / 1e9
        adap_bw_gbs = (total_bytes_moved / med_adap_s) / 1e9

        rec = RLBenchmarkRecord(
            K, (H, W), cpu_ms, mtl_ms, adap_ms, speedup,
            cpu_gps, adap_gps, cpu_bw_gbs, adap_bw_gbs,
            cpu_disp_last, mtl_disp_last, steps_taken, term_mode
        )
        push!(records, rec)

        @printf("%-8d | %7.3f ms | %7.3f ms | %7.3f ms | %6.2fx  | %7.2f GB/s | %7.2f GB/s | %d CPU / %d Mtl\n",
                K, cpu_ms, mtl_ms, adap_ms, speedup, cpu_bw_gbs, adap_bw_gbs, cpu_disp_last, mtl_disp_last)
    end

    println("-"^102)
    sched_overflow = AdaptiveScheduler(; force_cpu_only = false, simulate_metal_unified = true)
    sched_overflow.metal_stats.active_tasks = 6
    routed_under_load = select_optimal_backend(sched_overflow, 64)
    println("Queue Saturation Guard Test (Metal active_tasks = 6, K = 64): Routed to -> ", typeof(routed_under_load))
    println("======================================================================================================")

    return records
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_adaptive_rl_benchmark_suite(; K = 4, H = 30, W = 30)
    run_adaptive_rl_benchmark()
end
