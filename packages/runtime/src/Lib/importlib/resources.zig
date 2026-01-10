//! importlib.resources - Read resources contained within a package
//! Reference: cpython/Lib/importlib/resources/__init__.py
//!
//! CPython __all__:
//!   ['Package', 'Anchor', 'ResourceReader', 'as_file', 'files',
//!    'contents', 'is_resource', 'open_binary', 'open_text',
//!    'path', 'read_binary', 'read_text']

const std = @import("std");
const importlib = @import("../importlib.zig");

// ============================================================================
// Types
// ============================================================================

/// Package - Union type for module or module name
/// CPython: Package = Union[str, types.ModuleType]
pub const Package = union(enum) {
    name: []const u8,
    module: *anyopaque,

    pub fn getName(self: Package) []const u8 {
        return switch (self) {
            .name => |n| n,
            .module => "<module>",
        };
    }
};

/// Anchor - Same as Package (type alias)
/// CPython: Anchor = Package
pub const Anchor = Package;

/// ResourceReader - Abstract base class for reading resources
/// CPython: class ResourceReader(abc.ABC)
pub const ResourceReader = struct {
    /// Open a resource for binary reading
    pub fn openResource(self: *const ResourceReader, resource: []const u8) !std.fs.File {
        _ = self;
        _ = resource;
        return error.NotImplemented;
    }

    /// Return a Traversable for the resource
    pub fn resourcePath(self: *const ResourceReader, resource: []const u8) []const u8 {
        _ = self;
        return resource;
    }

    /// Return True if the named resource exists
    pub fn isResource(self: *const ResourceReader, name: []const u8) bool {
        _ = self;
        _ = name;
        return false;
    }

    /// Return an iterable of strings over the contents
    pub fn contents(self: *const ResourceReader, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        _ = self;
        return std.ArrayList([]const u8){}.init(allocator);
    }
};

/// Traversable - Protocol for resource traversal
pub const Traversable = struct {
    path: []const u8,

    pub fn init(path: []const u8) Traversable {
        return .{ .path = path };
    }

    pub fn isDir(self: *const Traversable) bool {
        const stat = std.fs.cwd().statFile(self.path) catch return false;
        return stat.kind == .directory;
    }

    pub fn isFile(self: *const Traversable) bool {
        const stat = std.fs.cwd().statFile(self.path) catch return false;
        return stat.kind == .file;
    }

    pub fn joinpath(self: *const Traversable, allocator: std.mem.Allocator, child: []const u8) !Traversable {
        const new_path = try std.fs.path.join(allocator, &.{ self.path, child });
        return Traversable.init(new_path);
    }

    pub fn name(self: *const Traversable) []const u8 {
        return std.fs.path.basename(self.path);
    }
};

// ============================================================================
// Functions
// ============================================================================

/// Return a Traversable object for the given package
/// CPython: def files(anchor: Anchor = None) -> Traversable
pub fn files(anchor: ?Anchor) !Traversable {
    const pkg_name = if (anchor) |a| a.getName() else ".";
    return Traversable.init(pkg_name);
}

/// Given a Traversable, return a context manager for a Path
/// CPython: def as_file(path: Traversable) -> AbstractContextManager[Path]
pub fn asFile(traversable: Traversable) std.fs.File {
    return std.fs.cwd().openFile(traversable.path, .{}) catch unreachable;
}

/// Return an iterable of entries in package
/// CPython: def contents(package: Package) -> Iterable[str]
pub fn contents(allocator: std.mem.Allocator, package: Package) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8){};
    const dir = std.fs.cwd().openDir(package.getName(), .{ .iterate = true }) catch return result;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        try result.append(allocator, try allocator.dupe(u8, entry.name));
    }
    return result;
}

/// Return True if the named resource exists in package
/// CPython: def is_resource(package: Package, name: str) -> bool
pub fn isResource(package: Package, name: []const u8) bool {
    var path_buf: [512]u8 = undefined;
    const full_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ package.getName(), name }) catch return false;
    std.fs.cwd().access(full_path, .{}) catch return false;
    return true;
}

/// Return a file-like opened for binary reading
/// CPython: def open_binary(package: Package, resource: Resource) -> BufferedReader
pub fn openBinary(package: Package, resource: []const u8) !std.fs.File {
    var path_buf: [512]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ package.getName(), resource });
    return std.fs.cwd().openFile(full_path, .{});
}

/// Return a file-like opened for text reading
/// CPython: def open_text(package: Package, resource: Resource, encoding: str = 'utf-8', errors: str = 'strict') -> TextIOWrapper
pub fn openText(package: Package, resource: []const u8) !std.fs.File {
    return openBinary(package, resource);
}

/// Return the path to the resource as context manager
/// CPython: def path(package: Package, resource: Resource) -> AbstractContextManager[Path]
pub fn path(allocator: std.mem.Allocator, package: Package, resource: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ package.getName(), resource });
}

/// Return the binary contents of the resource
/// CPython: def read_binary(package: Package, resource: Resource) -> bytes
pub fn readBinary(allocator: std.mem.Allocator, package: Package, resource: []const u8) ![]u8 {
    var path_buf: [512]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ package.getName(), resource });
    const file = try std.fs.cwd().openFile(full_path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

/// Return the decoded string of the resource
/// CPython: def read_text(package: Package, resource: Resource, encoding: str = 'utf-8', errors: str = 'strict') -> str
pub fn readText(allocator: std.mem.Allocator, package: Package, resource: []const u8) ![]u8 {
    return readBinary(allocator, package, resource);
}

// ============================================================================
// Tests
// ============================================================================

test "Package type" {
    const pkg = Package{ .name = "mypackage" };
    try std.testing.expectEqualStrings("mypackage", pkg.getName());
}

test "Traversable basic" {
    const t = Traversable.init(".");
    try std.testing.expectEqualStrings(".", t.path);
}

test "isResource non-existent" {
    const pkg = Package{ .name = "/nonexistent" };
    try std.testing.expect(!isResource(pkg, "file.txt"));
}
