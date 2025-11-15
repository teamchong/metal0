const std = @import("std");

/// Compile Zig source code to native binary
pub fn compileZig(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8) !void {
    // Copy runtime files to /tmp for import
    const runtime_files = [_][]const u8{ "runtime.zig", "pystring.zig", "pylist.zig", "dict.zig", "pyint.zig", "pytuple.zig", "async.zig", "http.zig", "python.zig", "json.zig" };
    for (runtime_files) |file| {
        const src_path = try std.fmt.allocPrint(allocator, "packages/runtime/src/{s}", .{file});
        defer allocator.free(src_path);
        const dst_path = try std.fmt.allocPrint(allocator, "/tmp/{s}", .{file});
        defer allocator.free(dst_path);

        const src = std.fs.cwd().openFile(src_path, .{}) catch continue;
        defer src.close();
        const dst = try std.fs.createFileAbsolute(dst_path, .{});
        defer dst.close();

        const content = try src.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);
        try dst.writeAll(content);
    }

    // Copy runtime subdirectories to /tmp
    try copyRuntimeDir(allocator, "http");
    try copyRuntimeDir(allocator, "async");
    try copyRuntimeDir(allocator, "json");

    // Write Zig code to temporary file
    const tmp_path = try std.fmt.allocPrint(allocator, "/tmp/pyaot_main_{d}.zig", .{std.time.milliTimestamp()});
    defer allocator.free(tmp_path);

    // Write temp file
    const tmp_file = try std.fs.createFileAbsolute(tmp_path, .{});
    defer tmp_file.close();
    // Keep for debugging - don't delete
    // defer std.fs.deleteFileAbsolute(tmp_path) catch {};

    try tmp_file.writeAll(zig_code);

    // Shell out to zig build-exe
    const zig_path = try findZigBinary(allocator);
    defer allocator.free(zig_path);

    const output_flag = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{output_path});
    defer allocator.free(output_flag);

    // Get runtime path and add it to the module search path
    const runtime_path = try std.fs.cwd().realpathAlloc(allocator, "packages/runtime/src");
    defer allocator.free(runtime_path);

    const i_flag = try std.fmt.allocPrint(allocator, "-I{s}", .{runtime_path});
    defer allocator.free(i_flag);

    // Get Python paths if needed
    const python_info = try getPythonPaths(allocator);
    defer if (python_info.lib_dir) |p| allocator.free(p);
    defer if (python_info.lib_name) |p| allocator.free(p);
    defer if (python_info.include_dir) |p| allocator.free(p);

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
    try args.append(allocator, "build-exe");
    try args.append(allocator, tmp_path);
    try args.append(allocator, i_flag);
    try args.append(allocator, "-ODebug");

    // Add Python include path
    if (python_info.include_dir) |inc_dir| {
        const inc_flag = try std.fmt.allocPrint(allocator, "-I{s}", .{inc_dir});
        try allocated_flags.append(allocator, inc_flag);
        try args.append(allocator, inc_flag);
    }

    if (python_info.lib_dir) |lib_dir| {
        const lib_path_flag = try std.fmt.allocPrint(allocator, "-L{s}", .{lib_dir});
        try allocated_flags.append(allocator, lib_path_flag);
        try args.append(allocator, lib_path_flag);
    }

    if (python_info.lib_name) |lib_name| {
        const lib_flag = try std.fmt.allocPrint(allocator, "-l{s}", .{lib_name});
        try allocated_flags.append(allocator, lib_flag);
        try args.append(allocator, lib_flag);
    }

    try args.append(allocator, "-lc");
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

/// Compile Zig source code to shared library (.so/.dylib)
pub fn compileZigSharedLib(allocator: std.mem.Allocator, zig_code: []const u8, output_path: []const u8) !void {
    // Copy runtime files to /tmp for import
    const runtime_files = [_][]const u8{ "runtime.zig", "pystring.zig", "pylist.zig", "dict.zig", "pyint.zig", "pytuple.zig", "async.zig", "http.zig", "python.zig", "json.zig" };
    for (runtime_files) |file| {
        const src_path = try std.fmt.allocPrint(allocator, "packages/runtime/src/{s}", .{file});
        defer allocator.free(src_path);
        const dst_path = try std.fmt.allocPrint(allocator, "/tmp/{s}", .{file});
        defer allocator.free(dst_path);

        const src = std.fs.cwd().openFile(src_path, .{}) catch continue;
        defer src.close();
        const dst = try std.fs.createFileAbsolute(dst_path, .{});
        defer dst.close();

        const content = try src.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);
        try dst.writeAll(content);
    }

    // Copy runtime subdirectories to /tmp
    try copyRuntimeDir(allocator, "http");
    try copyRuntimeDir(allocator, "async");
    try copyRuntimeDir(allocator, "json");

    // Write Zig code to temporary file
    const tmp_path = try std.fmt.allocPrint(allocator, "/tmp/pyaot_main_{d}.zig", .{std.time.milliTimestamp()});
    defer allocator.free(tmp_path);

    // Write temp file
    const tmp_file = try std.fs.createFileAbsolute(tmp_path, .{});
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

    // Get Python paths if needed
    const python_info = try getPythonPaths(allocator);
    defer if (python_info.lib_dir) |p| allocator.free(p);
    defer if (python_info.lib_name) |p| allocator.free(p);
    defer if (python_info.include_dir) |p| allocator.free(p);

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
    try args.append(allocator, "-ODebug");
    try args.append(allocator, "-dynamic");

    // Add Python include path
    if (python_info.include_dir) |inc_dir| {
        const inc_flag = try std.fmt.allocPrint(allocator, "-I{s}", .{inc_dir});
        try allocated_flags.append(allocator, inc_flag);
        try args.append(allocator, inc_flag);
    }

    if (python_info.lib_dir) |lib_dir| {
        const lib_path_flag = try std.fmt.allocPrint(allocator, "-L{s}", .{lib_dir});
        try allocated_flags.append(allocator, lib_path_flag);
        try args.append(allocator, lib_path_flag);
    }

    if (python_info.lib_name) |lib_name| {
        const lib_flag = try std.fmt.allocPrint(allocator, "-l{s}", .{lib_name});
        try allocated_flags.append(allocator, lib_flag);
        try args.append(allocator, lib_flag);
    }

    try args.append(allocator, "-lc");
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

const PythonInfo = struct {
    lib_dir: ?[]const u8,
    lib_name: ?[]const u8,
    include_dir: ?[]const u8,
};

/// Get Python library paths by calling python3-config
fn getPythonPaths(allocator: std.mem.Allocator) !PythonInfo {
    // Try to get library directory
    const libdir_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "python3", "-c", "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))" },
    }) catch {
        return PythonInfo{ .lib_dir = null, .lib_name = null, .include_dir = null };
    };
    defer allocator.free(libdir_result.stdout);
    defer allocator.free(libdir_result.stderr);

    const lib_dir = if (libdir_result.term.Exited == 0)
        try allocator.dupe(u8, std.mem.trim(u8, libdir_result.stdout, " \n\r\t"))
    else
        null;

    // Try to get library name (e.g., python3.12)
    const libname_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "python3", "-c", "import sysconfig; print('python' + sysconfig.get_config_var('py_version_short'))" },
    }) catch {
        return PythonInfo{ .lib_dir = lib_dir, .lib_name = null, .include_dir = null };
    };
    defer allocator.free(libname_result.stdout);
    defer allocator.free(libname_result.stderr);

    const lib_name = if (libname_result.term.Exited == 0)
        try allocator.dupe(u8, std.mem.trim(u8, libname_result.stdout, " \n\r\t"))
    else
        null;

    // Try to get include directory
    const incdir_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "python3", "-c", "import sysconfig; print(sysconfig.get_path('include'))" },
    }) catch {
        return PythonInfo{ .lib_dir = lib_dir, .lib_name = lib_name, .include_dir = null };
    };
    defer allocator.free(incdir_result.stdout);
    defer allocator.free(incdir_result.stderr);

    const include_dir = if (incdir_result.term.Exited == 0)
        try allocator.dupe(u8, std.mem.trim(u8, incdir_result.stdout, " \n\r\t"))
    else
        null;

    return PythonInfo{ .lib_dir = lib_dir, .lib_name = lib_name, .include_dir = include_dir };
}

/// Copy a runtime subdirectory recursively to /tmp
fn copyRuntimeDir(allocator: std.mem.Allocator, dir_name: []const u8) !void {
    const src_dir_path = try std.fmt.allocPrint(allocator, "packages/runtime/src/{s}", .{dir_name});
    defer allocator.free(src_dir_path);
    const dst_dir_path = try std.fmt.allocPrint(allocator, "/tmp/{s}", .{dir_name});
    defer allocator.free(dst_dir_path);

    // Create destination directory
    std.fs.makeDirAbsolute(dst_dir_path) catch |err| {
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
            const dst_file = try std.fs.createFileAbsolute(dst_file_path, .{});
            defer dst_file.close();

            const content = try src_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
            defer allocator.free(content);
            try dst_file.writeAll(content);
        } else if (entry.kind == .directory) {
            // Recursively copy subdirectory
            const subdir_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_name, entry.name });
            defer allocator.free(subdir_name);
            try copyRuntimeDir(allocator, subdir_name);
        }
    }
}
