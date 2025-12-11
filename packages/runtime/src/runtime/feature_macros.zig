/// CPython build configuration feature macros
const std = @import("std");

/// Feature macros struct - CPython build configuration with comptime-known values
/// Supports subscript access: feature_macros["HAVE_FORK"] returns bool
pub const FeatureMacros = struct {
    /// Comptime subscript access - used when key is known at compile time
    pub fn index(_: FeatureMacros, comptime key: []const u8) bool {
        if (comptime std.mem.eql(u8, key, "HAVE_FORK")) return true;
        if (comptime std.mem.eql(u8, key, "MS_WINDOWS")) return false;
        if (comptime std.mem.eql(u8, key, "PY_HAVE_THREAD_NATIVE_ID")) return true;
        if (comptime std.mem.eql(u8, key, "Py_REF_DEBUG")) return false;
        if (comptime std.mem.eql(u8, key, "Py_TRACE_REFS")) return false;
        if (comptime std.mem.eql(u8, key, "USE_STACKCHECK")) return false;
        return false;
    }

    /// Runtime key lookup - returns bool for known keys
    pub fn get(_: FeatureMacros, key: []const u8) bool {
        if (std.mem.eql(u8, key, "HAVE_FORK")) return true;
        if (std.mem.eql(u8, key, "MS_WINDOWS")) return false;
        if (std.mem.eql(u8, key, "PY_HAVE_THREAD_NATIVE_ID")) return true;
        if (std.mem.eql(u8, key, "Py_REF_DEBUG")) return false;
        if (std.mem.eql(u8, key, "Py_TRACE_REFS")) return false;
        if (std.mem.eql(u8, key, "USE_STACKCHECK")) return false;
        return false;
    }

    /// Static key list for iteration
    pub const key_list: [6][]const u8 = .{
        "HAVE_FORK",
        "MS_WINDOWS",
        "PY_HAVE_THREAD_NATIVE_ID",
        "Py_REF_DEBUG",
        "Py_TRACE_REFS",
        "USE_STACKCHECK",
    };

    /// Iterator for keys() - returns comptime slice of keys
    pub fn keys() []const []const u8 {
        return &key_list;
    }
};
