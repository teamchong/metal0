//! zoneinfo._tzpath - Timezone file path resolution
//! Reference: cpython/Lib/zoneinfo/_tzpath.py
//!
//! Manages the search path for timezone data files.

const std = @import("std");
const builtin = @import("builtin");

/// Default timezone data paths on Unix systems
pub const TZPATH_UNIX = [_][]const u8{
    "/usr/share/zoneinfo",
    "/usr/lib/zoneinfo",
    "/usr/share/lib/zoneinfo",
    "/etc/zoneinfo",
};

/// Default timezone data paths on macOS
pub const TZPATH_MACOS = [_][]const u8{
    "/var/db/timezone/zoneinfo",
    "/usr/share/zoneinfo",
    "/usr/share/zoneinfo.default",
};

/// Default timezone data paths on Windows (typically from pytz/tzdata)
pub const TZPATH_WINDOWS = [_][]const u8{
    // Usually from pip-installed tzdata package
};

/// Get the default TZPATH for the current platform
pub fn getDefaultTZPath() []const []const u8 {
    return switch (builtin.os.tag) {
        .macos => &TZPATH_MACOS,
        .windows => &TZPATH_WINDOWS,
        else => &TZPATH_UNIX,
    };
}

/// Current TZPATH state
var tzpath: ?std.ArrayList([]const u8) = null;
var tzpath_allocator: ?std.mem.Allocator = null;

/// Reset TZPATH to system default
pub fn reset_tzpath() void {
    if (tzpath) |*list| {
        list.deinit(tzpath_allocator.?);
        tzpath = null;
        tzpath_allocator = null;
    }
}

/// Set a custom TZPATH
pub fn set_tzpath(allocator: std.mem.Allocator, paths: []const []const u8) !void {
    reset_tzpath();

    var list: std.ArrayList([]const u8) = .{};
    for (paths) |path| {
        try list.append(allocator, path);
    }

    tzpath = list;
    tzpath_allocator = allocator;
}

/// Get current TZPATH
pub fn get_tzpath() []const []const u8 {
    if (tzpath) |list| {
        return list.items;
    }
    return getDefaultTZPath();
}

/// Find a timezone file by name
pub fn findTzFile(allocator: std.mem.Allocator, key: []const u8) !?[]const u8 {
    for (get_tzpath()) |base_path| {
        const full_path = try std.fs.path.join(allocator, &.{ base_path, key });

        // Check if file exists
        if (std.fs.cwd().access(full_path, .{})) |_| {
            return full_path;
        } else |_| {
            allocator.free(full_path);
        }
    }
    return null;
}

/// List available timezones
pub fn listTimezones(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result: std.ArrayList([]const u8) = .{};
    errdefer result.deinit(allocator);

    for (get_tzpath()) |base_path| {
        // Open directory if it exists
        var dir = std.fs.cwd().openDir(base_path, .{ .iterate = true }) catch continue;
        defer dir.close();

        // Iterate through directory
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file or entry.kind == .directory) {
                const name = try allocator.dupe(u8, entry.name);
                try result.append(allocator, name);
            }
        }
    }

    return result;
}

/// Check if TZPATH contains valid timezone data
pub fn validateTzPath() bool {
    for (get_tzpath()) |path| {
        // Check if UTC file exists (always present in valid tzdata)
        var buf: [256]u8 = undefined;
        const utc_path = std.fmt.bufPrint(&buf, "{s}/UTC", .{path}) catch continue;

        if (std.fs.cwd().access(utc_path, .{})) |_| {
            return true;
        } else |_| {}
    }
    return false;
}

/// Get TZDATA version string
pub fn getTzDataVersion(allocator: std.mem.Allocator) !?[]const u8 {
    for (get_tzpath()) |base_path| {
        const version_path = try std.fs.path.join(allocator, &.{ base_path, "+VERSION" });
        defer allocator.free(version_path);

        const content = std.fs.cwd().readFileAlloc(allocator, version_path, 128) catch continue;
        return std.mem.trim(u8, content, " \t\r\n");
    }
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "getDefaultTZPath" {
    const paths = getDefaultTZPath();
    try std.testing.expect(paths.len > 0);
}

test "get_tzpath default" {
    const paths = get_tzpath();
    try std.testing.expect(paths.len > 0);
}

test "findTzFile not found" {
    const allocator = std.testing.allocator;
    const result = try findTzFile(allocator, "NONEXISTENT_ZONE");
    try std.testing.expect(result == null);
}
