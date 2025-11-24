const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "test_dict",
        .root_source_file = b.path("test_dict.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add import paths
    exe.root_module.addAnonymousImport("collections", .{
        .root_source_file = b.path("../collections/dict_impl.zig"),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the test");
    run_step.dependOn(&run_cmd.step);
}
