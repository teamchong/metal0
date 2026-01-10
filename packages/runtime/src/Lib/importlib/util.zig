//! importlib.util - Utility functions for import system
//! Reference: cpython/Lib/importlib/util.py
//!
//! CPython exports (no explicit __all__):
//!   MAGIC_NUMBER, _RAW_MAGIC_NUMBER
//!   resolve_name, find_spec, module_from_spec
//!   source_hash, cache_from_source, source_from_cache, decode_source
//!   spec_from_loader, spec_from_file_location
//!   LazyLoader

const std = @import("std");
const importlib = @import("../importlib.zig");
const abc = @import("abc.zig");

// Re-export utility functions from importlib.zig (DRY)
pub const resolve_name = importlib.util.resolve_name;
pub const source_hash = importlib.util.source_hash;
pub const is_valid_module_name = importlib.util.is_valid_module_name;

// Re-export types
pub const ModuleSpec = importlib.ModuleSpec;

// Magic number for bytecode files (Python 3.12+)
// This is used to check bytecode file compatibility
pub const MAGIC_NUMBER: [4]u8 = .{ 0xa7, 0x0d, 0x0d, 0x0a };
pub const _RAW_MAGIC_NUMBER: u32 = 3531;

/// Find the spec for a module, optionally relative to a package
/// CPython signature: find_spec(name, package=None)
pub fn findSpec(allocator: std.mem.Allocator, name: []const u8, package: ?[]const u8) !?ModuleSpec {
    const full_name = try resolve_name(allocator, name, package);
    defer if (package != null) allocator.free(full_name);
    return importlib.PathFinder.find_spec(allocator, full_name, null, null);
}

/// Create a module based on the provided spec
/// CPython signature: module_from_spec(spec)
pub fn moduleFromSpec(spec: *const ModuleSpec) !*anyopaque {
    _ = spec;
    // Would create and return a new module object
    return error.LoaderError;
}

/// Create a ModuleSpec from a loader
/// CPython signature: spec_from_loader(name, loader, *, origin=None, is_package=None)
pub fn specFromLoader(
    allocator: std.mem.Allocator,
    name: []const u8,
    loader: ?*anyopaque,
    origin: ?[]const u8,
    is_package: ?bool,
) !ModuleSpec {
    var spec = ModuleSpec.init(allocator, name, loader);
    spec.origin = origin;
    if (is_package orelse false) {
        spec.submodule_search_locations = std.ArrayList([]const u8){};
    }
    return spec;
}

/// Create a ModuleSpec from a file location
/// CPython signature: spec_from_file_location(name, location=None, *, loader=None, submodule_search_locations=_POPULATE)
pub fn specFromFileLocation(
    allocator: std.mem.Allocator,
    name: []const u8,
    location: ?[]const u8,
    loader: ?*anyopaque,
) !ModuleSpec {
    var spec = ModuleSpec.init(allocator, name, loader);
    spec.origin = location;
    spec.has_location = true;
    return spec;
}

/// Convert source path to cache path (.pyc)
/// CPython signature: cache_from_source(path, debug_override=None, *, optimization=None)
pub fn cacheFromSource(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    // Simple implementation: replace .py with .pyc
    if (std.mem.endsWith(u8, path, ".py")) {
        var result = try allocator.alloc(u8, path.len + 1);
        @memcpy(result[0..path.len], path);
        result[path.len - 2] = 'p';
        result[path.len - 1] = 'y';
        result[path.len] = 'c';
        return result[0 .. path.len + 1];
    }
    return allocator.dupe(u8, path);
}

/// Convert cache path to source path
/// CPython signature: source_from_cache(path)
pub fn sourceFromCache(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, path, ".pyc")) {
        var result = try allocator.alloc(u8, path.len - 1);
        @memcpy(result[0 .. path.len - 3], path[0 .. path.len - 3]);
        result[path.len - 3] = 'p';
        result[path.len - 2] = 'y';
        return result[0 .. path.len - 1];
    }
    return allocator.dupe(u8, path);
}

/// Decode bytes to string for source files
/// CPython signature: decode_source(source_bytes)
pub fn decodeSource(source_bytes: []const u8) []const u8 {
    // In Zig, strings are already UTF-8
    return source_bytes;
}

/// Lazy module loader - delays loading until attribute access
/// CPython: class LazyLoader
pub const LazyLoader = struct {
    loader: *anyopaque,
    loaded: bool = false,

    pub fn init(loader: *anyopaque) LazyLoader {
        return .{ .loader = loader };
    }

    /// Factory method to create a lazy loader
    pub fn factory(loader_factory: *const fn () *anyopaque) LazyLoader {
        return .{ .loader = loader_factory() };
    }

    pub fn createModule(self: *LazyLoader, spec: *const ModuleSpec) ?*anyopaque {
        _ = self;
        _ = spec;
        return null;
    }

    pub fn execModule(self: *LazyLoader, module: *anyopaque) !void {
        _ = self;
        _ = module;
    }
};

/// Set the __loader__ attribute on module
pub fn setLoader(module: *anyopaque, loader: *anyopaque) void {
    _ = module;
    _ = loader;
}

/// Set the __package__ attribute on module
pub fn setPackage(module: *anyopaque, package: []const u8) void {
    _ = module;
    _ = package;
}

// Tests
test "MAGIC_NUMBER" {
    try std.testing.expectEqual(@as(u8, 0xa7), MAGIC_NUMBER[0]);
    try std.testing.expectEqual(@as(u8, 0x0d), MAGIC_NUMBER[1]);
}

test "cacheFromSource" {
    const allocator = std.testing.allocator;
    const result = try cacheFromSource(allocator, "mymodule.py");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("mymodule.pyc", result);
}

test "sourceFromCache" {
    const allocator = std.testing.allocator;
    const result = try sourceFromCache(allocator, "mymodule.pyc");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("mymodule.py", result);
}

test "decodeSource" {
    const source = "print('hello')";
    const decoded = decodeSource(source);
    try std.testing.expectEqualStrings(source, decoded);
}
