# ext/NeuroARCMetalExt.jl
# Apple Silicon Metal.jl GPU acceleration extension for NeuroARC.jl
module NeuroARCMetalExt

using NeuroARC
using Metal

function __init__()
    # Initialize Metal backend hooks on Apple Silicon
end

end # module NeuroARCMetalExt
