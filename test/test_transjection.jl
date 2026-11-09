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

@testset "6. Constructive Evidence Certificate Hierarchy & Gate Evaluation" begin
    @test Witness <: EvidenceStatus
    @test Refutation <: EvidenceStatus
    @test Unresolved <: EvidenceStatus

    # ThresholdGate constructive evaluation
    g_thresh = ThresholdGate("MinArea", x -> sum(x), 5.0)
    ev_pass = evaluate_gate_constructive(g_thresh, [2.0, 4.0]; proposition=:min_area_prop)
    @test ev_pass isa Witness{Symbol}
    @test ev_pass.proposition == :min_area_prop
    @test ev_pass.certificate.measured_value == 6.0
    @test ev_pass.certificate.threshold == 5.0
    @test verify_evidence_certificate(ev_pass) == true

    # Boundary equality on ThresholdGate (val == threshold -> Witness)
    ev_boundary = evaluate_gate_constructive(g_thresh, [2.0, 3.0]; proposition=:boundary_prop)
    @test ev_boundary isa Witness{Symbol}
    @test ev_boundary.certificate.margin == 0.0
    @test verify_evidence_certificate(ev_boundary) == true

    ev_fail = evaluate_gate_constructive(g_thresh, [1.0, 2.0]; proposition=:min_area_prop)
    @test ev_fail isa Refutation{Symbol}
    @test ev_fail.proposition == :min_area_prop
    @test ev_fail.countercertificate.measured_value == 3.0
    @test ev_fail.countercertificate.deficit == 2.0
    @test verify_evidence_certificate(ev_fail) == true

    # Critical Invariant: Unavailable prerequisites MUST produce Unresolved{T} and NEVER Refutation{T},
    # even when the input [1.0, 2.0] would otherwise fail the threshold!
    ev_unres = evaluate_gate_constructive(
        g_thresh,
        [1.0, 2.0];
        prerequisites=[:d8_symmetry_anchor, :calibration_table],
        available_prerequisites=[:d8_symmetry_anchor],
        proposition=:min_area_prop
    )
    @test ev_unres isa Unresolved{Symbol}
    @test !(ev_unres isa Refutation)
    @test ev_unres.proposition == :min_area_prop
    @test ev_unres.missing_prerequisites == [:calibration_table]
    @test verify_evidence_certificate(ev_unres) == true

    # BandpassGate constructive evaluation
    g_band = BandpassGate("DimBand", x -> length(x), 2, 4)
    ev_band_ok = evaluate_gate_constructive(g_band, [10, 20, 30])
    @test ev_band_ok isa Witness{String}
    @test verify_evidence_certificate(ev_band_ok) == true

    ev_band_low = evaluate_gate_constructive(g_band, [10])
    @test ev_band_low isa Refutation{String}
    @test ev_band_low.countercertificate.violation == :below_low
    @test verify_evidence_certificate(ev_band_low) == true

    ev_band_high = evaluate_gate_constructive(g_band, [1, 2, 3, 4, 5])
    @test ev_band_high isa Refutation{String}
    @test ev_band_high.countercertificate.violation == :above_high
    @test verify_evidence_certificate(ev_band_high) == true

    ev_band_unres = evaluate_gate_constructive(
        g_band,
        [1];
        prerequisites=[:grid_loaded],
        available_prerequisites=Symbol[]
    )
    @test ev_band_unres isa Unresolved{String}
    @test !(ev_band_unres isa Refutation)
    @test ev_band_unres.missing_prerequisites == [:grid_loaded]

    # SubtypeGate constructive evaluation
    g_sub_ok = SubtypeGate("PolySubtype", BoundedPolyomino, AbstractPolyomino)
    ev_sub_ok = evaluate_gate_constructive(g_sub_ok, nothing; proposition=:subtype_ok)
    @test ev_sub_ok isa Witness{Symbol}
    @test ev_sub_ok.certificate.out_type == BoundedPolyomino
    @test ev_sub_ok.certificate.in_type == AbstractPolyomino
    @test verify_evidence_certificate(ev_sub_ok) == true

    g_sub_bad = SubtypeGate("BadSubtype", AbstractGridArtifact, BoundedPolyomino)
    ev_sub_bad = evaluate_gate_constructive(g_sub_bad, nothing; proposition=:subtype_bad)
    @test ev_sub_bad isa Refutation{Symbol}
    @test verify_evidence_certificate(ev_sub_bad) == true

    # ConjunctionGate constructive evaluation
    g_conj = ConjunctionGate("ConjGate", [
        ThresholdGate("MinLen", x -> length(x), 3),
        BandpassGate("MaxVal", x -> maximum(x), 1, 9)
    ])
    ev_conj_ok = evaluate_gate_constructive(g_conj, [2, 4, 6])
    @test ev_conj_ok isa Witness
    @test length(ev_conj_ok.certificate.child_certificates) == 2
    @test verify_evidence_certificate(ev_conj_ok) == true

    ev_conj_fail = evaluate_gate_constructive(g_conj, [2, 15, 6])
    @test ev_conj_fail isa Refutation
    @test ev_conj_fail.countercertificate.failed_indices == [2]
    @test verify_evidence_certificate(ev_conj_fail) == true

    # DisjunctionGate constructive evaluation
    g_disj = DisjunctionGate("DisjGate", [
        ThresholdGate("BranchLeft", x -> maximum(x), 8),
        ThresholdGate("BranchRight", x -> length(x), 4)
    ])
    ev_disj_left = evaluate_gate_constructive(g_disj, [9, 1])
    @test ev_disj_left isa Witness
    @test ev_disj_left.certificate.injection == :left
    @test verify_evidence_certificate(ev_disj_left) == true

    ev_disj_right = evaluate_gate_constructive(g_disj, [1, 2, 3, 4])
    @test ev_disj_right isa Witness
    @test ev_disj_right.certificate.injection == :right
    @test verify_evidence_certificate(ev_disj_right) == true

    ev_disj_fail = evaluate_gate_constructive(g_disj, [1, 2])
    @test ev_disj_fail isa Refutation
    @test length(ev_disj_fail.countercertificate.failed_countercertificates) == 2
    @test verify_evidence_certificate(ev_disj_fail) == true

    # KOfNGate constructive evaluation
    g_kofn = KOfNGate("TwoOfThree", [
        ThresholdGate("G1", x -> x[1], 5),
        ThresholdGate("G2", x -> x[2], 5),
        ThresholdGate("G3", x -> x[3], 5)
    ], 2)
    ev_kofn_ok = evaluate_gate_constructive(g_kofn, [6, 7, 1])
    @test ev_kofn_ok isa Witness
    @test ev_kofn_ok.certificate.passed_count == 2
    @test ev_kofn_ok.certificate.witness_indices == [1, 2]
    @test verify_evidence_certificate(ev_kofn_ok) == true

    ev_kofn_fail = evaluate_gate_constructive(g_kofn, [6, 1, 2])
    @test ev_kofn_fail isa Refutation
    @test ev_kofn_fail.countercertificate.refuted_count == 2
    @test ev_kofn_fail.countercertificate.failed_indices == [2, 3]
    @test verify_evidence_certificate(ev_kofn_fail) == true
end

@testset "7. BHK Constructive Combinators, Tamper Detection & Verdict Bridges" begin
    g1 = ThresholdGate("G1", x -> x, 5.0)
    g2 = ThresholdGate("G2", x -> x, 10.0)

    w1 = evaluate_gate_constructive(g1, 7.0; proposition=:P1)
    r1 = evaluate_gate_constructive(g1, 2.0; proposition=:P1)
    u1 = evaluate_gate_constructive(g1, 2.0; prerequisites=[:prereq_a], available_prerequisites=Symbol[], proposition=:P1)

    w2 = evaluate_gate_constructive(g2, 12.0; proposition=:P2)
    r2 = evaluate_gate_constructive(g2, 4.0; proposition=:P2)
    u2 = evaluate_gate_constructive(g2, 4.0; prerequisites=[:prereq_b], available_prerequisites=Symbol[], proposition=:P2)

    # BHK Conjunction 3x3 table
    c_ww = conjunction_evidence(w1, w2)
    @test c_ww isa Witness{Tuple{Symbol, Symbol}}
    @test c_ww.certificate.left == w1.certificate
    @test c_ww.certificate.right == w2.certificate
    @test verify_evidence_certificate(c_ww) == true

    c_wr = conjunction_evidence(w1, r2)
    @test c_wr isa Refutation
    @test c_wr.countercertificate.failed_branch == :right
    @test verify_evidence_certificate(c_wr) == true

    c_rw = conjunction_evidence(r1, w2)
    @test c_rw isa Refutation
    @test c_rw.countercertificate.failed_branch == :left
    @test verify_evidence_certificate(c_rw) == true

    c_rr = conjunction_evidence(r1, r2)
    @test c_rr isa Refutation
    @test c_rr.countercertificate.failed_branch == :both
    @test verify_evidence_certificate(c_rr) == true

    c_ur = conjunction_evidence(u1, r2)
    @test c_ur isa Refutation
    @test verify_evidence_certificate(c_ur) == true

    c_ru = conjunction_evidence(r1, u2)
    @test c_ru isa Refutation
    @test verify_evidence_certificate(c_ru) == true

    # Neither is Refutation and at least one is Unresolved -> Unresolved (NEVER Refutation)
    c_wu = conjunction_evidence(w1, u2)
    @test c_wu isa Unresolved
    @test !(c_wu isa Refutation)
    @test c_wu.missing_prerequisites == [:prereq_b]
    @test verify_evidence_certificate(c_wu) == true

    c_uw = conjunction_evidence(u1, w2)
    @test c_uw isa Unresolved
    @test !(c_uw isa Refutation)
    @test c_uw.missing_prerequisites == [:prereq_a]
    @test verify_evidence_certificate(c_uw) == true

    c_uu = conjunction_evidence(u1, u2)
    @test c_uu isa Unresolved
    @test !(c_uu isa Refutation)
    @test c_uu.missing_prerequisites == [:prereq_a, :prereq_b]
    @test verify_evidence_certificate(c_uu) == true

    # BHK Disjunction 3x3 table
    d_ww = disjunction_evidence(w1, w2)
    @test d_ww isa Witness
    @test d_ww.certificate.injection == :left
    @test verify_evidence_certificate(d_ww) == true

    d_wr = disjunction_evidence(w1, r2)
    @test d_wr isa Witness
    @test d_wr.certificate.injection == :left
    @test verify_evidence_certificate(d_wr) == true

    d_wu = disjunction_evidence(w1, u2)
    @test d_wu isa Witness
    @test d_wu.certificate.injection == :left
    @test verify_evidence_certificate(d_wu) == true

    d_rw = disjunction_evidence(r1, w2)
    @test d_rw isa Witness
    @test d_rw.certificate.injection == :right
    @test verify_evidence_certificate(d_rw) == true

    d_uw = disjunction_evidence(u1, w2)
    @test d_uw isa Witness
    @test d_uw.certificate.injection == :right
    @test verify_evidence_certificate(d_uw) == true

    d_rr = disjunction_evidence(r1, r2)
    @test d_rr isa Refutation
    @test d_rr.countercertificate.left == r1.countercertificate
    @test d_rr.countercertificate.right == r2.countercertificate
    @test verify_evidence_certificate(d_rr) == true

    # Disjunction with one Refutation and one Unresolved MUST be Unresolved (NOT Refutation!)
    d_ru = disjunction_evidence(r1, u2)
    @test d_ru isa Unresolved
    @test !(d_ru isa Refutation)
    @test d_ru.missing_prerequisites == [:prereq_b]

    d_ur = disjunction_evidence(u1, r2)
    @test d_ur isa Unresolved
    @test !(d_ur isa Refutation)
    @test d_ur.missing_prerequisites == [:prereq_a]

    d_uu = disjunction_evidence(u1, u2)
    @test d_uu isa Unresolved
    @test d_uu.missing_prerequisites == [:prereq_a, :prereq_b]

    # Type-level and construction-time proof-term enforcement:
    # Witness{T, C <: AbstractProofTerm} and Refutation{T, C <: AbstractRefutationTerm}
    # must NOT use an unguarded `::Any` field and must reject unverified or mismatched payloads at construction time.
    @test AbstractProofTerm <: AbstractCertificate
    @test AbstractRefutationTerm <: AbstractCertificate
    @test StructuredProofTerm <: AbstractProofTerm
    @test StructuredRefutationTerm <: AbstractRefutationTerm
    @test fieldtype(Witness, :certificate) == AbstractProofTerm
    @test fieldtype(Refutation, :countercertificate) == AbstractRefutationTerm
    @test w1.certificate isa AbstractProofTerm
    @test r1.countercertificate isa AbstractRefutationTerm

    # Unguarded primitives ("Boolean wearing a costume" / nothing / sentinels / empty collections)
    # MUST throw ArgumentError at construction time:
    @test_throws ArgumentError Witness(:prop, nothing)
    @test_throws ArgumentError Witness(:prop, missing)
    @test_throws ArgumentError Witness(:prop, true)
    @test_throws ArgumentError Witness(:prop, false)
    @test_throws ArgumentError Witness(:prop, -1.0)
    @test_throws ArgumentError Witness(:prop, 1.0)
    @test_throws ArgumentError Witness(:prop, "")
    @test_throws ArgumentError Witness(:prop, Int[])
    @test_throws ArgumentError Witness(:prop, ())
    @test_throws ArgumentError Witness(:prop, (verified = true,))
    @test_throws ArgumentError Witness(:prop, (arbitrary_key = 42,))

    @test_throws ArgumentError Refutation(:prop, nothing)
    @test_throws ArgumentError Refutation(:prop, missing)
    @test_throws ArgumentError Refutation(:prop, true)
    @test_throws ArgumentError Refutation(:prop, false)
    @test_throws ArgumentError Refutation(:prop, -1.0)
    @test_throws ArgumentError Refutation(:prop, "")
    @test_throws ArgumentError Refutation(:prop, ())
    @test_throws ArgumentError Refutation(:prop, (refuted = true,))
    @test_throws ArgumentError Refutation(:prop, (arbitrary_key = 42,))

    @test_throws ArgumentError Unresolved(:empty_prereq, Symbol[])
    @test_throws ArgumentError Unresolved(:empty_sym, [Symbol("")])

    # Forged and mismatched certificates MUST throw ArgumentError at construction time
    # AND evaluate to false under check_proof_term / check_refutation_term / verify_evidence_certificate:
    forged_w_payload = (gate_type = :threshold, gate_name = "G", measured_value = 2.0, threshold = 5.0)
    @test check_proof_term(:forged, forged_w_payload) == false
    @test verify_evidence_certificate(:forged, forged_w_payload) == false
    @test_throws ArgumentError Witness(:forged, forged_w_payload)

    forged_r_payload = (gate_type = :threshold, gate_name = "G", measured_value = 8.0, threshold = 5.0)
    @test check_refutation_term(:forged, forged_r_payload) == false
    @test_throws ArgumentError Refutation(:forged, forged_r_payload)

    forged_sub_payload = (gate_type = :subtype, out_type = Real, in_type = Int)
    @test check_proof_term(:forged_sub, forged_sub_payload) == false
    @test_throws ArgumentError Witness(:forged_sub, forged_sub_payload)

    # Proposition mismatch: w1.certificate proves :P1, so binding it to :P2 must fail at construction time
    @test check_proof_term(:P1, w1.certificate) == true
    @test check_proof_term(:P2, w1.certificate) == false
    @test_throws ArgumentError Witness(:P2, w1.certificate)

    # Proposition mismatch on Refutation: r1.countercertificate refutes :P1, not :P2
    @test check_refutation_term(:P1, r1.countercertificate) == true
    @test check_refutation_term(:P2, r1.countercertificate) == false
    @test_throws ArgumentError Refutation(:P2, r1.countercertificate)

    # Polarity mismatch: passing a refutation term to Witness or a witness term to Refutation must fail
    @test_throws ArgumentError Witness(:P1, r1.countercertificate)
    @test_throws ArgumentError Refutation(:P1, w1.certificate)

    # Duplicate-index forgery on KOfNGate (repeating index 1 to fake 2-of-3 pass, or repeating index 2 to fake 2-of-3 refutation)
    dup_kofn_w = (
        gate_type = :k_of_n,
        gate_name = "TwoOfThree",
        k = 2,
        n = 3,
        witness_indices = [1, 1],
        child_evidence = EvidenceStatus[w1, r1, r2]
    )
    @test check_proof_term(:forged_kofn, dup_kofn_w) == false
    @test_throws ArgumentError Witness(:forged_kofn, dup_kofn_w)

    dup_kofn_r = (
        gate_type = :k_of_n,
        gate_name = "TwoOfThree",
        k = 2,
        n = 3,
        failed_indices = [2, 2],
        child_evidence = EvidenceStatus[w1, r1, u1]
    )
    @test check_refutation_term(:forged_kofn, dup_kofn_r) == false
    @test_throws ArgumentError Refutation(:forged_kofn, dup_kofn_r)

    # Inconsistent margin / deficit / injection tampering rejected at construction time
    bad_margin_w = (gate_type = :threshold, gate_name = "G", measured_value = 8.0, threshold = 5.0, margin = 99.0)
    @test check_proof_term(:bad_margin, bad_margin_w) == false
    @test_throws ArgumentError Witness(:bad_margin, bad_margin_w)

    bad_disj_inj = (
        combinator = :disjunction,
        injection = :left,
        witness_evidence = w2,
        left_evidence = r1,
        right_evidence = w2
    )
    @test check_proof_term((:P1, :P2), bad_disj_inj) == false
    @test_throws ArgumentError Witness((:P1, :P2), bad_disj_inj)

    # Verdict <-> Evidence bridges
    v_acc = verdict_from_evidence(w1)
    @test v_acc isa TransjectionCalculus.Accepted
    @test v_acc isa CriterialVerdict
    ev_back_w = evidence_from_verdict(v_acc, :P1)
    @test ev_back_w isa Witness{Symbol}
    @test verify_evidence_certificate(ev_back_w) == true

    v_rej = verdict_from_evidence(r1)
    @test v_rej isa TransjectionCalculus.Rejected
    ev_back_r = evidence_from_verdict(v_rej, :P1)
    @test ev_back_r isa Refutation{Symbol}
    @test verify_evidence_certificate(ev_back_r) == true

    v_inc = verdict_from_evidence(u1)
    @test v_inc isa TransjectionCalculus.Incomplete
    @test v_inc.missing_prerequisites == [:prereq_a]
    ev_back_u = evidence_from_verdict(v_inc, :P1)
    @test ev_back_u isa Unresolved{Symbol}
    @test !(ev_back_u isa Refutation)
    @test ev_back_u.missing_prerequisites == [:prereq_a]
end

@testset "8. Four-Level Scientific Achievement Taxonomy & Claim Boundary Audit" begin
    @test Int(IMPLEMENTED_INTERFACE) == 1
    @test Int(VERIFIED_NUMERICAL_COMPONENT) == 2
    @test Int(VALIDATED_PHYSICAL_MODEL) == 3
    @test Int(EXPERIMENTALLY_SUPPORTED_CLAIM) == 4
    @test IMPLEMENTED_INTERFACE < VERIFIED_NUMERICAL_COMPONENT < VALIDATED_PHYSICAL_MODEL < EXPERIMENTALLY_SUPPORTED_CLAIM

    g_num = ThresholdGate("LOOExactMatch", x -> x, 1.0)
    w_num = evaluate_gate_constructive(g_num, 1.0; proposition=:loo_verified)
    r_num = evaluate_gate_constructive(g_num, 0.25; proposition=:loo_failed)
    u_num = evaluate_gate_constructive(
        g_num,
        0.0;
        prerequisites=[:wet_lab_recoil_assay],
        available_prerequisites=Symbol[],
        proposition=:experimental_assay
    )

    # 1. Valid claim within achieved boundary -> Witness
    audit_valid = ScientificClaimAudit(
        :verified_loo_filter,
        VERIFIED_NUMERICAL_COMPONENT,
        VERIFIED_NUMERICAL_COMPONENT,
        w_num,
        true,
        true,
        true
    )
    res_valid = audit_scientific_claim_boundary(audit_valid)
    @test res_valid isa Witness{Symbol}
    @test verify_evidence_certificate(res_valid) == true

    # 2. Overclaimed level (claimed_level > achieved_level) -> Refutation
    audit_overclaim = ScientificClaimAudit(
        :overclaimed_biological_theorem,
        VERIFIED_NUMERICAL_COMPONENT,
        EXPERIMENTALLY_SUPPORTED_CLAIM,
        w_num,
        true,
        true,
        true
    )
    res_overclaim = audit_scientific_claim_boundary(audit_overclaim)
    @test res_overclaim isa Refutation{Symbol}
    @test res_overclaim.countercertificate.reason == :claim_exceeds_achievement
    @test verify_evidence_certificate(res_overclaim) == true

    # 3. Underlying evidence is Refutation -> Refutation
    audit_refuted = ScientificClaimAudit(
        :failed_numerical_claim,
        VERIFIED_NUMERICAL_COMPONENT,
        IMPLEMENTED_INTERFACE,
        r_num,
        true,
        true,
        true
    )
    res_refuted = audit_scientific_claim_boundary(audit_refuted)
    @test res_refuted isa Refutation{Symbol}
    @test res_refuted.countercertificate.reason == :underlying_evidence_refuted
    @test verify_evidence_certificate(res_refuted) == true

    # 4. Underlying evidence is Unresolved (missing experimental prerequisite) -> Unresolved (NEVER Refutation)
    audit_unresolved = ScientificClaimAudit(
        :pending_experimental_claim,
        EXPERIMENTALLY_SUPPORTED_CLAIM,
        EXPERIMENTALLY_SUPPORTED_CLAIM,
        u_num,
        true,
        true,
        true
    )
    res_unresolved = audit_scientific_claim_boundary(audit_unresolved)
    @test res_unresolved isa Unresolved{Symbol}
    @test !(res_unresolved isa Refutation)
    @test res_unresolved.missing_prerequisites == [:wet_lab_recoil_assay]
    @test verify_evidence_certificate(res_unresolved) == true

    # 5. Missing independent verification or source tracking -> Unresolved
    audit_unverified = ScientificClaimAudit(
        :unverified_delivery_claim,
        VERIFIED_NUMERICAL_COMPONENT,
        VERIFIED_NUMERICAL_COMPONENT,
        w_num,
        true,
        false,
        false
    )
    res_unverified = audit_scientific_claim_boundary(audit_unverified)
    @test res_unverified isa Unresolved{Symbol}
    @test :reported_in_delivery in res_unverified.missing_prerequisites
    @test :independently_verified in res_unverified.missing_prerequisites

    # 6. Edge Cases: Empty Conjunction/Disjunction, KOfN k > N, and mixed Unresolved child gates
    g_empty_conj = ConjunctionGate("EmptyConj", AbstractCriterialGate[])
    ev_empty_conj = evaluate_gate_constructive(g_empty_conj, [1, 2])
    @test ev_empty_conj isa Witness
    @test verify_evidence_certificate(ev_empty_conj) == true

    g_empty_disj = DisjunctionGate("EmptyDisj", AbstractCriterialGate[])
    ev_empty_disj = evaluate_gate_constructive(g_empty_disj, [1, 2])
    @test ev_empty_disj isa Refutation
    @test verify_evidence_certificate(ev_empty_disj) == true

    g_k_exceeds_n = KOfNGate("ImpossibleK", [ThresholdGate("G1", x -> x, 1.0)], 3)
    ev_k_exceeds_n = evaluate_gate_constructive(g_k_exceeds_n, 5.0)
    @test ev_k_exceeds_n isa Refutation
    @test verify_evidence_certificate(ev_k_exceeds_n) == true

    # KOfN where 1 passes, 1 fails, 1 returns missing measurement (k=2 -> still reachable -> Unresolved)
    g_kofn_mixed = KOfNGate("MixedKOfN", [
        ThresholdGate("PassBranch", x -> x[1], 5.0),
        ThresholdGate("FailBranch", x -> x[2], 5.0),
        ThresholdGate("MissingBranch", _ -> missing, 5.0)
    ], 2)
    ev_kofn_mixed_unres = evaluate_gate_constructive(g_kofn_mixed, [6.0, 2.0])
    @test ev_kofn_mixed_unres isa Unresolved
    @test !(ev_kofn_mixed_unres isa Refutation)
    @test :missing_measurement in ev_kofn_mixed_unres.missing_prerequisites

    # KOfN where 2 fail and 1 returns missing measurement (k=2 of 3 -> impossible even if missing passed -> Refutation)
    ev_kofn_mixed_ref = evaluate_gate_constructive(g_kofn_mixed, [1.0, 2.0])
    @test ev_kofn_mixed_ref isa Refutation
    @test verify_evidence_certificate(ev_kofn_mixed_ref) == true

    # 7. Exception-throwing child gates and malformed bandpass bounds yield Unresolved (NEVER crash or Refutation)
    g_throw = ThresholdGate("ThrowsBoundsError", x -> x[10], 5.0)
    ev_throw = evaluate_gate_constructive(g_throw, [1.0, 2.0]; proposition=:oob_prop)
    @test ev_throw isa Unresolved{Symbol}
    @test !(ev_throw isa Refutation)
    @test :evaluation_exception in ev_throw.missing_prerequisites

    g_disj_resilient = DisjunctionGate("ResilientDisj", [
        g_throw,
        ThresholdGate("SafeBranch", x -> length(x), 2)
    ])
    ev_disj_resilient = evaluate_gate_constructive(g_disj_resilient, [1.0, 2.0])
    @test ev_disj_resilient isa Witness
    @test ev_disj_resilient.certificate.branch_index == 2
    @test ev_disj_resilient.certificate.injection == :right
    @test verify_evidence_certificate(ev_disj_resilient) == true

    g_inverted_band = BandpassGate("InvertedBounds", x -> x, 10.0, 5.0)
    ev_inv_band = evaluate_gate_constructive(g_inverted_band, 7.0)
    @test ev_inv_band isa Unresolved
    @test !(ev_inv_band isa Refutation)
    @test :invalid_bandpass_bounds in ev_inv_band.missing_prerequisites

    # GateViolationRefutationTerm proposition identity and polarity checks
    gvc = GateViolationCertificate(:TopologyGate, 1, 2.5, (2, 3))
    gv_term = GateViolationRefutationTerm(gvc)
    @test check_refutation_term(:TopologyGate, gv_term) == true
    @test check_refutation_term("TopologyGate", gv_term) == true
    @test check_refutation_term(:OtherGate, gv_term) == false
    @test check_refutation_term("OtherGate", gv_term) == false
    @test check_proof_term(:TopologyGate, gv_term) == false
    ref_gv = Refutation(:TopologyGate, gvc)
    @test verify_evidence_certificate(ref_gv) == true
    @test_throws ArgumentError Refutation(:OtherGate, gvc)
    @test_throws ArgumentError Refutation("OtherGate", gv_term)
    @test_throws ArgumentError Witness(:TopologyGate, gv_term)

    w_a = evaluate_gate_constructive(ThresholdGate("GA", x -> x, 5.0), 7.0; proposition=:PA)
    w_b = evaluate_gate_constructive(ThresholdGate("GB", x -> x, 10.0), 12.0; proposition=:PB)
    r_a = evaluate_gate_constructive(ThresholdGate("GA", x -> x, 5.0), 2.0; proposition=:PA)
    r_b = evaluate_gate_constructive(ThresholdGate("GB", x -> x, 10.0), 4.0; proposition=:PB)

    # Combinator proposition identity when :proposition key is omitted
    comb_no_prop = (
        combinator = :conjunction,
        left_evidence = w_a,
        right_evidence = w_b,
        left = w_a.certificate,
        right = w_b.certificate,
        verified = true
    )
    @test check_proof_term((:PA, :PB), comb_no_prop) == true
    @test check_proof_term((:PA, :WRONG), comb_no_prop) == false
    @test check_proof_term(:NotATuple, comb_no_prop) == false
    @test_throws ArgumentError Witness(:NotATuple, comb_no_prop)

    # Post-validation mutation immunity (1): caller-held input vector mutation after construction
    caller_w_idxs = [1, 2]
    caller_children_w = EvidenceStatus[w_a, w_b, r_a]
    w_kofn_caller = Witness(
        :caller_immut_w,
        (
            gate_type = :k_of_n,
            proposition = :caller_immut_w,
            gate_name = "TwoOfThree",
            k = 2,
            n = 3,
            passed_count = 2,
            witness_indices = caller_w_idxs,
            child_evidence = caller_children_w,
            verified = true
        )
    )
    caller_w_idxs[1] = 2 # duplicate index in caller array
    empty!(caller_children_w)
    @test w_kofn_caller.certificate.witness_indices == [1, 2]
    @test length(w_kofn_caller.certificate.child_evidence) == 3
    @test verify_evidence_certificate(w_kofn_caller) == true

    caller_f_idxs = [2, 3]
    caller_children_r = EvidenceStatus[w_a, r_a, r_b]
    r_kofn_caller = Refutation(
        :caller_immut_r,
        (
            gate_type = :k_of_n,
            proposition = :caller_immut_r,
            gate_name = "TwoOfThree",
            k = 2,
            n = 3,
            refuted_count = 2,
            failed_indices = caller_f_idxs,
            child_evidence = caller_children_r,
            refuted = true
        )
    )
    caller_f_idxs[1] = 3
    empty!(caller_children_r)
    @test r_kofn_caller.countercertificate.failed_indices == [2, 3]
    @test length(r_kofn_caller.countercertificate.child_evidence) == 3
    @test verify_evidence_certificate(r_kofn_caller) == true

    # Post-validation mutation immunity (2): mutating vectors returned by getproperty / get / payload
    empty!(w_kofn_caller.certificate.witness_indices)
    empty!(w_kofn_caller.certificate.child_evidence)
    empty!(get(w_kofn_caller.certificate, :witness_indices, Int[]))
    empty!(w_kofn_caller.certificate.payload.witness_indices)
    @test w_kofn_caller.certificate.witness_indices == [1, 2]
    @test length(w_kofn_caller.certificate.child_evidence) == 3
    @test verify_evidence_certificate(w_kofn_caller) == true

    empty!(r_kofn_caller.countercertificate.failed_indices)
    empty!(r_kofn_caller.countercertificate.child_evidence)
    empty!(get(r_kofn_caller.countercertificate, :failed_indices, Int[]))
    empty!(r_kofn_caller.countercertificate.payload.failed_indices)
    @test r_kofn_caller.countercertificate.failed_indices == [2, 3]
    @test length(r_kofn_caller.countercertificate.child_evidence) == 3
    @test verify_evidence_certificate(r_kofn_caller) == true

    # Post-validation mutation immunity (3): low-level getfield backing-array tampering breaks structural _seal
    w_tamper = Witness(
        :tamper_w,
        (
            gate_type = :k_of_n,
            proposition = :tamper_w,
            gate_name = "TwoOfThree",
            k = 2,
            n = 3,
            passed_count = 2,
            witness_indices = [1, 2],
            child_evidence = EvidenceStatus[w_a, w_b, w_a],
            verified = true
        )
    )
    @test verify_evidence_certificate(w_tamper) == true
    # Even a low-level getfield mutation that preserves gate arithmetic ([1, 3] where child 3 is also a Witness)
    # MUST break the structural seal and invalidate the certificate:
    getfield(w_tamper.certificate, :payload).witness_indices[2] = 3
    @test check_proof_term(:tamper_w, w_tamper.certificate) == false
    @test verify_evidence_certificate(w_tamper) == false
    @test_throws ArgumentError Witness(:tamper_w, w_tamper.certificate)

    r_tamper = Refutation(
        :tamper_r,
        (
            gate_type = :k_of_n,
            proposition = :tamper_r,
            gate_name = "TwoOfThree",
            k = 2,
            n = 3,
            refuted_count = 2,
            failed_indices = [2, 3],
            child_evidence = EvidenceStatus[w_a, r_a, r_b],
            refuted = true
        )
    )
    @test verify_evidence_certificate(r_tamper) == true
    empty!(getfield(r_tamper.countercertificate, :payload).failed_indices)
    @test check_refutation_term(:tamper_r, r_tamper.countercertificate) == false
    @test verify_evidence_certificate(r_tamper) == false
    @test_throws ArgumentError Refutation(:tamper_r, r_tamper.countercertificate)

    # Nested child certificate low-level tampering propagates to invalidate parent composite certificates
    w_child_nested = Witness(
        :child_kofn,
        (
            gate_type = :k_of_n,
            proposition = :child_kofn,
            gate_name = "TwoOfThree",
            k = 2,
            n = 3,
            passed_count = 2,
            witness_indices = [1, 2],
            child_evidence = EvidenceStatus[w_a, w_b, w_a],
            verified = true
        )
    )
    w_parent_conj = conjunction_evidence(w_child_nested, w_a)
    @test verify_evidence_certificate(w_parent_conj) == true
    getfield(w_child_nested.certificate, :payload).witness_indices[2] = 3
    @test verify_evidence_certificate(w_child_nested) == false
    @test verify_evidence_certificate(w_parent_conj) == false

    # Verdict-bridge mutation immunity and low-level seal invalidation
    acc_verdict = Accepted(:bridge_prop, [1.0, 2.0], 3.0, "ok")
    ev_from_acc = evidence_from_verdict(acc_verdict, :bridge_prop)
    push!(acc_verdict.salient_features, 99.0)
    @test ev_from_acc.certificate.salient_features == [1.0, 2.0]
    @test verify_evidence_certificate(ev_from_acc) == true
    getfield(ev_from_acc.certificate, :payload).salient_features[1] = 42.0
    @test verify_evidence_certificate(ev_from_acc) == false

    # Unresolved defensive property copy and low-level getfield seal verification
    caller_prereqs = [:prereq_x, :prereq_y]
    u_mut = Unresolved(:mut_test, caller_prereqs)
    empty!(caller_prereqs)
    @test u_mut.missing_prerequisites == [:prereq_x, :prereq_y]
    @test verify_evidence_certificate(u_mut) == true

    # Property access returns a defensive copy, so mutating u_mut.missing_prerequisites does not corrupt u_mut
    empty!(u_mut.missing_prerequisites)
    @test u_mut.missing_prerequisites == [:prereq_x, :prereq_y]
    @test verify_evidence_certificate(u_mut) == true

    # Low-level getfield mutation of missing_prerequisites is caught by _sealed_prerequisites check
    getfield(u_mut, :missing_prerequisites)[1] = :forged_prereq
    @test verify_evidence_certificate(u_mut) == false
    empty!(getfield(u_mut, :missing_prerequisites))
    @test verify_evidence_certificate(u_mut) == false

    # Mutable proposition freezing, defensive property copy, and low-level getfield proposition seal check
    caller_prop_vec = [:prop_part_1, :prop_part_2]
    w_vec_prop = Witness(caller_prop_vec, (measured_value = 7.0, threshold = 5.0))
    u_vec_prop = Unresolved(caller_prop_vec, [:prereq_z])
    push!(caller_prop_vec, :forged_tail)
    @test w_vec_prop.proposition == [:prop_part_1, :prop_part_2]
    @test u_vec_prop.proposition == [:prop_part_1, :prop_part_2]
    empty!(w_vec_prop.proposition)
    empty!(u_vec_prop.proposition)
    @test w_vec_prop.proposition == [:prop_part_1, :prop_part_2]
    @test u_vec_prop.proposition == [:prop_part_1, :prop_part_2]
    @test verify_evidence_certificate(w_vec_prop) == true
    @test verify_evidence_certificate(u_vec_prop) == true
    getfield(w_vec_prop, :proposition)[1] = :tampered_prop
    getfield(u_vec_prop, :proposition)[1] = :tampered_prop
    @test verify_evidence_certificate(w_vec_prop) == false
    @test verify_evidence_certificate(u_vec_prop) == false

    # Combinator proposition forgery when :proposition is included or left/right evidence omitted
    forged_comb_with_prop = (
        combinator = :conjunction,
        proposition = (:PA, :WRONG),
        left_evidence = w_a,
        right_evidence = w_b,
        left = w_a.certificate,
        right = w_b.certificate,
        verified = true
    )
    @test check_proof_term((:PA, :WRONG), forged_comb_with_prop) == false
    @test_throws ArgumentError Witness((:PA, :WRONG), forged_comb_with_prop)

    forged_disj_no_lr = (
        combinator = :disjunction,
        injection = :left,
        witness_evidence = w_b
    )
    @test check_proof_term((:PA, :PB), forged_disj_no_lr) == false
    @test_throws ArgumentError Witness((:PA, :PB), forged_disj_no_lr)

    forged_disj_partial_lr = (
        combinator = :disjunction,
        injection = :left,
        witness_evidence = w_b,
        left_evidence = r_a
    )
    @test check_proof_term((:PA, :PB), forged_disj_partial_lr) == false
    @test_throws ArgumentError Witness((:PA, :PB), forged_disj_partial_lr)

    # Symbol proposition mismatch when :proposition key is omitted and :gate_name is present
    term_gate_a = StructuredProofTerm((gate_type = :threshold, gate_name = "GateA", measured_value = 7.0, threshold = 5.0))
    @test check_proof_term(:GateA, term_gate_a) == true
    @test check_proof_term(:GateB, term_gate_a) == false
    @test_throws ArgumentError Witness(:GateB, term_gate_a)

    # Bool <: Integer <: Real type-punning and index rejection (never throw or accept Bool as numeric/index)
    @test check_proof_term(:bool_thresh, (gate_type = :threshold, measured_value = true, threshold = false)) == false
    @test check_proof_term(:bool_disj, (gate_type = :disjunction, branch_index = true, child_evidence = EvidenceStatus[w_a])) == false
    @test check_proof_term(:bool_kofn, (gate_type = :k_of_n, k = 1, witness_indices = Bool[true], child_evidence = EvidenceStatus[w_a])) == false
    @test check_refutation_term(:bool_conj_r, (gate_type = :conjunction, failed_indices = Bool[true], child_evidence = EvidenceStatus[r_a])) == false
    @test verify_evidence_certificate(42) == false
    @test check_proof_term(:garbage_child, (gate_type = :k_of_n, k = 1, witness_indices = [1], child_evidence = Any[w_a, "not_evidence"])) == false

    # Polarity contradiction flags and fallback margin/passed_count checks
    @test check_proof_term(:pol_contradict_w, (gate_type = :threshold, measured_value = 8.0, threshold = 5.0, verified = true, refuted = true)) == false
    @test check_refutation_term(:pol_contradict_r, (gate_type = :threshold, measured_value = 2.0, threshold = 5.0, refuted = true, verified = true)) == false
    @test check_proof_term(:fallback_bad_margin, (measured_value = 8.0, threshold = 5.0, margin = 999.0)) == false
    @test check_refutation_term(:fallback_bad_deficit, (measured_value = 2.0, threshold = 5.0, deficit = 999.0)) == false
    @test check_refutation_term(:bad_passed_count, (
        gate_type = :k_of_n,
        k = 2,
        n = 3,
        passed_count = 99,
        refuted_count = 2,
        failed_indices = [2, 3],
        child_evidence = EvidenceStatus[w_a, r_a, r_b]
    )) == false

    # Deeply nested multi-level combinator tree (DisjunctionGate inside KOfNGate inside ConjunctionGate)
    # under low-level getfield mutation of leaf Unresolved or Witness nodes
    g_deep_disj = DisjunctionGate("DeepDisj", [
        ThresholdGate("UnresBranch", _ -> missing, 5.0),
        ThresholdGate("PassBranch", x -> x[1], 5.0)
    ])
    g_deep_kofn = KOfNGate("DeepKOfN", [
        g_deep_disj,
        ThresholdGate("PassBranch2", x -> x[2], 5.0),
        ThresholdGate("FailBranch3", x -> x[3], 5.0)
    ], 2)
    g_deep_conj = ConjunctionGate("DeepConj", [
        g_deep_kofn,
        BandpassGate("TopBand", x -> x[1], 1.0, 10.0)
    ])
    ev_deep = evaluate_gate_constructive(g_deep_conj, [6.0, 8.0, 1.0])
    @test ev_deep isa Witness
    @test verify_evidence_certificate(ev_deep) == true

    # Locate the leaf Unresolved node inside DisjunctionGate -> KOfNGate -> ConjunctionGate
    kofn_ev = getfield(ev_deep.certificate, :payload).child_evidence[1]
    disj_ev = getfield(kofn_ev.certificate, :payload).child_evidence[1]
    leaf_unres = getfield(disj_ev.certificate, :payload).child_evidence[1]
    @test leaf_unres isa Unresolved
    # Tampering with the leaf Unresolved's backing array invalidates the leaf, Disjunction, KOfN, and root Conjunction!
    getfield(leaf_unres, :missing_prerequisites)[1] = :forged_leaf_prereq
    @test verify_evidence_certificate(leaf_unres) == false
    @test verify_evidence_certificate(disj_ev) == false
    @test verify_evidence_certificate(kofn_ev) == false
    @test verify_evidence_certificate(ev_deep) == false
end

struct UnverifiedCustomProof <: AbstractProofTerm end
struct UnverifiedCustomRefutation <: AbstractRefutationTerm end

@testset "9. Unverified Custom Proof/Refutation Subtype Rejection" begin
    @test check_proof_term(:any_prop, UnverifiedCustomProof()) == false
    @test check_refutation_term(:any_prop, UnverifiedCustomRefutation()) == false
    @test verify_evidence_certificate(:any_prop, UnverifiedCustomProof()) == false
    @test verify_evidence_certificate(:any_prop, UnverifiedCustomRefutation()) == false
    @test_throws ArgumentError Witness(:any_prop, UnverifiedCustomProof())
    @test_throws ArgumentError Refutation(:any_prop, UnverifiedCustomRefutation())
end

println("All Transjection Calculus and Logic Gates tests passed successfully!")


end # module TestTransjection
