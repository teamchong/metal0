/// Incremental build system inspired by Bun's fast compilation
///
/// Key techniques from Bun:
/// 1. Use Zig's built-in --cache-dir (extremely fast hash-based caching)
/// 2. Object file separation (.o then link)
/// 3. Function sections for DCE (-ffunction-sections + --gc-sections)
/// 4. Skip strip in debug builds
///
/// Build flow:
/// 1. Codegen: .py → .zig (our code, fast)
/// 2. Compile: .zig → .o via zig build-obj --cache-dir (Zig's cache handles this!)
/// 3. Link: .o → binary via zig build-exe (fast, just linking)
///
/// The key insight: Zig's --cache-dir already does content-hash caching!
/// We just need to:
/// - Use consistent cache-dir across invocations
/// - Use build-obj + build-exe separately (not combined build-exe)
/// - Enable function sections for better DCE
const std = @import("std");
const build_dirs = @import("../../build_dirs.zig");
const compiler = @import("../../compiler.zig");

/// Global Zig cache directory (shared across all compilations)
pub const ZIG_CACHE_DIR = ".metal0/.zig-cache";

/// Path to precompiled runtime archive
pub const RUNTIME_ARCHIVE_PATH = build_dirs.LIB ++ "/libruntime.a";

/// Check if runtime archive exists
pub fn hasRuntimeArchive() bool {
    std.fs.cwd().access(RUNTIME_ARCHIVE_PATH, .{}) catch return false;
    return true;
}

/// Build runtime.zig to static archive (.a) for fast linking
/// This is done ONCE and cached - massive speed improvement
pub fn buildRuntimeArchive(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Ensure runtime.zig exists
    try compiler.setupRuntimeFiles(allocator);

    // Create lib directory
    std.fs.cwd().makeDir(build_dirs.LIB) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create zig cache dir
    std.fs.cwd().makeDir(ZIG_CACHE_DIR) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const runtime_zig = build_dirs.CACHE ++ "/runtime.zig";

    // Build args for creating static library
    var args = std.ArrayList([]const u8){};

    try args.append(aa, "zig");
    try args.append(aa, "build-lib");
    try args.append(aa, runtime_zig);

    // Use Zig's cache
    try args.append(aa, "--cache-dir");
    try args.append(aa, ZIG_CACHE_DIR);

    // Optimization flags
    try args.append(aa, "-OReleaseFast");
    try args.append(aa, "-fno-stack-check");

    // Function sections for DCE
    try args.append(aa, "-ffunction-sections");
    try args.append(aa, "-fdata-sections");

    // Static library output
    try args.append(aa, "-fno-emit-bin");
    try args.append(aa, try std.fmt.allocPrint(aa, "-femit-bin={s}", .{RUNTIME_ARCHIVE_PATH}));

    // Link with libc
    try args.append(aa, "-lc");

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = args.items,
    });

    if (result.term.Exited != 0) {
        std.debug.print("Runtime archive build failed:\n{s}\n", .{result.stderr});
        return error.RuntimeArchiveBuildFailed;
    }
}

/// Ensure runtime archive is up-to-date
/// Rebuilds if missing or if runtime.zig is newer
pub fn ensureRuntimeArchive(allocator: std.mem.Allocator) !void {
    // Check if archive exists
    if (!hasRuntimeArchive()) {
        std.debug.print("Building runtime archive (first time)...\n", .{});
        try buildRuntimeArchive(allocator);
        return;
    }

    // Check if runtime.zig is newer than archive
    const runtime_stat = std.fs.cwd().statFile(build_dirs.CACHE ++ "/runtime.zig") catch {
        try buildRuntimeArchive(allocator);
        return;
    };

    const archive_stat = std.fs.cwd().statFile(RUNTIME_ARCHIVE_PATH) catch {
        try buildRuntimeArchive(allocator);
        return;
    };

    if (runtime_stat.mtime > archive_stat.mtime) {
        std.debug.print("Rebuilding runtime archive (source changed)...\n", .{});
        try buildRuntimeArchive(allocator);
    }
}

/// Batch compile: setup runtime once, then compile multiple .zig files in parallel
/// Returns number of successful compilations
pub fn batchCompile(allocator: std.mem.Allocator, zig_files: []const []const u8, parallelism: usize) !usize {
    // Ensure runtime is ready
    try compiler.setupRuntimeFiles(allocator);

    // Create zig cache dir
    std.fs.cwd().makeDir(ZIG_CACHE_DIR) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var success_count = std.atomic.Value(usize).init(0);
    const actual_parallelism = @min(parallelism, zig_files.len);

    // Spawn worker threads
    const threads = try allocator.alloc(std.Thread, actual_parallelism);
    defer allocator.free(threads);

    const WorkerContext = struct {
        zig_files: []const []const u8,
        success: *std.atomic.Value(usize),
        next_idx: std.atomic.Value(usize),
        alloc: std.mem.Allocator,
    };

    var ctx = WorkerContext{
        .zig_files = zig_files,
        .success = &success_count,
        .next_idx = std.atomic.Value(usize).init(0),
        .alloc = allocator,
    };

    const worker_fn = struct {
        fn work(context: *WorkerContext) void {
            while (true) {
                const idx = context.next_idx.fetchAdd(1, .seq_cst);
                if (idx >= context.zig_files.len) break;

                const zig_path = context.zig_files[idx];
                // Extract module name from path
                const basename = std.fs.path.basename(zig_path);
                const stem = basename[0 .. basename.len - 4]; // Remove .zig

                // Compile to object
                compileToObjectInternal(context.alloc, zig_path, stem) catch {
                    continue; // Failed, don't increment success
                };

                _ = context.success.fetchAdd(1, .seq_cst);
            }
        }
    }.work;

    for (threads) |*t| {
        t.* = try std.Thread.spawn(.{}, worker_fn, .{&ctx});
    }

    for (threads) |t| {
        t.join();
    }

    return success_count.load(.seq_cst);
}

/// Compile a single .zig file to .o using Zig's cache
fn compileToObjectInternal(allocator: std.mem.Allocator, zig_path: []const u8, module_name: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const obj_path = try build_dirs.objectPath(aa, module_name);

    // Build args - Bun-style optimization flags
    var args = std.ArrayList([]const u8){};

    try args.append(aa, "zig");
    try args.append(aa, "build-obj");
    try args.append(aa, zig_path);

    // Use Zig's built-in cache (handles hash-based incremental compilation)
    try args.append(aa, "--cache-dir");
    try args.append(aa, ZIG_CACHE_DIR);

    // Optimization flags (from Bun)
    try args.append(aa, "-OReleaseFast");
    try args.append(aa, "-fno-stack-check");

    // Function sections for DCE at link time (like Bun's link_function_sections)
    try args.append(aa, "-ffunction-sections");
    try args.append(aa, "-fdata-sections");

    // Import path for runtime modules
    try args.append(aa, try std.fmt.allocPrint(aa, "-I{s}", .{build_dirs.CACHE}));

    // Output
    try args.append(aa, try std.fmt.allocPrint(aa, "-femit-bin={s}", .{obj_path}));

    // Link with libc
    try args.append(aa, "-lc");

    const result = std.process.Child.run(.{
        .allocator = aa,
        .argv = args.items,
    }) catch |err| {
        std.debug.print("Child.run failed: {any}\n", .{err});
        return err;
    };

    if (result.term.Exited != 0) {
        std.debug.print("Compile failed for {s}: {s}\n", .{ zig_path, result.stderr });
        return error.ZigCompilationFailed;
    }
}

/// Fast compile using Zig's built-in caching
/// Key: use --cache-dir for hash-based caching (Zig handles this!)
pub fn compileToObject(allocator: std.mem.Allocator, zig_source: []const u8, module_name: []const u8) !void {
    try build_dirs.init();

    // Ensure runtime files are available
    try compiler.setupRuntimeFiles(allocator);

    // Create zig cache dir
    std.fs.cwd().makeDir(ZIG_CACHE_DIR) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const zig_path = try build_dirs.zigPath(aa, module_name);
    const obj_path = try build_dirs.objectPath(aa, module_name);

    // Write Zig source
    const zig_file = try std.fs.cwd().createFile(zig_path, .{});
    defer zig_file.close();
    try zig_file.writeAll(zig_source);

    // Build args - Bun-style optimization flags
    var args = std.ArrayList([]const u8){};

    try args.append(aa, "zig");
    try args.append(aa, "build-obj");
    try args.append(aa, zig_path);

    // Use Zig's built-in cache (handles hash-based incremental compilation)
    try args.append(aa, "--cache-dir");
    try args.append(aa, ZIG_CACHE_DIR);

    // Optimization flags (from Bun)
    try args.append(aa, "-OReleaseFast");
    try args.append(aa, "-fno-stack-check");

    // Function sections for DCE at link time (like Bun's link_function_sections)
    try args.append(aa, "-ffunction-sections");
    try args.append(aa, "-fdata-sections");

    // Import path for runtime modules
    try args.append(aa, try std.fmt.allocPrint(aa, "-I{s}", .{build_dirs.CACHE}));

    // Output
    try args.append(aa, try std.fmt.allocPrint(aa, "-femit-bin={s}", .{obj_path}));

    // Link with libc
    try args.append(aa, "-lc");

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = args.items,
    });

    if (result.term.Exited != 0) {
        std.debug.print("Zig compilation failed:\n{s}\n", .{result.stderr});
        return error.ZigCompilationFailed;
    }
}

/// Link object file to produce binary (fast - just linking, no compilation)
/// Uses precompiled runtime archive if available
pub fn linkBinary(allocator: std.mem.Allocator, module_name: []const u8, output_path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const obj_path = try build_dirs.objectPath(aa, module_name);

    // Build args for linking
    var args = std.ArrayList([]const u8){};

    try args.append(aa, "zig");
    try args.append(aa, "build-exe");
    try args.append(aa, obj_path);

    // Link with precompiled runtime archive if available (HUGE speed boost)
    if (hasRuntimeArchive()) {
        try args.append(aa, RUNTIME_ARCHIVE_PATH);
    }

    // Use cache for linking too
    try args.append(aa, "--cache-dir");
    try args.append(aa, ZIG_CACHE_DIR);

    // Optimization
    try args.append(aa, "-OReleaseFast");
    try args.append(aa, "-lc");

    // DCE at link time (removes unused functions from runtime)
    try args.append(aa, "--gc-sections");

    // Import path for any remaining dependencies
    try args.append(aa, try std.fmt.allocPrint(aa, "-I{s}", .{build_dirs.CACHE}));

    // Output
    try args.append(aa, try std.fmt.allocPrint(aa, "-femit-bin={s}", .{output_path}));

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = args.items,
    });

    if (result.term.Exited != 0) {
        std.debug.print("Link failed:\n{s}\n", .{result.stderr});
        return error.LinkFailed;
    }
}

/// Full incremental build: compile + link
pub fn build(allocator: std.mem.Allocator, zig_source: []const u8, module_name: []const u8, output_path: []const u8) !void {
    // Compile to .o (Zig's cache handles incremental)
    try compileToObject(allocator, zig_source, module_name);

    // Link to binary
    try linkBinary(allocator, module_name, output_path);
}

test "incremental build flow" {
    const allocator = std.testing.allocator;

    // This is a simple test to verify the flow compiles
    const zig_source =
        \\pub fn main() void {}
    ;

    // Skip actual compilation in tests
    _ = zig_source;
    _ = allocator;
}
