using Test

include(joinpath(@__DIR__, "..", "src", "RadiationNucleicAcidDamage.jl"))
using .RadiationNucleicAcidDamage

@testset "RadiationNucleicAcidDamage Standalone Physical Model Suite" begin

    @testset "1. Elastic Recoil Kinematics, Impedance Matching & Minimum Velocity (Table 1)" begin
        # Table 1 of Drukier et al. (2015), p. 17: E_nr and v_min at E_th = 0.5, 5.0, 10.0 keV
        kin_W_400  = compute_kinematic_recoil_keV(400.0, 171.3; E_th_keV = 0.5)
        kin_W_200  = compute_kinematic_recoil_keV(200.0, 171.3; E_th_keV = 0.5)
        kin_Sn_100 = compute_kinematic_recoil_keV(100.0, 110.6; E_th_keV = 0.5)
        kin_Cu_50  = compute_kinematic_recoil_keV(50.0, 59.2; E_th_keV = 0.5)
        kin_Au_200 = compute_kinematic_recoil_keV(200.0, 183.5; E_th_keV = 0.5)
        kin_Au_1k  = compute_kinematic_recoil_keV(1000.0, 183.5; E_th_keV = 0.5)

        @test isapprox(kin_W_400.mu_GeV, 119.94; atol = 0.01)
        @test isapprox(kin_W_400.E_nr_keV, 83.98; atol = 0.05)
        @test isapprox(kin_W_400.E_max_keV, 2.0 * kin_W_400.E_nr_keV; rtol = 1e-12)
        @test isapprox(kin_W_200.E_nr_keV, 49.71; atol = 0.05)
        @test isapprox(kin_Sn_100.E_nr_keV, 24.94; atol = 0.05)
        @test isapprox(kin_Cu_50.E_nr_keV, 12.41; atol = 0.05)
        @test isapprox(kin_Au_200.E_nr_keV, 49.91; atol = 0.05)
        @test isapprox(kin_Au_1k.E_nr_keV, 131.01; atol = 0.05)

        # Verify v_min(E_th) across 0.5 keV, 5.0 keV, 10.0 keV (including documented Table 1 row label erratum)
        @test isapprox(kin_W_400.v_min_kms, 16.4; atol = 0.05)
        @test isapprox(kin_W_200.v_min_kms, 21.3; atol = 0.05)
        @test isapprox(kin_Sn_100.v_min_kms, 30.0; atol = 0.05)
        @test isapprox(kin_Cu_50.v_min_kms, 42.6; atol = 0.05)

        @test isapprox(compute_minimum_velocity_kms(400.0, 171.3, 5.0), 51.8; atol = 0.05)
        @test isapprox(compute_minimum_velocity_kms(200.0, 171.3, 5.0), 67.3; atol = 0.05)
        @test isapprox(compute_minimum_velocity_kms(100.0, 110.6, 5.0), 95.0; atol = 0.05)
        @test isapprox(compute_minimum_velocity_kms(50.0, 59.2, 5.0), 134.6; atol = 0.05)

        @test isapprox(compute_minimum_velocity_kms(400.0, 171.3, 10.0), 73.2; atol = 0.05)
        @test isapprox(compute_minimum_velocity_kms(200.0, 171.3, 10.0), 95.2; atol = 0.05)
        @test isapprox(compute_minimum_velocity_kms(100.0, 110.6, 10.0), 134.3; atol = 0.05)
        @test isapprox(compute_minimum_velocity_kms(50.0, 59.2, 10.0), 190.4; atol = 0.05)

        # Verify impedance matching peaks at M_target == m_chi (efficiency == 1.0)
        kin_matched = compute_kinematic_recoil_keV(183.5, 183.5)
        @test isapprox(kin_matched.impedance_efficiency, 1.0; atol = 1e-12)
        @test kin_W_400.impedance_efficiency < 1.0

        # Edge cases & invalid inputs
        @test compute_minimum_velocity_kms(100.0, 100.0, 0.0) == 0.0
        @test compute_kinematic_recoil_keV(100.0, 100.0; v_kms = 0.0).E_nr_keV == 0.0
        @test_throws ArgumentError compute_kinematic_recoil_keV(-10.0, 100.0)
        @test_throws ArgumentError compute_kinematic_recoil_keV(100.0, 0.0)
    end

    @testset "2. First-Principles 40K and 14C Radiochemical Background Regression" begin
        bg = compute_rna_radiochemical_background(0.1)

        # 1. Exact 40K atom count for 0.1 kg RNA (2.0e23 nt * 1.2e-4 / 1.0e7 == 2.4e12 atoms, NOT 2.0e18)
        @test isapprox(bg.n_nucleotides, 2.0e23; rtol = 1e-12)
        @test isapprox(bg.k40_atoms, 2.4e12; rtol = 1e-12)
        @test bg.k40_atoms != 2.0e18

        # 2. Decay constant lambda_40 = ln(2) / (1.25e9 * 365.25) day^-1
        expected_lambda_k40 = log(2.0) / (1.25e9 * 365.25)
        @test isapprox(bg.lambda_k40_per_day, expected_lambda_k40; rtol = 1e-12)

        # 3. Fundamental rate-equation consistency: rate == atoms * lambda (3.6436484234773303 decays/day)
        @test isapprox(bg.k40_decays_per_day, bg.k40_atoms * bg.lambda_k40_per_day; rtol = 1e-12)
        @test isapprox(bg.k40_decays_per_day, 2.4e12 * expected_lambda_k40; rtol = 1e-12)
        @test isapprox(bg.k40_decays_per_day, 3.6436484234773303; rtol = 1e-10)

        # 4. Literature comparison fields preserved separately for transparency
        @test isapprox(bg.paper_approx_k40_decays_per_day, 6.0; rtol = 1e-12)
        @test isapprox(bg.paper_printed_k40_atoms_typo, 2.0e11; rtol = 1e-12)

        # 5. 14C petrochemical depletion consistency: rate == atoms * lambda (1.220775895227734 decays/day)
        @test isapprox(bg.c14_atoms, 3.686e6; rtol = 1e-12)
        @test isapprox(bg.c14_decays_per_day, bg.c14_atoms * bg.lambda_c14_per_day; rtol = 1e-12)
        @test isapprox(bg.c14_decays_per_day, 1.220775895227734; rtol = 1e-10)
        @test isapprox(bg.total_decays_per_day, bg.k40_decays_per_day + bg.c14_decays_per_day; rtol = 1e-12)

        # 6. Linear mass scaling and inverse Na:K ratio scaling
        bg_1kg = compute_rna_radiochemical_background(1.0)
        @test isapprox(bg_1kg.k40_atoms, 10.0 * bg.k40_atoms; rtol = 1e-12)
        @test isapprox(bg_1kg.k40_decays_per_day, 10.0 * bg.k40_decays_per_day; rtol = 1e-12)
        @test isapprox(bg_1kg.c14_decays_per_day, 10.0 * bg.c14_decays_per_day; rtol = 1e-12)

        bg_zero = compute_rna_radiochemical_background(0.0)
        @test bg_zero.k40_atoms == 0.0
        @test bg_zero.k40_decays_per_day == 0.0
        @test bg_zero.total_decays_per_day == 0.0
        @test_throws ArgumentError compute_rna_radiochemical_background(-0.1)
        @test_throws ArgumentError compute_rna_radiochemical_background(0.1; na_to_k_ratio = 0.0)
    end

    @testset "3. Stochastic Single-Strand Cleavage Probability" begin
        @test scission_probability_eV(0.0) == 0.0
        @test scission_probability_eV(5.0; E_min_eV = 5.0) == 0.0
        p_char = scission_probability_eV(10.0; E_scission_eV = 10.0, E_min_eV = 5.0, steepness = 1.0)
        @test isapprox(p_char, 1.0 - exp(-1.0); rtol = 1e-12)
        p_high = scission_probability_eV(50.0; E_scission_eV = 10.0, E_min_eV = 5.0, steepness = 2.0)
        @test p_char < p_high <= 1.0
        @test_throws ArgumentError scission_probability_eV(10.0; E_scission_eV = 4.0, E_min_eV = 5.0)
    end

    @testset "4. Separated Detector Geometries (Architecture A vs. Architecture B)" begin
        # Architecture A: Hanging ssNA curtain + PCR/sequencing
        curtain_spec = HangingCurtainDetectorSpec(target_symbol = :Au, M_target_GeV = 183.5, m_chi_GeV = 200.0)
        @test curtain_spec.bundle_xy_nm == 1000.0
        @test curtain_spec.strand_pitch_nm == 10.0
        @test curtain_spec.base_spacing_nm == 0.7

        # Primary 200 GeV WIMP Au recoil (1 foil, 255 severed strands, forward hemisphere)
        v_curtain_ok = evaluate_curtain_track_candidate(curtain_spec, 1, 255; forward_hemisphere = true)
        @test v_curtain_ok.accepted
        @test v_curtain_ok.status == :accepted
        @test v_curtain_ok.reason == :curtain_primary_recoil_verified
        @test v_curtain_ok.metrics.track_length_nm == 2550.0
        @test v_curtain_ok.metrics.deposited_cleavage_eV == 2550.0

        # 5 MeV alpha background punching through 6 pages -> rejected (:multi_page_background_bleed)
        v_alpha = evaluate_curtain_track_candidate(curtain_spec, 6, 400; forward_hemisphere = true)
        @test !v_alpha.accepted
        @test v_alpha.reason == :multi_page_background_bleed
        @test :single_foil_quarantine_gate in v_alpha.failed_gates

        # Backward Au recoil stopping silently in 1 um Mylar -> rejected (:backward_mylar_stopped)
        v_back = evaluate_curtain_track_candidate(curtain_spec, 1, 255; forward_hemisphere = false)
        @test !v_back.accepted
        @test v_back.reason == :backward_mylar_stopped
        @test :forward_hemisphere_rectification_gate in v_back.failed_gates

        # Secondary knock-on Au cascade (18 strands) -> rejected (:secondary_knockon_cascade)
        v_sec = evaluate_curtain_track_candidate(curtain_spec, 1, 18; forward_hemisphere = true)
        @test !v_sec.accepted
        @test v_sec.reason == :secondary_knockon_cascade
        @test :primary_recoil_cascade_gate in v_sec.failed_gates

        # Architecture B: Stretched 2,904-nt 23S-rRNA coverslip + TIRF evanescent readout
        tirf_spec = StretchedRRNACoverslipSpec()
        @test tirf_spec.nucleotide_length == 2904
        @test tirf_spec.stretched_length_nm == 1400.0
        @test tirf_spec.intact_anchor_z_nm == 200.0
        @test tirf_spec.tirf_evanescent_max_nm == 1.0

        # Cleaved 23S-rRNA relaxing from 200 nm to 0.5 nm inside TIRF evanescent field
        v_tirf_ok = evaluate_tirf_coverslip_candidate(tirf_spec, 0.5; intact_anchor_z_nm = 200.0)
        @test v_tirf_ok.accepted
        @test v_tirf_ok.reason == :tirf_cleavage_step_verified

        # Un-cleaved 23S-rRNA remaining at 200 nm outside evanescent range
        v_tirf_intact = evaluate_tirf_coverslip_candidate(tirf_spec, 200.0; intact_anchor_z_nm = 200.0)
        @test !v_tirf_intact.accepted
        @test v_tirf_intact.reason == :tirf_out_of_evanescent_range
        @test :tirf_evanescent_cleavage_gate in v_tirf_intact.failed_gates

        # Mis-anchored control already inside evanescent zone before cleavage
        v_tirf_bad_ctrl = evaluate_tirf_coverslip_candidate(tirf_spec, 0.5, 10.0)
        @test !v_tirf_bad_ctrl.accepted
        @test v_tirf_bad_ctrl.reason == :intact_control_inside_evanescent_zone
        @test :intact_anchor_standoff_gate in v_tirf_bad_ctrl.failed_gates
    end

    @testset "5. Population-Level Directional Asymmetry Gate (Ensemble vs. Single Event)" begin
        # 10:1 backward-to-forward WIMP recoil asymmetry over 99 events (>= 30 minimum)
        v_pop_ok = evaluate_population_directional_asymmetry(90, 9; min_asymmetry_ratio = 5.0, min_total_events = 30)
        @test v_pop_ok.accepted
        @test v_pop_ok.reason == :population_directional_asymmetry_verified
        @test isapprox(v_pop_ok.metrics.asymmetry_ratio, 10.0; rtol = 1e-12)

        # Single event or small sample (N = 11 < 30) cannot claim population directional discovery
        v_small = evaluate_population_directional_asymmetry(10, 1; min_asymmetry_ratio = 5.0, min_total_events = 30)
        @test !v_small.accepted
        @test v_small.reason == :insufficient_population_sample
        @test :minimum_ensemble_size_gate in v_small.failed_gates

        # Isotropic background (50 backward, 50 forward -> ratio 1.0 < 5.0)
        v_iso = evaluate_population_directional_asymmetry(50, 50; min_asymmetry_ratio = 5.0, min_total_events = 30)
        @test !v_iso.accepted
        @test v_iso.reason == :isotropic_population_background
        @test :population_head_tail_asymmetry_gate in v_iso.failed_gates
    end

end
