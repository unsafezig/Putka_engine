const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Engine library module (headless, testable, no raylib dependency).
    const engine_mod = b.addModule("engine", .{
        .root_source_file = b.path("engine/root.zig"),
        .target = target,
    });

    // raylib backend (window + rendering). Only the game executable links it,
    // engine simulation code stays backend-independent.
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib_mod = raylib_dep.module("raylib");
    const raygui_mod = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    // PUTKA game data (embedded JSON). Own package so @embedFile stays
    // inside the package directory.
    const data_mod = b.addModule("putka_data", .{
        .root_source_file = b.path("data/root.zig"),
        .target = target,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("game/putka/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "engine", .module = engine_mod },
            .{ .name = "putka_data", .module = data_mod },
            .{ .name = "raylib", .module = raylib_mod },
            .{ .name = "raygui", .module = raygui_mod },
        },
    });
    exe_mod.linkLibrary(raylib_artifact);

    const exe = b.addExecutable(.{
        .name = "putka",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the PUTKA engine demo");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Tests: engine module + executable module, run in parallel.
    const engine_tests = b.addTest(.{ .root_module = engine_mod });
    const run_engine_tests = b.addRunArtifact(engine_tests);

    const exe_tests = b.addTest(.{ .root_module = exe_mod });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_engine_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
