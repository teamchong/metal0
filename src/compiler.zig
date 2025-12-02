const std = @import("std");
const compiler_utils = @import("compiler_utils.zig");

/// Get build directory (reuse .build for all processes)
fn getBuildDir(allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    return ".build";
}

/// Compile Zig source code to native binary
pub fn compileZig(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8, c_libraries: []const []const u8) !void {
    // Use arena for all intermediate allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const build_dir = try getBuildDir(aa);

    // Create build directory if it doesn't exist
    std.fs.cwd().makeDir(build_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Copy runtime files to .build for import
    const runtime_files = [_][]const u8{ "runtime.zig", "runtime_format.zig", "pystring.zig", "pylist.zig", "dict.zig", "pyint.zig", "pyfloat.zig", "pybool.zig", "pytuple.zig", "async.zig", "asyncio.zig", "http.zig", "json.zig", "re.zig", "numpy_array.zig", "eval.zig", "exec.zig", "ast_executor.zig", "bytecode.zig", "eval_cache.zig", "compile.zig", "dynamic_import.zig", "dynamic_attrs.zig", "flask.zig", "requests.zig", "string_utils.zig", "comptime_helpers.zig", "math.zig", "closure_impl.zig", "sys.zig", "time.zig", "py_value.zig", "green_thread.zig", "scheduler.zig", "work_queue.zig", "netpoller.zig", "unittest.zig", "datetime.zig", "pathlib.zig", "os.zig", "pyfile.zig", "io.zig", "hashlib.zig", "pickle.zig", "test_support.zig", "expr_parser.zig", "zlib.zig", "base64.zig", "pylong.zig", "_string.zig", "type_factory.zig", "pycomplex.zig" };
    for (runtime_files) |file| {
        const src_path = try std.fmt.allocPrint(aa, "packages/runtime/src/{s}", .{file});
        const dst_path = try std.fmt.allocPrint(aa, "{s}/{s}", .{ build_dir, file });

        const src = std.fs.cwd().openFile(src_path, .{}) catch continue;
        defer src.close();
        var content = try src.readToEndAlloc(aa, 1024 * 1024);

        // Patch module imports to file imports for standalone compilation
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"green_thread\")", "@import(\"green_thread.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"work_queue\")", "@import(\"work_queue.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"scheduler\")", "@import(\"scheduler.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"netpoller\")", "@import(\"netpoller.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"hashmap_helper\")", "@import(\"utils/hashmap_helper.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"allocator_helper\")", "@import(\"utils/allocator_helper.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"regex\")", "@import(\"regex/src/pyregex/regex.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"bigint\")", "@import(\"bigint.zig\")");

        // Patch relative utils imports to use local utils/ directory
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"../../src/utils/", "@import(\"utils/");

        const dst = try std.fs.cwd().createFile(dst_path, .{});
        defer dst.close();
        try dst.writeAll(content);
    }

    // Copy bigint package to .build
    {
        const src = std.fs.cwd().openFile("packages/bigint/src/bigint.zig", .{}) catch |e| {
            std.debug.print("Failed to open bigint.zig: {any}\n", .{e});
            return e;
        };
        defer src.close();
        const bigint_content = try src.readToEndAlloc(aa, 1024 * 1024);
        const dst_path = try std.fmt.allocPrint(aa, "{s}/bigint.zig", .{build_dir});
        const dst = try std.fs.cwd().createFile(dst_path, .{});
        defer dst.close();
        try dst.writeAll(bigint_content);
    }

    // Copy runtime subdirectories to .build
    try compiler_utils.copyRuntimeDir(aa, "http", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "async", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "json", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "runtime", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "pystring", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "unittest", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "gzip", build_dir);

    // Copy individual runtime files
    try compiler_utils.copyRuntimeFile(aa, "calendar.zig", build_dir);

    // Copy JSON SIMD files from shared/json/simd
    try compiler_utils.copyJsonSimd(aa, build_dir);

    // Copy c_interop directory to build dir
    try compiler_utils.copyCInteropDir(aa, build_dir);

    // Copy regex package to build dir
    try compiler_utils.copyRegexPackage(aa, build_dir);

    // Copy utils directory to build dir (for hashmap_helper, wyhash)
    try compiler_utils.copySrcUtilsDir(aa, build_dir);

    // Copy any compiled modules from .build/ to per-process build dir
    // (Skip this if build_dir is .build itself to avoid copying files to themselves)
    if (!std.mem.eql(u8, build_dir, ".build")) {
        if (std.fs.cwd().openDir(".build", .{ .iterate = true })) |build_iter_dir| {
            var mut_dir = build_iter_dir;
            defer mut_dir.close();
            var walker = mut_dir.iterate();
            while (try walker.next()) |entry| {
                if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
                    const src_path = try std.fmt.allocPrint(aa, ".build/{s}", .{entry.name});
                    const dst_path = try std.fmt.allocPrint(aa, "{s}/{s}", .{ build_dir, entry.name });

                    const src = std.fs.cwd().openFile(src_path, .{}) catch continue;
                    defer src.close();
                    const dst = try std.fs.cwd().createFile(dst_path, .{});
                    defer dst.close();

                    const mod_content = try src.readToEndAlloc(aa, 1024 * 1024);
                    try dst.writeAll(mod_content);
                }
            }
        } else |err| {
            // If .build doesn't exist, that's fine - no modules to copy
            if (err != error.FileNotFound) return err;
        }
    }

    // Write Zig code to temporary file
    const tmp_path = try std.fmt.allocPrint(aa, "{s}/metal0_main_{d}.zig", .{ build_dir, std.time.milliTimestamp() });

    // Write temp file
    const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
    defer tmp_file.close();
    // Keep for debugging - don't delete
    // defer std.fs.deleteFileAbsolute(tmp_path) catch {};

    try tmp_file.writeAll(zig_code);

    // DEBUG: Verify runtime files before zig compilation
    {
        const check = try std.fs.cwd().openFile(".build/runtime.zig", .{});
        defer check.close();
        const stat = try check.stat();
        std.debug.print("RIGHT BEFORE ZIG: .build/runtime.zig is {d} bytes\n", .{stat.size});
    }

    // Shell out to zig build-exe
    const zig_path = try findZigBinary(aa);

    const output_flag = try std.fmt.allocPrint(aa, "-femit-bin={s}", .{output_path});

    // Build argument list
    var args = std.ArrayList([]const u8){};

    try args.append(aa, zig_path);
    try args.append(aa, "build-exe");

    // Add build dir to import path so @import("runtime") finds runtime.zig
    const import_flag = try std.fmt.allocPrint(aa, "-I{s}", .{build_dir});
    try args.append(aa, import_flag);

    // Add main source file
    try args.append(aa, tmp_path);

    try args.append(aa, "-OReleaseFast");
    try args.append(aa, "-fno-stack-check"); // ~1.08x speedup
    // LTO disabled: requires LLD linker which isn't always available
    // try args.append(aa, "-flto"); // Link-time optimization ~1.05x speedup
    try args.append(aa, "-lc");

    // Add dynamically detected C libraries
    for (c_libraries) |lib| {
        const lib_flag = try std.fmt.allocPrint(aa, "-l{s}", .{lib});
        try args.append(aa, lib_flag);
    }

    // Add BLAS linking ONLY if explicitly needed (c_libraries non-empty)
    // This avoids unnecessary Accelerate framework loading (~1.2ms startup overhead)
    const builtin = @import("builtin");
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
            // macOS: Use Accelerate framework (built-in BLAS)
            try args.append(aa, "-framework");
            try args.append(aa, "Accelerate");
        } else if (builtin.os.tag == .linux) {
            // Linux: Link with OpenBLAS or system BLAS
            try args.append(aa, "-lopenblas");
        }
    }

    try args.append(aa, output_flag);

    const argv = try args.toOwnedSlice(aa);

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = argv,
    });

    if (result.term.Exited != 0) {
        std.debug.print("Zig compilation failed:\n{s}\n", .{result.stderr});
        return error.ZigCompilationFailed;
    }
}

/// Compile Zig source code to shared library (.so/.dylib)
pub fn compileZigSharedLib(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8, c_libraries: []const []const u8) !void {
    const build_dir = try getBuildDir(allocator);

    // Create build directory if it doesn't exist
    std.fs.cwd().makeDir(build_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Copy runtime files to .build for import
    const runtime_files = [_][]const u8{ "runtime.zig", "runtime_format.zig", "pystring.zig", "pylist.zig", "dict.zig", "pyint.zig", "pyfloat.zig", "pybool.zig", "pytuple.zig", "async.zig", "asyncio.zig", "http.zig", "json.zig", "re.zig", "numpy_array.zig", "eval.zig", "exec.zig", "ast_executor.zig", "bytecode.zig", "eval_cache.zig", "compile.zig", "dynamic_import.zig", "dynamic_attrs.zig", "flask.zig", "requests.zig", "string_utils.zig", "comptime_helpers.zig", "math.zig", "closure_impl.zig", "sys.zig", "time.zig", "py_value.zig", "green_thread.zig", "scheduler.zig", "work_queue.zig", "unittest.zig", "datetime.zig", "pathlib.zig", "os.zig", "pyfile.zig", "io.zig", "hashlib.zig", "pickle.zig", "test_support.zig", "expr_parser.zig", "zlib.zig", "base64.zig", "pylong.zig", "_string.zig", "type_factory.zig" };
    for (runtime_files) |file| {
        const src_path = try std.fmt.allocPrint(allocator, "packages/runtime/src/{s}", .{file});
        defer allocator.free(src_path);
        const dst_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ build_dir, file });
        defer allocator.free(dst_path);

        const src = std.fs.cwd().openFile(src_path, .{}) catch continue;
        const content = try src.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);
        src.close();

        const dst = try std.fs.cwd().createFile(dst_path, .{});
        try dst.writeAll(content);
        dst.close();
    }

    // Copy runtime subdirectories to .build
    try compiler_utils.copyRuntimeDir(allocator, "http", build_dir);
    try compiler_utils.copyRuntimeDir(allocator, "async", build_dir);
    try compiler_utils.copyRuntimeDir(allocator, "json", build_dir);
    try compiler_utils.copyRuntimeDir(allocator, "runtime", build_dir);
    try compiler_utils.copyRuntimeDir(allocator, "pystring", build_dir);
    try compiler_utils.copyRuntimeDir(allocator, "unittest", build_dir);
    try compiler_utils.copyRuntimeDir(allocator, "gzip", build_dir);

    // Copy individual runtime files
    try compiler_utils.copyRuntimeFile(allocator, "calendar.zig", build_dir);

    // Copy JSON SIMD files from shared/json/simd
    try compiler_utils.copyJsonSimd(allocator, build_dir);

    // Copy c_interop directory to build dir
    try compiler_utils.copyCInteropDir(allocator, build_dir);

    // Copy utils directory to build dir (for hashmap_helper, wyhash)
    try compiler_utils.copySrcUtilsDir(allocator, build_dir);

    // Copy any compiled modules from .build/ to per-process build dir
    if (std.fs.cwd().openDir(".build", .{ .iterate = true })) |build_iter_dir| {
        var mut_dir = build_iter_dir;
        defer mut_dir.close();
        var walker = mut_dir.iterate();
        while (try walker.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
                const src_path = try std.fmt.allocPrint(allocator, ".build/{s}", .{entry.name});
                defer allocator.free(src_path);
                const dst_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ build_dir, entry.name });
                defer allocator.free(dst_path);

                const src = std.fs.cwd().openFile(src_path, .{}) catch continue;
                defer src.close();
                const dst = try std.fs.cwd().createFile(dst_path, .{});
                defer dst.close();

                const mod_content = try src.readToEndAlloc(allocator, 1024 * 1024);
                defer allocator.free(mod_content);
                try dst.writeAll(mod_content);
            }
        }
    } else |err| {
        // If .build doesn't exist, that's fine - no modules to copy
        if (err != error.FileNotFound) return err;
    }

    // Write Zig code to temporary file
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}/metal0_main_{d}.zig", .{ build_dir, std.time.milliTimestamp() });
    defer allocator.free(tmp_path);

    // Write temp file
    const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
    defer tmp_file.close();

    try tmp_file.writeAll(zig_code);

    // Shell out to zig build-lib (shared library)
    const zig_path = try findZigBinary(allocator);
    defer allocator.free(zig_path);

    const output_flag = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{output_path});
    defer allocator.free(output_flag);

    // Get runtime path and add it to the module search path
    const runtime_path = try std.fs.cwd().realpathAlloc(allocator, "packages/runtime/src");
    defer allocator.free(runtime_path);

    const i_flag = try std.fmt.allocPrint(allocator, "-I{s}", .{runtime_path});
    defer allocator.free(i_flag);

    // Build argument list
    var args = std.ArrayList([]const u8){};
    defer args.deinit(allocator);

    // Track allocated flags to free later
    var allocated_flags = std.ArrayList([]const u8){};
    defer {
        for (allocated_flags.items) |flag| {
            allocator.free(flag);
        }
        allocated_flags.deinit(allocator);
    }

    try args.append(allocator, zig_path);
    try args.append(allocator, "build-lib");
    try args.append(allocator, tmp_path);
    try args.append(allocator, i_flag);
    try args.append(allocator, "-OReleaseFast");
    try args.append(allocator, "-fno-stack-check");
    // LTO disabled: requires LLD linker which isn't always available
    // try args.append(allocator, "-flto");
    try args.append(allocator, "-dynamic");
    try args.append(allocator, "-lc");

    // Add dynamically detected C libraries
    for (c_libraries) |lib| {
        const lib_flag = try std.fmt.allocPrint(allocator, "-l{s}", .{lib});
        try allocated_flags.append(allocator, lib_flag);
        try args.append(allocator, lib_flag);
    }

    // Add BLAS linking ONLY if explicitly needed (c_libraries non-empty)
    // This avoids unnecessary Accelerate framework loading (~1.2ms startup overhead)
    const builtin = @import("builtin");
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
            // macOS: Use Accelerate framework (built-in BLAS)
            try args.append(allocator, "-framework");
            try args.append(allocator, "Accelerate");
        } else if (builtin.os.tag == .linux) {
            // Linux: Link with OpenBLAS or system BLAS
            try args.append(allocator, "-lopenblas");
        }
    }

    try args.append(allocator, output_flag);

    const argv = try args.toOwnedSlice(allocator);
    defer allocator.free(argv);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    // Child.run always allocates stdout/stderr, must free them
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.debug.print("Zig compilation failed:\n{s}\n", .{result.stderr});
        return error.ZigCompilationFailed;
    }
}

/// Compile Zig source code to WASM binary
pub fn compileWasm(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8) !void {
    // Use arena for all intermediate allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const build_dir = try getBuildDir(aa);

    // Create build directory if it doesn't exist
    std.fs.cwd().makeDir(build_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Copy runtime files to .build for import (same as compileZig)
    const runtime_files = [_][]const u8{ "runtime.zig", "runtime_format.zig", "pystring.zig", "pylist.zig", "dict.zig", "pyint.zig", "pyfloat.zig", "pybool.zig", "pytuple.zig", "async.zig", "asyncio.zig", "http.zig", "json.zig", "re.zig", "numpy_array.zig", "eval.zig", "exec.zig", "ast_executor.zig", "bytecode.zig", "eval_cache.zig", "compile.zig", "dynamic_import.zig", "dynamic_attrs.zig", "flask.zig", "requests.zig", "string_utils.zig", "comptime_helpers.zig", "math.zig", "closure_impl.zig", "sys.zig", "time.zig", "py_value.zig", "green_thread.zig", "scheduler.zig", "work_queue.zig", "unittest.zig", "datetime.zig", "pathlib.zig", "os.zig", "pyfile.zig", "io.zig", "hashlib.zig", "pickle.zig", "test_support.zig", "expr_parser.zig", "zlib.zig", "base64.zig", "pylong.zig", "_string.zig", "type_factory.zig" };
    for (runtime_files) |file| {
        const src_path = try std.fmt.allocPrint(aa, "packages/runtime/src/{s}", .{file});
        const dst_path = try std.fmt.allocPrint(aa, "{s}/{s}", .{ build_dir, file });

        const src = std.fs.cwd().openFile(src_path, .{}) catch continue;
        defer src.close();
        var content = try src.readToEndAlloc(aa, 1024 * 1024);

        // Patch module imports to file imports for standalone compilation
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"green_thread\")", "@import(\"green_thread.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"work_queue\")", "@import(\"work_queue.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"scheduler\")", "@import(\"scheduler.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"hashmap_helper\")", "@import(\"utils/hashmap_helper.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"allocator_helper\")", "@import(\"utils/allocator_helper.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"regex\")", "@import(\"regex/src/pyregex/regex.zig\")");
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"bigint\")", "@import(\"bigint.zig\")");

        // Patch relative utils imports to use local utils/ directory
        content = try std.mem.replaceOwned(u8, aa, content, "@import(\"../../src/utils/", "@import(\"utils/");

        const dst = try std.fs.cwd().createFile(dst_path, .{});
        defer dst.close();
        try dst.writeAll(content);
    }

    // Copy bigint package to .build
    {
        const src = std.fs.cwd().openFile("packages/bigint/src/bigint.zig", .{}) catch |e| {
            std.debug.print("Failed to open bigint.zig: {any}\n", .{e});
            return e;
        };
        defer src.close();
        const bigint_content = try src.readToEndAlloc(aa, 1024 * 1024);
        const dst_path = try std.fmt.allocPrint(aa, "{s}/bigint.zig", .{build_dir});
        const dst = try std.fs.cwd().createFile(dst_path, .{});
        defer dst.close();
        try dst.writeAll(bigint_content);
    }

    // Copy runtime subdirectories to .build
    try compiler_utils.copyRuntimeDir(aa, "http", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "async", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "json", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "runtime", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "pystring", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "unittest", build_dir);
    try compiler_utils.copyRuntimeDir(aa, "gzip", build_dir);

    // Copy individual runtime files
    try compiler_utils.copyRuntimeFile(aa, "calendar.zig", build_dir);

    // Copy JSON SIMD files from shared/json/simd
    try compiler_utils.copyJsonSimd(aa, build_dir);

    // Copy c_interop directory to build dir
    try compiler_utils.copyCInteropDir(aa, build_dir);

    // Copy regex package to build dir
    try compiler_utils.copyRegexPackage(aa, build_dir);

    // Copy utils directory to build dir (for hashmap_helper, wyhash)
    try compiler_utils.copySrcUtilsDir(aa, build_dir);

    // Write Zig code to temporary file
    const tmp_path = try std.fmt.allocPrint(aa, "{s}/metal0_main_{d}.zig", .{ build_dir, std.time.milliTimestamp() });

    // Write temp file
    const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
    defer tmp_file.close();

    try tmp_file.writeAll(zig_code);

    // Shell out to zig build-exe with WASM target
    const zig_path = try findZigBinary(aa);

    const output_flag = try std.fmt.allocPrint(aa, "-femit-bin={s}", .{output_path});

    // Build argument list
    var args = std.ArrayList([]const u8){};

    try args.append(aa, zig_path);
    try args.append(aa, "build-exe");

    // Add build dir to import path so @import("runtime") finds runtime.zig
    const import_flag = try std.fmt.allocPrint(aa, "-I{s}", .{build_dir});
    try args.append(aa, import_flag);

    // Add main source file
    try args.append(aa, tmp_path);

    // WASM target: wasm32-wasi (supports print via fd_write, DCE removes if unused)
    try args.append(aa, "-target");
    try args.append(aa, "wasm32-wasi");

    try args.append(aa, "-OReleaseSmall"); // Size optimization for WASM
    try args.append(aa, "-fno-stack-check");
    // Note: -flto not supported for WASM target

    try args.append(aa, output_flag);

    const argv = try args.toOwnedSlice(aa);

    const result = try std.process.Child.run(.{
        .allocator = aa,
        .argv = argv,
    });

    if (result.term.Exited != 0) {
        std.debug.print("WASM compilation failed:\n{s}\n", .{result.stderr});
        return error.WasmCompilationFailed;
    }
}

fn findZigBinary(allocator: std.mem.Allocator) ![]const u8 {
    // Try to find zig in PATH
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "which", "zig" },
    }) catch {
        // Default to "zig" and hope it's in PATH
        return try allocator.dupe(u8, "zig");
    };
    // Child.run succeeded, must free stdout/stderr
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited == 0) {
        const path = std.mem.trim(u8, result.stdout, " \n\r\t");
        return try allocator.dupe(u8, path);
    }

    return try allocator.dupe(u8, "zig");
}
