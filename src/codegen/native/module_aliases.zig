//! Module Alias System
//!
//! Maps Python import names to their actual Zig implementation names.
//! This mirrors CPython's internal module aliasing (e.g., `_io` -> `_pyio`).
//!
//! When a new upstream file is added:
//! 1. The check mirror script ensures the file exists
//! 2. If import name differs from file name, add mapping here
//! 3. Unknown modules cause compile errors (not warnings) to force handling

const std = @import("std");
const stdlib_gen = @import("stdlib_modules_gen.zig");

/// Module aliases: Python import name -> Zig implementation name
/// These mirror CPython's internal mappings where import name differs from implementation
pub const module_aliases = std.StaticStringMap([]const u8).initComptime(.{
    // I/O modules - Python imports `_io` but implementation is `_pyio`
    .{ "_io", "_pyio" },

    // Collections - Python imports `_collections` but we have submodules
    .{ "_collections", "_collections._collections" },

    // String module
    .{ "_string", "_string" },

    // Operator module
    .{ "_operator", "_operator" },

    // Functools
    .{ "_functools", "_functools" },

    // Struct module
    .{ "_struct", "_struct" },

    // Pickle
    .{ "_pickle", "_pickle" },

    // Random
    .{ "_random", "_random" },

    // Bisect
    .{ "_bisect", "_bisect" },

    // Heapq
    .{ "_heapq", "_heapq" },

    // Decimal
    .{ "_decimal", "_pydecimal" },

    // Datetime - maps to pydatetime
    .{ "_datetime", "_pydatetime" },
});

/// Test-only stub modules that don't need implementations
/// These are CPython test infrastructure modules that we stub out
pub const stub_modules = std.StaticStringMap(void).initComptime(.{
    .{ "xxsubtype", {} }, // C extension test type
    .{ "_testcapi", {} }, // C API test module
    .{ "_testbuffer", {} }, // Buffer protocol test module
    .{ "_testinternalcapi", {} }, // Internal C API tests
    .{ "_xxsubinterpreters", {} }, // Subinterpreter tests
    .{ "_xxinterpchannels", {} }, // Interpreter channel tests
    // Test-to-test imports (tests importing other tests)
    .{ "test.test_grammar", {} }, // Grammar tests
    .{ "test.test_support", {} }, // Support utilities (use test.support instead)
});

/// Resolve a Python module name to its Zig implementation name
/// Returns the resolved name or null if not found
pub fn resolveAlias(python_name: []const u8) ?[]const u8 {
    // Check alias map first
    if (module_aliases.get(python_name)) |alias| {
        return alias;
    }
    // Check if exact name exists in stdlib
    if (stdlib_gen.hasModule(python_name)) {
        return python_name;
    }
    // Check if it's a stub module
    if (stub_modules.has(python_name)) {
        return null; // Will be handled as stub
    }
    return null;
}

/// Check if a module is a known stub (test-only module)
pub fn isStubModule(python_name: []const u8) bool {
    return stub_modules.has(python_name);
}

/// Check if a module can be resolved (either via alias, direct, or stub)
pub fn canResolve(python_name: []const u8) bool {
    return resolveAlias(python_name) != null or isStubModule(python_name);
}

/// Get the Zig implementation path for a module
/// Returns the path suitable for runtime.Lib.{path} access
pub fn getImplementationPath(python_name: []const u8) ?[]const u8 {
    if (module_aliases.get(python_name)) |alias| {
        return alias;
    }
    if (stdlib_gen.hasModule(python_name)) {
        return python_name;
    }
    return null;
}
