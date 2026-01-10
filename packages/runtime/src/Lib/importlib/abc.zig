//! importlib.abc - Abstract base classes for import system
//! Reference: cpython/Lib/importlib/abc.py
//!
//! CPython __all__:
//!   ['Loader', 'MetaPathFinder', 'PathEntryFinder', 'ResourceLoader',
//!    'InspectLoader', 'ExecutionLoader', 'FileLoader', 'SourceLoader']

const std = @import("std");
const importlib = @import("../importlib.zig");

// Re-export base types from importlib.zig (DRY)
pub const ModuleSpec = importlib.ModuleSpec;
pub const Loader = importlib.Loader;

/// Abstract base class for import finders on sys.meta_path
/// CPython: class MetaPathFinder
pub const MetaPathFinder = struct {
    /// Find module spec for the named module
    /// CPython signature: find_spec(fullname, path, target=None)
    pub fn findSpec(
        fullname: []const u8,
        path: ?[]const []const u8,
        target: ?*anyopaque,
    ) ?ModuleSpec {
        _ = fullname;
        _ = path;
        _ = target;
        return null;
    }

    /// Deprecated: Find module (use find_spec instead)
    pub fn findModule(fullname: []const u8, path: ?[]const u8) ?*anyopaque {
        _ = fullname;
        _ = path;
        return null;
    }

    /// Invalidate any cached data
    pub fn invalidateCaches() void {}
};

/// Abstract base class for path entry finders
/// CPython: class PathEntryFinder
pub const PathEntryFinder = struct {
    /// Find module spec for the named module
    pub fn findSpec(fullname: []const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = fullname;
        _ = target;
        return null;
    }

    /// Invalidate any cached data
    pub fn invalidateCaches() void {}
};

/// Abstract base class for loaders that can load resources
/// CPython: class ResourceLoader(Loader)
pub const ResourceLoader = struct {
    /// Return the bytes for the resource at path
    pub fn getData(path: []const u8) ![]u8 {
        _ = path;
        return error.NotImplemented;
    }
};

/// Abstract base class for loaders that can provide source inspection
/// CPython: class InspectLoader(Loader)
pub const InspectLoader = struct {
    /// Return the source code for the named module
    pub fn getSource(fullname: []const u8) ![]u8 {
        _ = fullname;
        return error.NotImplemented;
    }

    /// Compile source into code object
    pub fn sourceToCode(data: []const u8, path: []const u8) !*anyopaque {
        _ = data;
        _ = path;
        return error.NotImplemented;
    }

    /// Return the code object for the named module
    pub fn getCode(fullname: []const u8) !*anyopaque {
        _ = fullname;
        return error.NotImplemented;
    }

    /// Return True if the module is a package
    pub fn isPackage(fullname: []const u8) !bool {
        _ = fullname;
        return error.NotImplemented;
    }
};

/// Abstract base class for loaders that can execute modules
/// CPython: class ExecutionLoader(InspectLoader)
pub const ExecutionLoader = struct {
    /// Get the path to the source file for the module
    pub fn getFilename(fullname: []const u8) ![]const u8 {
        _ = fullname;
        return error.NotImplemented;
    }
};

/// Abstract base class for loaders that load from files
/// CPython: class FileLoader(ResourceLoader, ExecutionLoader)
pub const FileLoader = struct {
    name: []const u8,
    path: []const u8,

    pub fn init(name: []const u8, path: []const u8) FileLoader {
        return .{ .name = name, .path = path };
    }

    pub fn getFilename(self: *const FileLoader, fullname: []const u8) []const u8 {
        _ = fullname;
        return self.path;
    }

    pub fn getData(self: *const FileLoader, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        _ = self;
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, std.math.maxInt(usize));
    }
};

/// Abstract base class for loaders loading Python source
/// CPython: class SourceLoader(ResourceLoader, ExecutionLoader)
pub const SourceLoader = struct {
    /// Return the path to cached bytecode file
    pub fn pathStats(path: []const u8) !std.fs.File.Stat {
        _ = path;
        return error.NotImplemented;
    }

    /// Optional: Set cached data for later retrieval
    pub fn setCachedData(path: []const u8, data: []const u8) void {
        _ = path;
        _ = data;
    }

    /// Return the path to the cached bytecode file
    pub fn cachePath(source_path: []const u8) ![]const u8 {
        _ = source_path;
        return error.NotImplemented;
    }
};

/// Traversable protocol for resource access
/// CPython: class Traversable(Protocol)
pub const Traversable = struct {
    /// Return True if self is a directory
    pub fn isDir(self: *const Traversable) bool {
        _ = self;
        return false;
    }

    /// Return True if self is a file
    pub fn isFile(self: *const Traversable) bool {
        _ = self;
        return false;
    }

    /// Return contents as an iterable
    pub fn iterdir(self: *const Traversable, allocator: std.mem.Allocator) !std.ArrayList(*Traversable) {
        _ = self;
        return std.ArrayList(*Traversable){}.init(allocator);
    }

    /// Return Traversable child
    pub fn joinpath(self: *const Traversable, child: []const u8) *Traversable {
        _ = self;
        _ = child;
        return undefined;
    }

    /// Open file and return stream
    pub fn open(self: *const Traversable, mode: []const u8) !std.fs.File {
        _ = self;
        _ = mode;
        return error.NotImplemented;
    }

    /// Read and return contents as bytes
    pub fn readBytes(self: *const Traversable, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return error.NotImplemented;
    }

    /// Read and return contents as text
    pub fn readText(self: *const Traversable, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = allocator;
        return error.NotImplemented;
    }
};

/// TraversableResources protocol
/// CPython: class TraversableResources(Protocol)
pub const TraversableResources = struct {
    /// Return Traversable for package files
    pub fn files(self: *const TraversableResources) *Traversable {
        _ = self;
        return undefined;
    }
};

// Tests
test "MetaPathFinder" {
    const spec = MetaPathFinder.findSpec("test", null, null);
    try std.testing.expect(spec == null);
}

test "FileLoader init" {
    const loader = FileLoader.init("mymodule", "/path/to/mymodule.py");
    try std.testing.expectEqualStrings("mymodule", loader.name);
    try std.testing.expectEqualStrings("/path/to/mymodule.py", loader.path);
}
