/// pkgutil/path_utils.zig - Path utilities for package operations
/// Handles path operations and data retrieval from packages

const std = @import("std");

/// Read data from a package resource
pub fn get_data(allocator: std.mem.Allocator, package: []const u8, resource: []const u8) ![]u8 {
    // Convert package path (dots to slashes)
    var pkg_path = try allocator.alloc(u8, package.len);
    defer allocator.free(pkg_path);

    for (package, 0..) |c, i| {
        pkg_path[i] = if (c == '.') '/' else c;
    }

    // Build full path
    const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ pkg_path, resource });
    defer allocator.free(full_path);

    // Read file
    const file = try std.fs.cwd().openFile(full_path, .{});
    defer file.close();

    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

/// Extend package __path__ for namespace packages
/// Searches sys.path for additional directories containing the package
pub fn extend_path(allocator: std.mem.Allocator, path: []const []const u8, name: []const u8) ![]const []const u8 {
    var result: std.ArrayList([]const u8) = .{};

    // Keep existing paths
    for (path) |p| {
        try result.append(allocator, try allocator.dupe(u8, p));
    }

    // Check sys.path for additional namespace package paths
    // In a real implementation, this would get sys.path from the runtime
    // For now, check common Python paths
    const sys_paths = [_][]const u8{
        "/usr/lib/python3/dist-packages",
        "/usr/local/lib/python3.12/site-packages",
        "/usr/local/lib/python3.11/site-packages",
        "/usr/lib/python3.12/site-packages",
        "/usr/lib/python3.11/site-packages",
    };

    // Also check user site-packages
    const home = std.posix.getenv("HOME") orelse "";

    for (sys_paths) |sys_path| {
        // Check if sys_path/name exists and is a directory (namespace package)
        var pkg_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const pkg_path = std.fmt.bufPrint(&pkg_path_buf, "{s}/{s}", .{ sys_path, name }) catch continue;

        // Check if this path exists and isn't already in result
        if (std.fs.cwd().openDir(pkg_path, .{})) |dir| {
            var d = dir;
            d.close();

            // Check it's not already in the list
            var found = false;
            for (result.items) |existing| {
                if (std.mem.eql(u8, existing, pkg_path)) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                try result.append(allocator, try allocator.dupe(u8, pkg_path));
            }
        } else |_| {}
    }

    // Check user site-packages
    if (home.len > 0) {
        const user_paths = [_][]const u8{
            ".local/lib/python3.12/site-packages",
            ".local/lib/python3.11/site-packages",
            ".local/lib/python3.10/site-packages",
        };

        for (user_paths) |user_path| {
            var full_buf: [std.fs.max_path_bytes]u8 = undefined;
            const full_path = std.fmt.bufPrint(&full_buf, "{s}/{s}/{s}", .{ home, user_path, name }) catch continue;

            if (std.fs.cwd().openDir(full_path, .{})) |dir| {
                var d = dir;
                d.close();

                var found = false;
                for (result.items) |existing| {
                    if (std.mem.eql(u8, existing, full_path)) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    try result.append(allocator, try allocator.dupe(u8, full_path));
                }
            } else |_| {}
        }
    }

    return result.toOwnedSlice(allocator);
}

test "extend_path preserves paths" {
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{ "/path/one", "/path/two" };
    const result = try extend_path(allocator, &paths, "mypackage");
    defer {
        for (result) |p| allocator.free(p);
        allocator.free(result);
    }
    try std.testing.expectEqual(@as(usize, 2), result.len);
}
