/// pkgutil/types.zig - Type definitions for package utilities
/// Defines core structures used throughout the pkgutil module

const std = @import("std");

/// Information about a module or package
pub const ModuleInfo = struct {
    /// The module finder that located this module
    module_finder: ?*anyopaque = null,
    /// The module name
    name: []const u8,
    /// Whether this is a package (has __path__)
    ispkg: bool,

    pub fn deinit(self: *ModuleInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

/// Importer type (simplified representation)
pub const Importer = struct {
    path: []const u8,
    is_package_path: bool,

    pub fn find_module(self: *const Importer, fullname: []const u8) bool {
        // Check if module exists at this path
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;

        // Try .py file
        const py_path = std.fmt.bufPrint(&path_buf, "{s}/{s}.py", .{ self.path, fullname }) catch return false;
        if (std.fs.cwd().access(py_path, .{})) |_| {
            return true;
        } else |_| {}

        // Try package (__init__.py)
        const pkg_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/__init__.py", .{ self.path, fullname }) catch return false;
        if (std.fs.cwd().access(pkg_path, .{})) |_| {
            return true;
        } else |_| {}

        return false;
    }
};

/// Loader result
pub const LoaderResult = struct {
    loader: ?*const Importer,
    portions: []const []const u8,
};

test "ModuleInfo" {
    var info = ModuleInfo{
        .name = "test_module",
        .ispkg = false,
    };
    try std.testing.expectEqualStrings("test_module", info.name);
    try std.testing.expect(!info.ispkg);
    _ = &info;
}
