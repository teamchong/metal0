/// Build commands: build, run, deploy, codegen, build-fast, build-runtime, setup-runtime
const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const CompileOptions = @import("../../main.zig").CompileOptions;
const utils = @import("../utils.zig");
const compile_mod = @import("../compile.zig");
const compiler = @import("../../compiler.zig");
const build_dirs = @import("../../build_dirs.zig");
const Color = @import("common.zig").Color;
const printSuccess = @import("common.zig").printSuccess;
const printError = @import("common.zig").printError;
const printInfo = @import("common.zig").printInfo;
const printWarn = @import("common.zig").printWarn;

pub fn cmdBuild(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var opts = CompileOptions{ .input_file = undefined, .mode = "build" };
    var input_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--binary") or std.mem.eql(u8, arg, "-b")) {
            opts.binary = true;
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            opts.force = true;
        } else if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "-g")) {
            opts.debug = true;
        } else if (std.mem.eql(u8, arg, "--emit-zig")) {
            opts.emit_zig_only = true;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            // Parse -o <output> or --output <output>
            i += 1;
            if (i < args.len) {
                output_file = args[i];
            }
        } else if (std.mem.startsWith(u8, arg, "-o=")) {
            output_file = arg["-o=".len..];
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            output_file = arg["--output=".len..];
        } else if (std.mem.eql(u8, arg, "--target") or std.mem.eql(u8, arg, "-t")) {
            // Parse --target <value>
            i += 1;
            if (i < args.len) {
                opts.target = parseTarget(args[i]);
            }
        } else if (std.mem.startsWith(u8, arg, "--target=")) {
            // Parse --target=<value>
            const value = arg["--target=".len..];
            opts.target = parseTarget(value);
        } else if (std.mem.eql(u8, arg, "--pgo-generate")) {
            opts.pgo_generate = true;
        } else if (std.mem.startsWith(u8, arg, "--pgo-use=")) {
            // Parse --pgo-use=<profile>
            const value = arg["--pgo-use=".len..];
            opts.pgo_use = value;
        } else if (std.mem.eql(u8, arg, "--pgo-use")) {
            // Parse --pgo-use <profile>
            i += 1;
            if (i < args.len) {
                opts.pgo_use = args[i];
            }
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            // First positional = input, second positional = output
            if (input_file == null) {
                input_file = arg;
            } else if (output_file == null) {
                output_file = arg;
            }
        }
    }

    if (input_file == null) {
        try utils.buildDirectory(allocator, ".", opts);
        return;
    }

    opts.input_file = input_file.?;
    opts.output_file = output_file;
    try compile_mod.compileFile(allocator, opts);
}

pub fn parseTarget(value: []const u8) CompileOptions.Target {
    if (std.mem.eql(u8, value, "native")) return .native;
    if (std.mem.eql(u8, value, "wasm-browser") or std.mem.eql(u8, value, "wasm_browser")) return .wasm_browser;
    if (std.mem.eql(u8, value, "wasm-edge") or std.mem.eql(u8, value, "wasm_edge")) return .wasm_edge;
    if (std.mem.eql(u8, value, "linux-x64") or std.mem.eql(u8, value, "linux_x64")) return .linux_x64;
    if (std.mem.eql(u8, value, "linux-arm64") or std.mem.eql(u8, value, "linux_arm64")) return .linux_arm64;
    if (std.mem.eql(u8, value, "macos-x64") or std.mem.eql(u8, value, "macos_x64")) return .macos_x64;
    if (std.mem.eql(u8, value, "macos-arm64") or std.mem.eql(u8, value, "macos_arm64")) return .macos_arm64;
    if (std.mem.eql(u8, value, "windows-x64") or std.mem.eql(u8, value, "windows_x64")) return .windows_x64;
    // Default to native for unknown targets
    printWarn("Unknown target '{s}', using native", .{value});
    return .native;
}

/// Deploy to remote server (WIP - not yet implemented)
pub fn cmdDeploy(args: []const []const u8) void {
    _ = args;
    printWarn("Deploy command is work-in-progress", .{});
    std.debug.print("\n{s}Coming soon:{s}\n", .{ Color.bold, Color.reset });
    std.debug.print("  metal0 deploy app.py --to my-server\n", .{});
    std.debug.print("  metal0 deploy app.py --to user@host:/path\n", .{});
    std.debug.print("\nFor now, use:\n", .{});
    std.debug.print("  metal0 build -b app.py && scp ./app my-server:\n\n", .{});
}

pub fn cmdRun(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No file specified", .{});
        return;
    }
    try cmdRunFile(allocator, args);
}

pub fn cmdRunFile(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var opts = CompileOptions{ .input_file = args[0], .mode = "run" };

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            opts.force = true;
        } else if (std.mem.eql(u8, arg, "--binary") or std.mem.eql(u8, arg, "-b")) {
            opts.binary = true;
        } else if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "-g")) {
            opts.debug = true;
        } else if (std.mem.eql(u8, arg, "--emit-zig")) {
            opts.emit_zig_only = true;
        } else if (std.mem.eql(u8, arg, "--target") or std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i < args.len) opts.target = parseTarget(args[i]);
        } else if (std.mem.startsWith(u8, arg, "--target=")) {
            opts.target = parseTarget(arg["--target=".len..]);
        } else if (std.mem.eql(u8, arg, "--pgo-generate")) {
            opts.pgo_generate = true;
        } else if (std.mem.startsWith(u8, arg, "--pgo-use=")) {
            opts.pgo_use = arg["--pgo-use=".len..];
        } else if (std.mem.eql(u8, arg, "--pgo-use")) {
            i += 1;
            if (i < args.len) opts.pgo_use = args[i];
        }
    }

    try compile_mod.compileFile(allocator, opts);
}

/// Setup runtime (no-op with module flags, kept for backward compatibility)
pub fn cmdSetupRuntime(allocator: std.mem.Allocator) !void {
    _ = allocator;
    // With -M module flags, runtime is compiled directly from source
    // No file copying needed - just ensure directories exist
    try build_dirs.init();
    printSuccess("Runtime ready (using -M module flags)", .{});
}

/// Build runtime static archive (.a) for fast linking
/// Usage: metal0 build-runtime
pub fn cmdBuildRuntime(allocator: std.mem.Allocator) !void {
    const incr = @import("../compile/incremental.zig");

    std.debug.print("{s}=== Building Runtime Archive ==={s}\n", .{ Color.bold, Color.reset });
    std.debug.print("Building .metal0/lib/libruntime.a (precompiled, cached)...\n", .{});

    try incr.buildRuntimeArchive(allocator);

    printSuccess("Runtime archive built: {s}", .{incr.RUNTIME_ARCHIVE_PATH});
    std.debug.print("Future compilations will link against this archive (10x faster).\n", .{});
}

/// Build precompiled module objects (.o files) for ultra-fast linking
/// Usage: metal0 build-objects
pub fn cmdBuildObjects(allocator: std.mem.Allocator) !void {
    const incr = @import("../compile/incremental.zig");

    std.debug.print("{s}=== Building Precompiled Module Objects ==={s}\n", .{ Color.bold, Color.reset });
    std.debug.print("Building .metal0/obj/*.o files (one-time, then link-only builds)...\n\n", .{});

    try incr.buildAllModuleObjects(allocator);

    printSuccess("Module objects built in .metal0/obj/", .{});
    std.debug.print("\nFuture builds will link against these objects (~10x faster).\n", .{});
    std.debug.print("To rebuild: rm -rf .metal0/obj && metal0 build-objects\n", .{});
}

/// Codegen-only batch command: fast parallel codegen with error summary
/// Usage: metal0 codegen tests/cpython
pub fn cmdCodegen(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const test_dir = if (args.len > 0) args[0] else ".";

    // Discover .py files
    var py_files = std.ArrayList([]const u8){};
    defer {
        for (py_files.items) |f| allocator.free(f);
        py_files.deinit(allocator);
    }

    var dir = std.fs.cwd().openDir(test_dir, .{ .iterate = true }) catch |err| {
        printError("Cannot open directory: {s} ({any})", .{ test_dir, err });
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".py")) {
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ test_dir, entry.name });
            try py_files.append(allocator, path);
        }
    }

    const total = py_files.items.len;
    if (total == 0) {
        printWarn("No .py files found in {s}", .{test_dir});
        return;
    }

    std.debug.print("Codegen {d} files from {s}...\n", .{ total, test_dir });

    const ErrorInfo = struct {
        file: []const u8,
        message: []const u8,
    };

    // Track results
    var passed: usize = 0;
    var errors = std.ArrayList(ErrorInfo){};
    defer {
        for (errors.items) |e| {
            allocator.free(e.file);
            allocator.free(e.message);
        }
        errors.deinit(allocator);
    }

    // Run codegen on each file sequentially (thread-safe output)
    for (py_files.items) |file_path| {
        const opts = CompileOptions{ .input_file = file_path, .mode = "build", .force = true, .emit_zig_only = true };

        // Capture stderr for error message
        var err_msg: []const u8 = "";
        compile_mod.compileFile(allocator, opts) catch |err| {
            err_msg = try std.fmt.allocPrint(allocator, "{any}", .{err});
            try errors.append(allocator, .{
                .file = try allocator.dupe(u8, std.fs.path.basename(file_path)),
                .message = err_msg,
            });
            continue;
        };
        passed += 1;
    }

    // Print summary
    std.debug.print("\n{s}=== Codegen Results ==={s}\n", .{ Color.bold, Color.reset });
    std.debug.print("Passed: {s}{d}/{d}{s}\n", .{ Color.green, passed, total, Color.reset });

    if (errors.items.len > 0) {
        std.debug.print("Failed: {s}{d}{s}\n\n", .{ Color.red, errors.items.len, Color.reset });

        // Group errors by type
        var error_counts = hashmap_helper.StringHashMap(usize).init(allocator);
        defer error_counts.deinit();

        for (errors.items) |e| {
            const count = error_counts.get(e.message) orelse 0;
            error_counts.put(e.message, count + 1) catch {};
        }

        std.debug.print("{s}Error summary:{s}\n", .{ Color.bold, Color.reset });
        var err_iter = error_counts.iterator();
        while (err_iter.next()) |entry| {
            std.debug.print("  {s}{d}x{s} {s}\n", .{ Color.yellow, entry.value_ptr.*, Color.reset, entry.key_ptr.* });
        }

        // Show first 10 failed files
        std.debug.print("\n{s}Failed files (first 10):{s}\n", .{ Color.bold, Color.reset });
        const show_count = @min(errors.items.len, 10);
        for (errors.items[0..show_count]) |e| {
            std.debug.print("  {s}✗{s} {s}\n", .{ Color.red, Color.reset, e.file });
        }
    }
}

/// Fast incremental build using Zig's --cache-dir for hash-based caching
/// Usage: metal0 build-fast <dir> [-j N]
/// - Codegens .py → .zig
/// - Compiles .zig → .o with Zig's built-in caching
/// - Links .o → binary with --gc-sections for DCE
pub fn cmdBuildFast(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const incremental = @import("../compile/incremental.zig");

    // Parse args
    var dir_path: []const u8 = ".";
    var parallelism: usize = 8;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-j") and i + 1 < args.len) {
            parallelism = std.fmt.parseInt(usize, args[i + 1], 10) catch 8;
            i += 1;
        } else {
            dir_path = args[i];
        }
    }

    // Phase 1: Discover .py files
    var py_files = std.ArrayList([]const u8){};
    defer {
        for (py_files.items) |f| allocator.free(f);
        py_files.deinit(allocator);
    }

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        printError("Cannot open directory: {s} ({any})", .{ dir_path, err });
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".py")) {
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
            try py_files.append(allocator, path);
        }
    }

    const total = py_files.items.len;
    if (total == 0) {
        printWarn("No .py files found in {s}", .{dir_path});
        return;
    }

    std.debug.print("{s}=== Incremental Build ({d} files, {d} parallel) ==={s}\n", .{ Color.bold, total, parallelism, Color.reset });

    // Phase 2: Codegen .py → .zig
    std.debug.print("Phase 1: Codegen .py → .zig...\n", .{});
    var zig_files = std.ArrayList([]const u8){};
    defer {
        for (zig_files.items) |f| allocator.free(f);
        zig_files.deinit(allocator);
    }

    var codegen_ok: usize = 0;
    for (py_files.items) |file_path| {
        const opts = CompileOptions{ .input_file = file_path, .mode = "build", .force = true, .emit_zig_only = true };
        compile_mod.compileFile(allocator, opts) catch continue;
        codegen_ok += 1;

        // Get the generated .zig path - check if it exists
        const basename = std.fs.path.basename(file_path);
        const stem = if (std.mem.lastIndexOf(u8, basename, ".")) |idx| basename[0..idx] else basename;
        const zig_path = try std.fmt.allocPrint(allocator, ".metal0/cache/{s}.zig", .{stem});

        // Only add if file exists
        std.fs.cwd().access(zig_path, .{}) catch {
            allocator.free(zig_path);
            continue;
        };
        try zig_files.append(allocator, zig_path);
    }
    std.debug.print("  {s}✓{s} Codegen: {d}/{d} ({d} zig files)\n", .{ Color.green, Color.reset, codegen_ok, total, zig_files.items.len });

    if (codegen_ok == 0) {
        printError("All codegen failed", .{});
        return;
    }

    // Phase 3: Compile .zig → .o using Zig's cache
    std.debug.print("Phase 2: Compile .zig → .o (with Zig cache)...\n", .{});
    const compile_ok = incremental.batchCompile(allocator, zig_files.items, parallelism) catch |err| {
        printError("Batch compile failed: {any}", .{err});
        return;
    };
    std.debug.print("  {s}✓{s} Compiled: {d}/{d}\n", .{ Color.green, Color.reset, compile_ok, codegen_ok });

    printSuccess("Build complete! .o files in .metal0/cache/", .{});
    std.debug.print("  {s}Hint:{s} Run `metal0 <file.py>` to link and execute\n", .{ Color.dim, Color.reset });
}
