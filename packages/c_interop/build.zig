const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create collections module (shared dict/set/etc implementations)
    const collections_mod = b.addModule("collections", .{
        .root_source_file = b.path("../collections/dict_impl.zig"),
    });

    // Create c_interop module
    const c_interop_mod = b.addModule("c_interop", .{
        .root_source_file = b.path("src/registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    c_interop_mod.addImport("collections", collections_mod);

    // Unit tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mapper.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const registry_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/registry.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const object_protocol_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cpython_object_protocol.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const unicode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cpython_unicode.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const test_step = b.step("test", "Run c_interop unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(registry_tests).step);
    test_step.dependOn(&b.addRunArtifact(object_protocol_tests).step);
    test_step.dependOn(&b.addRunArtifact(unicode_tests).step);

    // PyDict test executable
    const test_dict_exe = b.addExecutable(.{
        .name = "test_dict",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test_dict.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_dict_exe.root_module.addImport("collections", collections_mod);

    const run_test_dict = b.addRunArtifact(test_dict_exe);
    const test_dict_step = b.step("test-dict", "Test PyDict implementation");
    test_dict_step.dependOn(&run_test_dict.step);
}
