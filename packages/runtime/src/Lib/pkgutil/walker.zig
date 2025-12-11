/// pkgutil/walker.zig - Package walking functionality
/// Provides recursive package discovery and traversal

const std = @import("std");
const iterator = @import("iterator.zig");
const types = @import("types.zig");

pub const ModuleInfo = types.ModuleInfo;
pub const iter_modules = iterator.iter_modules;

/// Walk all packages recursively
pub fn walk_packages(
    allocator: std.mem.Allocator,
    path: ?[]const []const u8,
    prefix: ?[]const u8,
    onerror: ?*const fn ([]const u8) void,
) !std.ArrayList(ModuleInfo) {
    var result = std.ArrayList(ModuleInfo).init(allocator);
    errdefer result.deinit();

    var iter = iter_modules(allocator, path, prefix);
    defer iter.deinit();

    while (try iter.next()) |info| {
        try result.append(info);

        if (info.ispkg) {
            // Recursively walk subpackages
            const subpath = &[_][]const u8{info.name};
            const subprefix = try std.fmt.allocPrint(allocator, "{s}.", .{info.name});
            defer allocator.free(subprefix);

            var subresult = walk_packages(allocator, subpath, subprefix, onerror) catch |err| {
                if (onerror) |handler| {
                    handler(info.name);
                }
                _ = err;
                continue;
            };

            for (subresult.items) |subinfo| {
                try result.append(subinfo);
            }
            subresult.deinit();
        }
    }

    return result;
}
