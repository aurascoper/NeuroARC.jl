using Test
using NeuroARC

@testset "NeuroARC.jl Package Suite" begin

    include("test_core.jl")
    include("test_transjection.jl")
    include("test_grafting.jl")

    @testset "Text Cleanliness & Epistemic Invariants Audit" begin
        clean_script = joinpath(@__DIR__, "check_text_clean.py")
        repo_root = normpath(joinpath(@__DIR__, ".."))
        cmd = `python3 $clean_script $repo_root`
        res = run(cmd)
        @test res.exitcode == 0
    end

end
