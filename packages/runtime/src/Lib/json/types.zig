/// JSON types and options

const std = @import("std");
const runtime = @import("../../runtime.zig");

/// Re-export JsonValue from json_impl
pub const JsonValue = @import("../json_impl/value.zig").JsonValue;
pub const Value = JsonValue;

/// DumpOptions - parameters for dumps/dump
pub const DumpOptions = struct {
    indent: ?usize = null, // None = compact, N = pretty print with N spaces
    sort_keys: bool = false,
    separators: ?struct { item: []const u8, key: []const u8 } = null,
    ensure_ascii: bool = true,
    allow_nan: bool = false, // Allow NaN and Infinity (non-standard)
    default: ?*const fn (*runtime.PyObject, std.mem.Allocator) anyerror!*runtime.PyObject = null,
};

/// LoadsOptions - parameters for json.loads()
pub const LoadsOptions = struct {
    object_hook: ?*const fn (*runtime.PyObject, std.mem.Allocator) anyerror!*runtime.PyObject = null,
    parse_float: ?*const fn ([]const u8, std.mem.Allocator) anyerror!*runtime.PyObject = null,
    parse_int: ?*const fn ([]const u8, std.mem.Allocator) anyerror!*runtime.PyObject = null,
    parse_constant: ?*const fn ([]const u8, std.mem.Allocator) anyerror!*runtime.PyObject = null,
    object_pairs_hook: ?*const fn ([]struct { []const u8, *runtime.PyObject }, std.mem.Allocator) anyerror!*runtime.PyObject = null,
    strict: bool = true,
};
