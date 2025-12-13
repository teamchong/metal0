/// Test command: Zero-config fast test runner
/// Usage: metal0 test [dir] [patterns...] [@group...]
///
/// Supports @group syntax for platform-specific test groups:
///   @core    - Platform-independent tests (no skip decorators)
///   @linux   - Linux-specific tests
///   @macos   - macOS-specific tests
///   @windows - Windows-specific tests
const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const CompileOptions = @import("../../main.zig").CompileOptions;
const compile_mod = @import("../compile.zig");
const compiler = @import("../../compiler.zig");
const build_dirs = @import("../../build_dirs.zig");
const incremental = @import("../compile/incremental.zig");
const Color = @import("common.zig").Color;
const printSuccess = @import("common.zig").printSuccess;
const printError = @import("common.zig").printError;
const printWarn = @import("common.zig").printWarn;

/// Load test patterns from a group file (tests/groups/{group}.txt)
/// Returns slice of test names (e.g., ["bool", "float", "int"])
fn loadTestGroup(allocator: std.mem.Allocator, group_name: []const u8) ![]const []const u8 {
    // Try tests/groups/{group}.txt (committed to repo)
    var path_buf: [256]u8 = undefined;
    const group_path = std.fmt.bufPrint(&path_buf, "tests/groups/{s}.txt", .{group_name}) catch {
        return error.PathTooLong;
    };

    const file = std.fs.cwd().openFile(group_path, .{}) catch {
        return error.GroupFileNotFound;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return error.ReadFailed;
    };
    defer allocator.free(content);

    // Count lines
    var line_count: usize = 0;
    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        if (line.len > 0 and !std.mem.startsWith(u8, line, "#")) {
            line_count += 1;
        }
    }

    // Allocate result array
    var patterns = try allocator.alloc([]const u8, line_count);
    var idx: usize = 0;

    iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        if (line.len > 0 and !std.mem.startsWith(u8, line, "#")) {
            // For multi.txt format "name: platform1,platform2", extract just the name
            const name = if (std.mem.indexOf(u8, line, ":")) |colon_pos|
                line[0..colon_pos]
            else
                line;
            patterns[idx] = try allocator.dupe(u8, name);
            idx += 1;
        }
    }

    return patterns[0..idx];
}

/// Zero-config test runner: metal0 test [dir] [patterns...]
/// Fast by default. Fail fast. No flags needed.
///
/// Examples:
///   metal0 test tests/cpython              # Run all tests
///   metal0 test tests/cpython bool float   # Only test_bool.py, test_float.py
pub fn cmdTest(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Zero config - sensible defaults
    var test_dir: []const u8 = "tests/cpython";
    const timeout_sec: u64 = 5; // 5s per test - fail fast
    const bail_count: usize = 0; // Run all tests
    const jobs: usize = std.Thread.getCpuCount() catch 8;
    const dots_mode: bool = false;
    const batch_mode: bool = true; // Fast batch compilation
    const filter_pattern: ?[]const u8 = null;
    var file_patterns = std.ArrayList([]const u8){};
    defer file_patterns.deinit(allocator);

    // Simple arg parsing - first arg is dir, rest are patterns
    // Supports @group syntax: @core, @linux, @macos, @windows
    var first_pos = true;
    for (args) |arg| {
        if (!std.mem.startsWith(u8, arg, "-")) {
            if (first_pos) {
                test_dir = arg;
                first_pos = false;
            } else if (std.mem.startsWith(u8, arg, "@")) {
                // @group syntax - load patterns from group file
                const group_name = arg[1..]; // Remove '@'
                const group_patterns = loadTestGroup(allocator, group_name) catch |err| {
                    printWarn("Failed to load test group @{s}: {any}", .{ group_name, err });
                    continue;
                };
                for (group_patterns) |pattern| {
                    try file_patterns.append(allocator, pattern);
                }
            } else {
                try file_patterns.append(allocator, arg);
            }
        }
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

    // Clean stale cache files that don't match current test set
    // This prevents "Compile: 3/1" issues from orphaned files
    cleanStaleCache(allocator, test_files.items);

    if (!dots_mode) {
        std.debug.print("Found {d} tests, using {d} workers (timeout: {d}s", .{ total, ncpu, timeout_sec });
        if (bail_count > 0) std.debug.print(", bail: {d}", .{bail_count});
        std.debug.print(")\n\n", .{});
    }

    // Get compiler mtime - invalidate cache if compiler is newer than cached files
    const compiler_mtime: i128 = blk: {
        var path_buf: [4096]u8 = undefined;
        const self_exe = std.fs.selfExePath(&path_buf) catch break :blk 0;
        // Use openFileAbsolute for absolute paths
        const file = std.fs.openFileAbsolute(self_exe, .{}) catch break :blk 0;
        defer file.close();
        const stat = file.stat() catch break :blk 0;
        break :blk stat.mtime;
    };

    // Phase 1: Codegen (.py → .zig) - PARALLEL for speed
    if (!dots_mode) std.debug.print("Phase 1: Codegen (parallel)...\n", .{});

    // Build task list first
    const CodegenTask = struct {
        file_path: []const u8,
        zig_path: []const u8,
        needs_codegen: bool,
    };
    var codegen_tasks = std.ArrayList(CodegenTask){};
    defer codegen_tasks.deinit(allocator);

    for (test_files.items) |file_path| {
        const basename = std.fs.path.basename(file_path);
        const stem = if (std.mem.lastIndexOf(u8, basename, ".")) |idx| basename[0..idx] else basename;
        const zig_path = try std.fmt.allocPrint(allocator, "{s}/{s}.zig", .{ build_dirs.CACHE, stem });

        // Check cache
        const needs_codegen = blk: {
            const py_stat = std.fs.cwd().statFile(file_path) catch break :blk true;
            const zig_stat = std.fs.cwd().statFile(zig_path) catch break :blk true;
            if (zig_stat.mtime < py_stat.mtime) break :blk true;
            if (compiler_mtime > 0 and zig_stat.mtime < compiler_mtime) break :blk true;
            break :blk false;
        };

        try codegen_tasks.append(allocator, .{
            .file_path = file_path,
            .zig_path = zig_path,
            .needs_codegen = needs_codegen,
        });
    }

    // Run codegen in parallel
    var codegen_ok = std.atomic.Value(usize).init(0);
    var codegen_fail = std.atomic.Value(usize).init(0);
    var codegen_cached = std.atomic.Value(usize).init(0);

    const CodegenContext = struct {
        tasks: []CodegenTask,
        next_task: std.atomic.Value(usize),
        codegen_ok: *std.atomic.Value(usize),
        codegen_fail: *std.atomic.Value(usize),
        codegen_cached: *std.atomic.Value(usize),

        fn worker(ctx: *@This()) void {
            while (true) {
                const idx = ctx.next_task.fetchAdd(1, .seq_cst);
                if (idx >= ctx.tasks.len) break;

                const task = ctx.tasks[idx];
                if (!task.needs_codegen) {
                    _ = ctx.codegen_cached.fetchAdd(1, .seq_cst);
                    continue;
                }

                // Use thread-local allocator for codegen
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();

                const opts = CompileOptions{
                    .input_file = task.file_path,
                    .mode = "build",
                    .force = false,
                    .emit_zig_only = true,
                };
                compile_mod.compileFile(arena.allocator(), opts) catch {
                    _ = ctx.codegen_fail.fetchAdd(1, .seq_cst);
                    continue;
                };
                _ = ctx.codegen_ok.fetchAdd(1, .seq_cst);
            }
        }
    };

    var codegen_ctx = CodegenContext{
        .tasks = codegen_tasks.items,
        .next_task = std.atomic.Value(usize).init(0),
        .codegen_ok = &codegen_ok,
        .codegen_fail = &codegen_fail,
        .codegen_cached = &codegen_cached,
    };

    // Spawn codegen worker threads
    const num_codegen_threads = @min(ncpu, codegen_tasks.items.len);
    var codegen_threads: [32]std.Thread = undefined;
    const actual_codegen_threads = @min(num_codegen_threads, 32);

    for (0..actual_codegen_threads) |ti| {
        codegen_threads[ti] = std.Thread.spawn(.{}, CodegenContext.worker, .{&codegen_ctx}) catch continue;
    }
    for (0..actual_codegen_threads) |ti| {
        codegen_threads[ti].join();
    }

    // Build zig_files list from successful codegens
    var zig_files = std.ArrayList([]const u8){};
    defer {
        for (zig_files.items) |f| allocator.free(f);
        zig_files.deinit(allocator);
    }

    for (codegen_tasks.items) |task| {
        // Only add if codegen succeeded or was cached
        if (std.fs.cwd().access(task.zig_path, .{})) |_| {
            // zig_path was allocated earlier, keep it
            try zig_files.append(allocator, task.zig_path);
        } else |_| {
            // Failed - free the path
            allocator.free(task.zig_path);
        }
    }

    const final_codegen_ok = codegen_ok.load(.seq_cst);
    const final_codegen_cached = codegen_cached.load(.seq_cst);
    const final_codegen_fail = codegen_fail.load(.seq_cst);
    const codegen_total = final_codegen_ok + final_codegen_cached;
    if (!dots_mode) {
        std.debug.print("  Codegen: {d}/{d}", .{ codegen_total, total });
        if (final_codegen_cached > 0) std.debug.print(" (cached: {d})", .{final_codegen_cached});
        if (final_codegen_fail > 0) std.debug.print(" | {s}{d} failed{s}", .{ Color.red, final_codegen_fail, Color.reset });
        std.debug.print("\n", .{});
    }

    if (codegen_total == 0) {
        printError("All codegen failed", .{});
        return;
    }

    // Phase 2: Compile (.zig → binary)
    // Two modes:
    //   - batch_mode: Single zig build invocation (3-5x faster, shares runtime analysis)
    //   - normal mode: Parallel zig build-exe (slower but more granular caching)
    if (!dots_mode) std.debug.print("Phase 2: Compile ({s})...\n", .{if (batch_mode) "batch" else "parallel"});

    // Get runtime archive mtime - invalidate cache if runtime was rebuilt
    const runtime_mtime = incremental.getRuntimeArchiveMtime();

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
            // Also check if runtime archive was rebuilt (needs relinking)
            if (runtime_mtime > 0 and bin_stat.mtime < runtime_mtime) break :blk true;
            break :blk false;
        };

        try tasks.append(allocator, .{ .zig_path = zig_path, .bin_path = bin_path, .needs_compile = needs_compile });
        try bin_paths.append(allocator, bin_path);
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // BATCH MODE: Use single zig build invocation
    // This compiles all tests in one process, sharing runtime module analysis
    // Expected: 3-5x faster than individual compilations
    // ══════════════════════════════════════════════════════════════════════════════
    var batch_succeeded = false;
    if (batch_mode and incremental.hasBatchBuildZig()) {
        // Filter to only files needing compilation
        var needs_compile_paths = std.ArrayList([]const u8){};
        defer needs_compile_paths.deinit(allocator);

        for (tasks.items) |task| {
            if (task.needs_compile) {
                try needs_compile_paths.append(allocator, task.zig_path);
            } else {
                _ = compile_cached.fetchAdd(1, .seq_cst);
            }
        }

        if (needs_compile_paths.items.len > 0) {
            // Generate manifest and run batch compile
            try incremental.generateTestManifest(allocator, needs_compile_paths.items);

            if (incremental.batchCompileWithZigBuild(allocator, ncpu)) |result| {
                // Batch compile succeeded
                _ = compile_ok.fetchAdd(result.success, .seq_cst);
                batch_succeeded = true;
                if (!dots_mode) std.debug.print("  Batch compile: {d}/{d}\n", .{ result.success, result.total });
            } else |err| {
                printWarn("Batch compilation failed ({any}), falling back to individual compilation", .{err});
                // Reset cached count since we counted them above but will recount in individual mode
                compile_cached.store(0, .seq_cst);
            }
        } else {
            // All cached, no need to compile
            batch_succeeded = true;
        }

        // Print stats if batch succeeded
        if (batch_succeeded) {
            const final_compile_ok = compile_ok.load(.seq_cst);
            const final_compile_cached = compile_cached.load(.seq_cst);
            if (!dots_mode) std.debug.print("  Compile: {d}/{d} (cached: {d})\n", .{ final_compile_ok + final_compile_cached, codegen_total, final_compile_cached });
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // NORMAL MODE (or fallback): Compile in parallel using thread pool
    // ══════════════════════════════════════════════════════════════════════════════
    if (!batch_succeeded) {
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
        if (!dots_mode) std.debug.print("  Compile: {d}/{d} (cached: {d})\n", .{ final_compile_ok + final_compile_cached, codegen_total, final_compile_cached });
    } // End of normal/fallback mode block

    // Phase 3: Run binaries that exist
    if (!dots_mode) std.debug.print("Phase 3: Run...\n", .{});
    var run_ok: usize = 0;
    var run_fail: usize = 0;
    var run_timeout_count: usize = 0;
    var compile_fail: usize = 0;

    for (bin_paths.items) |bin_path| {
        // Skip if binary doesn't exist (compile failed)
        std.fs.cwd().access(bin_path, .{}) catch {
            compile_fail += 1;
            continue;
        };

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

    // Summary - show all failure types
    if (dots_mode) std.debug.print("\n", .{});
    std.debug.print("\n", .{});

    if (run_ok == total and final_codegen_fail == 0 and compile_fail == 0) {
        printSuccess("All {d} tests passed!", .{total});
    } else {
        const passed_pct = if (total > 0) @as(f64, @floatFromInt(run_ok)) / @as(f64, @floatFromInt(total)) * 100.0 else 0.0;
        std.debug.print("{s}Results:{s} {s}{d}/{d} passed ({d:.1}%%){s}", .{
            Color.bold,
            Color.reset,
            if (run_ok > 0) Color.green else Color.red,
            run_ok,
            total,
            passed_pct,
            Color.reset,
        });
        // Show failure breakdown
        if (final_codegen_fail > 0) std.debug.print(" | {s}{d} codegen{s}", .{ Color.red, final_codegen_fail, Color.reset });
        if (compile_fail > 0) std.debug.print(" | {s}{d} compile{s}", .{ Color.red, compile_fail, Color.reset });
        if (run_fail > 0) std.debug.print(" | {s}{d} runtime{s}", .{ Color.red, run_fail, Color.reset });
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
        "utils.allocator_helper",
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

/// Clean stale cache files that don't match current test set
/// Prevents "Compile: 3/1" issues from orphaned .zig and binary files
fn cleanStaleCache(allocator: std.mem.Allocator, test_files: []const []const u8) void {
    // Build set of valid test paths (full paths without extension)
    // e.g., "tests/cpython/test_bool" for "tests/cpython/test_bool.py"
    var valid_paths = hashmap_helper.StringHashMap(void).init(allocator);
    defer valid_paths.deinit();

    for (test_files) |test_path| {
        // Strip .py extension to get the base path
        const path_no_ext = if (std.mem.endsWith(u8, test_path, ".py"))
            test_path[0 .. test_path.len - 3]
        else
            test_path;
        valid_paths.put(path_no_ext, {}) catch continue;
    }

    // Clean .metal0/bin/ recursively - remove files that don't match current tests
    cleanDirRecursive(allocator, ".metal0/bin", &valid_paths);
}

/// Recursively clean directory, removing files not in valid_paths
fn cleanDirRecursive(allocator: std.mem.Allocator, dir_path: []const u8, valid_paths: *hashmap_helper.StringHashMap(void)) void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var walker = dir.walk(allocator) catch return;
    defer walker.deinit();

    // Collect files to delete (can't delete while iterating)
    var to_delete: std.ArrayList([]const u8) = .{};
    defer {
        for (to_delete.items) |path| allocator.free(path);
        to_delete.deinit(allocator);
    }

    while (walker.next() catch null) |entry| {
        if (entry.kind != .file) continue;

        // Convert sentinel-terminated to regular slice
        const path: []const u8 = entry.path;

        // Only clean test-related files (.so, .hash, binaries starting with test_)
        const is_test_file = std.mem.indexOf(u8, path, "test_") != null;
        if (!is_test_file) continue;

        // Get the base path (strip .so, .hash, .cpython-* suffixes)
        var base_path: []const u8 = path;
        if (std.mem.indexOf(u8, base_path, ".cpython-")) |idx| {
            base_path = base_path[0..idx];
        } else if (std.mem.endsWith(u8, base_path, ".hash")) {
            base_path = base_path[0 .. base_path.len - 5];
            if (std.mem.indexOf(u8, base_path, ".cpython-")) |idx| {
                base_path = base_path[0..idx];
            }
        }

        // Check if this matches any valid test path
        if (!valid_paths.contains(base_path)) {
            const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, path }) catch continue;
            to_delete.append(allocator, full_path) catch continue;
        }
    }

    // Delete stale files
    for (to_delete.items) |path| {
        std.fs.cwd().deleteFile(path) catch {};
    }
}
