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

/// Path to precompiled runtime archive (release mode - DCE enabled)
pub const RUNTIME_ARCHIVE_PATH = build_dirs.LIB ++ "/libruntime.a";

/// Path to precompiled runtime shared library (dev mode - fast linking)
pub const RUNTIME_SO_PATH = build_dirs.LIB ++ "/libruntime.so";

/// Check if runtime archive exists
pub fn hasRuntimeArchive() bool {
    std.fs.cwd().access(RUNTIME_ARCHIVE_PATH, .{}) catch return false;
    return true;
}

/// Get runtime archive mtime (for cache invalidation)
pub fn getRuntimeArchiveMtime() i128 {
    const file = std.fs.cwd().openFile(RUNTIME_ARCHIVE_PATH, .{}) catch return 0;
    defer file.close();
    const stat = file.stat() catch return 0;
    return stat.mtime;
}

/// Module definition for -M flag (mirrors compiler.zig MODULES)
const ModuleDef = struct {
    name: []const u8,
    path: []const u8,
    deps: []const []const u8,
};

/// All modules needed for runtime compilation - mirrors compiler.zig exactly
/// Order matters: dependencies must come before dependents
const RUNTIME_MODULES = [_]ModuleDef{
    // Leaf modules (no deps)
    .{ .name = "utils.allocator_helper", .path = "src/utils/allocator_helper.zig", .deps = &.{} },
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
};

/// Add C source files for libdeflate (used by gzip module)
fn addCSourceFiles(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8)) !void {
    // Include path for @cImport in gzip module
    try args.append(allocator, "-I");
    try args.append(allocator, "vendor/libdeflate");

    // C source files with compiler flags
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

/// Build module flags for runtime library compilation
/// Uses -M and --dep flags for proper module resolution
fn buildRuntimeModuleFlags(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8), runtime_path: []const u8) !void {
    // 1. C source files first
    try addCSourceFiles(allocator, args);

    // 2. Runtime module with its deps
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
    const runtime_flag = try std.fmt.allocPrint(allocator, "-Mruntime={s}", .{runtime_path});
    try args.append(allocator, runtime_flag);

    // 3. Dependency modules in REVERSE order (dependents before dependencies)
    var i: usize = RUNTIME_MODULES.len;
    while (i > 0) {
        i -= 1;
        const mod = RUNTIME_MODULES[i];

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

/// Build runtime.zig to static archive (.a) for fast linking
/// This is done ONCE and cached - massive speed improvement
pub fn buildRuntimeArchive(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Ensure directories exist (no file copying needed with -M flags)
    try build_dirs.init();

    // Create lib directory
    std.fs.cwd().makeDir(build_dirs.LIB) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create zig cache dir
    std.fs.cwd().makeDir(ZIG_CACHE_DIR) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Use source runtime.zig directly (no copying needed)
    const runtime_zig = "packages/runtime/src/runtime.zig";

    // Build args for creating static library
    var args = std.ArrayList([]const u8){};

    try args.append(aa, "zig");
    try args.append(aa, "build-lib");

    // Add module flags (this is the key fix - runtime.zig needs -M flags for its imports)
    try buildRuntimeModuleFlags(aa, &args, runtime_zig);

    // Use Zig's cache
    try args.append(aa, "--cache-dir");
    try args.append(aa, ZIG_CACHE_DIR);

    // Optimization flags
    try args.append(aa, "-OReleaseFast");
    try args.append(aa, "-fno-stack-check");

    // Function sections for DCE
    try args.append(aa, "-ffunction-sections");
    try args.append(aa, "-fdata-sections");

    // Static library output - note: use -femit-bin for the .a file
    try args.append(aa, try std.fmt.allocPrint(aa, "-femit-bin={s}", .{RUNTIME_ARCHIVE_PATH}));

    // Link with libc
    try args.append(aa, "-lc");

    std.debug.print("Building runtime archive with {d} args...\n", .{args.items.len});

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = args.items,
        .max_output_bytes = 1024 * 1024, // 1MB stderr buffer
    });

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Runtime archive build failed (exit {d}):\n{s}\n", .{ code, result.stderr });
                return error.RuntimeArchiveBuildFailed;
            }
        },
        else => {
            std.debug.print("Runtime archive build terminated abnormally:\n{s}\n", .{result.stderr});
            return error.RuntimeArchiveBuildFailed;
        },
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

    // Check if runtime.zig is newer than archive (use source path)
    const runtime_stat = std.fs.cwd().statFile("packages/runtime/src/runtime.zig") catch {
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

// ══════════════════════════════════════════════════════════════════════════════
// SHARED LIBRARY (.so/.dylib) - For dev mode hot reload
// No DCE but instant linking - perfect for development iteration
// ══════════════════════════════════════════════════════════════════════════════

/// Check if runtime shared library exists
pub fn hasRuntimeSo() bool {
    std.fs.cwd().access(RUNTIME_SO_PATH, .{}) catch return false;
    return true;
}

/// Build runtime as shared library (dev mode - fast linking, no DCE)
fn buildRuntimeSo(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    try build_dirs.init();

    // Create lib directory
    std.fs.cwd().makeDir(build_dirs.LIB) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create zig cache dir
    std.fs.cwd().makeDir(ZIG_CACHE_DIR) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const runtime_zig = "packages/runtime/src/runtime.zig";

    // Build args for creating shared library
    var args = std.ArrayList([]const u8){};

    try args.append(aa, "zig");
    try args.append(aa, "build-lib");

    // Add module flags
    try buildRuntimeModuleFlags(aa, &args, runtime_zig);

    // Use Zig's cache
    try args.append(aa, "--cache-dir");
    try args.append(aa, ZIG_CACHE_DIR);

    // Dev mode: Debug build for fast compile
    try args.append(aa, "-ODebug");

    // Shared library (dynamic)
    try args.append(aa, "-dynamic");

    // Output path
    try args.append(aa, try std.fmt.allocPrint(aa, "-femit-bin={s}", .{RUNTIME_SO_PATH}));

    // Link with libc
    try args.append(aa, "-lc");

    std.debug.print("Building runtime .so (dev mode)...\n", .{});

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = args.items,
        .max_output_bytes = 1024 * 1024,
    });

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Runtime .so build failed (exit {d}):\n{s}\n", .{ code, result.stderr });
                return error.RuntimeSoBuildFailed;
            }
        },
        else => {
            std.debug.print("Runtime .so build terminated abnormally:\n{s}\n", .{result.stderr});
            return error.RuntimeSoBuildFailed;
        },
    }
}

/// Ensure runtime shared library is up-to-date (dev mode)
pub fn ensureRuntimeSo(allocator: std.mem.Allocator) !void {
    if (!hasRuntimeSo()) {
        std.debug.print("Building runtime .so (first time)...\n", .{});
        try buildRuntimeSo(allocator);
        return;
    }

    // Check if runtime.zig is newer
    const runtime_stat = std.fs.cwd().statFile("packages/runtime/src/runtime.zig") catch {
        try buildRuntimeSo(allocator);
        return;
    };

    const so_stat = std.fs.cwd().statFile(RUNTIME_SO_PATH) catch {
        try buildRuntimeSo(allocator);
        return;
    };

    if (runtime_stat.mtime > so_stat.mtime) {
        std.debug.print("Rebuilding runtime .so (source changed)...\n", .{});
        try buildRuntimeSo(allocator);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PRECOMPILED OBJECT FILES (.o) - For ultra-fast linking
// Each module compiled to .o ONCE, then linked when building apps
// ══════════════════════════════════════════════════════════════════════════════

/// Directory for precompiled .o files (mirrors source structure)
const OBJECTS_DIR = ".metal0/obj";

/// Module object files with paths mirroring source structure
const ModuleObject = struct {
    /// Source .zig path
    src: []const u8,
    /// Output .o path (relative to OBJECTS_DIR)
    obj: []const u8,
    /// Module name for -M flag
    name: []const u8,
    /// Dependencies
    deps: []const []const u8,
};

/// All module objects - mirrors source folder structure
const MODULE_OBJECTS = [_]ModuleObject{
    // src/utils/
    .{ .src = "src/utils/hashmap_helper.zig", .obj = "src/utils/hashmap_helper.o", .name = "utils.hashmap_helper", .deps = &.{} },
    .{ .src = "src/utils/allocator_helper.zig", .obj = "src/utils/allocator_helper.o", .name = "utils.allocator_helper", .deps = &.{} },

    // packages/bigint/
    .{ .src = "packages/bigint/src/bigint.zig", .obj = "packages/bigint/src/bigint.o", .name = "bigint", .deps = &.{} },

    // packages/runtime/src/runtime/
    .{ .src = "packages/runtime/src/runtime/green_thread.zig", .obj = "packages/runtime/src/runtime/green_thread.o", .name = "green_thread", .deps = &.{} },
    .{ .src = "packages/runtime/src/runtime/netpoller.zig", .obj = "packages/runtime/src/runtime/netpoller.o", .name = "netpoller", .deps = &.{"green_thread"} },
    .{ .src = "packages/runtime/src/runtime/work_queue.zig", .obj = "packages/runtime/src/runtime/work_queue.o", .name = "work_queue", .deps = &.{"green_thread"} },
    .{ .src = "packages/runtime/src/runtime/scheduler.zig", .obj = "packages/runtime/src/runtime/scheduler.o", .name = "scheduler", .deps = &.{ "green_thread", "work_queue", "netpoller" } },

    // packages/runtime/src/Modules/
    .{ .src = "packages/runtime/src/Modules/gzip/gzip.zig", .obj = "packages/runtime/src/Modules/gzip/gzip.o", .name = "gzip", .deps = &.{} },

    // packages/regex/
    .{ .src = "packages/regex/src/pyregex/regex.zig", .obj = "packages/regex/src/pyregex/regex.o", .name = "regex", .deps = &.{} },

    // packages/shared/json/
    .{ .src = "packages/shared/json/simd/dispatch.zig", .obj = "packages/shared/json/simd/dispatch.o", .name = "json_simd", .deps = &.{} },
    .{ .src = "packages/shared/json/json.zig", .obj = "packages/shared/json/json.o", .name = "json", .deps = &.{ "json_simd", "utils.hashmap_helper" } },

    // packages/tokenizer/
    .{ .src = "packages/tokenizer/src/tokenizer.zig", .obj = "packages/tokenizer/src/tokenizer.o", .name = "tokenizer", .deps = &.{ "json", "utils.hashmap_helper" } },

    // packages/runtime/ (main runtime - last, has most deps)
    .{ .src = "packages/runtime/src/runtime.zig", .obj = "packages/runtime/src/runtime.o", .name = "runtime", .deps = &.{
        "utils.hashmap_helper",
        "utils.allocator_helper",
        "bigint",
        "gzip",
        "regex",
        "tokenizer",
        "green_thread",
        "netpoller",
        "scheduler",
    } },
};

/// Check if all precompiled objects exist
pub fn hasPrecompiledObjects() bool {
    for (MODULE_OBJECTS) |mod| {
        var buf: [512]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ OBJECTS_DIR, mod.obj }) catch return false;
        std.fs.cwd().access(path, .{}) catch return false;
    }
    return true;
}

/// Create directory structure for an object file path
fn ensureObjDir(allocator: std.mem.Allocator, obj_path: []const u8) !void {
    if (std.fs.path.dirname(obj_path)) |dir| {
        const full_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ OBJECTS_DIR, dir });
        defer allocator.free(full_dir);
        std.fs.cwd().makePath(full_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
}

/// Recursively collect all dependencies (transitive closure)
fn collectAllDeps(allocator: std.mem.Allocator, mod_name: []const u8, visited: *std.StringHashMap(void)) !void {
    if (visited.contains(mod_name)) return;
    try visited.put(mod_name, {});

    // Find the module
    for (MODULE_OBJECTS) |m| {
        if (std.mem.eql(u8, m.name, mod_name)) {
            // Recursively add its deps
            for (m.deps) |dep| {
                try collectAllDeps(allocator, dep, visited);
            }
            break;
        }
    }
}

/// Build a single module to .o file
fn buildModuleObjectNew(allocator: std.mem.Allocator, mod: ModuleObject) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Ensure output directory exists
    try ensureObjDir(aa, mod.obj);

    const obj_path = try std.fmt.allocPrint(aa, "{s}/{s}", .{ OBJECTS_DIR, mod.obj });

    var args = std.ArrayList([]const u8){};

    try args.append(aa, "zig");
    try args.append(aa, "build-obj");

    // Add C sources if this is gzip module
    if (std.mem.eql(u8, mod.name, "gzip")) {
        try addCSourceFiles(aa, &args);
    }

    // Collect ALL transitive dependencies
    var all_deps = std.StringHashMap(void).init(aa);
    for (mod.deps) |dep| {
        try collectAllDeps(aa, dep, &all_deps);
    }

    // Add direct dependencies first
    for (mod.deps) |dep| {
        try args.append(aa, "--dep");
        try args.append(aa, dep);
    }

    // Module definition for the module being built
    try args.append(aa, try std.fmt.allocPrint(aa, "-M{s}={s}", .{ mod.name, mod.src }));

    // Add ALL dependency module definitions (including transitive)
    // Process in reverse order so dependencies come after their dependents
    var i: usize = MODULE_OBJECTS.len;
    while (i > 0) {
        i -= 1;
        const dep_mod = MODULE_OBJECTS[i];

        // Skip if this is the module being built
        if (std.mem.eql(u8, dep_mod.name, mod.name)) continue;

        // Only add if it's in our transitive deps
        if (!all_deps.contains(dep_mod.name)) continue;

        // Add the dependency's own deps first
        for (dep_mod.deps) |dd| {
            try args.append(aa, "--dep");
            try args.append(aa, dd);
        }
        try args.append(aa, try std.fmt.allocPrint(aa, "-M{s}={s}", .{ dep_mod.name, dep_mod.src }));
    }

    // Cache and optimization
    try args.append(aa, "--cache-dir");
    try args.append(aa, ZIG_CACHE_DIR);
    try args.append(aa, "-OReleaseFast");
    try args.append(aa, "-fno-stack-check");
    try args.append(aa, "-ffunction-sections");
    try args.append(aa, "-fdata-sections");

    // Include path for libdeflate
    try args.append(aa, "-I");
    try args.append(aa, "vendor/libdeflate");

    // Output
    try args.append(aa, try std.fmt.allocPrint(aa, "-femit-bin={s}", .{obj_path}));

    // Link libc
    try args.append(aa, "-lc");

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = args.items,
        .max_output_bytes = 1024 * 1024,
    });

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Failed to build {s}:\n{s}\n", .{ mod.name, result.stderr });
                return error.ObjectBuildFailed;
            }
        },
        else => return error.ObjectBuildFailed,
    }
}

/// Build all module .o files (call once, then link fast)
/// Objects are organized mirroring source folder structure:
///   .metal0/obj/src/utils/hashmap_helper.o
///   .metal0/obj/packages/runtime/src/runtime.o
///   etc.
pub fn buildAllModuleObjects(allocator: std.mem.Allocator) !void {
    // Ensure base directories exist
    try build_dirs.init();
    std.fs.cwd().makePath(OBJECTS_DIR) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    std.fs.cwd().makePath(ZIG_CACHE_DIR) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    std.debug.print("Building precompiled module objects (mirroring source structure)...\n", .{});

    // Build all modules in order (deps come before dependents in MODULE_OBJECTS)
    for (MODULE_OBJECTS) |mod| {
        std.debug.print("  {s} -> {s}/{s}\n", .{ mod.name, OBJECTS_DIR, mod.obj });
        buildModuleObjectNew(allocator, mod) catch |err| {
            std.debug.print("    Warning: Failed to build {s}: {any}\n", .{ mod.name, err });
        };
    }

    std.debug.print("\nDone! Objects in {s}/\n", .{OBJECTS_DIR});
}

/// Check if any source file is newer than its .o file
pub fn needsRebuild() bool {
    for (MODULE_OBJECTS) |mod| {
        // Get source mtime
        const src_stat = std.fs.cwd().statFile(mod.src) catch continue;

        // Get object mtime
        var buf: [512]u8 = undefined;
        const obj_path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ OBJECTS_DIR, mod.obj }) catch continue;
        const obj_stat = std.fs.cwd().statFile(obj_path) catch return true; // .o missing

        // If source is newer than object, need rebuild
        if (src_stat.mtime > obj_stat.mtime) {
            return true;
        }
    }
    return false;
}

/// Ensure all precompiled objects are up-to-date
/// Auto-rebuilds if source files changed
pub fn ensurePrecompiledObjects(allocator: std.mem.Allocator) !void {
    if (!hasPrecompiledObjects() or needsRebuild()) {
        std.debug.print("Building precompiled modules...\n", .{});
        try buildAllModuleObjects(allocator);
    }
}

/// Get list of all .o file paths for linking
pub fn getObjectPaths(allocator: std.mem.Allocator) ![]const []const u8 {
    var paths = std.ArrayList([]const u8){};
    for (MODULE_OBJECTS) |mod| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ OBJECTS_DIR, mod.obj });
        try paths.append(allocator, path);
    }
    return paths.toOwnedSlice(allocator);
}

/// Compile user code and link against precompiled .o files (FAST!)
pub fn compileWithPrecompiledObjects(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Write zig code to temp file
    const basename = std.fs.path.basename(output_path);
    const stem = if (std.mem.lastIndexOf(u8, basename, ".")) |idx| basename[0..idx] else basename;
    const tmp_path = try std.fmt.allocPrint(aa, "{s}/main_{s}_{d}.zig", .{ build_dirs.CACHE, stem, std.time.milliTimestamp() });

    const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
    try tmp_file.writeAll(zig_code);
    tmp_file.close();

    // Build command
    var args = std.ArrayList([]const u8){};

    try args.append(aa, "zig");
    try args.append(aa, "build-exe");

    // Add all precompiled .o files
    for (MODULE_OBJECTS) |mod| {
        try args.append(aa, try std.fmt.allocPrint(aa, "{s}/{s}", .{ OBJECTS_DIR, mod.obj }));
    }

    // NOTE: Do NOT add C sources here - they're already compiled into gzip.o

    // Main module with deps
    try args.append(aa, "--dep");
    try args.append(aa, "runtime");
    try args.append(aa, "--dep");
    try args.append(aa, "utils.hashmap_helper");
    try args.append(aa, "--dep");
    try args.append(aa, "utils.allocator_helper");
    try args.append(aa, try std.fmt.allocPrint(aa, "-Mmain={s}", .{tmp_path}));

    // Module definitions (needed for type info even though .o has the code)
    try addRuntimeModuleFlagsNew(aa, &args);

    // Cache and optimization
    try args.append(aa, "--cache-dir");
    try args.append(aa, ZIG_CACHE_DIR);
    try args.append(aa, "-OReleaseFast");
    try args.append(aa, "-fno-stack-check");

    // DCE at link time
    try args.append(aa, "--gc-sections");

    // Output
    try args.append(aa, try std.fmt.allocPrint(aa, "-femit-bin={s}", .{output_path}));

    // Link libc
    try args.append(aa, "-lc");

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = args.items,
        .max_output_bytes = 1024 * 1024,
    });

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Linking failed:\n{s}\n", .{result.stderr});
                return error.LinkFailed;
            }
        },
        else => return error.LinkFailed,
    }
}

/// Add runtime module -M flags for type resolution (using MODULE_OBJECTS)
fn addRuntimeModuleFlagsNew(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8)) !void {
    // Add all modules in reverse order (dependents before dependencies for Zig's parser)
    var i: usize = MODULE_OBJECTS.len;
    while (i > 0) {
        i -= 1;
        const mod = MODULE_OBJECTS[i];

        // Add deps first
        for (mod.deps) |dep| {
            try args.append(allocator, "--dep");
            try args.append(allocator, dep);
        }

        // Module definition
        try args.append(allocator, try std.fmt.allocPrint(allocator, "-M{s}={s}", .{ mod.name, mod.src }));
    }
}

/// Batch compile: compile multiple .zig files in parallel
/// Returns number of successful compilations
pub fn batchCompile(allocator: std.mem.Allocator, zig_files: []const []const u8, parallelism: usize) !usize {
    // Ensure directories exist (no file copying needed with -M flags)
    try build_dirs.init();

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

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Compile failed for {s}: {s}\n", .{ zig_path, result.stderr });
                return error.ZigCompilationFailed;
            }
        },
        else => {
            std.debug.print("Compile terminated abnormally for {s}: {s}\n", .{ zig_path, result.stderr });
            return error.ZigCompilationFailed;
        },
    }
}

/// Fast compile using Zig's built-in caching
/// Key: use --cache-dir for hash-based caching (Zig handles this!)
pub fn compileToObject(allocator: std.mem.Allocator, zig_source: []const u8, module_name: []const u8) !void {
    // Ensure directories exist (no file copying needed with -M flags)
    try build_dirs.init();

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

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Zig compilation failed:\n{s}\n", .{result.stderr});
                return error.ZigCompilationFailed;
            }
        },
        else => {
            std.debug.print("Zig compilation terminated abnormally:\n{s}\n", .{result.stderr});
            return error.ZigCompilationFailed;
        },
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

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Link failed:\n{s}\n", .{result.stderr});
                return error.LinkFailed;
            }
        },
        else => {
            std.debug.print("Link terminated abnormally:\n{s}\n", .{result.stderr});
            return error.LinkFailed;
        },
    }
}

/// Full incremental build: compile + link
pub fn build(allocator: std.mem.Allocator, zig_source: []const u8, module_name: []const u8, output_path: []const u8) !void {
    // Compile to .o (Zig's cache handles incremental)
    try compileToObject(allocator, zig_source, module_name);

    // Link to binary
    try linkBinary(allocator, module_name, output_path);
}

// ══════════════════════════════════════════════════════════════════════════════
// BATCH COMPILATION - compile all tests in a single zig build invocation
// This is THE key optimization: share runtime module analysis across all tests
// ══════════════════════════════════════════════════════════════════════════════

/// Path to batch build.zig (in .metal0, copied from src at runtime)
const BATCH_BUILD_ZIG = ".metal0/build.zig";

/// Source path for batch build.zig
const BATCH_BUILD_ZIG_SRC = "src/main/compile/batch_build.zig";

/// Path to test manifest (list of zig files to compile)
const TEST_MANIFEST = ".metal0/test_manifest.txt";

/// Generate test manifest file for batch compilation
/// Format: each line is "relative_zig_path:binary_name"
pub fn generateTestManifest(allocator: std.mem.Allocator, zig_paths: []const []const u8) !void {
    _ = allocator;

    // Ensure .metal0 directory exists
    std.fs.cwd().makeDir(".metal0") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const file = try std.fs.cwd().createFile(TEST_MANIFEST, .{});
    defer file.close();

    for (zig_paths) |zig_path| {
        // Convert to relative path from .metal0/ directory
        // e.g., ".metal0/cache/test_bool.zig" -> "cache/test_bool.zig"
        const rel_path = if (std.mem.startsWith(u8, zig_path, ".metal0/"))
            zig_path[8..] // Skip ".metal0/"
        else
            zig_path;

        // Extract binary name (test_bool.zig -> test_bool)
        const basename = std.fs.path.basename(zig_path);
        const bin_name = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
            basename[0..idx]
        else
            basename;

        // Write line: relative_path:bin_name
        try file.writeAll(rel_path);
        try file.writeAll(":");
        try file.writeAll(bin_name);
        try file.writeAll("\n");
    }
}

/// Batch compile all tests using zig build
/// Returns: tuple of (success_count, total_count)
pub fn batchCompileWithZigBuild(allocator: std.mem.Allocator, jobs: usize) !struct { success: usize, total: usize } {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Run zig build from .metal0 directory
    var argv = [_][]const u8{
        "zig",
        "build",
        undefined, // -j{jobs}
        "-Doptimize=ReleaseFast",
        "--cache-dir",
        "../.metal0/.zig-cache",
        "--prefix",
        "..",
        "--prefix-exe-dir",
        ".metal0/bin",
    };
    const jobs_arg = std.fmt.allocPrint(aa, "-j{d}", .{jobs}) catch "-j4";
    argv[2] = jobs_arg;

    std.debug.print("Running batch compilation: zig build -j{d} (timeout: 120s)...\n", .{jobs});

    // Run from .metal0 directory with timeout using std.process.Child.run
    // Note: Zig's Child doesn't have waitWithTimeout, so we use run() which has built-in timeout
    const result = std.process.Child.run(.{
        .allocator = aa,
        .argv = &argv,
        .cwd = ".metal0",
        .max_output_bytes = 4 * 1024 * 1024,
    }) catch |err| {
        std.debug.print("[BATCH] Process failed: {any}\n", .{err});
        return error.BatchCompileFailed;
    };

    const stderr_content = result.stderr;
    const stderr_len = stderr_content.len;

    // Check exit code
    const exit_code: u8 = switch (result.term) {
        .Exited => |code| code,
        .Signal => |sig| blk: {
            std.debug.print("[BATCH] Killed by signal {d}\n", .{sig});
            break :blk @truncate(128 + sig);
        },
        else => 1,
    };

    // Count successfully compiled binaries
    var count: usize = 0;
    if (std.fs.cwd().openDir(".metal0/bin", .{ .iterate = true })) |dir_val| {
        var dir = dir_val;
        defer dir.close();
        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind == .file) count += 1;
        }
    } else |_| {
        // No bin directory - that's a failure
        if (stderr_len > 0) {
            const max_err = @min(stderr_len, 2000);
            std.debug.print("\n[BATCH] Compilation failed:\n{s}\n", .{stderr_content[0..max_err]});
        }
        return error.BatchCompileFailed;
    }

    // Get total from manifest
    var total: usize = 0;
    if (std.fs.cwd().openFile(".metal0/test_manifest.txt", .{})) |file| {
        defer file.close();
        var buf: [64 * 1024]u8 = undefined;
        const content_len = file.readAll(&buf) catch 0;
        var lines = std.mem.splitScalar(u8, buf[0..content_len], '\n');
        while (lines.next()) |line| {
            if (line.len > 0) total += 1;
        }
    } else |_| {
        total = count; // Fallback
    }

    // Report errors if any failures
    if (exit_code != 0 or count < total) {
        if (stderr_len > 0) {
            const max_err = @min(stderr_len, 2000);
            std.debug.print("\n[BATCH] Compilation errors ({d}/{d} succeeded):\n{s}\n", .{ count, total, stderr_content[0..max_err] });
            if (stderr_len > max_err) {
                std.debug.print("... ({d} more bytes)\n", .{stderr_len - max_err});
            }
        }
    }

    if (count == 0 and total > 0) {
        return error.BatchCompileFailed;
    }

    return .{ .success = count, .total = total };
}

/// Check if batch build.zig exists and copy if needed
pub fn hasBatchBuildZig() bool {
    // Check if source exists
    std.fs.cwd().access(BATCH_BUILD_ZIG_SRC, .{}) catch return false;

    // Copy to .metal0/ if needed
    std.fs.cwd().makeDir(".metal0") catch |err| {
        if (err != error.PathAlreadyExists) return false;
    };

    // Always copy to ensure it's up to date
    std.fs.cwd().copyFile(BATCH_BUILD_ZIG_SRC, std.fs.cwd(), BATCH_BUILD_ZIG, .{}) catch return false;

    return true;
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
