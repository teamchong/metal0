//! Stdlib module generator - scans Zig source directories and generates module list
//!
//! This is a build-time tool that replaces scripts/gen_stdlib_imports.py
//! Run via: zig build gen-stdlib

const std = @import("std");

/// Directories to scan for module discovery
const ScanDir = struct {
    path: []const u8,
    prefix: []const u8,
};

const scan_dirs = [_]ScanDir{
    .{ .path = "packages/runtime/src/Lib", .prefix = "" },
    .{ .path = "packages/runtime/src/Modules", .prefix = "" },
    .{ .path = "packages/runtime/src/Objects", .prefix = "_objects." },
    .{ .path = "packages/runtime/src/Python", .prefix = "_python." },
    .{ .path = "packages/c_interop/src/objects", .prefix = "_c_objects." },
    .{ .path = "packages/c_interop/src/modules", .prefix = "_c_modules." },
};

/// Patterns to exclude from discovery
fn shouldExclude(path: []const u8) bool {
    const exclude_patterns = [_][]const u8{
        "_impl/",
        "_impl.",
        "/utils/",
        "test_",
        "benchmark",
        ".test.",
        "mimalloc/",
        "prim/",
    };

    for (exclude_patterns) |pattern| {
        if (std.mem.indexOf(u8, path, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Modules that need special handling (manual registry entries)
fn isManualModule(name: []const u8) bool {
    const manual_modules = [_][]const u8{
        "json",          "http",        "http.client",  "requests",
        "asyncio",       "re",          "sys",          "time",
        "math",          "unittest",    "sqlite3",      "zlib",
        "ssl",           "hashlib",     "io",           "struct",
        "base64",        "pickle",      "hmac",         "socket",
        "os",            "random",      "collections",  "collections.abc",
        "functools",     "itertools",   "logging",      "threading",
        "queue",         "copy",        "operator",     "typing",
        "ast",           "contextlib",  "string",       "_string",
        "_testcapi",     "_testbuffer", "shutil",       "glob",
        "fnmatch",       "secrets",     "csv",          "configparser",
        "argparse",      "zipfile",     "gzip",         "textwrap",
        "uuid",          "tempfile",    "subprocess",   "heapq",
        "bisect",        "statistics",  "decimal",      "fractions",
        "cmath",         "html",        "xml",          "email",
        "signal",        "multiprocessing",             "array",
        "weakref",       "types",       "abc",          "inspect",
        "dataclasses",   "enum",        "atexit",       "warnings",
        "traceback",     "pprint",      "ctypes",       "_ctypes",
        "platform",      "locale",      "codecs",       "calendar",
        "binascii",      "errno",       "gc",           "builtins",
        "metal0",        "metal0.tokenizer",
    };

    for (manual_modules) |m| {
        if (std.mem.eql(u8, name, m)) {
            return true;
        }
    }
    return false;
}

/// Convert file path to module name
fn pathToModuleName(allocator: std.mem.Allocator, rel_path: []const u8, prefix: []const u8) ![]const u8 {
    // Remove .zig extension
    const without_ext = if (std.mem.endsWith(u8, rel_path, ".zig"))
        rel_path[0 .. rel_path.len - 4]
    else
        rel_path;

    // Replace path separators with dots
    var result = try allocator.alloc(u8, prefix.len + without_ext.len);
    @memcpy(result[0..prefix.len], prefix);

    for (without_ext, 0..) |c, i| {
        result[prefix.len + i] = if (c == '/' or c == '\\') '.' else c;
    }

    return result;
}

/// Recursively scan a directory for .zig files
fn scanDirectory(
    allocator: std.mem.Allocator,
    base_path: []const u8,
    prefix: []const u8,
    modules: *std.ArrayListUnmanaged([]const u8),
) !void {
    var dir = std.fs.cwd().openDir(base_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        if (shouldExclude(entry.path)) continue;

        const module_name = try pathToModuleName(allocator, entry.path, prefix);
        try modules.append(allocator, module_name);
    }
}

/// Compare function for sorting module names
fn compareModuleNames(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

/// Append a string to the output buffer
fn append(output: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    try output.appendSlice(allocator, str);
}

/// Append a formatted string to the output buffer
fn appendFmt(output: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    var buf: [1024]u8 = undefined;
    const str = std.fmt.bufPrint(&buf, fmt, args) catch {
        // Buffer too small, allocate
        const s = try std.fmt.allocPrint(allocator, fmt, args);
        defer allocator.free(s);
        try output.appendSlice(allocator, s);
        return;
    };
    try output.appendSlice(allocator, str);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var all_modules: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (all_modules.items) |m| allocator.free(m);
        all_modules.deinit(allocator);
    }

    // Scan all directories
    for (scan_dirs) |scan_dir| {
        try scanDirectory(allocator, scan_dir.path, scan_dir.prefix, &all_modules);
    }

    // Sort modules
    std.mem.sort([]const u8, all_modules.items, {}, compareModuleNames);

    // Separate into categories
    var lib_modules: std.ArrayListUnmanaged([]const u8) = .empty;
    var objects_modules: std.ArrayListUnmanaged([]const u8) = .empty;
    var python_modules: std.ArrayListUnmanaged([]const u8) = .empty;
    var c_interop_modules: std.ArrayListUnmanaged([]const u8) = .empty;
    var auto_modules: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        lib_modules.deinit(allocator);
        objects_modules.deinit(allocator);
        python_modules.deinit(allocator);
        c_interop_modules.deinit(allocator);
        auto_modules.deinit(allocator);
    }

    for (all_modules.items) |mod| {
        if (std.mem.startsWith(u8, mod, "_c_objects.") or std.mem.startsWith(u8, mod, "_c_modules.")) {
            try c_interop_modules.append(allocator, mod);
        } else if (std.mem.startsWith(u8, mod, "_objects.")) {
            try objects_modules.append(allocator, mod);
        } else if (std.mem.startsWith(u8, mod, "_python.")) {
            try python_modules.append(allocator, mod);
        } else {
            try lib_modules.append(allocator, mod);
        }

        if (!isManualModule(mod)) {
            try auto_modules.append(allocator, mod);
        }
    }

    // Build output in memory
    var output: std.ArrayListUnmanaged(u8) = .empty;
    defer output.deinit(allocator);

    try append(&output, allocator,
        \\//! Auto-generated stdlib module list - DO NOT EDIT
        \\//! Generated by: zig build gen-stdlib
        \\//!
        \\//! Sources:
        \\//!   - packages/runtime/src/Lib/*.zig (stdlib)
        \\//!   - packages/runtime/src/Modules/*.zig (C extension modules)
        \\//!   - packages/runtime/src/Objects/*.zig (object implementations)
        \\//!   - packages/runtime/src/Python/*.zig (interpreter internals)
        \\//!   - packages/c_interop/src/objects/*.zig (CPython object mirrors)
        \\//!   - packages/c_interop/src/modules/*.zig (CPython module mirrors)
        \\
        \\const std = @import("std");
        \\
        \\/// List of all discovered stdlib module files
        \\pub const stdlib_module_names = [_][]const u8{
        \\
    );

    // Write Lib modules
    if (lib_modules.items.len > 0) {
        try append(&output, allocator, "    // === Lib/ (stdlib) ===\n");
        for (lib_modules.items) |mod| {
            try appendFmt(&output, allocator, "    \"{s}\",\n", .{mod});
        }
    }

    // Write Objects modules
    if (objects_modules.items.len > 0) {
        try append(&output, allocator, "    // === Objects/ ===\n");
        for (objects_modules.items) |mod| {
            try appendFmt(&output, allocator, "    \"{s}\",\n", .{mod});
        }
    }

    // Write Python modules
    if (python_modules.items.len > 0) {
        try append(&output, allocator, "    // === Python/ (interpreter) ===\n");
        for (python_modules.items) |mod| {
            try appendFmt(&output, allocator, "    \"{s}\",\n", .{mod});
        }
    }

    // Write c_interop modules
    if (c_interop_modules.items.len > 0) {
        try append(&output, allocator, "    // === c_interop/ ===\n");
        for (c_interop_modules.items) |mod| {
            try appendFmt(&output, allocator, "    \"{s}\",\n", .{mod});
        }
    }

    try append(&output, allocator, "};\n\n");

    try appendFmt(&output, allocator,
        \\/// Number of discovered stdlib modules
        \\pub const stdlib_module_count: usize = {d};
        \\
        \\/// Check if a module name exists in stdlib
        \\pub fn hasModule(name: []const u8) bool {{
        \\    for (stdlib_module_names) |mod| {{
        \\        if (std.mem.eql(u8, name, mod)) return true;
        \\    }}
        \\    return false;
        \\}}
        \\
        \\/// Modules that can be auto-registered (not in manual registry)
        \\pub const auto_registrable_modules = [_][]const u8{{
        \\
    , .{all_modules.items.len});

    for (auto_modules.items) |mod| {
        try appendFmt(&output, allocator, "    \"{s}\",\n", .{mod});
    }

    try appendFmt(&output, allocator,
        \\}};
        \\
        \\pub const auto_registrable_count: usize = {d};
        \\
    , .{auto_modules.items.len});

    // Write to file
    const output_path = "src/codegen/native/stdlib_modules_gen.zig";
    var file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(output.items);

    // Print summary
    var summary_buf: [512]u8 = undefined;
    const summary = std.fmt.bufPrint(&summary_buf,
        \\
        \\Generated {s}
        \\  Lib/ (stdlib):     {d}
        \\  Objects/:          {d}
        \\  Python/:           {d}
        \\  c_interop/:        {d}
        \\  Total:             {d}
        \\  Auto-registrable:  {d}
        \\
    , .{
        output_path,
        lib_modules.items.len,
        objects_modules.items.len,
        python_modules.items.len,
        c_interop_modules.items.len,
        all_modules.items.len,
        auto_modules.items.len,
    }) catch "Error formatting summary";

    // Write summary to stdout
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    stdout.writeAll(summary) catch {};
}
