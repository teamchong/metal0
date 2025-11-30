/// metal0 Runtime Format Utilities
/// Formatting functions for Python-style printing
const std = @import("std");
const pystring = @import("pystring.zig");
const pyint = @import("pyint.zig");
const pyfloat = @import("pyfloat.zig");
const pybool = @import("pybool.zig");
const dict_module = @import("dict.zig");

pub const PyString = pystring.PyString;
pub const PyInt = pyint.PyInt;
pub const PyFloat = pyfloat.PyFloat;
pub const PyBool = pybool.PyBool;
pub const PyDict = dict_module.PyDict;

// Forward declare PyObject from runtime
const runtime = @import("runtime.zig");
pub const PyObject = runtime.PyObject;

/// Format any value for Python-style printing (booleans as True/False)
/// This function is a no-op at runtime - it's just for compile-time type checking
/// For bool: returns "True" or "False"
/// For other types: identity function (returns the value unchanged)
pub inline fn formatAny(value: anytype) (if (@TypeOf(value) == bool) []const u8 else @TypeOf(value)) {
    if (@TypeOf(value) == bool) {
        return if (value) "True" else "False";
    } else {
        return value;
    }
}

/// Format any value to string for printing (used for module constants with unknown types)
/// Handles: strings (as-is), bools ("True"/"False"), ints (converted to string), other types (unchanged)
/// Note: This is a COMPILE-TIME function that generates different code based on the input type
pub inline fn formatUnknown(value: anytype) @TypeOf(value) {
    // For unknown module constants, just return as-is
    // Zig's compiler will figure out the actual type
    // String literals will be coerced to []const u8 when printed with {s}
    // Ints/bools will use their natural formatting with {any}
    return value;
}

/// Format float value for printing (Python-style: always show .0 for whole numbers)
/// Examples: 25.0 -> "25.0", 3.14159 -> "3.14159"
pub fn formatFloat(value: f64, allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayList(u8){};
    if (@mod(value, 1.0) == 0.0) {
        // Whole number: force .0 to match Python behavior
        try buf.writer(allocator).print("{d:.1}", .{value});
    } else {
        // Has decimals: show all significant digits
        try buf.writer(allocator).print("{d}", .{value});
    }
    return try buf.toOwnedSlice(allocator);
}

/// Format PyObject as string for printing
/// Used when printing dict values with unknown/mixed types
/// Returns a formatted string that can be printed with {s}
pub fn formatPyObject(obj: *PyObject, allocator: std.mem.Allocator) ![]const u8 {
    return switch (obj.type_id) {
        .string => blk: {
            const str_data: *PyString = @ptrCast(@alignCast(obj.data));
            break :blk try allocator.dupe(u8, str_data.data);
        },
        .int => blk: {
            const int_data: *PyInt = @ptrCast(@alignCast(obj.data));
            var buf = std.ArrayList(u8){};
            try buf.writer(allocator).print("{d}", .{int_data.value});
            break :blk try buf.toOwnedSlice(allocator);
        },
        .float => blk: {
            const float_data: *PyFloat = @ptrCast(@alignCast(obj.data));
            break :blk try formatFloat(float_data.value, allocator);
        },
        .bool => blk: {
            const bool_data: *PyBool = @ptrCast(@alignCast(obj.data));
            const str = if (bool_data.value) "True" else "False";
            break :blk try allocator.dupe(u8, str);
        },
        .dict => blk: {
            const dict_data: *PyDict = @ptrCast(@alignCast(obj.data));
            var buf = std.ArrayList(u8){};
            try buf.appendSlice(allocator, "{");

            var it = dict_data.map.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) {
                    try buf.appendSlice(allocator, ", ");
                }
                // Format as Python dict: {'key': value}
                try buf.writer(allocator).print("'{s}': ", .{entry.key_ptr.*});

                // Format value based on type
                const val_obj = entry.value_ptr.*;
                switch (val_obj.type_id) {
                    .string => {
                        const val_str: *PyString = @ptrCast(@alignCast(val_obj.data));
                        try buf.writer(allocator).print("'{s}'", .{val_str.data});
                    },
                    .int => {
                        const val_int: *PyInt = @ptrCast(@alignCast(val_obj.data));
                        try buf.writer(allocator).print("{d}", .{val_int.value});
                    },
                    else => {
                        try buf.appendSlice(allocator, "<object>");
                    },
                }
                first = false;
            }

            try buf.appendSlice(allocator, "}");
            break :blk try buf.toOwnedSlice(allocator);
        },
        else => try allocator.dupe(u8, "<object>"),
    };
}

/// Format dict as Python dict string: {key: value, ...}
/// Supports both StringHashMap and ArrayList(KV) for dict comprehensions
/// ArrayList preserves insertion order (Python 3.7+ behavior)
pub fn PyDict_AsString(dict: anytype, allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayList(u8){};
    try buf.appendSlice(allocator, "{");

    const T = @TypeOf(dict);
    const type_info = @typeInfo(T);

    // Check if it's an ArrayList by checking for 'items' field
    const is_arraylist = comptime blk: {
        if (type_info == .@"struct") {
            if (@hasDecl(T, "Slice")) {
                // It's likely an ArrayList
                break :blk true;
            }
        }
        break :blk false;
    };

    if (is_arraylist) {
        // ArrayList(KV) - iterate in order
        for (dict.items, 0..) |item, i| {
            if (i > 0) {
                try buf.appendSlice(allocator, ", ");
            }
            try buf.writer(allocator).print("{s}: {d}", .{ item.key, item.value });
        }
    } else {
        // StringHashMap - iterate in hash order
        var it = dict.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) {
                try buf.appendSlice(allocator, ", ");
            }

            // Format key and value
            try buf.writer(allocator).print("{s}: {d}", .{
                entry.key_ptr.*,
                entry.value_ptr.*,
            });

            first = false;
        }
    }

    try buf.appendSlice(allocator, "}");
    return try buf.toOwnedSlice(allocator);
}

/// Generic value printer using comptime type detection
/// Prints any value with Python-style formatting
pub fn printValue(value: anytype) void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    switch (type_info) {
        .int, .comptime_int => std.debug.print("{d}", .{value}),
        .float, .comptime_float => std.debug.print("{d}", .{value}),
        .bool => std.debug.print("{s}", .{if (value) "True" else "False"}),
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice) {
                // Check if it's a string ([]const u8 or []u8)
                if (ptr_info.child == u8) {
                    std.debug.print("'{s}'", .{value});
                } else {
                    // Generic slice/array
                    std.debug.print("[", .{});
                    for (value, 0..) |item, i| {
                        if (i > 0) std.debug.print(", ", .{});
                        printValue(item);
                    }
                    std.debug.print("]", .{});
                }
            } else {
                std.debug.print("{any}", .{value});
            }
        },
        .array => {
            std.debug.print("[", .{});
            for (value, 0..) |item, i| {
                if (i > 0) std.debug.print(", ", .{});
                printValue(item);
            }
            std.debug.print("]", .{});
        },
        .void => std.debug.print("None", .{}),
        else => std.debug.print("{any}", .{value}),
    }
}

/// Python format(value, format_spec) builtin
/// Applies format_spec to value and returns formatted string
/// For now, this is a basic implementation that ignores most format specs
/// and just returns a string representation of the value
pub fn pyFormat(allocator: std.mem.Allocator, value: anytype, format_spec: anytype) ![]const u8 {
    // Ensure format_spec is used to avoid unused variable warnings
    _ = format_spec;

    // Basic formatting - convert value to string
    const T = @TypeOf(value);
    if (T == []const u8 or T == [:0]const u8) {
        return allocator.dupe(u8, value);
    } else if (T == f64 or T == f32) {
        return formatFloat(value, allocator);
    } else if (T == bool) {
        return if (value) "True" else "False";
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        var buf = std.ArrayList(u8){};
        try buf.writer(allocator).print("{d}", .{value});
        return buf.toOwnedSlice(allocator);
    } else {
        // Default: use {any} format
        var buf = std.ArrayList(u8){};
        try buf.writer(allocator).print("{any}", .{value});
        return buf.toOwnedSlice(allocator);
    }
}

/// Python % operator - runtime dispatch for string formatting vs numeric modulo
/// When left operand type is unknown at compile time, this function decides at runtime
pub fn pyMod(allocator: std.mem.Allocator, left: anytype, right: anytype) ![]const u8 {
    const L = @TypeOf(left);

    // Check if left is a string type
    if (L == []const u8 or L == [:0]const u8) {
        // String formatting: "format" % value
        return pyStringFormat(allocator, left, right);
    } else if (@typeInfo(L) == .pointer and @typeInfo(std.meta.Child(L)) == .array) {
        // String literal type [N:0]u8
        return pyStringFormat(allocator, left, right);
    } else if (@typeInfo(L) == .int or @typeInfo(L) == .comptime_int) {
        // Numeric modulo - return result as string for consistency
        const result = @rem(left, right);
        var buf = std.ArrayList(u8){};
        try buf.writer(allocator).print("{d}", .{result});
        return buf.toOwnedSlice(allocator);
    } else if (@typeInfo(L) == .float or @typeInfo(L) == .comptime_float) {
        // Float modulo
        const result = @rem(left, right);
        return formatFloat(result, allocator);
    } else {
        // Unknown type - try string formatting as fallback
        return pyStringFormat(allocator, left, right);
    }
}

/// Python string formatting helper - "format" % value
fn pyStringFormat(allocator: std.mem.Allocator, format: anytype, value: anytype) ![]const u8 {
    const F = @TypeOf(format);
    const V = @TypeOf(value);

    // Get format string as slice
    const format_str: []const u8 = if (F == []const u8 or F == [:0]const u8) format else @as([]const u8, format);

    // Simple implementation - just substitute %s, %d, %f patterns
    var result = std.ArrayList(u8){};
    var i: usize = 0;
    while (i < format_str.len) {
        if (format_str[i] == '%' and i + 1 < format_str.len) {
            const spec = format_str[i + 1];
            if (spec == 's') {
                // String format
                if (V == []const u8 or V == [:0]const u8) {
                    try result.appendSlice(allocator, value);
                } else {
                    try result.writer(allocator).print("{any}", .{value});
                }
                i += 2;
            } else if (spec == 'd' or spec == 'i') {
                // Integer format
                if (@typeInfo(V) == .int or @typeInfo(V) == .comptime_int) {
                    try result.writer(allocator).print("{d}", .{value});
                } else if (@typeInfo(V) == .float or @typeInfo(V) == .comptime_float) {
                    try result.writer(allocator).print("{d}", .{@as(i64, @intFromFloat(value))});
                } else {
                    try result.writer(allocator).print("{any}", .{value});
                }
                i += 2;
            } else if (spec == 'f' or spec == 'e' or spec == 'g') {
                // Float format
                if (@typeInfo(V) == .float or @typeInfo(V) == .comptime_float) {
                    const val_str = try formatFloat(value, allocator);
                    defer allocator.free(val_str);
                    try result.appendSlice(allocator, val_str);
                } else if (@typeInfo(V) == .int or @typeInfo(V) == .comptime_int) {
                    try result.writer(allocator).print("{d}.0", .{value});
                } else {
                    try result.writer(allocator).print("{any}", .{value});
                }
                i += 2;
            } else if (spec == '%') {
                // Escaped %
                try result.append(allocator, '%');
                i += 2;
            } else {
                // Unknown spec - just copy
                try result.append(allocator, format_str[i]);
                i += 1;
            }
        } else {
            try result.append(allocator, format_str[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}
