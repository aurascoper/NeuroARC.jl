module RadiationNucleicAcidDamage

export
    DetectorCandidateVerdict,
    HangingCurtainDetectorSpec,
    StretchedRRNACoverslipSpec,
    compute_kinematic_recoil_keV,
    compute_minimum_velocity_kms,
    scission_probability_eV,
    compute_rna_radiochemical_background,
    evaluate_curtain_track_candidate,
    evaluate_tirf_coverslip_candidate,
    evaluate_population_directional_asymmetry

"""
    DetectorCandidateVerdict

Structured evaluation result for physical track and population-level detector gates.
- `accepted::Bool`: `true` if all gates for the architecture or ensemble passed.
- `status::Symbol`: `:accepted` or `:rejected`.
- `reason::Symbol`: Primary acceptance or rejection reason symbol.
- `passed_gates::Vector{Symbol}`: Gates satisfied by the candidate or ensemble.
- `failed_gates::Vector{Symbol}`: Gates failed by the candidate or ensemble.
- `metrics::NamedTuple`: Computed physical observables for the evaluation.
"""
struct DetectorCandidateVerdict{M<:NamedTuple}
    accepted::Bool
    status::Symbol
    reason::Symbol
    passed_gates::Vector{Symbol}
    failed_gates::Vector{Symbol}
    metrics::M
end

# ------------------------------------------------------------------------------
# 1. Detector Architecture Specifications (Separated per Drukier et al., 2015)
# ------------------------------------------------------------------------------

"""
    HangingCurtainDetectorSpec

Architecture A (Drukier et al., 2015, Section III, pp. 8 to 11):
Modular stack of 1 um Mylar backing + 5 to 10 nm heavy-metal foil (`Au`, `W`, `Sn`, `Cu`) +
hanging single-stranded nucleic acid (ssNA) curtain in `He` or `N2` gas + bottom capture plate.
- Lateral (x-y) resolution is set by the 1 um x 1 um bundle barcode (`bundle_xy_nm = 1000.0`),
  with individual strands spaced at `strand_pitch_nm = 10.0` nm within a bundle.
- Axial (z) resolution is set by the single-base spacing `base_spacing_nm = 0.7` nm read out via PCR
  and high-throughput sequencing.
"""
struct HangingCurtainDetectorSpec
    target_symbol::Symbol
    M_target_GeV::Float64
    m_chi_GeV::Float64
    v_halo_kms::Float64
    mylar_thickness_um::Float64
    foil_thickness_nm::Float64
    bundle_xy_nm::Float64
    strand_pitch_nm::Float64
    base_spacing_nm::Float64
    strand_cleavage_eV::Float64
    min_primary_strands::Int
end

function HangingCurtainDetectorSpec(;
    target_symbol::Symbol = :Au,
    M_target_GeV::Real = 183.5,
    m_chi_GeV::Real = 200.0,
    v_halo_kms::Real = 300.0,
    mylar_thickness_um::Real = 1.0,
    foil_thickness_nm::Real = 5.0,
    bundle_xy_nm::Real = 1000.0,
    strand_pitch_nm::Real = 10.0,
    base_spacing_nm::Real = 0.7,
    strand_cleavage_eV::Real = 10.0,
    min_primary_strands::Int = 100
)
    M_target_GeV > 0 || throw(ArgumentError("M_target_GeV must be positive"))
    m_chi_GeV > 0 || throw(ArgumentError("m_chi_GeV must be positive"))
    v_halo_kms >= 0 || throw(ArgumentError("v_halo_kms must be non-negative"))
    strand_pitch_nm > 0 || throw(ArgumentError("strand_pitch_nm must be positive"))
    base_spacing_nm > 0 || throw(ArgumentError("base_spacing_nm must be positive"))
    strand_cleavage_eV > 0 || throw(ArgumentError("strand_cleavage_eV must be positive"))
    min_primary_strands >= 1 || throw(ArgumentError("min_primary_strands must be >= 1"))

    return HangingCurtainDetectorSpec(
        target_symbol,
        Float64(M_target_GeV),
        Float64(m_chi_GeV),
        Float64(v_halo_kms),
        Float64(mylar_thickness_um),
        Float64(foil_thickness_nm),
        Float64(bundle_xy_nm),
        Float64(strand_pitch_nm),
        Float64(base_spacing_nm),
        Float64(strand_cleavage_eV),
        min_primary_strands
    )
end

"""
    StretchedRRNACoverslipSpec

Architecture B (Drukier et al., 2015, Section III, p. 12):
25 x 25 x 0.1 mm coverslip surface with bacterial 23S-rRNA (2,904 nt) stretched to 1,400 nm
and anchored at both 5' and 3' ends via complementary 10-mer oligonucleotides.
A fluorescent 10-mer placed at `intact_anchor_z_nm = 200.0` nm (outside Total Internal Reflection
Fluorescence [TIRF] evanescent range) relaxes to `<= tirf_evanescent_max_nm` (1.0 nm) upon strand cleavage.
"""
struct StretchedRRNACoverslipSpec
    coverslip_xy_mm::Float64
    coverslip_thickness_mm::Float64
    nucleotide_length::Int
    stretched_length_nm::Float64
    intact_anchor_z_nm::Float64
    intact_anchor_min_nm::Float64
    tirf_evanescent_max_nm::Float64
end

function StretchedRRNACoverslipSpec(;
    coverslip_xy_mm::Real = 25.0,
    coverslip_thickness_mm::Real = 0.1,
    nucleotide_length::Int = 2904,
    stretched_length_nm::Real = 1400.0,
    intact_anchor_z_nm::Real = 200.0,
    intact_anchor_min_nm::Real = 100.0,
    tirf_evanescent_max_nm::Real = 1.0
)
    stretched_length_nm > 0 || throw(ArgumentError("stretched_length_nm must be positive"))
    tirf_evanescent_max_nm > 0 || throw(ArgumentError("tirf_evanescent_max_nm must be positive"))
    intact_anchor_min_nm > tirf_evanescent_max_nm || throw(ArgumentError("intact_anchor_min_nm must exceed tirf_evanescent_max_nm"))

    return StretchedRRNACoverslipSpec(
        Float64(coverslip_xy_mm),
        Float64(coverslip_thickness_mm),
        nucleotide_length,
        Float64(stretched_length_nm),
        Float64(intact_anchor_z_nm),
        Float64(intact_anchor_min_nm),
        Float64(tirf_evanescent_max_nm)
    )
end

# ------------------------------------------------------------------------------
# 2. Non-Relativistic Elastic Recoil Kinematics & Minimum Velocity
# ------------------------------------------------------------------------------

"""
    compute_minimum_velocity_kms(m_chi_GeV::Real, M_target_GeV::Real,
                                 E_th_keV::Real; c_kms::Real = 3.0e5) -> Float64

Computes the minimum projectile speed `v_min` (in km/s) required to impart an elastic nuclear
recoil energy equal to threshold `E_th_keV` (in keV):
`v_min(E_th) = c * sqrt(M * E_th / (2 * mu^2))` where `1 GeV = 10^6 keV`.
"""
function compute_minimum_velocity_kms(
    m_chi_GeV::Real,
    M_target_GeV::Real,
    E_th_keV::Real;
    c_kms::Real = 3.0e5
)::Float64
    m_chi = Float64(m_chi_GeV)
    M_tgt = Float64(M_target_GeV)
    E_th  = Float64(E_th_keV)
    c_val = Float64(c_kms)
    m_chi > 0 || throw(ArgumentError("m_chi_GeV must be positive"))
    M_tgt > 0 || throw(ArgumentError("M_target_GeV must be positive"))
    E_th >= 0 || throw(ArgumentError("E_th_keV must be non-negative"))
    c_val > 0 || throw(ArgumentError("c_kms must be positive"))

    mu = (m_chi * M_tgt) / (m_chi + M_tgt)
    E_th_GeV = E_th * 1.0e-6
    return c_val * sqrt((M_tgt * E_th_GeV) / (2.0 * mu^2))
end

"""
    compute_kinematic_recoil_keV(m_chi_GeV::Real, M_target_GeV::Real;
                                 v_kms::Real = 300.0,
                                 E_th_keV::Real = 0.5,
                                 c_kms::Real = 3.0e5) -> NamedTuple

Computes the reduced mass `mu_GeV`, mean elastic recoil energy `E_nr_keV = (mu^2 / M) * (v/c)^2 * 10^6`,
maximum elastic recoil energy `E_max_keV = 2 * E_nr_keV`, kinematic impedance efficiency
`4 * m_chi * M / (m_chi + M)^2` (maximized at `M == m_chi`), and minimum velocity `v_min_kms`
at `E_th_keV`.
"""
function compute_kinematic_recoil_keV(
    m_chi_GeV::Real,
    M_target_GeV::Real;
    v_kms::Real = 300.0,
    E_th_keV::Real = 0.5,
    c_kms::Real = 3.0e5
)
    m_chi = Float64(m_chi_GeV)
    M_tgt = Float64(M_target_GeV)
    v_val = Float64(v_kms)
    c_val = Float64(c_kms)
    m_chi > 0 || throw(ArgumentError("m_chi_GeV must be positive"))
    M_tgt > 0 || throw(ArgumentError("M_target_GeV must be positive"))
    v_val >= 0 || throw(ArgumentError("v_kms must be non-negative"))
    c_val > 0 || throw(ArgumentError("c_kms must be positive"))

    mu = (m_chi * M_tgt) / (m_chi + M_tgt)
    beta_sq_keV = (v_val / c_val)^2 * 1.0e6
    E_nr_keV = (mu^2 / M_tgt) * beta_sq_keV
    E_max_keV = 2.0 * E_nr_keV
    impedance_eff = (4.0 * m_chi * M_tgt) / ((m_chi + M_tgt)^2)
    v_min = compute_minimum_velocity_kms(m_chi, M_tgt, E_th_keV; c_kms = c_val)

    return (
        mu_GeV = mu,
        E_nr_keV = E_nr_keV,
        E_max_keV = E_max_keV,
        impedance_efficiency = impedance_eff,
        v_min_kms = v_min
    )
end

# ------------------------------------------------------------------------------
# 3. Stochastic Single-Strand Backbone Scission Probability
# ------------------------------------------------------------------------------

"""
    scission_probability_eV(delta_E_eV::Real;
                            E_scission_eV::Real = 10.0,
                            E_min_eV::Real = 5.0,
                            steepness::Real = 1.0) -> Float64

Computes the single-stranded nucleic acid (ssDNA or ssRNA) phosphodiester cleavage probability
given local energy deposition `delta_E_eV` (in eV) inside the strand cylinder:
`P_scission = 1 - exp(-((max(delta_E - E_min, 0)) / (E_scission - E_min))^steepness)`.
"""
function scission_probability_eV(
    delta_E_eV::Real;
    E_scission_eV::Real = 10.0,
    E_min_eV::Real = 5.0,
    steepness::Real = 1.0
)::Float64
    dE = Float64(delta_E_eV)
    E_sc = Float64(E_scission_eV)
    E_mn = Float64(E_min_eV)
    m = Float64(steepness)
    E_mn >= 0.0 || throw(ArgumentError("E_min_eV must be non-negative"))
    E_sc > E_mn || throw(ArgumentError("E_scission_eV must be strictly greater than E_min_eV"))
    m >= 1.0 || throw(ArgumentError("steepness must be >= 1.0"))

    if dE <= E_mn
        return 0.0
    end
    scaled = (dE - E_mn) / (E_sc - E_mn)
    return 1.0 - exp(-(scaled^m))
end

# ------------------------------------------------------------------------------
# 4. First-Principles Radiochemical Background in Depleted 23S-rRNA
# ------------------------------------------------------------------------------

"""
    compute_rna_radiochemical_background(mass_kg::Real;
                                         na_to_k_ratio::Real = 1.0e7,
                                         c14_to_c12_ratio::Real = 1.94e-18,
                                         k40_abundance::Real = 1.2e-4,
                                         k40_half_life_yr::Real = 1.25e9,
                                         c14_half_life_yr::Real = 5730.0) -> NamedTuple

Computes the intrinsic daily radioactive decay rate in `mass_kg` of depleted bacterial 23S-rRNA
from first principles, and explicitly documents the difference between the exact equation and
the approximate values printed in Drukier et al. (2015), Section III, p. 13:
- For `0.1 kg` RNA (`2.0e23` nucleotides), natural `K40` abundance `f_40 = 1.2e-4`, and
  `Na+:K+` substitution ratio `R_Na:K = 1.0e7`:
  * `k40_atoms = n_nucleotides * (k40_abundance / na_to_k_ratio) = 2.4e12` atoms
    (fixing the 8.33e5-fold `2.0e18` bug in commit 4498ead and noting the paper's 10x misprint `2.0e11`).
  * `lambda_k40_per_day = log(2.0) / (k40_half_life_yr * 365.25) = 1.5181868431155543e-12 day^-1`.
  * `k40_decays_per_day = k40_atoms * lambda_k40_per_day = 3.6436484234773303 decays/day`
    (compared to the paper's order-of-magnitude text estimate of `~6 decays/day`).
- For petrochemical methane-depleted `C14` (`C14/C12 = 1.94e-18`, `9.5` carbons/nt, `t_1/2 = 5730 yr`):
  * `c14_atoms = 3.686e6` atoms, `c14_decays_per_day = c14_atoms * lambda_c14_per_day = 1.220775895227734 decays/day`
    (compared to the paper's rounded text estimate of `~2 decays/day`).
"""
function compute_rna_radiochemical_background(
    mass_kg::Real;
    na_to_k_ratio::Real = 1.0e7,
    c14_to_c12_ratio::Real = 1.94e-18,
    k40_abundance::Real = 1.2e-4,
    k40_half_life_yr::Real = 1.25e9,
    c14_half_life_yr::Real = 5730.0
)
    m_kg = Float64(mass_kg)
    na_k = Float64(na_to_k_ratio)
    c14_r = Float64(c14_to_c12_ratio)
    f40 = Float64(k40_abundance)
    t_k40 = Float64(k40_half_life_yr)
    t_c14 = Float64(c14_half_life_yr)

    m_kg >= 0.0 || throw(ArgumentError("mass_kg must be non-negative"))
    na_k > 0.0 || throw(ArgumentError("na_to_k_ratio must be positive"))
    c14_r >= 0.0 || throw(ArgumentError("c14_to_c12_ratio must be non-negative"))
    (0.0 < f40 <= 1.0) || throw(ArgumentError("k40_abundance must be in (0, 1]"))
    t_k40 > 0.0 || throw(ArgumentError("k40_half_life_yr must be positive"))
    t_c14 > 0.0 || throw(ArgumentError("c14_half_life_yr must be positive"))

    m_scale = m_kg / 0.1
    n_nucleotides = 2.0e23 * m_scale

    # First-principles 40K atom count and decay rate
    k40_atoms = n_nucleotides * (f40 / na_k)
    lambda_k40_per_day = log(2.0) / (t_k40 * 365.25)
    k40_decays_per_day = k40_atoms * lambda_k40_per_day

    # Literature comparison metadata (Drukier et al., 2015, p. 13)
    paper_approx_k40_decays_per_day = 6.0 * m_scale * (1.0e7 / na_k) * (f40 / 1.2e-4)
    paper_printed_k40_atoms_typo = 2.0e11 * m_scale * (1.0e7 / na_k) * (f40 / 1.2e-4)

    # First-principles 14C atom count and decay rate
    n_carbons = n_nucleotides * 9.5
    c14_atoms = n_carbons * c14_r
    lambda_c14_per_day = log(2.0) / (t_c14 * 365.25)
    c14_decays_per_day = c14_atoms * lambda_c14_per_day
    paper_approx_c14_decays_per_day = 2.0 * m_scale * (c14_r / 1.94e-18)

    return (
        n_nucleotides = n_nucleotides,
        n_carbons = n_carbons,
        k40_atoms = k40_atoms,
        lambda_k40_per_day = lambda_k40_per_day,
        k40_decays_per_day = k40_decays_per_day,
        paper_approx_k40_decays_per_day = paper_approx_k40_decays_per_day,
        paper_printed_k40_atoms_typo = paper_printed_k40_atoms_typo,
        c14_atoms = c14_atoms,
        lambda_c14_per_day = lambda_c14_per_day,
        c14_decays_per_day = c14_decays_per_day,
        paper_approx_c14_decays_per_day = paper_approx_c14_decays_per_day,
        total_decays_per_day = k40_decays_per_day + c14_decays_per_day
    )
end

# ------------------------------------------------------------------------------
# 5. Separated Per-Track and Population-Level Evaluators
# ------------------------------------------------------------------------------

"""
    evaluate_curtain_track_candidate(spec::HangingCurtainDetectorSpec,
                                     pages_traversed::Int,
                                     severed_strands::Int;
                                     forward_hemisphere::Bool = true,
                                     forward_hemi::Bool = forward_hemisphere) -> DetectorCandidateVerdict

Per-track evaluator for Architecture A (hanging ssNA curtain + PCR/sequencing):
1. `:single_foil_quarantine_gate`: `pages_traversed == 1` ("one and only one" metal film, rejecting
   5 MeV alpha-particles that traverse ~30 pages of 1 um Mylar).
2. `:forward_hemisphere_rectification_gate`: `forward_hemi == true` (forward Mylar -> metal foil -> ssNA
   curtain trajectory; backward recoils into Mylar stop silently without entering the ssNA curtain).
3. `:primary_recoil_cascade_gate`: `severed_strands >= spec.min_primary_strands` (separating primary
   heavy-ion recoils [255 to 583 strands] from secondary knock-on cascades [18 to 20 strands]).
"""
function evaluate_curtain_track_candidate(
    spec::HangingCurtainDetectorSpec,
    pages_traversed::Int,
    severed_strands::Int;
    forward_hemisphere::Bool = true,
    forward_hemi::Bool = forward_hemisphere
)::DetectorCandidateVerdict
    passed = Symbol[]
    failed = Symbol[]

    if pages_traversed == 1
        push!(passed, :single_foil_quarantine_gate)
    else
        push!(failed, :single_foil_quarantine_gate)
    end

    if forward_hemi
        push!(passed, :forward_hemisphere_rectification_gate)
    else
        push!(failed, :forward_hemisphere_rectification_gate)
    end

    if severed_strands >= spec.min_primary_strands
        push!(passed, :primary_recoil_cascade_gate)
    else
        push!(failed, :primary_recoil_cascade_gate)
    end

    kin = compute_kinematic_recoil_keV(spec.m_chi_GeV, spec.M_target_GeV; v_kms = spec.v_halo_kms)
    track_length_nm = Float64(max(severed_strands, 0)) * spec.strand_pitch_nm
    deposited_cleavage_eV = Float64(max(severed_strands, 0)) * spec.strand_cleavage_eV

    metrics = (
        target = spec.target_symbol,
        E_nr_keV = kin.E_nr_keV,
        track_length_nm = track_length_nm,
        deposited_cleavage_eV = deposited_cleavage_eV,
        severed_strands = severed_strands,
        pages_traversed = pages_traversed,
        forward_hemisphere = forward_hemi,
        xy_resolution_nm = spec.bundle_xy_nm,
        z_resolution_nm = spec.base_spacing_nm
    )

    if !isempty(failed)
        reason = if :single_foil_quarantine_gate in failed
            pages_traversed > 1 ? :multi_page_background_bleed : :zero_foil_interaction
        elseif :forward_hemisphere_rectification_gate in failed
            :backward_mylar_stopped
        else
            :secondary_knockon_cascade
        end
        return DetectorCandidateVerdict(false, :rejected, reason, passed, failed, metrics)
    end

    return DetectorCandidateVerdict(true, :accepted, :curtain_primary_recoil_verified, passed, failed, metrics)
end

"""
    evaluate_tirf_coverslip_candidate(spec::StretchedRRNACoverslipSpec,
                                      cleaved_fluorophore_z_nm::Real,
                                      intact_control_z_nm::Real = spec.intact_anchor_z_nm;
                                      intact_anchor_z_nm::Real = intact_control_z_nm) -> DetectorCandidateVerdict

Per-molecule optical readout evaluator for Architecture B (stretched 2,904-nt 23S-rRNA coverslip + TIRF):
1. `:intact_anchor_standoff_gate`: `intact_anchor_z_nm >= spec.intact_anchor_min_nm` (verifying that
   prior to cleavage, the 200 nm fluorophore anchor sits outside the TIRF evanescent zone).
2. `:tirf_evanescent_cleavage_gate`: `0.0 <= cleaved_fluorophore_z_nm <= spec.tirf_evanescent_max_nm`
   (verifying that strand cleavage allows the fluorophore to relax onto the coverslip within `<= 1.0 nm`).
"""
function evaluate_tirf_coverslip_candidate(
    spec::StretchedRRNACoverslipSpec,
    cleaved_fluorophore_z_nm::Real,
    intact_control_z_nm::Real = spec.intact_anchor_z_nm;
    intact_anchor_z_nm::Real = intact_control_z_nm
)::DetectorCandidateVerdict
    cleaved_z = Float64(cleaved_fluorophore_z_nm)
    intact_z  = Float64(intact_anchor_z_nm)

    passed = Symbol[]
    failed = Symbol[]

    if intact_z >= spec.intact_anchor_min_nm
        push!(passed, :intact_anchor_standoff_gate)
    else
        push!(failed, :intact_anchor_standoff_gate)
    end

    if 0.0 <= cleaved_z <= spec.tirf_evanescent_max_nm
        push!(passed, :tirf_evanescent_cleavage_gate)
    else
        push!(failed, :tirf_evanescent_cleavage_gate)
    end

    metrics = (
        cleaved_fluorophore_z_nm = cleaved_z,
        intact_anchor_z_nm = intact_z,
        tirf_evanescent_max_nm = spec.tirf_evanescent_max_nm,
        stretched_length_nm = spec.stretched_length_nm,
        nucleotide_length = spec.nucleotide_length
    )

    if !isempty(failed)
        reason = if :intact_anchor_standoff_gate in failed
            :intact_control_inside_evanescent_zone
        elseif cleaved_z < 0.0
            :invalid_negative_fluorophore_z
        else
            :tirf_out_of_evanescent_range
        end
        return DetectorCandidateVerdict(false, :rejected, reason, passed, failed, metrics)
    end

    return DetectorCandidateVerdict(true, :accepted, :tirf_cleavage_step_verified, passed, failed, metrics)
end

"""
    evaluate_population_directional_asymmetry(backward_recoil_count::Int,
                                              forward_recoil_count::Int;
                                              min_asymmetry_ratio::Real = 5.0,
                                              min_total_events::Int = 30) -> DetectorCandidateVerdict

Population-level ensemble evaluator for the backward-to-forward WIMP wind recoil asymmetry
(Drukier et al., 2015, Section II/III: ~10:1 backward-to-forward ratio across N = 30 to 100 events).
Modeled strictly at the population level rather than as a per-track gate.
"""
function evaluate_population_directional_asymmetry(
    backward_recoil_count::Int,
    forward_recoil_count::Int;
    min_asymmetry_ratio::Real = 5.0,
    min_total_events::Int = 30
)::DetectorCandidateVerdict
    backward_recoil_count >= 0 || throw(ArgumentError("backward_recoil_count must be non-negative"))
    forward_recoil_count >= 0 || throw(ArgumentError("forward_recoil_count must be non-negative"))
    min_asymmetry_ratio > 0 || throw(ArgumentError("min_asymmetry_ratio must be positive"))
    min_total_events >= 1 || throw(ArgumentError("min_total_events must be >= 1"))

    total_events = backward_recoil_count + forward_recoil_count
    asymmetry_ratio = if forward_recoil_count == 0
        backward_recoil_count > 0 ? Inf : 0.0
    else
        Float64(backward_recoil_count) / Float64(forward_recoil_count)
    end

    passed = Symbol[]
    failed = Symbol[]

    if total_events >= min_total_events
        push!(passed, :minimum_ensemble_size_gate)
    else
        push!(failed, :minimum_ensemble_size_gate)
    end

    if asymmetry_ratio >= Float64(min_asymmetry_ratio)
        push!(passed, :population_head_tail_asymmetry_gate)
    else
        push!(failed, :population_head_tail_asymmetry_gate)
    end

    metrics = (
        backward_recoil_count = backward_recoil_count,
        forward_recoil_count = forward_recoil_count,
        total_events = total_events,
        asymmetry_ratio = asymmetry_ratio,
        min_asymmetry_ratio = Float64(min_asymmetry_ratio),
        min_total_events = min_total_events
    )

    if !isempty(failed)
        reason = if :minimum_ensemble_size_gate in failed
            :insufficient_population_sample
        else
            :isotropic_population_background
        end
        return DetectorCandidateVerdict(false, :rejected, reason, passed, failed, metrics)
    end

    return DetectorCandidateVerdict(true, :accepted, :population_directional_asymmetry_verified, passed, failed, metrics)
end

end # module RadiationNucleicAcidDamage
