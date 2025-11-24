/// Helper utilities for package analysis
const std = @import("std");

/// Extract the directory from a file path
/// Returns "." if path has no directory component
pub fn getFileDirectory(file_path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // Find last slash
    var i = file_path.len;
    while (i > 0) {
        i -= 1;
        if (file_path[i] == '/' or file_path[i] == '\\') {
            // Return everything before the slash
            return try allocator.dupe(u8, file_path[0..i]);
        }
    }

    // No slash found - file is in current directory
    return try allocator.dupe(u8, ".");
}

/// Package information
pub const PackageInfo = struct {
    is_package: bool,
    init_path: []const u8, // Path to __init__.py
    package_dir: []const u8, // Directory containing package
    submodules: [][]const u8, // List of submodule names

    pub fn deinit(self: *PackageInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.init_path);
        allocator.free(self.package_dir);
        for (self.submodules) |submod| {
            allocator.free(submod);
        }
        allocator.free(self.submodules);
    }
};

/// Analyze a resolved import path to determine if it's a package with submodules
pub fn analyzePackage(
    import_path: []const u8,
    allocator: std.mem.Allocator,
) !PackageInfo {
    // Check if path points to __init__.py (package) or regular .py file (module)
    const is_init = std.mem.endsWith(u8, import_path, "__init__.py");

    if (!is_init) {
        // Single module, not a package
        return PackageInfo{
            .is_package = false,
            .init_path = try allocator.dupe(u8, import_path),
            .package_dir = try allocator.dupe(u8, "."),
            .submodules = &[_][]const u8{},
        };
    }

    // It's a package - extract directory path
    const package_dir = blk: {
        const last_slash = std.mem.lastIndexOf(u8, import_path, "/") orelse break :blk ".";
        break :blk import_path[0..last_slash];
    };

    // Scan package directory for submodules
    var submodules = std.ArrayList([]const u8){};
    errdefer {
        for (submodules.items) |item| allocator.free(item);
        submodules.deinit(allocator);
    }

    // Try to open directory
    var dir = std.fs.cwd().openDir(package_dir, .{ .iterate = true }) catch {
        // Can't open directory - treat as simple package
        return PackageInfo{
            .is_package = true,
            .init_path = try allocator.dupe(u8, import_path),
            .package_dir = try allocator.dupe(u8, package_dir),
            .submodules = &[_][]const u8{},
        };
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            // Check for .py files (excluding __init__.py and __pycache__)
            if (std.mem.endsWith(u8, entry.name, ".py") and
                !std.mem.eql(u8, entry.name, "__init__.py") and
                !std.mem.startsWith(u8, entry.name, "__"))
            {
                // Extract module name (remove .py)
                const mod_name = try allocator.dupe(u8, entry.name[0 .. entry.name.len - 3]);
                try submodules.append(allocator, mod_name);
            }
        } else if (entry.kind == .directory) {
            // Check for subpackages (directories with __init__.py)
            if (!std.mem.startsWith(u8, entry.name, "__")) {
                const subpkg_init = try std.fmt.allocPrint(allocator, "{s}/{s}/__init__.py", .{ package_dir, entry.name });
                defer allocator.free(subpkg_init);

                std.fs.cwd().access(subpkg_init, .{}) catch continue;

                // It's a subpackage
                const subpkg_name = try allocator.dupe(u8, entry.name);
                try submodules.append(allocator, subpkg_name);
            }
        }
    }

    return PackageInfo{
        .is_package = true,
        .init_path = try allocator.dupe(u8, import_path),
        .package_dir = try allocator.dupe(u8, package_dir),
        .submodules = try submodules.toOwnedSlice(allocator),
    };
}
