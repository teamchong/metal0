/// PyAOT Runtime Format Utilities
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
