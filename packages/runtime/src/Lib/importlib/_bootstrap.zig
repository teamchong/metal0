//! importlib._bootstrap - Core import machinery (frozen module)
//! Reference: cpython/Lib/importlib/_bootstrap.py
//!
//! This module is normally frozen into the Python interpreter.
//! In AOT compilation, imports are resolved at compile time.

const std = @import("std");
const importlib = @import("../importlib.zig");

// Re-export core types from parent module (DRY)
pub const ModuleSpec = importlib.ModuleSpec;
pub const Loader = importlib.Loader;

/// Module lock for import synchronization
pub const ModuleLock = struct {
    name: []const u8,
    count: usize = 0,

    pub fn init(name: []const u8) ModuleLock {
        return .{ .name = name };
    }

    pub fn acquire(self: *ModuleLock) void {
        self.count += 1;
    }

    pub fn release(self: *ModuleLock) void {
        if (self.count > 0) self.count -= 1;
    }
};

/// Module type enumeration
pub const ModuleType = enum {
    builtin,
    frozen,
    source,
    bytecode,
    extension,
    namespace,
};

/// Get the builtins dict (stub)
pub fn getBuiltins() ?*anyopaque {
    return null;
}

/// Get the globals dict (stub)
pub fn getGlobals() ?*anyopaque {
    return null;
}

test "ModuleLock" {
    var lock = ModuleLock.init("test_module");
    lock.acquire();
    try std.testing.expectEqual(@as(usize, 1), lock.count);
    lock.release();
    try std.testing.expectEqual(@as(usize, 0), lock.count);
}
