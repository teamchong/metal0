const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Metal library module
    const metal_module = b.addModule("metal", .{
        .root_source_file = b.path("src/metal.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link Metal framework (macOS only)
    if (target.result.os.tag == .macos) {
        metal_module.linkFramework("Metal", .{});
        metal_module.linkFramework("Foundation", .{});
    }

    // Simple test executable
    const test_exe = b.addExecutable(.{
        .name = "test_metal",
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    test_exe.root_module.addImport("metal", metal_module);

    if (target.result.os.tag == .macos) {
        test_exe.linkFramework("Metal");
        test_exe.linkFramework("Foundation");
    }

    const run_cmd = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run Metal tests");
    test_step.dependOn(&run_cmd.step);

    b.installArtifact(test_exe);
}
