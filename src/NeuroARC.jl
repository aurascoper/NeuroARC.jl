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

    # Rules
    MarkerLineReflectionRule,
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
    EmpowermentOperator,
    TransjectionOperator,
    TransjectVerdict,
    evaluate_gate,
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
    build_canonical_fixtures

include("types.jl")
include("component.jl")
include("rules/reflection.jl")
include("rules/geyser.jl")
include("rules/gyrism.jl")
include("rules/extensions.jl")
include("verifier/loo.jl")
include("bridge/json_parser.jl")
include("transjection/calculus.jl")
include("transjection/grafting.jl")

using .TransjectionCalculus
using .HyphalGraftingContract

end # module NeuroARC
