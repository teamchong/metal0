const std = @import("std");

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
    const runtime_files = [_][]const u8{ "runtime.zig", "pystring.zig", "pylist.zig", "dict.zig", "pyint.zig", "pyfloat.zig", "pybool.zig", "pytuple.zig", "async.zig", "http.zig", "json.zig", "re.zig", "numpy_array.zig", "eval.zig", "exec.zig", "ast_executor.zig", "string_utils.zig", "comptime_helpers.zig", "math.zig" };
    for (runtime_files) |file| {
        const src_path = try std.fmt.allocPrint(aa, "packages/runtime/src/{s}", .{file});
        const dst_path = try std.fmt.allocPrint(aa, "{s}/{s}", .{ build_dir, file });

        const src = std.fs.cwd().openFile(src_path, .{}) catch continue;
        defer src.close();
        const content = try src.readToEndAlloc(aa, 1024 * 1024);

        const dst = try std.fs.cwd().createFile(dst_path, .{});
        defer dst.close();
        try dst.writeAll(content);
    }

    // Copy runtime subdirectories to .build
    try copyRuntimeDir(aa, "http", build_dir);
    try copyRuntimeDir(aa, "async", build_dir);
    try copyRuntimeDir(aa, "json", build_dir);
    try copyRuntimeDir(aa, "runtime", build_dir);
    try copyRuntimeDir(aa, "pystring", build_dir);

    // Copy c_interop directory to build dir
    try copyCInteropDir(aa, build_dir);

    // Copy regex package to build dir
    try copyRegexPackage(aa, build_dir);

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
    const tmp_path = try std.fmt.allocPrint(aa, "{s}/pyaot_main_{d}.zig", .{ build_dir, std.time.milliTimestamp() });

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
    try args.append(aa, tmp_path);

    // Add build dir to import path so @import("runtime") finds runtime.zig
    const import_flag = try std.fmt.allocPrint(aa, "-I{s}", .{build_dir});
    try args.append(aa, import_flag);

    try args.append(aa, "-OReleaseFast");
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
    const runtime_files = [_][]const u8{ "runtime.zig", "pystring.zig", "pylist.zig", "dict.zig", "pyint.zig", "pyfloat.zig", "pybool.zig", "pytuple.zig", "async.zig", "http.zig", "json.zig", "re.zig", "numpy_array.zig", "eval.zig", "exec.zig", "ast_executor.zig", "string_utils.zig", "comptime_helpers.zig", "math.zig" };
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
    try copyRuntimeDir(allocator, "http", build_dir);
    try copyRuntimeDir(allocator, "async", build_dir);
    try copyRuntimeDir(allocator, "json", build_dir);
    try copyRuntimeDir(allocator, "runtime", build_dir);
    try copyRuntimeDir(allocator, "pystring", build_dir);

    // Copy c_interop directory to build dir
    try copyCInteropDir(allocator, build_dir);

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
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}/pyaot_main_{d}.zig", .{ build_dir, std.time.milliTimestamp() });
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

/// Copy a runtime subdirectory recursively to .build
fn copyRuntimeDir(allocator: std.mem.Allocator, dir_name: []const u8, build_dir: []const u8) !void {
    const src_dir_path = try std.fmt.allocPrint(allocator, "packages/runtime/src/{s}", .{dir_name});
    defer allocator.free(src_dir_path);
    const dst_dir_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ build_dir, dir_name });
    defer allocator.free(dst_dir_path);

    // Create destination directory
    std.fs.cwd().makeDir(dst_dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Open source directory
    var src_dir = std.fs.cwd().openDir(src_dir_path, .{ .iterate = true }) catch |err| {
        // If directory doesn't exist, that's okay - just skip it
        if (err == error.FileNotFound) return;
        return err;
    };
    defer src_dir.close();

    // Iterate through files in source directory
    var iterator = src_dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file) {
            // Copy file
            const src_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir_path, entry.name });
            defer allocator.free(src_file_path);
            const dst_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir_path, entry.name });
            defer allocator.free(dst_file_path);

            const src_file = try std.fs.cwd().openFile(src_file_path, .{});
            defer src_file.close();
            const dst_file = try std.fs.cwd().createFile(dst_file_path, .{});
            defer dst_file.close();

            const content = try src_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
            defer allocator.free(content);
            try dst_file.writeAll(content);
        } else if (entry.kind == .directory) {
            // Recursively copy subdirectory
            const subdir_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_name, entry.name });
            defer allocator.free(subdir_name);
            try copyRuntimeDir(allocator, subdir_name, build_dir);
        }
    }
}

/// Copy c_interop directory to .build for C library interop
fn copyCInteropDir(allocator: std.mem.Allocator, build_dir: []const u8) !void {
    const src_dir_path = "packages/c_interop";
    const dst_dir_path = try std.fmt.allocPrint(allocator, "{s}/c_interop", .{build_dir});
    defer allocator.free(dst_dir_path);

    // Create destination directory
    std.fs.cwd().makeDir(dst_dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Open source directory
    var src_dir = std.fs.cwd().openDir(src_dir_path, .{ .iterate = true }) catch |err| {
        // If directory doesn't exist, that's okay - just skip it
        if (err == error.FileNotFound) return;
        return err;
    };
    defer src_dir.close();

    // Iterate through files and directories
    var iterator = src_dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file) {
            // Copy file
            const src_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir_path, entry.name });
            defer allocator.free(src_file_path);
            const dst_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir_path, entry.name });
            defer allocator.free(dst_file_path);

            const src_file = try std.fs.cwd().openFile(src_file_path, .{});
            defer src_file.close();
            const dst_file = try std.fs.cwd().createFile(dst_file_path, .{});
            defer dst_file.close();

            const content = try src_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
            defer allocator.free(content);
            try dst_file.writeAll(content);
        } else if (entry.kind == .directory) {
            // Recursively copy subdirectory
            const new_src = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir_path, entry.name });
            defer allocator.free(new_src);
            const new_dst = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir_path, entry.name });
            try copyDirRecursive(allocator, new_src, new_dst);
        }
    }
}

/// Copy regex package to .build for re module
fn copyRegexPackage(allocator: std.mem.Allocator, build_dir: []const u8) !void {
    // Copy packages/regex/src/pyregex to .build/regex/src/pyregex
    try copyDirRecursive(allocator, "packages/regex/src/pyregex", try std.fmt.allocPrint(allocator, "{s}/regex/src/pyregex", .{build_dir}));
}

/// Recursively copy directory
fn copyDirRecursive(allocator: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) !void {
    defer allocator.free(dst_path);

    // Create destination directory
    std.fs.cwd().makePath(dst_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Open source directory
    var src_dir = std.fs.cwd().openDir(src_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer src_dir.close();

    // Iterate through entries
    var iterator = src_dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file) {
            const src_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_path, entry.name });
            defer allocator.free(src_file_path);
            const dst_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_path, entry.name });
            defer allocator.free(dst_file_path);

            const src_file = try std.fs.cwd().openFile(src_file_path, .{});
            defer src_file.close();
            const dst_file = try std.fs.cwd().createFile(dst_file_path, .{});
            defer dst_file.close();

            const content = try src_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
            defer allocator.free(content);
            try dst_file.writeAll(content);
        } else if (entry.kind == .directory) {
            const new_src = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_path, entry.name });
            defer allocator.free(new_src);
            const new_dst = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_path, entry.name });
            try copyDirRecursive(allocator, new_src, new_dst);
        }
    }
}
