# ext/NeuroARCJACCExt.jl
# JACC.jl GPU acceleration extension for NeuroARC.jl
module NeuroARCJACCExt

using NeuroARC
using JACC

function __init__()
    # Initialize JACC backend hooks if available
end

end # module NeuroARCJACCExt
