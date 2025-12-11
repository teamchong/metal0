/// args - Command Line Arguments Handling
/// Manages sys.argv storage and access

const std = @import("std");

// ============================================================================
// Argument Storage
// ============================================================================

/// Command line arguments storage
threadlocal var argv_storage: [256][]const u8 = undefined;
threadlocal var argv_len: usize = 0;

// ============================================================================
// Argument Operations
// ============================================================================

/// Get sys.argv
pub fn getArgv() []const []const u8 {
    return argv_storage[0..argv_len];
}

/// Set sys.argv
pub fn setArgv(args: []const []const u8) void {
    const copy_len = @min(args.len, argv_storage.len);
    for (args[0..copy_len], 0..) |arg, i| {
        argv_storage[i] = arg;
    }
    argv_len = copy_len;
}

/// Initialize empty argv
pub fn initArgv() void {
    argv_len = 0;
}
