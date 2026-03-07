"""
Static Analysis Tests

Uses JET.jl to catch errors at "compile time" including:
- Undefined variable references
- Missing exports
- Type instabilities
- Method errors

Run this before commits to catch issues like missing exports from modules.
"""

using ReTest
using JET
using Kaimon

@testset "Static Analysis" begin
    @testset "Module Loading" begin
        # Test that Kaimon loaded without errors
        @test isdefined(Main, :Kaimon)
        @test Kaimon isa Module
    end

    @testset "Session Module Exports" begin
        # Verify key Session exports are accessible from the top-level module
        @test isdefined(Kaimon, :Session)
        @test isdefined(Kaimon.Session, :update_activity!)
    end

    @testset "Top-level Module Analysis" begin
        # report_package conflicts with Revise.jl when both are loaded in the
        # same process (JET reads Revise internals that change between versions).
        # Skip automatically when Revise is present; run manually in a fresh
        # Julia session with `include("test/static_analysis_tests.jl")`.
        revise_loaded = any(m -> nameof(m) === :Revise, values(Base.loaded_modules))
        if revise_loaded
            @test_skip "report_package skipped: Revise is loaded (JET/Revise version conflict)"
        else
            rep = report_package(Kaimon; ignore_missing_comparison = true)

            issues = filter(rep.res.inference_error_reports) do report
                !any(sf -> occursin("test/", string(sf.file)), report.vst)
            end

            if !isempty(issues)
                println("\n❌ Static analysis found issues:")
                for (i, issue) in enumerate(issues)
                    println("\n$i. ", issue)
                end
            end

            @test isempty(issues)
        end
    end

    @testset "Export Consistency Check" begin
        @testset "Core Type Exports" begin
            # MCPServer and MCPSession are structs, not sub-modules
            @test isdefined(Kaimon, :MCPServer)
            @test isdefined(Kaimon, :MCPSession)
            @test isdefined(Kaimon, :Session)
        end
    end
end
