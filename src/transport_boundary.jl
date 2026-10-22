# ==============================================================================
# File: src/transport_boundary.jl
# Layer 2 C-ABI Zero-Copy Buffer Handoff, Atomic CAS Slot Locks & FNV-1a TOCTOU
# (Implemented in src/backends.jl)
# ==============================================================================
# Core definitions `CandidateBufferDescriptor`, `TransportFeedbackPacket`,
# `TransportSlotLock`, `compute_fnv1a_64`, and `verify_zero_copy_eligibility`
# are loaded by `src/NeuroARC.jl`.
