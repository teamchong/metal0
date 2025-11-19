/// Utility functions for compilation
const std = @import("std");
const ast = @import("../ast.zig");
const c_interop = @import("c_interop");
const CompileOptions = @import("../main.zig").CompileOptions;
const compileFile = @import("compile.zig").compileFile;

/// Build all .py files in a directory
pub fn buildDirectory(allocator: std.mem.Allocator, dir_path: []const u8, opts: CompileOptions) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    var file_count: usize = 0;
    var error_count: usize = 0;

    std.debug.print("Building all .py files in {s}/\n\n", .{dir_path});

    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;

        // Check if file ends with .py
        if (!std.mem.endsWith(u8, entry.name, ".py")) continue;

        // Build full path
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        defer allocator.free(full_path);

        file_count += 1;
        std.debug.print("=== Building {s} ===\n", .{entry.name});

        var file_opts = opts;
        file_opts.input_file = full_path;

        compileFile(allocator, file_opts) catch |err| {
            std.debug.print("✗ Failed: {s} - {any}\n\n", .{ entry.name, err });
            error_count += 1;
            continue;
        };

        std.debug.print("\n", .{});
    }

    std.debug.print("=== Summary ===\n", .{});
    std.debug.print("Total files: {d}\n", .{file_count});
    std.debug.print("Success: {d}\n", .{file_count - error_count});
    std.debug.print("Failed: {d}\n", .{error_count});
}

/// Get current architecture string (e.g., "x86_64", "arm64")
pub fn getArch() []const u8 {
    const builtin = @import("builtin");
    return switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "arm64",
        .arm => "arm",
        .riscv64 => "riscv64",
        else => "unknown",
    };
}

/// Scan AST for import statements and register them with ImportContext
pub fn detectImports(ctx: *c_interop.ImportContext, node: ast.Node) !void {
    switch (node) {
        .module => |m| {
            for (m.body) |*stmt| {
                try detectImports(ctx, stmt.*);
            }
        },
        .import_stmt => |imp| {
            try ctx.registerImport(imp.module, imp.asname);
        },
        .import_from => |imp| {
            try ctx.registerImport(imp.module, null);
        },
        else => {},
    }
}

/// Load and execute a shared library (.so/.dylib)
pub fn runSharedLib(allocator: std.mem.Allocator, lib_path: []const u8) !void {
    // Get absolute path for dlopen (need null-terminated string)
    const abs_path = try std.fs.cwd().realpathAlloc(allocator, lib_path);
    defer allocator.free(abs_path);

    // Create null-terminated version for dlopen
    const abs_path_z = try allocator.dupeZ(u8, abs_path);
    defer allocator.free(abs_path_z);

    // Load the shared library (LAZY = deferred binding)
    const handle = std.c.dlopen(abs_path_z.ptr, .{ .LAZY = true }) orelse {
        const err = std.c.dlerror();
        const err_str = if (err) |e| std.mem.span(e) else "unknown error";
        std.debug.print("Failed to load library: {s}\n", .{err_str});
        return error.DlopenFailed;
    };
    defer _ = std.c.dlclose(handle);

    // Find the main function
    const main_symbol = std.c.dlsym(handle, "main") orelse {
        const err = std.c.dlerror();
        const err_str = if (err) |e| std.mem.span(e) else "main not found";
        std.debug.print("Failed to find main: {s}\n", .{err_str});
        return error.DlsymFailed;
    };

    // Cast to function pointer and call
    const main_fn: *const fn () callconv(.c) c_int = @ptrCast(@alignCast(main_symbol));
    const result = main_fn();

    if (result != 0) {
        std.debug.print("main returned non-zero: {d}\n", .{result});
        return error.MainFailed;
    }
}

pub fn printUsage() !void {
    std.debug.print(
        \\Usage:
        \\  pyaot <file.py>                    # Compile .so and run
        \\  pyaot <file.ipynb>                 # Compile notebook and run
        \\  pyaot <file.py> --force            # Force recompile
        \\  pyaot <file.py> --binary           # Compile to binary and run
        \\  pyaot build                        # Build all .py in current directory
        \\  pyaot build <dir/>                 # Build all .py in directory
        \\  pyaot build <file.py>              # Build .so only
        \\  pyaot build <file.ipynb>           # Build notebook only
        \\  pyaot build <file.py> --binary     # Build standalone binary
        \\  pyaot build <file.py> <out>        # Custom output path
        \\  pyaot build <file.py> -f           # Force rebuild
        \\  pyaot test                         # Run test suite
        \\
        \\Flags:
        \\  --binary, -b  Build standalone binary (default: shared library)
        \\  --force, -f   Force recompile (ignore cache)
        \\
        \\Examples:
        \\  pyaot myapp.py                     # Fast: builds myapp_x86_64.so
        \\  pyaot notebook.ipynb               # Compile Jupyter notebook
        \\  pyaot build                        # Build all .py in current dir
        \\  pyaot build examples/              # Build all .py in examples/
        \\  pyaot build --binary myapp.py      # Deploy: builds myapp binary
        \\
    , .{});
}
