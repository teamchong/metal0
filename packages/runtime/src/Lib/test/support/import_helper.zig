//! test.support.import_helper - CPython test import utilities
//! These functions help tests import modules in various ways
const std = @import("std");

/// Import a module by name, optionally blocking certain deprecated/fresh imports
/// In AOT compilation, modules are statically linked - this is a no-op stub
pub fn import_module(comptime name: []const u8) ?type {
    _ = name;
    return null; // Stub - actual import done at compile time
}

/// Import a fresh (non-cached) copy of a module
/// In AOT compilation, modules are statically linked - returns null (stub)
pub fn import_fresh_module(comptime name: []const u8) ?type {
    _ = name;
    return null; // Stub - no module caching in AOT
}

/// Import a fresh module with specific blocking of C/Python implementations
/// Allows tests to import pure Python vs C implementations
/// In AOT compilation, this is handled at compile time - returns null
pub fn import_fresh_module_blocking(comptime name: []const u8, comptime fresh: anytype, comptime deprecated: anytype, comptime blocked: anytype) ?type {
    _ = name;
    _ = fresh;
    _ = deprecated;
    _ = blocked;
    return null; // Stub - compile-time module selection in AOT
}

/// Temporary module import that gets cleaned up
/// Returns the module for use within a scope
pub fn CleanImport(comptime name: []const u8) type {
    _ = name;
    return struct {
        pub fn deinit(_: *@This()) void {}
    };
}

/// Context manager for importing modules that may modify sys.modules
pub const ModulesSetup = struct {
    pub fn init() ModulesSetup {
        return .{};
    }
    pub fn deinit(_: *ModulesSetup) void {}
};

/// Check if a module can be imported
pub fn can_import(comptime name: []const u8) bool {
    _ = name;
    return true; // In AOT, all linked modules can be "imported"
}

pub fn __stub__() void {
    // Stub - see module header for why this isn't needed
}
