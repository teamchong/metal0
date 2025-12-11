/// pkgutil/loader.zig - Module loader functionality
/// Provides importer and loader lookup operations

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");

pub const Importer = types.Importer;
pub const LoaderResult = types.LoaderResult;

/// Importer cache (path → Importer)
var importer_cache: ?hashmap_helper.StringHashMap(Importer) = null;

/// Get the importer for a path item
pub fn get_importer(allocator: std.mem.Allocator, path_item: []const u8) ?*const Importer {
    // Initialize cache if needed
    if (importer_cache == null) {
        importer_cache = hashmap_helper.StringHashMap(Importer).init(allocator);
    }

    // Check cache first
    if (importer_cache) |*cache| {
        if (cache.getPtr(path_item)) |importer| {
            return importer;
        }

        // Check if path exists and is a directory
        if (std.fs.cwd().access(path_item, .{})) |_| {
            // Create new importer for this path
            cache.put(path_item, Importer{
                .path = path_item,
                .is_package_path = true,
            }) catch return null;

            return cache.getPtr(path_item);
        } else |_| {}
    }

    return null;
}

/// Find loader for a module by searching paths
pub fn find_loader(allocator: std.mem.Allocator, fullname: []const u8, path: ?[]const []const u8) !?LoaderResult {
    // Default search paths
    const default_paths = [_][]const u8{
        ".",
        "/usr/lib/python3/dist-packages",
        "/usr/local/lib/python3.12/site-packages",
    };

    const search_paths = path orelse &default_paths;

    for (search_paths) |search_path| {
        if (get_importer(allocator, search_path)) |importer| {
            if (importer.find_module(fullname)) {
                return LoaderResult{
                    .loader = importer,
                    .portions = &[_][]const u8{},
                };
            }
        }
    }

    return null;
}

/// Get loader for a module (convenience wrapper)
pub fn get_loader(allocator: std.mem.Allocator, module_or_name: []const u8) ?*const Importer {
    if (find_loader(allocator, module_or_name, null)) |result| {
        return result.loader;
    } else |_| {}
    return null;
}

test "get_importer returns null" {
    const result = get_importer(std.testing.allocator, "/some/path");
    try std.testing.expect(result == null);
}

test "get_loader returns null" {
    const result = get_loader(std.testing.allocator, "os");
    try std.testing.expect(result == null);
}

test "find_loader returns null" {
    const result = try find_loader(std.testing.allocator, "os", null);
    try std.testing.expect(result == null);
}
