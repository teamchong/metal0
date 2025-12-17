/// Test command: Zero-config fast test runner
/// Usage: metal0 test [dir] [patterns...] [@group...]
///
/// Supports @group syntax for platform-specific test groups:
///   @core1   - Platform-independent tests (__all__-float) (98 tests)
///   @core2   - Platform-independent tests (flufl-quopri) (98 tests)
///   @core3   - Platform-independent tests (raise-zstd) (98 tests)
///   @linux   - Linux-specific tests (18 tests)
///   @macos   - macOS-specific tests (25 tests)
///   @windows - Windows-specific tests (93 tests)
const std = @import("std");
const builtin = @import("builtin");
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

/// Load platform restrictions from tests/groups/multi.txt
/// Returns HashMap: test_name → [supported_platforms]
fn loadPlatformMap(allocator: std.mem.Allocator) !std.StringHashMap([]const []const u8) {
    var map = std.StringHashMap([]const []const u8).init(allocator);

    const multi_path = "tests/groups/multi.txt";
    const content = std.fs.cwd().readFileAlloc(allocator, multi_path, 1024 * 1024) catch |err| {
        // multi.txt is optional - if it doesn't exist, no restrictions
        if (err == error.FileNotFound) return map;
        return err;
    };
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Parse format: test_name: platform1,platform2,...
        var parts = std.mem.splitScalar(u8, trimmed, ':');
        const test_name = parts.next() orelse continue;
        const platforms_str = parts.next() orelse continue;

        const test_key = std.mem.trim(u8, test_name, " \t");
        const platforms_part = std.mem.trim(u8, platforms_str, " \t");

        // Duplicate test_key since it's a slice into content buffer
        const test_key_owned = try allocator.dupe(u8, test_key);

        // Split platforms by comma
        var platform_list: std.ArrayList([]const u8) = .{};
        var platform_iter = std.mem.splitScalar(u8, platforms_part, ',');
        while (platform_iter.next()) |platform| {
            const platform_trimmed = std.mem.trim(u8, platform, " \t");
            if (platform_trimmed.len > 0) {
                // Duplicate platform string since it's a slice into content buffer
                const platform_owned = try allocator.dupe(u8, platform_trimmed);
                try platform_list.append(allocator, platform_owned);
            }
        }

        try map.put(test_key_owned, try platform_list.toOwnedSlice(allocator));
    }

    return map;
}

/// Get current platform name as string
fn getCurrentPlatformName() []const u8 {
    return switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        .freebsd, .openbsd, .netbsd => "bsd",
        .wasi => "wasi",
        else => "unknown",
    };
}

/// Check if test is supported on current platform
/// Returns true if:
/// - Test not in platform_map (no restrictions)
/// - Current platform is in test's supported platforms list
fn isTestSupportedOnCurrentPlatform(
    test_name: []const u8,
    platform_map: std.StringHashMap([]const []const u8),
    current_platform: []const u8,
) bool {
    const supported_platforms = platform_map.get(test_name) orelse return true; // No restrictions

    // Check if current platform is in supported list
    for (supported_platforms) |platform| {
        if (std.mem.eql(u8, platform, current_platform)) return true;
    }

    return false;
}

/// Zero-config test runner: metal0 test [dir] [patterns...]
/// Fast by default. Fail fast. No flags needed.
///
/// Examples:
///   metal0 test tests/cpython              # Run all tests
///   metal0 test tests/cpython bool float   # Only test_bool.py, test_float.py
///   metal0 test tests/cpython --codegen-only  # Only run codegen phase (py → zig)
///   metal0 test tests/cpython --compile-only  # Run codegen + compile (skip run)
pub fn cmdTest(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Zero config - sensible defaults
    var test_dir: []const u8 = "tests/cpython";
    const timeout_sec: u64 = 5; // 5s per test - fail fast
    const bail_count: usize = 0; // Run all tests
    // CI runners have only 2 vCPU - reduce parallelism to avoid thrashing
    const is_ci = std.posix.getenv("CI") != null;
    const jobs: usize = if (is_ci) 2 else std.Thread.getCpuCount() catch 8;
    const dots_mode: bool = false;
    const batch_mode: bool = true; // Fast batch compilation
    const filter_pattern: ?[]const u8 = null;
    var codegen_only: bool = false; // Only run codegen phase
    var compile_only: bool = false; // Run codegen + compile, skip run
    var file_patterns = std.ArrayList([]const u8){};
    defer file_patterns.deinit(allocator);

    // Track patterns allocated from group files (need to be freed)
    var allocated_patterns = std.ArrayList([]const u8){};
    defer {
        for (allocated_patterns.items) |p| allocator.free(p);
        allocated_patterns.deinit(allocator);
    }

    // Simple arg parsing - first arg is dir, rest are patterns
    // Supports @group syntax: @core, @linux, @macos, @windows
    var first_pos = true;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--codegen-only")) {
            codegen_only = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--compile-only")) {
            compile_only = true;
            continue;
        }
        if (!std.mem.startsWith(u8, arg, "-")) {
            if (first_pos) {
                test_dir = arg;
                first_pos = false;
            } else if (std.mem.startsWith(u8, arg, "@")) {
                // @group syntax - load patterns from group file
                const group_name = arg[1..]; // Remove '@'
                const group_patterns = loadTestGroup(allocator, group_name) catch |err| {
                    printError("Failed to load test group @{s}: {any}", .{ group_name, err });
                    printError("Group file should be at: tests/groups/{s}.txt", .{group_name});
                    return; // FATAL: Don't run all tests if group file fails to load
                };
                defer allocator.free(group_patterns);

                // Track allocated patterns for cleanup (loadTestGroup dupes strings)
                for (group_patterns) |pattern| {
                    try allocated_patterns.append(allocator, pattern);
                }

                // Load platform restrictions (if multi.txt exists)
                var platform_map = loadPlatformMap(allocator) catch |err| {
                    printWarn("Failed to load platform map: {any}", .{err});
                    // Continue without platform filtering on error
                    for (group_patterns) |pattern| {
                        try file_patterns.append(allocator, pattern);
                    }
                    continue;
                };
                defer {
                    // Free allocated strings and platform lists
                    var iter = platform_map.iterator();
                    while (iter.next()) |entry| {
                        // Free each platform string in the list
                        for (entry.value_ptr.*) |platform_str| {
                            allocator.free(platform_str);
                        }
                        // Free the platform list itself
                        allocator.free(entry.value_ptr.*);
                        // Free the test_key string
                        allocator.free(entry.key_ptr.*);
                    }
                    platform_map.deinit();
                }

                const current_platform = getCurrentPlatformName();

                // Filter tests by platform
                var skipped_count: usize = 0;
                for (group_patterns) |pattern| {
                    if (isTestSupportedOnCurrentPlatform(pattern, platform_map, current_platform)) {
                        try file_patterns.append(allocator, pattern);
                    } else {
                        skipped_count += 1;
                    }
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

    // Ensure output dir exists (for legacy compatibility)
    std.fs.cwd().makeDir(build_dirs.ROOT) catch |err| {
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
        // Print parseable format for CI and exit with error
        std.debug.print("\n{s}Results:{s} {s}0/0 passed (0%%){s}\n", .{
            Color.bold,
            Color.reset,
            Color.red,
            Color.reset,
        });
        return error.NoTestsFound;
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

    // Detect project root once for all test files
    const project_root = try build_dirs.findProjectRoot(allocator, test_dir);
    defer if (project_root) |root| allocator.free(root.path);

    for (test_files.items) |file_path| {
        // Use project-relative paths when project root is found
        const zig_path = if (project_root) |root|
            try build_dirs.projectZigPath(allocator, root.path, file_path)
        else
            try build_dirs.zigPath(allocator, file_path);

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
                compile_mod.compileFile(arena.allocator(), opts) catch |err| {
                    // FAIL LOUD: Print error details for debugging
                    std.debug.print("ERROR: Codegen failed for '{s}': {}\n", .{ task.file_path, err });
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

    // Timeout watchdog for codegen phase (5 minutes total for CI with 2 workers)
    var codegen_done = std.atomic.Value(bool).init(false);
    const watchdog = std.Thread.spawn(.{}, struct {
        fn run(done: *std.atomic.Value(bool)) void {
            std.Thread.sleep(600 * std.time.ns_per_s); // 10 minute timeout
            if (!done.load(.seq_cst)) {
                printError("Phase 1 (Codegen) TIMEOUT after 10 minutes", .{});
                printError("One or more test files caused infinite loop in codegen", .{});
                printError("This is a compiler bug - please bisect to find hanging file", .{});
                std.process.exit(1);
            }
        }
    }.run, .{&codegen_done}) catch unreachable;

    for (0..actual_codegen_threads) |ti| {
        codegen_threads[ti].join();
    }
    codegen_done.store(true, .seq_cst);
    watchdog.detach(); // Let watchdog exit naturally

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

    // Continue even if all codegen failed - we still want to show the full summary
    // if (codegen_total == 0) {
    //     printError("All codegen failed", .{});
    //     return;
    // }

    // If codegen-only mode, print summary and exit
    if (codegen_only) {
        if (final_codegen_fail == 0) {
            printSuccess("Codegen complete: {d}/{d} succeeded", .{ codegen_total, total });
        } else {
            printError("Codegen: {d}/{d} succeeded, {d} failed", .{ codegen_total, total, final_codegen_fail });
            return error.TestsFailed;
        }
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

        // Derive source path and binary path from zig_path
        // Two cases:
        // 1) Project-relative: <project>/.metal0/tests/cpython/test_bool.zig
        // 2) Source-relative: tests/cpython/.metal0/test_bool.zig
        const basename = std.fs.path.basename(zig_path); // test_bool.zig
        const stem = if (std.mem.endsWith(u8, basename, ".zig"))
            basename[0 .. basename.len - 4]
        else
            basename;

        // Check if zig_path is under .metal0/gen/ at project root
        const source_path = if (project_root) |root| blk: {
            // Project-relative: <project>/.metal0/gen/tests/cpython/test_bool.zig
            // Remove <project>/.metal0/gen/ prefix and add .py extension
            // Handle "." root specially - don't prefix with "./"
            const metal0_src_prefix = if (std.mem.eql(u8, root.path, "."))
                build_dirs.OUTPUT_DIR ++ "/" ++ build_dirs.SRC_SUBDIR ++ "/"
            else
                try std.fmt.allocPrint(allocator, "{s}/" ++ build_dirs.OUTPUT_DIR ++ "/" ++ build_dirs.SRC_SUBDIR ++ "/", .{root.path});
            defer if (!std.mem.eql(u8, root.path, ".")) allocator.free(metal0_src_prefix);

            if (std.mem.startsWith(u8, zig_path, metal0_src_prefix)) {
                // Get relative path under .metal0/gen (e.g., tests/cpython/test_bool.zig)
                const rel_path = zig_path[metal0_src_prefix.len..];
                const rel_dir = std.fs.path.dirname(rel_path);
                // Construct source path: tests/cpython/test_bool.py
                break :blk if (rel_dir) |rd|
                    try std.fmt.allocPrint(allocator, "{s}/{s}.py", .{ rd, stem })
                else
                    try std.fmt.allocPrint(allocator, "{s}.py", .{stem});
            }
            // Fallback to source-relative parsing
            const zig_dir = std.fs.path.dirname(zig_path) orelse ".";
            const parent_dir = std.fs.path.dirname(zig_dir);
            break :blk if (parent_dir) |pd|
                try std.fmt.allocPrint(allocator, "{s}/{s}.py", .{ pd, stem })
            else
                try std.fmt.allocPrint(allocator, "{s}.py", .{stem});
        } else blk: {
            // Source-relative: tests/cpython/.metal0/test_bool.zig
            const zig_dir = std.fs.path.dirname(zig_path) orelse ".";
            const parent_dir = std.fs.path.dirname(zig_dir);
            break :blk if (parent_dir) |pd|
                try std.fmt.allocPrint(allocator, "{s}/{s}.py", .{ pd, stem })
            else
                try std.fmt.allocPrint(allocator, "{s}.py", .{stem});
        };

        const bin_path = if (project_root) |root|
            try build_dirs.projectBinaryPath(allocator, root.path, source_path)
        else
            try build_dirs.binaryPath(allocator, source_path);

        // source_path only needed for bin_path derivation, free it now
        allocator.free(source_path);

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
                // Check if this was a timeout - fail fast, don't fall back
                if (err == error.BatchTimeout) {
                    printError("Batch compilation TIMEOUT - failing fast (no fallback)", .{});
                    printError("Consider reducing number of tests or increasing timeout", .{});
                    std.process.exit(1);
                }
                // Other batch failures - fall back to individual compilation
                printError("Batch compilation failed: {any}", .{err});
                printError("Falling back to individual compilation for {d} tests", .{needs_compile_paths.items.len});
                batch_succeeded = false; // Allow fallback to individual compilation
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
                        const zig_file = std.fs.cwd().openFile(task.zig_path, .{}) catch |err| {
                            std.debug.print("ERROR: Failed to open '{s}': {}\n", .{ task.zig_path, err });
                            continue;
                        };
                        defer zig_file.close();

                        const zig_code = zig_file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch |err| {
                            std.debug.print("ERROR: Failed to read '{s}': {}\n", .{ task.zig_path, err });
                            continue;
                        };
                        defer ctx.allocator.free(zig_code);

                        // Use fast linking if runtime archive is available
                        if (ctx.use_runtime_archive) {
                            compileWithRuntimeArchive(ctx.allocator, zig_code, task.bin_path) catch |err| {
                                // Fall back to full compilation
                                std.debug.print("WARN: Fast linking failed for '{s}': {}, falling back to full compilation\n", .{ task.bin_path, err });
                                compiler.compileZigWithOptions(ctx.allocator, zig_code, task.bin_path, &.{}, false, .{}) catch |err2| {
                                    std.debug.print("ERROR: Compilation failed for '{s}': {}\n", .{ task.bin_path, err2 });
                                    continue;
                                };
                            };
                        } else {
                            compiler.compileZigWithOptions(ctx.allocator, zig_code, task.bin_path, &.{}, false, .{}) catch |err| {
                                std.debug.print("ERROR: Compilation failed for '{s}': {}\n", .{ task.bin_path, err });
                                continue;
                            };
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

    // If compile-only mode, print summary and exit
    if (compile_only) {
        const compiled_count = bin_paths.items.len;
        const failed_count = codegen_total - compiled_count;
        if (failed_count == 0) {
            printSuccess("Compile complete: {d}/{d} succeeded", .{ compiled_count, codegen_total });
        } else {
            printError("Compile: {d}/{d} succeeded, {d} failed", .{ compiled_count, codegen_total, failed_count });
            return error.TestsFailed;
        }
        return;
    }

    // Phase 3: Run binaries that exist (PARALLEL)
    if (!dots_mode) std.debug.print("Phase 3: Run... ({d} binaries to check)\n", .{bin_paths.items.len});

    // Track failed/timeout test names for end summary
    const TestResult = struct {
        name: []const u8,
        status: enum { failed, timeout, compile_fail },
    };
    var failed_tests_mutex = std.Thread.Mutex{};
    var failed_tests = std.ArrayList(TestResult){};
    defer {
        for (failed_tests.items) |t| allocator.free(t.name);
        failed_tests.deinit(allocator);
    }

    const RunContext = struct {
        bin_paths: []const []const u8,
        next_task: std.atomic.Value(usize),
        run_ok: *std.atomic.Value(usize),
        run_fail: *std.atomic.Value(usize),
        run_timeout: *std.atomic.Value(usize),
        compile_fail: *std.atomic.Value(usize),
        timeout_ns: u64,
        allocator: std.mem.Allocator,
        bail_count: usize,
        dots_mode: bool,
        failed_tests: *std.ArrayList(TestResult),
        failed_mutex: *std.Thread.Mutex,

        fn worker(ctx: *@This()) void {
            while (true) {
                // Check bail condition BEFORE fetching next task
                if (ctx.bail_count > 0 and ctx.run_fail.load(.seq_cst) >= ctx.bail_count) {
                    return;
                }

                const idx = ctx.next_task.fetchAdd(1, .seq_cst);
                if (idx >= ctx.bin_paths.len) break;

                const bin_path = ctx.bin_paths[idx];
                const test_name = std.fs.path.stem(bin_path);

                // Skip if binary doesn't exist
                std.fs.cwd().access(bin_path, .{}) catch {
                    _ = ctx.compile_fail.fetchAdd(1, .seq_cst);
                    // Track compile failures
                    ctx.failed_mutex.lock();
                    defer ctx.failed_mutex.unlock();
                    const name_copy = ctx.allocator.dupe(u8, test_name) catch {
                        printError("CRITICAL: Failed to allocate memory for compile-fail test name '{s}'\n", .{test_name});
                        std.process.exit(1);
                    };
                    ctx.failed_tests.append(ctx.allocator, .{ .name = name_copy, .status = .compile_fail }) catch |err| {
                        printError("CRITICAL: Failed to record compilation failure for test '{s}': {}\n", .{test_name, err});
                        printError("Test failure tracking is broken - CI may report incorrect results.\n", .{});
                        // Don't continue - we need to know about this failure
                        std.process.exit(1);
                    };
                    continue;
                };

                const result = runBinaryWithTimeout(ctx.allocator, bin_path, ctx.timeout_ns);
                switch (result) {
                    .ok => {
                        _ = ctx.run_ok.fetchAdd(1, .seq_cst);
                        if (ctx.dots_mode) std.debug.print(".", .{});
                    },
                    .timeout => {
                        _ = ctx.run_timeout.fetchAdd(1, .seq_cst);
                        if (ctx.dots_mode) std.debug.print("?", .{});
                        // Track timeouts
                        ctx.failed_mutex.lock();
                        defer ctx.failed_mutex.unlock();
                        const name_copy = ctx.allocator.dupe(u8, test_name) catch {
                            printError("CRITICAL: Failed to allocate memory for timeout test name '{s}'\n", .{test_name});
                            std.process.exit(1);
                        };
                        ctx.failed_tests.append(ctx.allocator, .{ .name = name_copy, .status = .timeout }) catch |err| {
                            printError("CRITICAL: Failed to record timeout for test '{s}': {}\n", .{test_name, err});
                            printError("Test failure tracking is broken - CI may report incorrect results.\n", .{});
                            std.process.exit(1);
                        };
                    },
                    .failed => {
                        _ = ctx.run_fail.fetchAdd(1, .seq_cst);
                        if (ctx.dots_mode) std.debug.print("x", .{});
                        // Track failures
                        ctx.failed_mutex.lock();
                        defer ctx.failed_mutex.unlock();
                        const name_copy = ctx.allocator.dupe(u8, test_name) catch {
                            printError("CRITICAL: Failed to allocate memory for failed test name '{s}'\n", .{test_name});
                            std.process.exit(1);
                        };
                        ctx.failed_tests.append(ctx.allocator, .{ .name = name_copy, .status = .failed }) catch |err| {
                            printError("CRITICAL: Failed to record failure for test '{s}': {}\n", .{test_name, err});
                            printError("Test failure tracking is broken - CI may report incorrect results.\n", .{});
                            std.process.exit(1);
                        };
                    },
                }
            }
        }
    };

    // Initialize atomics
    var run_ok_atomic = std.atomic.Value(usize).init(0);
    var run_fail_atomic = std.atomic.Value(usize).init(0);
    var run_timeout_atomic = std.atomic.Value(usize).init(0);
    var compile_fail_atomic = std.atomic.Value(usize).init(0);

    var run_ctx = RunContext{
        .bin_paths = bin_paths.items,
        .next_task = std.atomic.Value(usize).init(0),
        .run_ok = &run_ok_atomic,
        .run_fail = &run_fail_atomic,
        .run_timeout = &run_timeout_atomic,
        .compile_fail = &compile_fail_atomic,
        .timeout_ns = run_timeout_ns,
        .allocator = allocator,
        .bail_count = bail_count,
        .dots_mode = dots_mode,
        .failed_tests = &failed_tests,
        .failed_mutex = &failed_tests_mutex,
    };

    // Spawn worker threads (use same ncpu as Phase 1/2)
    var threads: [32]std.Thread = undefined;
    const num_workers = @min(ncpu, bin_paths.items.len);
    const actual_threads = @min(num_workers, 32);

    for (0..actual_threads) |ti| {
        threads[ti] = std.Thread.spawn(.{}, RunContext.worker, .{&run_ctx}) catch continue;
    }
    for (0..actual_threads) |ti| {
        threads[ti].join();
    }

    // Load final counts
    const run_ok = run_ok_atomic.load(.seq_cst);
    const run_fail = run_fail_atomic.load(.seq_cst);
    const run_timeout_count = run_timeout_atomic.load(.seq_cst);
    const compile_fail = compile_fail_atomic.load(.seq_cst);

    // Print failed/timeout test names at the end (for debugging)
    if (failed_tests.items.len > 0) {
        std.debug.print("\n{s}Failed/Timeout Tests:{s}\n", .{ Color.bold, Color.reset });
        for (failed_tests.items) |t| {
            const status_str = switch (t.status) {
                .failed => "FAIL",
                .timeout => "TIMEOUT",
                .compile_fail => "COMPILE",
            };
            const color = switch (t.status) {
                .failed => Color.red,
                .timeout => Color.yellow,
                .compile_fail => Color.red,
            };
            std.debug.print("  {s}[{s}]{s} {s}\n", .{ color, status_str, Color.reset, t.name });
        }
    }

    // Bail message if applicable
    if (bail_count > 0 and run_fail >= bail_count) {
        if (dots_mode) std.debug.print("\n", .{});
        std.debug.print("\n{s}Bailed after {d} failures{s}\n", .{ Color.yellow, run_fail, Color.reset });
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
        return error.TestsFailed;
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
    defer {
        // Wait for killer thread to finish (it should be quick after done=true)
        // If it hangs, the timeout mechanism in killAfterTimeout will handle it
        killer.join();
    }

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
    // Try to kill the hung process
    const kill_result = child.kill() catch {
        std.debug.print("WARN: Failed to kill hung process\n", .{});
        done.store(true, .seq_cst);
        return;
    };
    _ = kill_result;
    // Force-mark as done to unblock main thread
    done.store(true, .seq_cst);
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

    // Link against the precompiled runtime archive from global cache
    const runtime_path = try incremental.getRuntimeArchivePathResolved(aa);
    try args.append(aa, runtime_path);

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
    // Build set of valid test base names
    // e.g., "test_bool" for "tests/cpython/test_bool.py"
    var valid_names = hashmap_helper.StringHashMap(void).init(allocator);
    defer valid_names.deinit();

    for (test_files) |test_path| {
        // Get base name without extension
        const basename = std.fs.path.basename(test_path);
        const name = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
            basename[0..idx]
        else
            basename;
        valid_names.put(name, {}) catch continue;
    }

    // With project-level .metal0/, clean the gen/ directory
    // Structure: .metal0/gen/tests/cpython/test_bool.zig
    const gen_dir = build_dirs.OUTPUT_DIR ++ "/" ++ build_dirs.SRC_SUBDIR;
    cleanDirRecursive(allocator, gen_dir, &valid_names);
}

/// Recursively clean directory, removing files not in valid_names
fn cleanDirRecursive(allocator: std.mem.Allocator, dir_path: []const u8, valid_names: *hashmap_helper.StringHashMap(void)) void {
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

        // Only clean test-related files (.so, .hash, .zig, binaries starting with test_)
        const basename = std.fs.path.basename(path);
        const is_test_file = std.mem.startsWith(u8, basename, "test_");
        if (!is_test_file) continue;

        // Get the base name (strip .so, .hash, .zig, .cpython-* suffixes)
        var base_name: []const u8 = basename;
        if (std.mem.indexOf(u8, base_name, ".cpython-")) |idx| {
            base_name = base_name[0..idx];
        } else if (std.mem.endsWith(u8, base_name, ".hash")) {
            base_name = base_name[0 .. base_name.len - 5];
        } else if (std.mem.endsWith(u8, base_name, ".zig")) {
            base_name = base_name[0 .. base_name.len - 4];
        } else if (std.mem.endsWith(u8, base_name, ".o")) {
            base_name = base_name[0 .. base_name.len - 2];
        }

        // Check if this matches any valid test name
        if (!valid_names.contains(base_name)) {
            const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, path }) catch continue;
            to_delete.append(allocator, full_path) catch continue;
        }
    }

    // Delete stale files
    for (to_delete.items) |path| {
        std.fs.cwd().deleteFile(path) catch {};
    }
}
