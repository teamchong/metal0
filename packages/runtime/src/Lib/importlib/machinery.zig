//! importlib.machinery - Finder and loader implementations
//! Reference: cpython/Lib/importlib/machinery.py
//!
//! CPython exports (no explicit __all__):
//!   ModuleSpec, BuiltinImporter, FrozenImporter
//!   SOURCE_SUFFIXES, DEBUG_BYTECODE_SUFFIXES, OPTIMIZED_BYTECODE_SUFFIXES,
//!   BYTECODE_SUFFIXES, EXTENSION_SUFFIXES
//!   WindowsRegistryFinder, PathFinder, FileFinder
//!   SourceFileLoader, SourcelessFileLoader, ExtensionFileLoader,
//!   AppleFrameworkLoader, NamespaceLoader

const std = @import("std");
const builtin = @import("builtin");
const importlib = @import("../importlib.zig");
const abc = @import("abc.zig");

// Re-export core types from importlib.zig (DRY)
pub const ModuleSpec = importlib.ModuleSpec;
pub const SourceFileLoader = importlib.SourceFileLoader;
pub const SourcelessFileLoader = importlib.SourcelessFileLoader;
pub const ExtensionFileLoader = importlib.ExtensionFileLoader;
pub const PathFinder = importlib.PathFinder;

// File suffixes
pub const SOURCE_SUFFIXES: []const []const u8 = &.{".py"};
pub const DEBUG_BYTECODE_SUFFIXES: []const []const u8 = &.{".pyc"};
pub const OPTIMIZED_BYTECODE_SUFFIXES: []const []const u8 = &.{".pyo", ".pyc"};
pub const BYTECODE_SUFFIXES: []const []const u8 = &.{".pyc"};
pub const EXTENSION_SUFFIXES: []const []const u8 = if (builtin.os.tag == .windows)
    &.{".pyd", ".dll"}
else if (builtin.os.tag == .macos)
    &.{".so", ".dylib"}
else
    &.{".so"};

/// Return all recognized suffixes
pub fn allSuffixes() []const []const u8 {
    return SOURCE_SUFFIXES ++ BYTECODE_SUFFIXES ++ EXTENSION_SUFFIXES;
}

/// Importer for built-in modules
/// CPython: class BuiltinImporter
pub const BuiltinImporter = struct {
    /// Find spec for built-in module
    pub fn findSpec(fullname: []const u8, path: ?[]const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = path;
        _ = target;
        // Check if module is built-in
        const builtins = [_][]const u8{
            "sys",    "builtins", "_io",     "_warnings", "_weakref",
            "errno",  "faulthandler", "_thread", "posix",     "nt",
            "_signal", "_abc",    "_ast",    "gc",        "_codecs",
        };
        for (builtins) |name| {
            if (std.mem.eql(u8, fullname, name)) {
                return ModuleSpec.init(std.heap.page_allocator, fullname, null);
            }
        }
        return null;
    }

    /// Load a built-in module
    pub fn loadModule(fullname: []const u8) !*anyopaque {
        _ = fullname;
        return error.ModuleNotFound;
    }

    /// Create module from spec
    pub fn createModule(spec: *const ModuleSpec) ?*anyopaque {
        _ = spec;
        return null;
    }

    /// Execute module
    pub fn execModule(module: *anyopaque) !void {
        _ = module;
    }

    /// Check if module is a package
    pub fn isPackage(fullname: []const u8) bool {
        _ = fullname;
        return false;
    }
};

/// Importer for frozen modules
/// CPython: class FrozenImporter
pub const FrozenImporter = struct {
    /// Find spec for frozen module
    pub fn findSpec(fullname: []const u8, path: ?[]const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = fullname;
        _ = path;
        _ = target;
        // In AOT compilation, there are no frozen modules
        return null;
    }

    /// Load a frozen module
    pub fn loadModule(fullname: []const u8) !*anyopaque {
        _ = fullname;
        return error.ModuleNotFound;
    }
};

/// Windows registry finder (Windows only)
/// CPython: class WindowsRegistryFinder
pub const WindowsRegistryFinder = struct {
    pub fn findSpec(fullname: []const u8, path: ?[]const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = fullname;
        _ = path;
        _ = target;
        if (builtin.os.tag != .windows) return null;
        // Would search Windows registry for module
        return null;
    }
};

/// File-based finder with cached directory contents
/// CPython: class FileFinder
pub const FileFinder = struct {
    path: []const u8,
    loaders: std.ArrayList(LoaderDetail),
    allocator: std.mem.Allocator,

    pub const LoaderDetail = struct {
        loader: type,
        suffixes: []const []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, path: []const u8) FileFinder {
        return .{
            .path = path,
            .loaders = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FileFinder) void {
        self.loaders.deinit(self.allocator);
    }

    pub fn findSpec(self: *FileFinder, fullname: []const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = self;
        _ = fullname;
        _ = target;
        return null;
    }

    pub fn invalidateCaches(self: *FileFinder) void {
        _ = self;
    }
};

/// Loader for Apple framework bundles (macOS/iOS)
/// CPython: class AppleFrameworkLoader
pub const AppleFrameworkLoader = struct {
    name: []const u8,
    path: []const u8,

    pub fn init(name: []const u8, path: []const u8) AppleFrameworkLoader {
        return .{ .name = name, .path = path };
    }

    pub fn createModule(self: *const AppleFrameworkLoader, spec: *const ModuleSpec) ?*anyopaque {
        _ = self;
        _ = spec;
        return null;
    }

    pub fn execModule(self: *const AppleFrameworkLoader, module: *anyopaque) !void {
        _ = self;
        _ = module;
    }
};

/// Loader for namespace packages
/// CPython: class NamespaceLoader
pub const NamespaceLoader = struct {
    path: []const []const u8,

    pub fn init(name: []const u8, path: []const []const u8, path_finder: *PathFinder) NamespaceLoader {
        _ = name;
        _ = path_finder;
        return .{ .path = path };
    }

    pub fn isPackage(self: *const NamespaceLoader, fullname: []const u8) bool {
        _ = self;
        _ = fullname;
        return true;
    }

    pub fn getSource(self: *const NamespaceLoader, fullname: []const u8) ?[]const u8 {
        _ = self;
        _ = fullname;
        return "";
    }

    pub fn getCode(self: *const NamespaceLoader, fullname: []const u8) ?*anyopaque {
        _ = self;
        _ = fullname;
        return null;
    }

    pub fn createModule(self: *const NamespaceLoader, spec: *const ModuleSpec) ?*anyopaque {
        _ = self;
        _ = spec;
        return null;
    }

    pub fn execModule(self: *const NamespaceLoader, module: *anyopaque) !void {
        _ = self;
        _ = module;
    }
};

// Tests
test "SOURCE_SUFFIXES" {
    try std.testing.expectEqual(@as(usize, 1), SOURCE_SUFFIXES.len);
    try std.testing.expectEqualStrings(".py", SOURCE_SUFFIXES[0]);
}

test "BuiltinImporter find builtin" {
    const spec = BuiltinImporter.findSpec("sys", null, null);
    try std.testing.expect(spec != null);
}

test "BuiltinImporter not found" {
    const spec = BuiltinImporter.findSpec("nonexistent_module", null, null);
    try std.testing.expect(spec == null);
}

test "FrozenImporter find" {
    const spec = FrozenImporter.findSpec("test", null, null);
    try std.testing.expect(spec == null);
}
