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
    // Patterns that should NOT be included as modules
    const exclude_patterns = [_][]const u8{
        "_impl/",
        "_impl.",
        "/utils/", // Exclude internal utils directories
        "benchmark",
        ".test.", // Exclude Zig test files like "foo.test.zig"
        "mimalloc/",
        "prim/",
    };

    for (exclude_patterns) |pattern| {
        if (std.mem.indexOf(u8, path, pattern) != null) {
            return true;
        }
    }

    // Exclude files that start with "test_" in the filename (test files)
    // But allow test/test_importlib/util.zig etc. (utility files in test directories)
    if (std.mem.lastIndexOf(u8, path, "/")) |last_slash| {
        const filename = path[last_slash + 1 ..];
        if (std.mem.startsWith(u8, filename, "test_")) {
            return true;
        }
    } else {
        // No slash, check if the file itself starts with test_
        if (std.mem.startsWith(u8, path, "test_")) {
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

/// Modules that need freestanding checks (OS-dependent)
fn needsFreestandingCheck(name: []const u8) bool {
    const freestanding_modules = [_][]const u8{
        "asyncio",   "http",       "shutil",   "socket",
        "subprocess", "tempfile", "threading", "websocket",
    };
    for (freestanding_modules) |m| {
        if (std.mem.eql(u8, name, m)) return true;
    }
    return false;
}

/// Convert module name to valid Zig identifier
fn toZigIdent(name: []const u8, buf: []u8) []const u8 {
    // Handle reserved keywords
    if (std.mem.eql(u8, name, "struct")) return "@\"struct\"";
    if (std.mem.eql(u8, name, "enum")) return "@\"enum\"";
    if (std.mem.eql(u8, name, "test")) return "test_";
    if (std.mem.eql(u8, name, "error")) return "@\"error\"";
    if (std.mem.eql(u8, name, "type")) return "@\"type\"";
    if (std.mem.eql(u8, name, "async")) return "@\"async\"";
    if (std.mem.eql(u8, name, "await")) return "@\"await\"";

    // Check for special characters that need escaping
    var needs_escape = false;
    for (name) |c| {
        if (c == '-' or c == '.') {
            needs_escape = true;
            break;
        }
    }

    if (needs_escape) {
        const len = std.fmt.bufPrint(buf, "@\"{s}\"", .{name}) catch return name;
        return buf[0..len.len];
    }

    return name;
}

/// Get the import path for a module
fn getImportPath(name: []const u8, buf: []u8) []const u8 {
    // Handle special cases with non-standard paths
    if (std.mem.eql(u8, name, "pickle")) {
        return "Lib/pickle/pickle.zig";
    }
    if (std.mem.eql(u8, name, "test") or std.mem.eql(u8, name, "test_")) {
        return "Lib/test/support.zig";
    }

    // Standard path: Lib/<name>.zig
    const len = std.fmt.bufPrint(buf, "Lib/{s}.zig", .{name}) catch return "";
    return buf[0..len.len];
}

/// Generate Lib_exports.zig for runtime.zig
/// This generates a REFERENCE file showing all available modules.
/// The actual Lib struct in runtime.zig is manually curated to only include
/// modules that are known to compile correctly.
///
/// When adding a new module:
/// 1. Create the .zig file in packages/runtime/src/Lib/
/// 2. Run `zig build gen-stdlib` to update this reference
/// 3. Add the export to runtime.zig Lib struct manually after testing
fn generateLibExports(allocator: std.mem.Allocator, lib_modules: []const []const u8) !void {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    defer output.deinit(allocator);

    try append(&output, allocator,
        \\//! Auto-generated Lib module REFERENCE - shows all available modules
        \\//! Generated by: zig build gen-stdlib
        \\//!
        \\//! NOTE: This file is for REFERENCE ONLY. The actual Lib struct is in runtime.zig.
        \\//! Not all modules listed here are guaranteed to compile - runtime.zig contains
        \\//! a curated subset of modules that are known to work.
        \\//!
        \\//! When adding a new module to runtime.zig:
        \\//! 1. Check this file to see the correct import path
        \\//! 2. Test that the module compiles: zig build
        \\//! 3. Add the export to runtime.zig Lib struct
        \\
        \\const std = @import("std");
        \\
        \\/// Reference list of all .zig files in Lib/ directory
        \\/// To add a module to runtime.Lib, copy the relevant line to runtime.zig
        \\pub const available_modules = [_][]const u8{
        \\
    );

    var count: usize = 0;
    var path_buf: [256]u8 = undefined;
    var check_path_buf: [512]u8 = undefined;

    for (lib_modules) |mod| {
        // Only emit top-level modules (no dots)
        if (std.mem.indexOf(u8, mod, ".")) |_| continue;

        const path = getImportPath(mod, &path_buf);

        // Verify the file actually exists in Lib/
        const full_path = std.fmt.bufPrint(&check_path_buf, "packages/runtime/src/{s}", .{path}) catch continue;
        std.fs.cwd().access(full_path, .{}) catch continue;

        try appendFmt(&output, allocator, "    \"{s}\", // @import(\"{s}\")\n", .{ mod, path });
        count += 1;
    }

    try append(&output, allocator, "};\n\n");
    try appendFmt(&output, allocator, "pub const module_count: usize = {d};\n", .{count});

    // Write to file
    const output_path = "packages/runtime/src/Lib_exports.zig";
    var file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(output.items);
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

    // Also generate Lib_exports.zig for runtime.zig
    try generateLibExports(allocator, lib_modules.items);

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
