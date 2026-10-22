module NeuroARC

export
    # Core types
    GridState,
    ConnectedComponent,
    Demonstration,
    ARCTask,
    Candidate,
    ProvenanceReceipt,
    AbstractGridRule,
    AbstractEvidence,
    RuleNotImplementedError,

    # Evidence types
    TrainExactEvidence,
    InformativeLOOEvidence,
    EquivarianceEvidence,
    WarrantScramblingEvidence,

    # Rules
    MarkerLineReflectionRule,
    LegendRelationalRecolorRule,
    GeodesicBarrierFloodRule,
    CorridorWireTraceRule,
    PeriodicStampWithPriorityRule,
    ExactCoverPolyominoRule,
    ArcGeyserRule,
    ArcGyrismRule,
    reflect_through_marker,
    cast_geyser_beams,
    circulate_gyre,
    apply_rule,

    # Analysis & extraction
    detect_background,
    compute_palette,
    count_holes,
    extract_components_8,
    extract_marker_groups_4,

    # Verification pipeline
    evaluate_train_exact,
    evaluate_loo,
    evaluate_equivariance,
    verify_candidate,
    depolarize_membrane,
    refit_rule_parameters,
    apply_d8_transform,
    dihedral_transform,
    inverse_dihedral_transform,
    permute_colors,
    scramble_in_grid_legend_pair,
    count_ast_nodes,
    prune_unwarranted_ast_introns,
    evaluate_warrant_under_scrambling,
    evaluate_arc_agi2_loo_and_warrant_gate,

    # Bridge & compiler
    parse_json,
    parse_json_file,
    compile_rule,
    compile_rule_from_file,

    # Transjection & Criterial Logic Gates
    TransjectionCalculus,
    AbstractCriterialGate,
    ThresholdGate,
    BandpassGate,
    SubtypeGate,
    ConjunctionGate,
    DisjunctionGate,
    KOfNGate,
    KofNGate,
    EmpowermentOperator,
    TransjectionOperator,
    TransjectVerdict,
    AbstractVerdict,
    evaluate_gate,
    gate_passed,
    transject,
    compose_transjections,
    MorphologicalProfile,
    compute_morphology,
    euler_characteristic,
    ScaffoldController,
    update_scaffold_state!,

    # Hyphal Grafting & Composition Contracts
    HyphalGraftingContract,
    AbstractGridArtifact,
    AbstractPolyomino,
    ColorMappedGrid,
    PolyominoGraph,
    BoundedPolyomino,
    GraftVerdict,
    GraftNode,
    in_type,
    out_type,
    In,
    Out,
    can_graft,
    try_graft,
    try_deep_graft,
    build_canonical_fixtures,

    # Execution Backends, C-ABI Transport, Revision 3 Audit & Chiral Percolation
    sha256_hex,
    ARCGrid,
    DihedralOp,
    apply_dihedral,
    AbstractExecutionBackend,
    CPUBackend,
    MetalBackend,
    JACCBackend,
    TuringGLMMBackend,
    extension_loaded,
    default_backend,
    evaluate_batch_demos!,
    OwnershipState,
    PYTHON_OWNED,
    JULIA_BORROWED_READONLY,
    RELEASED,
    NARC_MAGIC_HEADER,
    COL_MAJOR_CONTIGUOUS,
    VERIFIED_DSL_MAX_ID,
    GENESIS_SEAL_HASH,
    CandidateBufferDescriptor,
    TransportFeedbackPacket,
    TransportSlotLock,
    compute_fnv1a_64,
    verify_zero_copy_eligibility,
    EntrenchmentRegistry,
    empower_lineage!,
    TaskAuditRow,
    Revision3AuditLedger,
    ComputeBudgetScheduler,
    allocate_budget,
    append_sealed_row!,
    verify_ledger_cryptographic_seal,
    write_columnar_audit_snapshot,
    read_columnar_audit_snapshot,
    GLMMCalibrationConfig,
    GLMMPosteriorSummary,
    calibrate_audit_glmm!,
    apply_glmm_budget_calibration!,
    compute_chain_rhat_and_ess,
    TopologicalPriorToken,
    GLMMCalibrationSpec,
    build_ns_covariance,
    calibrate_glmm_posterior,
    ChiralReactorSpec,
    CompartmentHydroState,
    PercolationReactorSpec,
    relativistic_K_factor,
    electroweak_bias_gZ,
    bifurcation_B,
    compute_compartment_snr,
    homochiral_probability,
    run_gated_kondepudi_frank!,
    critical_percolation_coupling,
    build_core_ignition_kofn_gate,
    build_percolation_kofn_gate,
    verify_advective_percolation!,
    DevicePerformanceStats,
    AdaptiveScheduler,
    select_optimal_backend,
    update_device_stats!,
    submit_batch_work!,
    AdaptiveCRLAgent,
    check_compartment_percolation,
    evaluate_batch_action_adaptive!,
    run_adaptive_test_time_rl!,
    synthesize_zpd_mid_graft!,
    execute_c_abi_zpd_graft!,
    invert_dihedral,
    execute_split_overlay_weave,
    execute_d8_fold_consensus_weave,
    NanoscaleRNATrackerSpec,
    compute_kinematic_recoil_keV,
    compute_rna_radiochemical_background,
    evaluate_ssna_track_quarantine

include("types.jl")
include("component.jl")
include("rules/reflection.jl")
include("rules/geyser.jl")
include("rules/gyrism.jl")
include("rules/extensions.jl")
include("verifier/warrant_scrambling.jl")
include("verifier/loo.jl")
include("bridge/json_parser.jl")
include("transjection/calculus.jl")
include("transjection/grafting.jl")

using .TransjectionCalculus
using .HyphalGraftingContract
using .TransjectionCalculus: Accepted, Rejected, Incomplete

include("backends.jl")

end # module NeuroARC
