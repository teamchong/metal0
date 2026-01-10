//! importlib._abc - Core abstract base classes for import system
//! Reference: cpython/Lib/importlib/_abc.py
//!
//! This is an internal module that provides the core Loader ABC

const std = @import("std");
const importlib = @import("../importlib.zig");

// Re-export from parent module (DRY)
pub const Loader = importlib.Loader;
pub const ModuleSpec = importlib.ModuleSpec;

test "Loader re-export" {
    const module = Loader.create_module(&ModuleSpec.init(std.testing.allocator, "test", null));
    try std.testing.expect(module == null);
}
