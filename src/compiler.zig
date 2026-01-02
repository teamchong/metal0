const std = @import("std");
const builtin = @import("builtin");
const build_dirs = @import("build_dirs.zig");

/// Get build directory - uses .metal0/cache structure
fn getBuildDir(allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    // Initialize directory structure
    try build_dirs.init();
    return build_dirs.getBuildDir();
}

/// Module definition for -M flag
const ModuleDef = struct {
    name: []const u8,
    path: []const u8,
    deps: []const []const u8,
};

/// All modules needed for compilation - mirrors build.zig exactly
/// Order matters: dependencies must come before dependents
const MODULES = [_]ModuleDef{
    // Leaf modules (no deps)
    .{ .name = "utils.hashmap_helper", .path = "src/utils/hashmap_helper.zig", .deps = &.{} },
    .{ .name = "bigint", .path = "packages/bigint/src/bigint.zig", .deps = &.{} },
    .{ .name = "green_thread", .path = "packages/runtime/src/runtime/green_thread.zig", .deps = &.{} },
    .{ .name = "gzip", .path = "packages/runtime/src/Modules/gzip/gzip.zig", .deps = &.{} },
    .{ .name = "regex", .path = "packages/regex/src/pyregex/regex.zig", .deps = &.{} },
    .{ .name = "json_simd", .path = "packages/shared/json/simd/dispatch.zig", .deps = &.{} },

    // Modules with deps
    .{ .name = "json", .path = "packages/shared/json/json.zig", .deps = &.{ "json_simd", "utils.hashmap_helper" } },
    .{ .name = "netpoller", .path = "packages/runtime/src/runtime/netpoller.zig", .deps = &.{"green_thread"} },
    .{ .name = "work_queue", .path = "packages/runtime/src/runtime/work_queue.zig", .deps = &.{"green_thread"} },
    .{ .name = "scheduler", .path = "packages/runtime/src/runtime/scheduler.zig", .deps = &.{ "green_thread", "work_queue", "netpoller" } },
    .{ .name = "tokenizer", .path = "packages/tokenizer/src/tokenizer.zig", .deps = &.{ "json", "utils.hashmap_helper" } },

    // Runtime - imports modules needed by Lib/ submodules
    .{ .name = "runtime", .path = "packages/runtime/src/runtime.zig", .deps = &.{
        "utils.allocator_helper",
        "utils.hashmap_helper",
        "bigint",
        "gzip",
        "regex",
        "tokenizer",
        "green_thread",
        "netpoller",
        "scheduler",
    } },

    // Collections - shared data structures (for c_interop)
    .{ .name = "collections", .path = "packages/collections/collections.zig", .deps = &.{"runtime"} },

    // C interop - enables C extension support (numpy, pytorch, etc.)
    .{ .name = "c_interop", .path = "packages/c_interop/src/registry.zig", .deps = &.{
        "runtime",
        "collections",
        "utils.hashmap_helper",
    } },

    // allocator_helper - only used by main, must be last before main
    .{ .name = "utils.allocator_helper", .path = "src/utils/allocator_helper.zig", .deps = &.{} },
};

/// Add C source files for libdeflate (used by gzip module)
fn addCSourceFiles(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8)) !void {
    // Include path for @cImport in gzip module
    try args.append(allocator, "-I");
    try args.append(allocator, "vendor/libdeflate");

    // C source files with compiler flags
    // Always disable AVX-512 for maximum reliability across all platforms
    try args.append(allocator, "-cflags");
    try args.append(allocator, "-std=c99");
    try args.append(allocator, "-O3");

    // Always disable AVX-512 for reliability
    try args.append(allocator, "-DLIBDEFLATE_ASSEMBLER_DOES_NOT_SUPPORT_AVX512VNNI");
    try args.append(allocator, "-DLIBDEFLATE_ASSEMBLER_DOES_NOT_SUPPORT_VPCLMULQDQ");

    try args.append(allocator, "--");

    const libdeflate_srcs = [_][]const u8{
        "vendor/libdeflate/lib/deflate_compress.c",
        "vendor/libdeflate/lib/deflate_decompress.c",
        "vendor/libdeflate/lib/utils.c",
        "vendor/libdeflate/lib/gzip_compress.c",
        "vendor/libdeflate/lib/gzip_decompress.c",
        "vendor/libdeflate/lib/zlib_compress.c",
        "vendor/libdeflate/lib/zlib_decompress.c",
        "vendor/libdeflate/lib/adler32.c",
        "vendor/libdeflate/lib/crc32.c",
        "vendor/libdeflate/lib/arm/cpu_features.c",
        "vendor/libdeflate/lib/x86/cpu_features.c",
    };
    for (libdeflate_srcs) |src| {
        try args.append(allocator, src);
    }
}

/// Build module flags for zig build-exe -M and --dep
/// IMPORTANT: Modules must be defined in REVERSE dependency order!
/// Order: main -> runtime -> ... -> leaf modules
/// Each module's deps are declared BEFORE the module's -M flag
/// zig_code is used to filter which package modules to include (Zig 0.15 errors on unused modules)
fn buildModuleFlags(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8), main_path: []const u8, zig_code: []const u8) !void {
    // 1. C source files first
    try addCSourceFiles(allocator, args);

    // 2. Main module FIRST with ALL its deps
    // In Zig 0.15, --dep flags apply to the NEXT -M flag, so order is critical
    // Main module deps: runtime, c_interop, hashmap_helper, allocator_helper, + any package modules
    try args.append(allocator, "--dep");
    try args.append(allocator, "runtime");
    try args.append(allocator, "--dep");
    try args.append(allocator, "c_interop");
    try args.append(allocator, "--dep");
    try args.append(allocator, "utils.hashmap_helper");
    try args.append(allocator, "--dep");
    try args.append(allocator, "utils.allocator_helper");

    // 2.5 Add package deps (numpy, pytest, etc.) as deps for main
    // This ONLY adds --dep flags, not -M flags
    try addPackageDepFlags(allocator, args, zig_code);

    // Now declare the main module (all --dep flags above apply to this -M)
    // In Zig 0.15, the generated code must have an export function to mark the module as "used"
    // See genExportMarker() in codegen which adds: export fn _metal0_module_marker() callconv(.c) void {}
    const main_flag = try std.fmt.allocPrint(allocator, "-Mmain={s}", .{main_path});
    try args.append(allocator, main_flag);

    // 2.6 Add package module declarations (numpy, pytest, etc.) AFTER main
    // Each package needs its own deps followed by its -M declaration
    try addPackageModuleFlags(allocator, args, zig_code);

    // 3. Modules in REVERSE order (dependents before dependencies)
    // This is the reverse of MODULES array
    var i: usize = MODULES.len;
    while (i > 0) {
        i -= 1;
        const mod = MODULES[i];

        // --dep BEFORE the module that needs the dependency
        for (mod.deps) |dep| {
            try args.append(allocator, "--dep");
            try args.append(allocator, dep);
        }

        // -Mname=path
        const m_flag = try std.fmt.allocPrint(allocator, "-M{s}={s}", .{ mod.name, mod.path });
        try args.append(allocator, m_flag);
    }
}

/// Add package dependency flags (--dep only) for main module
/// This is called BEFORE -Mmain to set up deps for the main module
fn addPackageDepFlags(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8), zig_code: []const u8) !void {
    const manifest_path = build_dirs.CACHE ++ "/package_modules.txt";

    const file = std.fs.cwd().openFile(manifest_path, .{}) catch {
        return; // No manifest - that's fine, no external packages
    };
    defer file.close();

    var buf: [256 * 1024]u8 = undefined;
    const content_len = file.readAll(&buf) catch return;
    const content = buf[0..content_len];

    // Parse manifest: each line is "module_name:absolute_path"
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        const colon_idx = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const mod_name = line[0..colon_idx];

        if (mod_name.len == 0) continue;

        // Only add package if it's actually imported in the generated code
        var import_pattern_buf: [128]u8 = undefined;
        const import_pattern = std.fmt.bufPrint(&import_pattern_buf, "@import(\"{s}\")", .{mod_name}) catch continue;

        if (std.mem.indexOf(u8, zig_code, import_pattern) == null) {
            continue; // Skip this package - not used
        }

        // Add --dep for main to depend on this package
        try args.append(allocator, "--dep");
        // IMPORTANT: Allocate a copy since mod_name is a slice into a stack buffer
        const mod_name_copy = try allocator.dupe(u8, mod_name);
        try args.append(allocator, mod_name_copy);
    }
}

/// Add package module declarations from .metal0/package_modules.txt manifest
/// This is called AFTER -Mmain to declare package modules with their deps
fn addPackageModuleFlags(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8), zig_code: []const u8) !void {
    const manifest_path = build_dirs.CACHE ++ "/package_modules.txt";

    const file = std.fs.cwd().openFile(manifest_path, .{}) catch {
        return; // No manifest - that's fine, no external packages
    };
    defer file.close();

    var buf: [256 * 1024]u8 = undefined;
    const content_len = file.readAll(&buf) catch return;
    const content = buf[0..content_len];

    // Parse manifest: each line is "module_name:absolute_path"
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        const colon_idx = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const mod_name = line[0..colon_idx];
        const mod_path = line[colon_idx + 1 ..];

        if (mod_name.len == 0 or mod_path.len == 0) continue;

        // Only add package if it's actually imported in the generated code
        var import_pattern_buf: [128]u8 = undefined;
        const import_pattern = std.fmt.bufPrint(&import_pattern_buf, "@import(\"{s}\")", .{mod_name}) catch continue;
        if (std.mem.indexOf(u8, zig_code, import_pattern) == null) {
            continue; // Skip this package - not used
        }

        // Package modules need runtime and c_interop dependencies (--dep BEFORE -M)
        try args.append(allocator, "--dep");
        try args.append(allocator, "runtime");
        try args.append(allocator, "--dep");
        try args.append(allocator, "c_interop");
        try args.append(allocator, "--dep");
        try args.append(allocator, "utils.hashmap_helper");
        try args.append(allocator, "--dep");
        try args.append(allocator, "utils.allocator_helper");

        // -Mname=path
        const m_flag = try std.fmt.allocPrint(allocator, "-M{s}={s}", .{ mod_name, mod_path });
        try args.append(allocator, m_flag);
    }
}

/// PGO (Profile-Guided Optimization) options
pub const PgoOptions = struct {
    generate: bool = false, // --pgo-generate: Build with instrumentation
    use_profile: ?[]const u8 = null, // --pgo-use: Path to profile data
};

/// Compile Zig source code to native binary
/// When debug_mode is true, compiles with -ODebug for DWARF debug info
pub fn compileZig(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8, c_libraries: []const []const u8) !void {
    return compileZigWithOptions(allocator, zig_code, output_path, c_libraries, false, .{});
}

/// Compile Zig source code to native binary with debug and PGO options
pub fn compileZigWithOptions(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8, c_libraries: []const []const u8, debug_mode: bool, pgo: PgoOptions) !void {
    // Use arena for all intermediate allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Initialize directory structure (for output)
    try build_dirs.init();

    const build_dir = build_dirs.CACHE;

    // Write Zig code to temporary file (use output_path basename for uniqueness in parallel builds)
    const out_basename = std.fs.path.basename(output_path);
    const out_stem = if (std.mem.lastIndexOf(u8, out_basename, ".")) |idx| out_basename[0..idx] else out_basename;
    const tmp_path = try std.fmt.allocPrint(aa, "{s}/metal0_main_{s}_{d}.zig", .{ build_dir, out_stem, std.time.milliTimestamp() });

    // Write temp file
    const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
    defer tmp_file.close();

    try tmp_file.writeAll(zig_code);

    // Shell out to zig build-exe
    const zig_path = try findZigBinary(aa);

    const output_flag = try std.fmt.allocPrint(aa, "-femit-bin={s}", .{output_path});

    // Build argument list
    var args = std.ArrayList([]const u8){};

    try args.append(aa, zig_path);
    try args.append(aa, "build-exe");

    // Add all module definitions including main (-M and --dep flags)
    // This replaces file copying + patching with native Zig module system
    try buildModuleFlags(aa, &args, tmp_path, zig_code);

    // Use debug mode for DWARF info, release for performance
    if (debug_mode) {
        try args.append(aa, "-ODebug");
        // Keep stack checks in debug mode for better debugging
    } else {
        try args.append(aa, "-OReleaseFast");
        try args.append(aa, "-fno-stack-check"); // ~1.08x speedup
    }

    // PGO (Profile-Guided Optimization) flags
    if (pgo.generate) {
        std.debug.print("PGO: Generate mode enabled (use perf/Instruments to profile)\n", .{});
    } else if (pgo.use_profile) |profile_path| {
        std.debug.print("PGO: Using profile data from {s}\n", .{profile_path});
    }

    try args.append(aa, "-lc");

    // Add dynamically detected C libraries
    for (c_libraries) |lib| {
        const lib_flag = try std.fmt.allocPrint(aa, "-l{s}", .{lib});
        try args.append(aa, lib_flag);
    }

    // Add BLAS linking ONLY if explicitly needed
    const needs_blas = c_libraries.len > 0;
    const has_blas = blk: {
        for (c_libraries) |lib| {
            if (std.mem.eql(u8, lib, "openblas") or std.mem.eql(u8, lib, "blas")) {
                break :blk true;
            }
        }
        break :blk false;
    };

    if (needs_blas and !has_blas) {
        if (builtin.os.tag == .macos) {
            try args.append(aa, "-framework");
            try args.append(aa, "Accelerate");
        } else if (builtin.os.tag == .linux) {
            try args.append(aa, "-lopenblas");
        }
    }

    // Add Metal framework on macOS for GPU acceleration
    if (builtin.os.tag == .macos) {
        try args.append(aa, "-framework");
        try args.append(aa, "Metal");
        try args.append(aa, "-framework");
        try args.append(aa, "Foundation");
    }

    try args.append(aa, output_flag);

    const argv = try args.toOwnedSlice(aa);

    // Use spawn + timeout instead of blocking run (10s timeout for compilation)
    // If Zig can't compile in 10s, the generated code likely has comptime explosion
    const timeout_ns: u64 = 10 * std.time.ns_per_s;

    var child = std.process.Child.init(argv, aa);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var done = std.atomic.Value(bool).init(false);

    child.spawn() catch |err| {
        std.debug.print("Failed to spawn Zig compiler: {any}\n", .{err});
        return error.ZigCompilationFailed;
    };

    // Start killer thread
    const killer = std.Thread.spawn(.{}, killAfterTimeout, .{ &child, timeout_ns, &done }) catch null;

    // Read stderr while waiting
    var stderr_list = std.ArrayList(u8){};
    defer stderr_list.deinit(aa);

    if (child.stderr) |stderr| {
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = stderr.read(&buf) catch break;
            if (n == 0) break;
            stderr_list.appendSlice(aa, buf[0..n]) catch break;
        }
    }

    const term = child.wait() catch |err| {
        done.store(true, .seq_cst);
        if (killer) |k| k.join();
        std.debug.print("Failed to wait for Zig compiler: {any}\n", .{err});
        return error.ZigCompilationFailed;
    };

    done.store(true, .seq_cst);
    if (killer) |k| k.join();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Zig compilation failed:\n{s}\n", .{stderr_list.items});
                return error.ZigCompilationFailed;
            }
        },
        .Signal => |sig| {
            if (comptime builtin.os.tag != .windows) {
                if (sig == std.posix.SIG.KILL) {
                    std.debug.print("Zig compilation timed out (>{d}s)\n", .{timeout_ns / std.time.ns_per_s});
                } else {
                    std.debug.print("Zig compilation killed by signal {d}:\n{s}\n", .{ sig, stderr_list.items });
                }
            } else {
                std.debug.print("Zig compilation terminated (signal {d}):\n{s}\n", .{ sig, stderr_list.items });
            }
            return error.ZigCompilationFailed;
        },
        .Stopped => |sig| {
            std.debug.print("Zig compilation stopped by signal {d}:\n{s}\n", .{ sig, stderr_list.items });
            return error.ZigCompilationFailed;
        },
        .Unknown => |val| {
            std.debug.print("Zig compilation unknown termination {d}:\n{s}\n", .{ val, stderr_list.items });
            return error.ZigCompilationFailed;
        },
    }
}

fn killAfterTimeout(child: *std.process.Child, timeout_ns: u64, done: *std.atomic.Value(bool)) void {
    const poll_interval: u64 = 100 * std.time.ns_per_ms; // Check every 100ms
    var elapsed: u64 = 0;
    while (elapsed < timeout_ns) {
        if (done.load(.seq_cst)) return;
        std.Thread.sleep(poll_interval);
        elapsed += poll_interval;
    }
    // Timeout - kill the process using cross-platform Child.kill()
    if (!done.load(.seq_cst)) {
        _ = child.kill() catch {};
    }
}

/// Compile Zig source code to shared library (.so/.dylib)
/// source_dir: Optional directory where the generated .zig submodules are (for relative import resolution)
///             If null, uses the output_path directory
pub fn compileZigSharedLib(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8, c_libraries: []const []const u8, source_dir: ?[]const u8) !void {
    // Use arena for all intermediate allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    try build_dirs.init();

    // Write Zig code to temporary file in the SAME DIRECTORY as the generated submodules
    // This is critical for relative imports like @import("./version.zig") to work correctly
    // source_dir is where the generated .zig files are (e.g., .metal0/gen/venv/.../numpy/)
    // output_path is where the binary goes (may be different, e.g., .venv/.../numpy/.metal0/)
    const src_dir = source_dir orelse (std.fs.path.dirname(output_path) orelse ".");
    const out_basename = std.fs.path.basename(output_path);
    const out_stem = if (std.mem.lastIndexOf(u8, out_basename, ".")) |idx| out_basename[0..idx] else out_basename;
    const tmp_path = try std.fmt.allocPrint(aa, "{s}/metal0_main_{s}_{d}.zig", .{ src_dir, out_stem, std.time.milliTimestamp() });

    // Ensure the source directory exists before creating the temp file
    std.fs.cwd().makePath(src_dir) catch {};

    const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
    defer tmp_file.close();
    try tmp_file.writeAll(zig_code);

    // Shell out to zig build-lib
    const zig_path = try findZigBinary(aa);
    const output_flag = try std.fmt.allocPrint(aa, "-femit-bin={s}", .{output_path});

    var args = std.ArrayList([]const u8){};

    try args.append(aa, zig_path);
    try args.append(aa, "build-lib");

    // Add all module definitions including main (C source files included)
    try buildModuleFlags(aa, &args, tmp_path, zig_code);

    try args.append(aa, "-OReleaseFast");
    try args.append(aa, "-fno-stack-check");
    try args.append(aa, "-dynamic");
    try args.append(aa, "-lc");

    // Add dynamically detected C libraries
    for (c_libraries) |lib| {
        const lib_flag = try std.fmt.allocPrint(aa, "-l{s}", .{lib});
        try args.append(aa, lib_flag);
    }

    // Add BLAS linking if needed
    const needs_blas = c_libraries.len > 0;
    const has_blas = blk: {
        for (c_libraries) |lib| {
            if (std.mem.eql(u8, lib, "openblas") or std.mem.eql(u8, lib, "blas")) {
                break :blk true;
            }
        }
        break :blk false;
    };

    if (needs_blas and !has_blas) {
        if (builtin.os.tag == .macos) {
            try args.append(aa, "-framework");
            try args.append(aa, "Accelerate");
        } else if (builtin.os.tag == .linux) {
            try args.append(aa, "-lopenblas");
        }
    }

    // Add Metal framework on macOS for GPU acceleration
    if (builtin.os.tag == .macos) {
        try args.append(aa, "-framework");
        try args.append(aa, "Metal");
        try args.append(aa, "-framework");
        try args.append(aa, "Foundation");
    }

    try args.append(aa, output_flag);

    const argv = try args.toOwnedSlice(aa);

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = argv,
    });

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Zig compilation failed:\n{s}\n", .{result.stderr});
                return error.ZigCompilationFailed;
            }
        },
        .Signal, .Stopped, .Unknown => {
            std.debug.print("Zig compilation terminated abnormally:\n{s}\n", .{result.stderr});
            return error.ZigCompilationFailed;
        },
    }
}

/// Compile Zig source code to static library (.a)
/// Used for @logic_table output that can be linked into other projects
pub fn compileZigStaticLib(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8) !void {
    // Use arena for all intermediate allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    try build_dirs.init();
    const build_dir = build_dirs.CACHE;

    // Write Zig code to temporary file
    const out_basename = std.fs.path.basename(output_path);
    const out_stem = if (std.mem.lastIndexOf(u8, out_basename, ".")) |idx| out_basename[0..idx] else out_basename;
    const tmp_path = try std.fmt.allocPrint(aa, "{s}/logic_table_{s}_{d}.zig", .{ build_dir, out_stem, std.time.milliTimestamp() });

    const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
    defer tmp_file.close();
    try tmp_file.writeAll(zig_code);

    // Shell out to zig build-lib (static)
    const zig_path = try findZigBinary(aa);
    const output_flag = try std.fmt.allocPrint(aa, "-femit-bin={s}", .{output_path});

    var args = std.ArrayList([]const u8){};

    try args.append(aa, zig_path);
    try args.append(aa, "build-lib");

    // Add all module definitions including main (runtime, c_interop, etc.)
    try buildModuleFlags(aa, &args, tmp_path, zig_code);

    try args.append(aa, "-OReleaseFast");
    try args.append(aa, "-fno-stack-check");
    // No -dynamic flag = static library
    try args.append(aa, "-lc");

    // Add Accelerate framework on macOS for numpy/scipy operations
    if (builtin.os.tag == .macos) {
        try args.append(aa, "-framework");
        try args.append(aa, "Accelerate");
    }

    try args.append(aa, output_flag);

    const argv = try args.toOwnedSlice(aa);

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = argv,
    });

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Static lib compilation failed:\n{s}\n", .{result.stderr});
                return error.ZigCompilationFailed;
            }
        },
        .Signal, .Stopped, .Unknown => {
            std.debug.print("Static lib compilation terminated abnormally:\n{s}\n", .{result.stderr});
            return error.ZigCompilationFailed;
        },
    }
}

/// Compile Zig source code to WASM binary with target selection
pub fn compileWasmWithTarget(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8, target: @import("main.zig").CompileOptions.Target, exports: []const []const u8) !void {
    return compileWasmInternal(allocator, zig_code, output_path, target, exports);
}

/// Compile Zig source code to WASM binary (legacy - uses wasm32-wasi)
pub fn compileWasm(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8) !void {
    return compileWasmInternal(allocator, zig_code, output_path, .wasm_edge, &.{});
}

fn compileWasmInternal(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8, target: @import("main.zig").CompileOptions.Target, exports: []const []const u8) !void {
    // Use arena for all intermediate allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    try build_dirs.init();
    const build_dir = build_dirs.CACHE;

    // Write Zig code to temporary file (use output_path basename for uniqueness in parallel builds)
    const out_basename = std.fs.path.basename(output_path);
    const out_stem = if (std.mem.lastIndexOf(u8, out_basename, ".")) |idx| out_basename[0..idx] else out_basename;
    const tmp_path = try std.fmt.allocPrint(aa, "{s}/metal0_main_{s}_{d}.zig", .{ build_dir, out_stem, std.time.milliTimestamp() });

    const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
    defer tmp_file.close();
    try tmp_file.writeAll(zig_code);

    // Shell out to zig build-exe with WASM target
    const zig_path = try findZigBinary(aa);
    const output_flag = try std.fmt.allocPrint(aa, "-femit-bin={s}", .{output_path});

    var args = std.ArrayList([]const u8){};

    try args.append(aa, zig_path);
    try args.append(aa, "build-exe");

    // WASM target selection - MUST come before -M flags in Zig 0.15
    try args.append(aa, "-target");
    switch (target) {
        .wasm_browser => {
            try args.append(aa, "wasm32-freestanding");
            try args.append(aa, "-OReleaseSmall");
        },
        .wasm_edge => {
            try args.append(aa, "wasm32-wasi");
            try args.append(aa, "-OReleaseFast");
        },
        else => {
            try args.append(aa, "wasm32-wasi");
            try args.append(aa, "-OReleaseSmall");
        },
    }
    try args.append(aa, "-fno-stack-check");

    // Module declarations with proper --dep chains (Zig 0.15 requirement)
    // Each --dep adds to the NEXT module's import table
    // Main module needs: runtime, utils.hashmap_helper, utils.allocator_helper
    try args.append(aa, "--dep");
    try args.append(aa, "runtime");
    try args.append(aa, "--dep");
    try args.append(aa, "utils.hashmap_helper");
    try args.append(aa, "--dep");
    try args.append(aa, "utils.allocator_helper");
    const main_flag = try std.fmt.allocPrint(aa, "-Mmain={s}", .{tmp_path});
    try args.append(aa, main_flag);

    // Runtime module needs: utils.hashmap_helper, bigint
    try args.append(aa, "--dep");
    try args.append(aa, "utils.hashmap_helper");
    try args.append(aa, "--dep");
    try args.append(aa, "bigint");
    try args.append(aa, "-Mruntime=packages/runtime/src/runtime.zig");

    // Utility modules (no deps)
    try args.append(aa, "-Mutils.hashmap_helper=src/utils/hashmap_helper.zig");
    try args.append(aa, "-Mutils.allocator_helper=src/utils/allocator_helper.zig");
    try args.append(aa, "-Mbigint=packages/bigint/src/bigint.zig");

    // Add --export flags for each function to export
    for (exports) |export_name| {
        const export_flag = try std.fmt.allocPrint(aa, "--export={s}", .{export_name});
        try args.append(aa, export_flag);
    }

    try args.append(aa, output_flag);

    const argv = try args.toOwnedSlice(aa);

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = argv,
        .max_output_bytes = 10 * 1024 * 1024,
    });

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("WASM compilation failed:\n{s}\n", .{result.stderr});
                return error.WasmCompilationFailed;
            }
        },
        .Signal, .Stopped, .Unknown => {
            std.debug.print("WASM compilation terminated abnormally:\n{s}\n", .{result.stderr});
            return error.WasmCompilationFailed;
        },
    }
}

fn findZigBinary(allocator: std.mem.Allocator) ![]const u8 {
    // Try to find zig in PATH
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "which", "zig" },
    }) catch {
        return try allocator.dupe(u8, "zig");
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code == 0) {
                const path = std.mem.trim(u8, result.stdout, " \n\r\t");
                return try allocator.dupe(u8, path);
            }
        },
        .Signal, .Stopped, .Unknown => {},
    }

    return try allocator.dupe(u8, "zig");
}
