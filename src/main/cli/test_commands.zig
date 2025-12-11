/// Test command: Bun-style parallel test runner
/// Usage: metal0 test <dir> [patterns...] [options]
const std = @import("std");
const CompileOptions = @import("../../main.zig").CompileOptions;
const compile_mod = @import("../compile.zig");
const compiler = @import("../../compiler.zig");
const build_dirs = @import("../../build_dirs.zig");
const incremental = @import("../compile/incremental.zig");
const Color = @import("common.zig").Color;
const printSuccess = @import("common.zig").printSuccess;
const printError = @import("common.zig").printError;
const printWarn = @import("common.zig").printWarn;

/// Bun-style test command: metal0 test <dir> [patterns...] [options]
/// Options:
///   --timeout=N      Per-test timeout in seconds (default: 5)
///   --bail=N         Stop after N failures (default: 0 = no limit)
///   --jobs=N         Parallelism (default: CPU count)
///   --dots           Compact dot output (. = pass, x = fail, ? = timeout)
///   -t, --filter=P   Only run tests matching pattern P
///   --help           Show help
///
/// Examples:
///   metal0 test tests/cpython                    # Run all tests
///   metal0 test tests/cpython bool float         # Only test_bool.py, test_float.py
///   metal0 test tests/cpython -t "test_add"      # Filter by test name
///   metal0 test tests/cpython --timeout=10       # 10s per test (default: 5s)
///   metal0 test tests/cpython --bail=5           # Stop after 5 failures
pub fn cmdTest(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Parse options
    var test_dir: []const u8 = "tests/cpython";
    var timeout_sec: u64 = 5; // Default 5s per test - we're the fastest runtime, fail fast!
    var bail_count: usize = 0; // 0 = no limit
    var jobs: usize = std.Thread.getCpuCount() catch 8;
    var dots_mode: bool = false;
    var filter_pattern: ?[]const u8 = null;
    var file_patterns = std.ArrayList([]const u8){};
    defer file_patterns.deinit(allocator);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print(
                \\{s}metal0 test{s} - Fast parallel test runner
                \\
                \\{s}Usage:{s}
                \\  metal0 test [dir] [patterns...] [options]
                \\
                \\{s}Options:{s}
                \\  --timeout=N      Per-test timeout in seconds (default: 5)
                \\  --bail=N         Stop after N failures (default: 0 = no limit)
                \\  --jobs=N         Parallelism (default: CPU count)
                \\  --dots           Compact dot output (. = pass, x = fail, ? = timeout)
                \\  -t, --filter=P   Only run tests matching pattern P
                \\  --help           Show this help
                \\
                \\{s}Examples:{s}
                \\  metal0 test tests/cpython                    # Run all tests
                \\  metal0 test tests/cpython bool float         # Only test_bool.py, test_float.py
                \\  metal0 test tests/cpython -t "add|sub"       # Filter by test name regex
                \\  metal0 test tests/cpython --timeout=10       # 10s per test (default: 5s)
                \\  metal0 test tests/cpython --bail=5 --dots    # Stop after 5 failures, compact output
                \\
            , .{ Color.bold, Color.reset, Color.bold, Color.reset, Color.bold, Color.reset, Color.bold, Color.reset });
            return;
        } else if (std.mem.startsWith(u8, arg, "--timeout=")) {
            timeout_sec = std.fmt.parseInt(u64, arg["--timeout=".len..], 10) catch 5;
        } else if (std.mem.startsWith(u8, arg, "--bail=")) {
            bail_count = std.fmt.parseInt(usize, arg["--bail=".len..], 10) catch 0;
        } else if (std.mem.startsWith(u8, arg, "--jobs=")) {
            jobs = std.fmt.parseInt(usize, arg["--jobs=".len..], 10) catch jobs;
        } else if (std.mem.eql(u8, arg, "--dots")) {
            dots_mode = true;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--filter")) {
            i += 1;
            if (i < args.len) filter_pattern = args[i];
        } else if (std.mem.startsWith(u8, arg, "--filter=")) {
            filter_pattern = arg["--filter=".len..];
        } else if (std.mem.startsWith(u8, arg, "-t=")) {
            filter_pattern = arg["-t=".len..];
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            // First non-flag is directory, rest are patterns
            if (i == 0 or (i == 1 and std.mem.endsWith(u8, args[0], "test"))) {
                test_dir = arg;
            } else {
                try file_patterns.append(allocator, arg);
            }
        }
    }

    // If first positional looks like a directory, use it
    if (args.len > 0 and !std.mem.startsWith(u8, args[0], "-")) {
        test_dir = args[0];
    }

    const run_timeout_ns = timeout_sec * std.time.ns_per_s;
    const ncpu = jobs;

    if (!dots_mode) {
        std.debug.print("=== metal0 test ({s}) ===\n", .{test_dir});
        if (file_patterns.items.len > 0) {
            std.debug.print("Patterns: ", .{});
            for (file_patterns.items, 0..) |p, idx| {
                if (idx > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{p});
            }
            std.debug.print("\n", .{});
        }
        if (filter_pattern) |f| std.debug.print("Filter: {s}\n", .{f});
    }

    // Phase 0: Ensure cache dirs exist and runtime archive is built
    try build_dirs.init();

    // Ensure bin output dir exists
    std.fs.cwd().makeDir(".metal0/bin") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Build runtime archive if needed (ONE TIME - cached for all tests)
    // This is the key optimization: compile runtime once, link 390 times
    if (!dots_mode) std.debug.print("Checking runtime archive...\n", .{});
    incremental.ensureRuntimeArchive(allocator) catch |err| {
        printWarn("Runtime archive unavailable ({any}), using full compilation", .{err});
    };

    // Discover test files (with pattern matching)
    var test_files = std.ArrayList([]const u8){};
    defer {
        for (test_files.items) |f| allocator.free(f);
        test_files.deinit(allocator);
    }

    var dir = std.fs.cwd().openDir(test_dir, .{ .iterate = true }) catch {
        printError("Cannot open test directory: {s}", .{test_dir});
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.startsWith(u8, entry.name, "test_") and std.mem.endsWith(u8, entry.name, ".py")) {
            // Check file patterns (e.g., "bool" matches "test_bool.py")
            if (file_patterns.items.len > 0) {
                var matched = false;
                for (file_patterns.items) |pattern| {
                    if (std.mem.indexOf(u8, entry.name, pattern) != null) {
                        matched = true;
                        break;
                    }
                }
                if (!matched) continue;
            }

            const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ test_dir, entry.name });
            try test_files.append(allocator, path);
        }
    }

    const total = test_files.items.len;
    if (total == 0) {
        printWarn("No test files found in {s}", .{test_dir});
        if (file_patterns.items.len > 0) {
            std.debug.print("  (filtered by patterns: ", .{});
            for (file_patterns.items, 0..) |p, idx| {
                if (idx > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{p});
            }
            std.debug.print(")\n", .{});
        }
        return;
    }

    if (!dots_mode) {
        std.debug.print("Found {d} tests, using {d} workers (timeout: {d}s", .{ total, ncpu, timeout_sec });
        if (bail_count > 0) std.debug.print(", bail: {d}", .{bail_count});
        std.debug.print(")\n\n", .{});
    }

    // Get compiler mtime - invalidate cache if compiler is newer than cached files
    const compiler_mtime: i128 = blk: {
        // Get self exe path
        var path_buf: [4096]u8 = undefined;
        const self_exe = std.fs.selfExePath(&path_buf) catch break :blk 0;
        const stat = std.fs.cwd().statFile(self_exe) catch break :blk 0;
        break :blk stat.mtime;
    };

    // Phase 1: Parallel codegen (.py → .zig)
    // Use batched processing with arena reset to prevent memory accumulation
    // CACHING: Skip codegen if .zig file exists and is newer than .py source
    if (!dots_mode) std.debug.print("Phase 1: Codegen...\n", .{});
    var codegen_ok: usize = 0;
    var codegen_cached: usize = 0;
    var zig_files = std.ArrayList([]const u8){};
    defer {
        for (zig_files.items) |f| allocator.free(f);
        zig_files.deinit(allocator);
    }

    const BATCH_SIZE = 50; // Process in batches to limit memory
    var batch_start: usize = 0;
    while (batch_start < test_files.items.len) {
        const batch_end = @min(batch_start + BATCH_SIZE, test_files.items.len);

        for (test_files.items[batch_start..batch_end]) |file_path| {
            // Get the generated zig file path
            const basename = std.fs.path.basename(file_path);
            const stem = if (std.mem.lastIndexOf(u8, basename, ".")) |idx| basename[0..idx] else basename;
            const zig_path = try std.fmt.allocPrint(allocator, "{s}/{s}.zig", .{ build_dirs.CACHE, stem });

            // CACHING: Check if .zig file is newer than .py source AND compiler
            const needs_codegen = blk: {
                const py_stat = std.fs.cwd().statFile(file_path) catch break :blk true;
                const zig_stat = std.fs.cwd().statFile(zig_path) catch break :blk true;
                // Regenerate if: zig older than py, OR zig older than compiler
                if (zig_stat.mtime < py_stat.mtime) break :blk true;
                if (compiler_mtime > 0 and zig_stat.mtime < compiler_mtime) break :blk true;
                break :blk false;
            };

            if (needs_codegen) {
                const opts = CompileOptions{ .input_file = file_path, .mode = "build", .force = false, .emit_zig_only = true };
                compile_mod.compileFile(allocator, opts) catch {
                    allocator.free(zig_path);
                    continue;
                };
                codegen_ok += 1;
            } else {
                codegen_cached += 1;
            }

            try zig_files.append(allocator, zig_path);
        }

        batch_start = batch_end;
    }
    if (!dots_mode) std.debug.print("  Codegen: {d}/{d} (cached: {d})\n", .{ codegen_ok + codegen_cached, total, codegen_cached });

    if (codegen_ok == 0 and codegen_cached == 0) {
        printError("All codegen failed", .{});
        return;
    }

    // Phase 2: Parallel compile using thread pool (.zig → binary)
    // CACHING: Skip compilation if binary exists and is newer than .zig file AND compiler
    if (!dots_mode) std.debug.print("Phase 2: Compile (parallel)...\n", .{});
    var compile_ok = std.atomic.Value(usize).init(0);
    var compile_cached = std.atomic.Value(usize).init(0);
    var bin_paths = std.ArrayList([]const u8){};
    defer {
        for (bin_paths.items) |p| allocator.free(p);
        bin_paths.deinit(allocator);
    }

    // Build list of files that need compilation vs cached
    const CompileTask = struct {
        zig_path: []const u8,
        bin_path: []const u8,
        needs_compile: bool,
    };
    var tasks = std.ArrayList(CompileTask){};
    defer tasks.deinit(allocator);

    for (zig_files.items) |zig_path| {
        std.fs.cwd().access(zig_path, .{}) catch continue;

        const basename = std.fs.path.basename(zig_path);
        const stem = if (std.mem.lastIndexOf(u8, basename, ".")) |idx| basename[0..idx] else basename;
        const bin_path = try std.fmt.allocPrint(allocator, ".metal0/bin/{s}", .{stem});

        const needs_compile = blk: {
            const zig_stat = std.fs.cwd().statFile(zig_path) catch break :blk true;
            const bin_stat = std.fs.cwd().statFile(bin_path) catch break :blk true;
            if (bin_stat.mtime < zig_stat.mtime) break :blk true;
            if (compiler_mtime > 0 and bin_stat.mtime < compiler_mtime) break :blk true;
            break :blk false;
        };

        try tasks.append(allocator, .{ .zig_path = zig_path, .bin_path = bin_path, .needs_compile = needs_compile });
        try bin_paths.append(allocator, bin_path);
    }

    // Compile in parallel using thread pool
    const num_compile_threads = @min(ncpu, tasks.items.len);
    if (num_compile_threads > 0) {
        var threads: [32]std.Thread = undefined;
        const actual_threads = @min(num_compile_threads, 32);

        const CompileContext = struct {
            tasks: []CompileTask,
            allocator: std.mem.Allocator,
            compile_ok: *std.atomic.Value(usize),
            compile_cached: *std.atomic.Value(usize),
            next_task: std.atomic.Value(usize),
            use_runtime_archive: bool,

            fn worker(ctx: *@This()) void {
                while (true) {
                    const idx = ctx.next_task.fetchAdd(1, .seq_cst);
                    if (idx >= ctx.tasks.len) break;

                    const task = ctx.tasks[idx];
                    if (!task.needs_compile) {
                        _ = ctx.compile_cached.fetchAdd(1, .seq_cst);
                        continue;
                    }

                    // Read and compile
                    const zig_file = std.fs.cwd().openFile(task.zig_path, .{}) catch continue;
                    defer zig_file.close();

                    const zig_code = zig_file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch continue;
                    defer ctx.allocator.free(zig_code);

                    // Use fast linking if runtime archive is available
                    if (ctx.use_runtime_archive) {
                        compileWithRuntimeArchive(ctx.allocator, zig_code, task.bin_path) catch {
                            // Fall back to full compilation
                            compiler.compileZigWithOptions(ctx.allocator, zig_code, task.bin_path, &.{}, false, .{}) catch continue;
                        };
                    } else {
                        compiler.compileZigWithOptions(ctx.allocator, zig_code, task.bin_path, &.{}, false, .{}) catch continue;
                    }
                    _ = ctx.compile_ok.fetchAdd(1, .seq_cst);
                }
            }
        };

        var ctx = CompileContext{
            .tasks = tasks.items,
            .allocator = allocator,
            .compile_ok = &compile_ok,
            .compile_cached = &compile_cached,
            .next_task = std.atomic.Value(usize).init(0),
            .use_runtime_archive = incremental.hasRuntimeArchive(),
        };

        // Spawn worker threads
        for (0..actual_threads) |ti| {
            threads[ti] = std.Thread.spawn(.{}, CompileContext.worker, .{&ctx}) catch continue;
        }

        // Wait for all threads
        for (0..actual_threads) |ti| {
            threads[ti].join();
        }
    }

    const final_compile_ok = compile_ok.load(.seq_cst);
    const final_compile_cached = compile_cached.load(.seq_cst);
    if (!dots_mode) std.debug.print("  Compile: {d}/{d} (cached: {d})\n", .{ final_compile_ok + final_compile_cached, codegen_ok + codegen_cached, final_compile_cached });

    // Phase 3: Run binaries
    if (!dots_mode) std.debug.print("Phase 3: Run...\n", .{});
    var run_ok: usize = 0;
    var run_fail: usize = 0;
    var run_timeout_count: usize = 0;

    for (bin_paths.items) |bin_path| {
        const result = runBinaryWithTimeout(allocator, bin_path, run_timeout_ns);
        switch (result) {
            .ok => {
                run_ok += 1;
                if (dots_mode) std.debug.print(".", .{});
            },
            .timeout => {
                run_timeout_count += 1;
                if (dots_mode) std.debug.print("?", .{});
            },
            .failed => {
                run_fail += 1;
                if (dots_mode) std.debug.print("x", .{});
            },
        }

        // Bail on N failures
        if (bail_count > 0 and run_fail >= bail_count) {
            if (dots_mode) std.debug.print("\n", .{});
            std.debug.print("\n{s}Bailed after {d} failures{s}\n", .{ Color.yellow, run_fail, Color.reset });
            break;
        }
    }

    // Summary
    if (dots_mode) std.debug.print("\n", .{});
    std.debug.print("\n", .{});

    const passed_pct = if (total > 0) @as(f64, @floatFromInt(run_ok)) / @as(f64, @floatFromInt(total)) * 100.0 else 0.0;

    if (run_ok == total) {
        printSuccess("All {d} tests passed!", .{total});
    } else {
        std.debug.print("{s}Results:{s} {s}{d}/{d} passed ({d:.1}%%){s}", .{
            Color.bold,
            Color.reset,
            if (run_ok > 0) Color.green else Color.red,
            run_ok,
            total,
            passed_pct,
            Color.reset,
        });
        if (run_fail > 0) std.debug.print(" | {s}{d} failed{s}", .{ Color.red, run_fail, Color.reset });
        if (run_timeout_count > 0) std.debug.print(" | {s}{d} timeout{s}", .{ Color.yellow, run_timeout_count, Color.reset });
        std.debug.print("\n", .{});
    }
}

const RunResult = enum { ok, timeout, failed };

fn runBinaryWithTimeout(allocator: std.mem.Allocator, bin_path: []const u8, timeout_ns: u64) RunResult {
    var child = std.process.Child.init(&[_][]const u8{bin_path}, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    // Track completion across the killer thread
    var done = std.atomic.Value(bool).init(false);

    child.spawn() catch return .failed;

    var killer = std.Thread.spawn(.{}, killAfterTimeout, .{ &child, timeout_ns, &done }) catch {
        // If we can't start the killer thread, fall back to blocking wait
        const term = child.wait() catch return .failed;
        done.store(true, .seq_cst);
        return switch (term) {
            .Exited => |code| if (code == 0) .ok else .failed,
            else => .failed,
        };
    };
    defer killer.join();

    const term = child.wait() catch return .failed;
    done.store(true, .seq_cst);

    return switch (term) {
        .Exited => |code| if (code == 0) .ok else .failed,
        else => .failed,
    };
}

fn killAfterTimeout(child: *std.process.Child, timeout_ns: u64, done: *std.atomic.Value(bool)) void {
    // Poll every 10ms to check if process has finished
    const poll_interval: u64 = 10 * std.time.ns_per_ms;
    var elapsed: u64 = 0;
    while (elapsed < timeout_ns) {
        if (done.load(.seq_cst)) return;
        std.Thread.sleep(poll_interval);
        elapsed += poll_interval;
    }
    if (done.load(.seq_cst)) return;
    _ = child.kill() catch {};
}

/// Compile a test file by linking against the precompiled runtime archive
/// This is MUCH faster than recompiling the entire runtime for each test
fn compileWithRuntimeArchive(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Write zig code to temp file
    const out_basename = std.fs.path.basename(output_path);
    const out_stem = if (std.mem.lastIndexOf(u8, out_basename, ".")) |idx| out_basename[0..idx] else out_basename;
    const tmp_path = try std.fmt.allocPrint(aa, "{s}/metal0_main_{s}_{d}.zig", .{ build_dirs.CACHE, out_stem, std.time.milliTimestamp() });

    const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
    defer tmp_file.close();
    try tmp_file.writeAll(zig_code);

    // Build command to compile main and link against runtime archive
    var args = std.ArrayList([]const u8){};

    try args.append(aa, "zig");
    try args.append(aa, "build-exe");

    // Add module flags for main module - it imports runtime, hashmap_helper, allocator_helper
    try addCSourceFiles(aa, &args);

    // Main module with deps
    try args.append(aa, "--dep");
    try args.append(aa, "runtime");
    try args.append(aa, "--dep");
    try args.append(aa, "utils.hashmap_helper");
    try args.append(aa, "--dep");
    try args.append(aa, "utils.allocator_helper");
    try args.append(aa, try std.fmt.allocPrint(aa, "-Mmain={s}", .{tmp_path}));

    // Runtime module (will be satisfied by the .a archive mostly, but we still need the module path)
    // Note: The .a contains the compiled code, but we need the module definition for types
    try addRuntimeModuleFlags(aa, &args);

    // Link against the precompiled runtime archive
    try args.append(aa, incremental.RUNTIME_ARCHIVE_PATH);

    // Use Zig's cache
    try args.append(aa, "--cache-dir");
    try args.append(aa, incremental.ZIG_CACHE_DIR);

    // Optimization
    try args.append(aa, "-OReleaseFast");
    try args.append(aa, "-fno-stack-check");
    try args.append(aa, "-lc");

    // Output
    try args.append(aa, try std.fmt.allocPrint(aa, "-femit-bin={s}", .{output_path}));

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = args.items,
        .max_output_bytes = 1024 * 1024,
    });

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                return error.CompilationFailed;
            }
        },
        else => return error.CompilationFailed,
    }
}

/// Add C source files for libdeflate (mirrors compiler.zig)
fn addCSourceFiles(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8)) !void {
    try args.append(allocator, "-I");
    try args.append(allocator, "vendor/libdeflate");

    try args.append(allocator, "-cflags");
    try args.append(allocator, "-std=c99");
    try args.append(allocator, "-O3");
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

/// Add runtime module flags (mirrors incremental.zig RUNTIME_MODULES)
fn addRuntimeModuleFlags(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8)) !void {
    // allocator_helper (no deps)
    try args.append(allocator, try std.fmt.allocPrint(allocator, "-M{s}={s}", .{ "utils.allocator_helper", "src/utils/allocator_helper.zig" }));

    // Runtime module with its deps
    for ([_][]const u8{
        "utils.hashmap_helper",
        "bigint",
        "gzip",
        "regex",
        "tokenizer",
        "green_thread",
        "netpoller",
        "scheduler",
    }) |dep| {
        try args.append(allocator, "--dep");
        try args.append(allocator, dep);
    }
    try args.append(allocator, try std.fmt.allocPrint(allocator, "-Mruntime={s}", .{"packages/runtime/src/runtime.zig"}));

    // Dependency modules in REVERSE order (dependents before dependencies)
    const ModuleDef = struct {
        name: []const u8,
        path: []const u8,
        deps: []const []const u8,
    };

    const RUNTIME_MODULES = [_]ModuleDef{
        .{ .name = "utils.hashmap_helper", .path = "src/utils/hashmap_helper.zig", .deps = &.{} },
        .{ .name = "bigint", .path = "packages/bigint/src/bigint.zig", .deps = &.{} },
        .{ .name = "green_thread", .path = "packages/runtime/src/runtime/green_thread.zig", .deps = &.{} },
        .{ .name = "gzip", .path = "packages/runtime/src/Modules/gzip/gzip.zig", .deps = &.{} },
        .{ .name = "regex", .path = "packages/regex/src/pyregex/regex.zig", .deps = &.{} },
        .{ .name = "json_simd", .path = "packages/shared/json/simd/dispatch.zig", .deps = &.{} },
        .{ .name = "json", .path = "packages/shared/json/json.zig", .deps = &.{ "json_simd", "utils.hashmap_helper" } },
        .{ .name = "netpoller", .path = "packages/runtime/src/runtime/netpoller.zig", .deps = &.{"green_thread"} },
        .{ .name = "work_queue", .path = "packages/runtime/src/runtime/work_queue.zig", .deps = &.{"green_thread"} },
        .{ .name = "scheduler", .path = "packages/runtime/src/runtime/scheduler.zig", .deps = &.{ "green_thread", "work_queue", "netpoller" } },
        .{ .name = "tokenizer", .path = "packages/tokenizer/src/tokenizer.zig", .deps = &.{ "json", "utils.hashmap_helper" } },
    };

    var i: usize = RUNTIME_MODULES.len;
    while (i > 0) {
        i -= 1;
        const mod = RUNTIME_MODULES[i];

        for (mod.deps) |dep| {
            try args.append(allocator, "--dep");
            try args.append(allocator, dep);
        }

        try args.append(allocator, try std.fmt.allocPrint(allocator, "-M{s}={s}", .{ mod.name, mod.path }));
    }
}
