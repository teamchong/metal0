/// Build directory structure for metal0
///
/// .metal0/
/// ├── cache/      # Incremental build cache (.zig, .o, .hash)
/// ├── lib/        # Static archives (.a)
/// ├── bin/        # Final binaries
/// └── runtime/    # Cached runtime files
const std = @import("std");

/// Root build directory
pub const ROOT = ".metal0";

/// Subdirectories
pub const CACHE = ROOT ++ "/cache";
pub const LIB = ROOT ++ "/lib";
pub const BIN = ROOT ++ "/bin";
pub const RUNTIME = ROOT ++ "/runtime";

/// Initialize build directory structure
pub fn init() !void {
    // Create all directories
    inline for ([_][]const u8{ ROOT, CACHE, LIB, BIN, RUNTIME }) |dir| {
        std.fs.cwd().makeDir(dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
}

/// Get path for generated Zig source
pub fn zigPath(allocator: std.mem.Allocator, module_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, CACHE ++ "/{s}.zig", .{module_name});
}

/// Get path for compiled object file
pub fn objectPath(allocator: std.mem.Allocator, module_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, CACHE ++ "/{s}.o", .{module_name});
}

/// Get path for hash file (for incremental build detection)
pub fn hashPath(allocator: std.mem.Allocator, module_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, CACHE ++ "/{s}.o.hash", .{module_name});
}

/// Get path for static archive
pub fn archivePath(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, LIB ++ "/lib{s}.a", .{name});
}

/// Get path for final binary
pub fn binaryPath(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, BIN ++ "/{s}", .{name});
}

/// Get runtime directory (for cached runtime files)
pub fn runtimeDir() []const u8 {
    return RUNTIME;
}

/// Legacy: get build dir for backward compatibility
/// TODO: migrate callers to use specific paths above
pub fn getBuildDir() []const u8 {
    return CACHE;
}
