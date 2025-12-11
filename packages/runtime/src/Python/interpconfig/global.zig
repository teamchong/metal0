/// global - Global Interpreter Manager
/// Mirrors cpython/Python/interpconfig.c (global section)
///
/// Provides singleton access to the global interpreter manager:
/// - Lazy initialization on first access
/// - Process-wide interpreter registry
/// - Cleanup on shutdown

const std = @import("std");
const Allocator = std.mem.Allocator;
const manager_mod = @import("manager.zig");

var g_manager: ?manager_mod.InterpreterManager = null;

/// Get or create global interpreter manager
pub fn getManager(allocator: Allocator) *manager_mod.InterpreterManager {
    if (g_manager == null) {
        g_manager = manager_mod.InterpreterManager.init(allocator);
    }
    return &g_manager.?;
}

/// Deinitialize global manager
pub fn deinitManager() void {
    if (g_manager) |*manager| {
        manager.deinit();
        g_manager = null;
    }
}
