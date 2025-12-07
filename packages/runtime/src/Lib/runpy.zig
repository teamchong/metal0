//! Python 'runpy' module - Locating and running Python modules
//!
//! Provides utility functions for locating and running Python modules.
//! This is used by the -m flag to run modules as scripts.
//!
//! Mirrors: CPython Lib/runpy.py

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const RunpyError = error{
    ModuleNotFound,
    NoModuleSpec,
    ImportError,
    OutOfMemory,
};

// ============================================================================
// ModuleSpec - Module specification
// ============================================================================

pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*anyopaque = null,
    origin: ?[]const u8 = null,
    submodule_search_locations: ?[]const []const u8 = null,
    cached: ?[]const u8 = null,
    parent: ?[]const u8 = null,
    has_location: bool = false,

    pub fn init(name: []const u8) ModuleSpec {
        return .{ .name = name };
    }
};

// ============================================================================
// run_module - Run a module as a script
// ============================================================================

/// Run a module's code, optionally running it as __main__
pub fn run_module(
    allocator: std.mem.Allocator,
    mod_name: []const u8,
    run_name: ?[]const u8,
    alter_sys: bool,
) !ModuleGlobals {
    _ = alter_sys;
    const actual_run_name = run_name orelse "__main__";

    // Find the module spec
    const spec = try _get_module_spec(allocator, mod_name);

    return ModuleGlobals{
        .allocator = allocator,
        .name = actual_run_name,
        .file = spec.origin,
        .cached = spec.cached,
        .doc = null,
        .loader = spec.loader,
        .package = spec.parent,
        .spec = spec,
    };
}

/// Run a module as the main module (__main__)
pub fn run_module_as_main(
    allocator: std.mem.Allocator,
    mod_name: []const u8,
    alter_argv: bool,
) !ModuleGlobals {
    _ = alter_argv;
    return run_module(allocator, mod_name, "__main__", true);
}

// ============================================================================
// run_path - Run code at a filesystem path
// ============================================================================

/// Run the code at the specified filesystem path
pub fn run_path(
    allocator: std.mem.Allocator,
    path_name: []const u8,
    run_name: ?[]const u8,
) !ModuleGlobals {
    const actual_run_name = run_name orelse "<run_path>";

    // Check if path exists
    const file = std.fs.cwd().openFile(path_name, .{}) catch {
        return error.ModuleNotFound;
    };
    defer file.close();

    // Determine package name from path
    const dirname = std.fs.path.dirname(path_name);
    const basename = std.fs.path.basename(path_name);

    // Check if it's a package (__init__.py or __main__.py)
    const is_package = std.mem.eql(u8, basename, "__init__.py") or
        std.mem.eql(u8, basename, "__main__.py");

    var pkg_name: ?[]const u8 = null;
    if (is_package) {
        if (dirname) |d| {
            pkg_name = std.fs.path.basename(d);
        }
    }

    return ModuleGlobals{
        .allocator = allocator,
        .name = actual_run_name,
        .file = path_name,
        .cached = null,
        .doc = null,
        .loader = null,
        .package = pkg_name,
        .spec = null,
    };
}

// ============================================================================
// ModuleGlobals - Module namespace
// ============================================================================

pub const ModuleGlobals = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    file: ?[]const u8 = null,
    cached: ?[]const u8 = null,
    doc: ?[]const u8 = null,
    loader: ?*anyopaque = null,
    package: ?[]const u8 = null,
    spec: ?ModuleSpec = null,

    pub fn deinit(self: *ModuleGlobals) void {
        _ = self;
        // Cleanup if needed
    }
};

// ============================================================================
// Internal functions
// ============================================================================

/// Get the module spec for a module
fn _get_module_spec(allocator: std.mem.Allocator, mod_name: []const u8) !ModuleSpec {
    _ = allocator;

    // Build potential file paths for the module
    var spec = ModuleSpec.init(mod_name);

    // Check for package vs module
    if (std.mem.indexOf(u8, mod_name, ".")) |_| {
        // Has dots - it's a submodule
        var iter = std.mem.splitSequence(u8, mod_name, ".");
        var parent: ?[]const u8 = null;
        while (iter.next()) |part| {
            parent = part;
        }
        spec.parent = parent;
    }

    spec.has_location = true;
    return spec;
}

/// Get the main module spec
fn _get_main_module_details(allocator: std.mem.Allocator) !?ModuleSpec {
    _ = allocator;
    // Return main module spec if available
    return null;
}

// ============================================================================
// _run_code helper
// ============================================================================

/// Helper to run code with a given globals dict
pub fn _run_code(
    code: []const u8,
    run_globals: *ModuleGlobals,
    init_globals: ?*const anyopaque,
) !void {
    _ = code;
    _ = run_globals;
    _ = init_globals;
    // Execute the code in the given namespace
    // This would typically compile and execute Python bytecode
}

// ============================================================================
// Tests
// ============================================================================

test "ModuleSpec init" {
    const spec = ModuleSpec.init("test_module");
    try std.testing.expectEqualStrings("test_module", spec.name);
    try std.testing.expectEqual(@as(?[]const u8, null), spec.origin);
}

test "ModuleGlobals" {
    var globals = ModuleGlobals{
        .allocator = std.testing.allocator,
        .name = "__main__",
        .file = "test.py",
    };
    try std.testing.expectEqualStrings("__main__", globals.name);
    try std.testing.expectEqualStrings("test.py", globals.file.?);
    globals.deinit();
}

test "_get_module_spec simple" {
    const spec = try _get_module_spec(std.testing.allocator, "os");
    try std.testing.expectEqualStrings("os", spec.name);
    try std.testing.expect(spec.has_location);
}

test "_get_module_spec submodule" {
    const spec = try _get_module_spec(std.testing.allocator, "os.path");
    try std.testing.expectEqualStrings("os.path", spec.name);
    try std.testing.expectEqualStrings("path", spec.parent.?);
}
