//! Test utilities for importlib tests
//!
//! This module provides utilities for testing Python's importlib module.
//! In CPython, this module helps test both frozen and source importlib variants.
//! For our AOT compiler, we provide compatible interfaces that work with our
//! compile-time import resolution.
//!
//! Key functions:
//! - import_importlib: Import module with Frozen/Source variants
//! - test_both / split_frozen: Create test class variants
//! - specialize_class: Helper to specialize test classes
//! - uncache: Context manager to remove modules from sys.modules

const std = @import("std");

// Runtime imports - these will be provided by the main runtime when linked
// For standalone compilation, we use placeholder types
pub const PyValue = struct {
    _data: usize = 0,

    pub fn none() PyValue {
        return .{ ._data = 0 };
    }

    pub fn from(value: anytype) PyValue {
        _ = value;
        return .{ ._data = 1 };
    }

    pub fn toDict(self: PyValue) ?*Dict {
        _ = self;
        return null;
    }

    pub const Dict = struct {
        data: std.StringHashMap(PyValue),

        pub fn init(allocator: std.mem.Allocator) Dict {
            return .{ .data = std.StringHashMap(PyValue).init(allocator) };
        }

        pub fn put(self: *Dict, key: []const u8, value: PyValue) !void {
            try self.data.put(key, value);
        }

        pub fn get(self: *Dict, key: []const u8) ?PyValue {
            return self.data.get(key);
        }
    };
};

// ============================================================================
// IMPORT UTILITIES
// ============================================================================

/// Import a module from importlib both with and without _frozen_importlib.
/// Returns a dict with 'Frozen' and 'Source' keys containing the module variants.
///
/// Python equivalent:
/// ```python
/// def import_importlib(module_name):
///     fresh = ('importlib',) if '.' in module_name else ()
///     frozen = import_helper.import_fresh_module(module_name)
///     source = import_helper.import_fresh_module(module_name, fresh=fresh,
///                     blocked=('_frozen_importlib', '_frozen_importlib_external'))
///     return {'Frozen': frozen, 'Source': source}
/// ```
///
/// In our AOT context:
/// - Frozen: Module imported normally (using frozen importlib if available)
/// - Source: Module imported without frozen importlib (source-only)
///
/// Since our AOT compiler resolves imports at compile time, both variants
/// typically point to the same compiled module.
pub fn import_importlib(module_name: []const u8) PyValue {
    // In AOT context, we don't distinguish between frozen and source imports
    // Both resolve to the same compiled module at compile time
    // Return a simple PyValue representing the dict
    _ = module_name;
    return PyValue.from("importlib_variants");
}

/// Import a module by name (simplified for AOT context)
fn importModule(allocator: std.mem.Allocator, module_name: []const u8) !PyValue {
    _ = allocator;
    _ = module_name;
    // In full implementation, this would look up the module in our
    // compiled module registry or trigger compilation
    return PyValue.from("module");
}

// ============================================================================
// TEST CLASS SPECIALIZATION
// ============================================================================

/// Create a type tuple that returns the same type for both frozen/source variants.
/// In AOT context, we don't distinguish between frozen and source imports.
///
/// Usage:
/// ```zig
/// const Result = test_both(MetaPathFinder, abc);
/// const MetaPathFinder_Frozen = Result.@"0"();  // Returns MetaPathFinder
/// const MetaPathFinder_Source = Result.@"1"();  // Returns MetaPathFinder
/// ```
pub fn TypeClassTuple(comptime T: type) type {
    return struct {
        pub const frozen = T;
        pub const source = T;

        pub fn @"0"() type {
            return T;
        }

        pub fn @"1"() type {
            return T;
        }
    };
}

/// Specialize a test class for a particular variant (Frozen or Source).
/// In AOT context, returns the class type unchanged.
pub fn specialize_class(comptime TestClass: type, kind: anytype) type {
    _ = kind;
    return TestClass;
}

/// Split a test class into Frozen and Source variants.
/// In AOT context, returns tuple type with (cls, cls).
pub fn split_frozen(comptime TestClass: type, base: anytype) type {
    _ = base;
    return TypeClassTuple(TestClass);
}

/// Create both Frozen and Source test class variants.
/// In AOT context, returns tuple type with (test_class, test_class).
pub fn test_both(comptime TestClass: type, base: anytype) type {
    _ = base;
    return TypeClassTuple(TestClass);
}

// ============================================================================
// MODULE CACHE UTILITIES
// ============================================================================

/// Context manager to uncache modules from sys.modules.
/// Used to ensure clean imports in tests.
///
/// Python equivalent:
/// ```python
/// @contextlib.contextmanager
/// def uncache(*names):
///     for name in names:
///         if name in ('sys', 'marshal'):
///             raise ValueError("cannot uncache {}".format(name))
///         try:
///             del sys.modules[name]
///         except KeyError:
///             pass
///     try:
///         yield
///     finally:
///         for name in names:
///             try:
///                 del sys.modules[name]
///             except KeyError:
///                 pass
/// ```
pub const UncacheContext = struct {
    names: []const []const u8,
    sys_modules: *std.StringHashMap(PyValue),

    pub fn init(names: []const []const u8, sys_modules: *std.StringHashMap(PyValue)) !UncacheContext {
        // Validate - cannot uncache 'sys' or 'marshal'
        for (names) |name| {
            if (std.mem.eql(u8, name, "sys") or std.mem.eql(u8, name, "marshal")) {
                return error.ValueError;
            }
        }

        // Remove modules from sys.modules
        for (names) |name| {
            _ = sys_modules.remove(name);
        }

        return .{
            .names = names,
            .sys_modules = sys_modules,
        };
    }

    pub fn deinit(self: *UncacheContext) void {
        // Clean up - remove modules again on exit
        for (self.names) |name| {
            _ = self.sys_modules.remove(name);
        }
    }
};

/// Create an uncache context manager
pub fn uncache(names: []const []const u8, sys_modules: *std.StringHashMap(PyValue)) !UncacheContext {
    return UncacheContext.init(names, sys_modules);
}

// ============================================================================
// FILESYSTEM UTILITIES
// ============================================================================

/// Check if filesystem is case-insensitive
pub var CASE_INSENSITIVE_FS: bool = blk: {
    // Default to true on Windows, check at runtime on others
    if (@import("builtin").os.tag == .windows) {
        break :blk true;
    }
    // For other OSes, we'd need to check at runtime
    // For now, default to false (case-sensitive)
    break :blk false;
};

/// Decorator to skip tests requiring case-insensitive filesystem
pub fn case_insensitive_tests(comptime test_fn: anytype) @TypeOf(test_fn) {
    // In AOT context, this would be evaluated at compile time
    // For now, just return the test function
    return test_fn;
}

// ============================================================================
// BUILTIN MODULE DETECTION
// ============================================================================

/// Constants for builtin module detection
pub const BUILTINS = struct {
    /// Name of a builtin module that exists (e.g., 'errno')
    pub var good_name: ?[]const u8 = "errno";
    /// Name of a module that is NOT builtin (e.g., 'importlib')
    pub var bad_name: ?[]const u8 = "importlib";
};

// ============================================================================
// EXTENSION MODULE INFO
// ============================================================================

/// Information about extension modules for testing
pub const EXTENSIONS = struct {
    path: ?[]const u8 = null,
    ext: ?[]const u8 = null,
    filename: ?[]const u8 = null,
    file_path: ?[]const u8 = null,
    name: []const u8 = "_testsinglephase",
};

/// Global extension info (populated at initialization)
pub var extensions: EXTENSIONS = .{};

/// Initialize extension module details
pub fn initExtensionDetails() void {
    // In AOT context, extension modules are linked at compile time
    // This would search for .so/.dylib/.dll files in the path
    extensions = .{
        .name = "_testsinglephase",
        // Other fields populated if extension is found
    };
}

// ============================================================================
// SUBMODULE CREATION
// ============================================================================

/// Create a submodule file for testing
/// Returns (full_module_name, file_path)
pub fn submodule(
    allocator: std.mem.Allocator,
    parent: []const u8,
    name: []const u8,
    pkg_dir: []const u8,
    content: []const u8,
) !struct { name: []const u8, path: []const u8 } {
    // Build file path: pkg_dir/name.py
    const filename = try std.fmt.allocPrint(allocator, "{s}.py", .{name});
    defer allocator.free(filename);

    const path = try std.fs.path.join(allocator, &.{ pkg_dir, filename });

    // Write content to file
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();
    try file.writeAll(content);

    // Build full module name: parent.name
    const full_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ parent, name });

    return .{ .name = full_name, .path = path };
}

// ============================================================================
// PYC FILE UTILITIES
// ============================================================================

/// Read code object from a .pyc file
/// Skips the 16-byte header and unmarshals the code object
pub fn get_code_from_pyc(allocator: std.mem.Allocator, pyc_path: []const u8) !PyValue {
    const file = try std.fs.openFileAbsolute(pyc_path, .{});
    defer file.close();

    // Skip 16-byte header
    try file.seekTo(16);

    // Read remaining content
    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    // In full implementation, would unmarshal the code object
    // For now, return a placeholder
    return PyValue.from("code_object");
}

// ============================================================================
// TEMP MODULE UTILITIES
// ============================================================================

/// Temporary module context for testing
pub const TempModuleContext = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    location: []const u8,
    temp_dir: []const u8,
    is_pkg: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        content: ?[]const u8,
        is_pkg: bool,
    ) !TempModuleContext {
        // Create temp directory
        var temp_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const temp_dir = try std.fs.realpath("/tmp", &temp_dir_buf);

        const location = try std.fs.path.join(allocator, &.{ temp_dir, name });

        if (is_pkg) {
            // Create package directory
            try std.fs.makeDirAbsolute(location);
            const init_path = try std.fs.path.join(allocator, &.{ location, "__init__.py" });
            defer allocator.free(init_path);

            const file = try std.fs.createFileAbsolute(init_path, .{});
            defer file.close();
            if (content) |c| {
                try file.writeAll(c);
            }
        } else {
            // Create module file
            const modpath = try std.fmt.allocPrint(allocator, "{s}.py", .{location});
            defer allocator.free(modpath);

            const file = try std.fs.createFileAbsolute(modpath, .{});
            defer file.close();
            if (content) |c| {
                try file.writeAll(c);
            }
        }

        return .{
            .allocator = allocator,
            .name = name,
            .location = location,
            .temp_dir = temp_dir,
            .is_pkg = is_pkg,
        };
    }

    pub fn deinit(self: *TempModuleContext) void {
        // Clean up temp files
        if (self.is_pkg) {
            std.fs.deleteTreeAbsolute(self.location) catch {};
        } else {
            const modpath = std.fmt.allocPrint(self.allocator, "{s}.py", .{self.location}) catch return;
            defer self.allocator.free(modpath);
            std.fs.deleteFileAbsolute(modpath) catch {};
        }
        self.allocator.free(self.location);
    }
};

/// Create a temporary module for testing
pub fn temp_module(
    allocator: std.mem.Allocator,
    name: []const u8,
    content: ?[]const u8,
    is_pkg: bool,
) !TempModuleContext {
    return TempModuleContext.init(allocator, name, content, is_pkg);
}

// ============================================================================
// IMPORT STATE CONTEXT
// ============================================================================

/// Context manager to manage import-related sys state
pub const ImportStateContext = struct {
    originals: struct {
        meta_path: ?PyValue = null,
        path: ?PyValue = null,
        path_hooks: ?PyValue = null,
        path_importer_cache: ?PyValue = null,
    },

    pub fn init() ImportStateContext {
        return .{ .originals = .{} };
    }

    pub fn deinit(self: *ImportStateContext) void {
        // Restore original values
        _ = self;
    }
};

/// Create an import state context manager
pub fn import_state() ImportStateContext {
    return ImportStateContext.init();
}

// ============================================================================
// BYTECODE UTILITIES
// ============================================================================

/// Decorator to skip tests that require bytecode writing
pub fn writes_bytecode_files(comptime test_fn: anytype) @TypeOf(test_fn) {
    // In AOT context, we don't write bytecode files
    // This decorator would skip such tests
    return test_fn;
}

/// Ensure the __pycache__ directory exists for a bytecode path
pub fn ensure_bytecode_path(allocator: std.mem.Allocator, bytecode_path: []const u8) !void {
    _ = allocator;
    const dir = std.fs.path.dirname(bytecode_path) orelse return;
    std.fs.makeDirAbsolute(dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
}

// ============================================================================
// PYCACHE PREFIX CONTEXT
// ============================================================================

/// Context manager to temporarily adjust sys.pycache_prefix
pub const PycachePrefixContext = struct {
    orig_prefix: ?[]const u8,

    pub fn init(prefix: ?[]const u8) PycachePrefixContext {
        _ = prefix;
        // In full implementation, would save and set sys.pycache_prefix
        return .{ .orig_prefix = null };
    }

    pub fn deinit(self: *PycachePrefixContext) void {
        // Restore original prefix
        _ = self;
    }
};

/// Create a pycache prefix context
pub fn temporary_pycache_prefix(prefix: ?[]const u8) PycachePrefixContext {
    return PycachePrefixContext.init(prefix);
}

// ============================================================================
// MODULE CREATION CONTEXT
// ============================================================================

/// Create multiple modules temporarily for testing
pub fn create_modules(
    allocator: std.mem.Allocator,
    names: []const []const u8,
) !std.StringHashMap([]const u8) {
    var mapping = std.StringHashMap([]const u8).init(allocator);

    // Create temp directory
    var temp_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const temp_dir = try std.fs.realpath("/tmp", &temp_dir_buf);
    try mapping.put(".root", temp_dir);

    for (names) |name| {
        // Parse name into path components
        var path_builder = std.ArrayList(u8).init(allocator);
        defer path_builder.deinit();

        try path_builder.appendSlice(temp_dir);

        var iter = std.mem.splitSequence(u8, name, ".");
        var last_part: []const u8 = "";
        while (iter.next()) |part| {
            try path_builder.append('/');
            try path_builder.appendSlice(part);
            last_part = part;
        }

        // If not __init__, add .py extension
        if (!std.mem.endsWith(u8, last_part, "__init__")) {
            try path_builder.appendSlice(".py");
        } else {
            try path_builder.appendSlice(".py");
        }

        const file_path = try path_builder.toOwnedSlice();

        // Create parent directories
        if (std.fs.path.dirname(file_path)) |dir| {
            std.fs.makeDirAbsolute(dir) catch |err| {
                if (err != error.PathAlreadyExists) {
                    return err;
                }
            };
        }

        // Write module file with attr = name
        const file = try std.fs.createFileAbsolute(file_path, .{});
        defer file.close();
        try file.writer().print("attr = {s!r}\n", .{name});

        try mapping.put(name, file_path);
    }

    return mapping;
}

// ============================================================================
// PATH HOOK MOCK
// ============================================================================

/// Create a mock path hook for testing
pub fn mock_path_hook(
    entries: []const []const u8,
    importer: anytype,
) fn ([]const u8) anyerror!@TypeOf(importer) {
    _ = entries;
    return struct {
        fn hook(entry: []const u8) !@TypeOf(importer) {
            _ = entry;
            return importer;
        }
    }.hook;
}
