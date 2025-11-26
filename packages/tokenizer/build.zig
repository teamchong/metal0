const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build-time algorithm selection (industry standard: -D flag)
    // Users can opt-in to each algorithm individually:
    //   -Dinclude_bpe=true        (default: true)
    //   -Dinclude_wordpiece=true  (default: true)
    //   -Dinclude_unigram=true    (default: true)
    // All algorithms included by default - dead code elimination removes unused ones

    const include_bpe = b.option(bool, "include_bpe", "Include BPE algorithm") orelse true;
    const include_wordpiece = b.option(bool, "include_wordpiece", "Include WordPiece algorithm") orelse true;
    const include_unigram = b.option(bool, "include_unigram", "Include Unigram algorithm") orelse true;

    // Determine if multiple algorithms included (runtime selection needed)
    const included_count = @as(u8, if (include_bpe) 1 else 0) +
                           @as(u8, if (include_wordpiece) 1 else 0) +
                           @as(u8, if (include_unigram) 1 else 0);

    const runtime_selection = included_count > 1;

    // Default algorithm (only matters if single algorithm)
    const default_algorithm = if (include_bpe) "BPE"
                             else if (include_wordpiece) "WordPiece"
                             else if (include_unigram) "Unigram"
                             else {
        std.debug.print("ERROR: At least one algorithm must be included!\n", .{});
        std.process.exit(1);
    };

    // Create build options
    const options = b.addOptions();
    options.addOption(bool, "include_bpe", include_bpe);
    options.addOption(bool, "include_wordpiece", include_wordpiece);
    options.addOption(bool, "include_unigram", include_unigram);
    options.addOption(bool, "runtime_selection", runtime_selection);
    options.addOption([]const u8, "default_algorithm", default_algorithm);

    // Training benchmark binary
    const bench_train = b.addExecutable(.{
        .name = "bench_train",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench_train.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bench_train.root_module.addOptions("build_options", options);

    const allocator_helper = b.addModule("allocator_helper", .{
        .root_source_file = b.path("../../src/utils/allocator_helper.zig"),
    });
    bench_train.root_module.addImport("allocator_helper", allocator_helper);

    b.installArtifact(bench_train);

    // JSON parse benchmark binary
    const hashmap_helper = b.addModule("hashmap_helper", .{
        .root_source_file = b.path("../../src/utils/hashmap_helper.zig"),
    });
    const runtime = b.addModule("runtime", .{
        .root_source_file = b.path("../runtime/src/runtime.zig"),
    });
    runtime.addImport("hashmap_helper", hashmap_helper);

    const bench_json_parse = b.addExecutable(.{
        .name = "bench_pyaot_json_parse",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench_pyaot_json_parse_fast.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    bench_json_parse.root_module.addImport("allocator_helper", allocator_helper);
    bench_json_parse.root_module.addImport("hashmap_helper", hashmap_helper);
    bench_json_parse.root_module.addImport("runtime", runtime);
    bench_json_parse.linkLibC();

    b.installArtifact(bench_json_parse);

    // Install step with helpful message
    const install_step = b.getInstallStep();
    const print_step = b.addSystemCommand(&.{
        "echo",
    });
    const msg = b.fmt("Built bench_train with algorithm: {s}", .{default_algorithm});
    print_step.addArg(msg);
    install_step.dependOn(&print_step.step);

    // Run step
    const run_cmd = b.addRunArtifact(bench_train);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the training benchmark");
    run_step.dependOn(&run_cmd.step);
}
