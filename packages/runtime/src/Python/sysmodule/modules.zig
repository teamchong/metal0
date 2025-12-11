/// modules - Module Loading Information and Initialization
/// Tracks loaded modules and initializes the sys module

const std = @import("std");
const paths = @import("paths.zig");
const args = @import("args.zig");

// ============================================================================
// Module Loading Info
// ============================================================================

/// Dictionary of loaded modules (names only for now)
threadlocal var modules_storage: [1024][]const u8 = undefined;
threadlocal var modules_len: usize = 0;

/// Get list of loaded module names
pub fn getModules() []const []const u8 {
    return modules_storage[0..modules_len];
}

/// Register a module as loaded
pub fn registerModule(name: []const u8) !void {
    if (modules_len >= modules_storage.len) {
        return error.ModuleStorageFull;
    }
    modules_storage[modules_len] = name;
    modules_len += 1;
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the sys module
pub fn init() void {
    paths.initPaths();
    args.initArgv();
}

/// Initialize sys module with command line args
pub fn initWithArgs(init_args: []const []const u8) void {
    init();
    args.setArgv(init_args);
}
