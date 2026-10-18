module TestTransjection

# ==============================================================================
# NeuroARC.jl - Transjection Calculus Test Suite
# ==============================================================================

using Test
using NeuroARC
using NeuroARC.TransjectionCalculus

println("================================================================================")
println("Running Transjection Calculus & Logic Gates Test Suite in Julia $(VERSION)")
println("================================================================================")

@testset "1. Criterial Logic Gates Evaluation" begin
    # Threshold Gate
    g_thresh = ThresholdGate("MinArea", x -> sum(x), 5.0)
    p1, s1, m1 = evaluate_gate(g_thresh, [2.0, 4.0])
    @test p1 == true
    @test s1 == 6.0
    p2, s2, m2 = evaluate_gate(g_thresh, [1.0, 2.0])
    @test p2 == false
    @test s2 == 3.0

    # Bandpass Gate
    g_band = BandpassGate("DimensionLimit", x -> length(x), 2, 5)
    @test evaluate_gate(g_band, [1, 2, 3])[1] == true
    @test evaluate_gate(g_band, [1])[1] == false
    @test evaluate_gate(g_band, [1, 2, 3, 4, 5, 6])[1] == false

    # Subtype Gate
    g_sub_valid = SubtypeGate("SubtypeIntReal", Int, Real)
    g_sub_invalid = SubtypeGate("SubtypeRealInt", Real, Int)
    @test evaluate_gate(g_sub_valid, nothing)[1] == true
    @test evaluate_gate(g_sub_invalid, nothing)[1] == false

    # Conjunction Gate (AND)
    g_conj = ConjunctionGate("ValidPolyomino", [
        ThresholdGate("MinSize", x -> length(x), 3),
        BandpassGate("ValueRange", x -> maximum(x), 1, 9)
    ])
    @test evaluate_gate(g_conj, [2, 4, 5])[1] == true
    @test evaluate_gate(g_conj, [2, 4])[1] == false # fails MinSize
    @test evaluate_gate(g_conj, [2, 4, 15])[1] == false # fails ValueRange

    # Disjunction Gate (OR)
    g_disj = DisjunctionGate("ColorOrShape", [
        ThresholdGate("HasHighVal", x -> maximum(x), 8),
        ThresholdGate("LongVector", x -> length(x), 10)
    ])
    @test evaluate_gate(g_disj, [9, 1])[1] == true # matches first
    @test evaluate_gate(g_disj, ones(10))[1] == true # matches second
    @test evaluate_gate(g_disj, [1, 2])[1] == false # fails both

    # K-of-N Gate
    g_kofn = KOfNGate("TwoOfThree", [
        ThresholdGate("G1", x -> x[1], 5),
        ThresholdGate("G2", x -> x[2], 5),
        ThresholdGate("G3", x -> x[3], 5)
    ], 2)
    @test evaluate_gate(g_kofn, [6, 7, 2])[1] == true # 2 of 3
    @test evaluate_gate(g_kofn, [6, 7, 8])[1] == true # 3 of 3
    @test evaluate_gate(g_kofn, [6, 1, 2])[1] == false # 1 of 3
end

@testset "2. Topological Morphology & Invariants" begin
    # Create test grid with a single solid square (Euler chi = 1)
    grid_square = zeros(Int, 6, 6)
    grid_square[2:4, 2:4] .= 1 # 3x3 solid block
    
    prof_sq = compute_morphology(grid_square)
    @test prof_sq.height == 6
    @test prof_sq.width == 6
    @test prof_sq.area == 9
    @test prof_sq.perimeter == 12 # 3 * 4 edges
    @test prof_sq.num_components == 1
    # Euler characteristic for solid square without holes is 1
    @test prof_sq.euler_characteristic == 1

    # Create an annular donut (ring with 1 hole, Euler chi = 0)
    grid_donut = zeros(Int, 5, 5)
    grid_donut[2:4, 2:4] .= 2
    grid_donut[3, 3] = 0 # 1 hole in center
    
    prof_donut = compute_morphology(grid_donut)
    @test prof_donut.area == 8
    @test prof_donut.num_components == 1
    @test prof_donut.euler_characteristic == 0 # 1 component - 1 hole = 0

    # Two disjoint components
    grid_disjoint = zeros(Int, 5, 5)
    grid_disjoint[1:2, 1:2] .= 3
    grid_disjoint[4:5, 4:5] .= 4
    prof_disj = compute_morphology(grid_disjoint)
    @test prof_disj.num_components == 2
    @test prof_disj.euler_characteristic == 2
end

@testset "3. Transjection Operator & Non-Injectivity Proof" begin
    # Setup projection and empowerment
    proj = [1.0 0.0 0.0; 0.0 1.0 0.0] # project 3 features (area, perim, chi) to 2
    weights = [2.0, 1.5]
    emp = EmpowermentOperator(weights, proj, 50)
    
    # Gate requires Euler characteristic == 1 (topological disk, 0 holes)
    gate = ThresholdGate("DiskTopology", g -> compute_morphology(g).euler_characteristic, 1)
    
    feature_fn = g -> begin
        p = compute_morphology(g)
        return [Float64(p.area), Float64(p.perimeter), Float64(p.euler_characteristic)]
    end
    
    op = TransjectionOperator(gate, emp, feature_fn, 1)

    # Test grid A: 2x2 square in top-left
    gridA = zeros(Int, 6, 6)
    gridA[1:2, 1:2] .= 1
    
    # Test grid B: 2x2 square in bottom-right (translated)
    gridB = zeros(Int, 6, 6)
    gridB[5:6, 5:6] .= 1

    verdictA = transject(op, gridA)
    verdictB = transject(op, gridB)

    @test verdictA isa Accepted
    @test verdictB isa Accepted

    # Mathematical Non-Injectivity Proof:
    # Distinct grid states gridA != gridB collapse to IDENTICAL salient features
    @test gridA != gridB
    @test verdictA.salient_features == verdictB.salient_features
    @test verdictA.empowerment_score == verdictB.empowerment_score

    # Rejected grid: annular donut with hole (chi = 0 < 1)
    grid_hole = zeros(Int, 5, 5)
    grid_hole[2:4, 2:4] .= 1
    grid_hole[3, 3] = 0
    verdict_hole = transject(op, grid_hole)
    @test verdict_hole isa Rejected
    @test verdict_hole.reason == :criteria_failed
end

@testset "4. Sequential Transjection Composition" begin
    proj = [1.0 0.0; 0.0 1.0]
    emp = EmpowermentOperator([1.0, 1.0], proj, 10)
    
    # Gate 1: Area at least 4
    op1 = TransjectionOperator(
        ThresholdGate("MinArea", g -> compute_morphology(g).area, 4),
        emp,
        g -> [Float64(compute_morphology(g).area), Float64(compute_morphology(g).perimeter)],
        1
    )
    
    # Gate 2: Perimeter at most 16
    op2 = TransjectionOperator(
        BandpassGate("MaxPerimeter", g -> compute_morphology(g).perimeter, 0, 16),
        emp,
        g -> [Float64(compute_morphology(g).area), Float64(compute_morphology(g).perimeter)],
        2
    )

    composed = compose_transjections(op2, op1)

    # Valid grid: 2x2 square (area=4, perim=8)
    good_grid = zeros(Int, 5, 5)
    good_grid[2:3, 2:3] .= 5
    res_good = composed(good_grid)
    @test res_good isa Accepted

    # Fails gate 1: 1x1 pixel (area=1 < 4)
    small_grid = zeros(Int, 5, 5)
    small_grid[1, 1] = 5
    res_small = composed(small_grid)
    @test res_small isa Rejected
    @test occursin("MinArea", res_small.detail)
end

@testset "5. Pedagogical Scaffolding State Transitions" begin
    controller = ScaffoldController(500)
    @test controller.state == TransjectionCalculus.Focus
    @test controller.active_tolerance == 1.0

    # 3 consecutive rejections -> Still Focus
    s1 = update_scaffold_state!(controller, 3)
    @test s1 == TransjectionCalculus.Focus

    # 6 consecutive rejections -> Frustration (widened search)
    s2 = update_scaffold_state!(controller, 6)
    @test s2 == TransjectionCalculus.Frustration
    @test controller.active_tolerance == 1.5

    # 15 consecutive rejections -> Panic (drastic threshold relaxation)
    s3 = update_scaffold_state!(controller, 15)
    @test s3 == TransjectionCalculus.Panic
    @test controller.active_tolerance == 2.5

    # Recovery after success
    s4 = update_scaffold_state!(controller, 0)
    @test s4 == TransjectionCalculus.Focus
    @test controller.active_tolerance == 1.0
end

println("All Transjection Calculus and Logic Gates tests passed successfully!")


end # module TestTransjection
