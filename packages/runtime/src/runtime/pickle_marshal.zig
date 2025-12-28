/// Pickle and Marshal serialization helpers
const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const pickle = @import("../Lib/pickle/pickle.zig");
const runtime = @import("../runtime.zig");

/// Marshal loads - decode simplified marshal format back to value
/// Uses compile-time encoding: "T" = True, "F" = False
pub fn marshalLoads(data: []const u8) bool {
    if (data.len == 0) return false;
    // "T" for True, "F" for False
    return data[0] == 'T';
}

/// Pickle loads - decode pickle format back to value using full pickle implementation
/// Returns a *PyObject matching Python's pickle.loads() semantics
pub fn pickleLoads(data: []const u8) *runtime.PyObject {
    // Use global allocator for pickle deserialization
    const allocator = if (@import("builtin").is_test)
        std.testing.allocator
    else
        allocator_helper.fast_allocator;

    return pickle.loads(data, allocator) catch runtime.Py_None;
}

/// Pickle loads returning PickleValue (for internal/low-level use)
pub fn pickleLoadsInternal(data: []const u8) pickle.PickleValue {
    const allocator = if (@import("builtin").is_test)
        std.testing.allocator
    else
        allocator_helper.fast_allocator;

    return pickle.loadsInternal(data, allocator) catch .{ .none = {} };
}

/// Pickle loads returning bool (legacy compatibility for bool-only pickle)
pub fn pickleLoadsBool(data: []const u8) bool {
    if (data.len < 4) return false;
    // Protocol 0: "I01\n." = True, "I00\n." = False
    if (data[0] == 'I' and data[1] == '0') {
        return data[2] == '1';
    }
    // Protocol 2+: \x88 = True, \x89 = False
    if (data.len >= 4 and data[0] == 0x80 and data[1] == 0x02) {
        return data[2] == 0x88;
    }
    return false;
}
