/// Object and dict formatting utilities
const std = @import("std");
const runtime = @import("../../runtime.zig");
const float_format = @import("float_format.zig");

pub const PyObject = runtime.PyObject;
const pystring = @import("../../Objects/unicodeobject.zig");
const pyint = @import("../../Objects/intobject.zig");
const pyfloat = @import("../../Objects/floatobject.zig");
const pybool = @import("../../Objects/boolobject.zig");
const dict_module = @import("../../Objects/dictobject.zig");

pub const PyString = pystring.PyString;
pub const PyInt = pyint.PyInt;
pub const PyFloat = pyfloat.PyFloat;
pub const PyBool = pybool.PyBool;
pub const PyDict = dict_module.PyDict;

/// Format any value for Python-style printing
pub inline fn formatAny(value: anytype) (if (@TypeOf(value) == bool) []const u8 else @TypeOf(value)) {
    if (@TypeOf(value) == bool) {
        return if (value) "True" else "False";
    } else {
        return value;
    }
}

/// Format any value to string for printing
pub inline fn formatUnknown(value: anytype) @TypeOf(value) {
    return value;
}

/// Format PyObject as string for printing
pub fn formatPyObject(obj: *PyObject, allocator: std.mem.Allocator) ![]const u8 {
    return switch (obj.type_id) {
        .string => blk: {
            const str_data: *PyString = @ptrCast(@alignCast(obj.data));
            break :blk try allocator.dupe(u8, str_data.data);
        },
        .int => blk: {
            const int_data: *PyInt = @ptrCast(@alignCast(obj.data));
            break :blk try std.fmt.allocPrint(allocator, "{d}", .{int_data.value});
        },
        .float => blk: {
            const float_data: *PyFloat = @ptrCast(@alignCast(obj.data));
            break :blk try float_format.formatFloat(float_data.value, allocator);
        },
        .bool => blk: {
            const bool_data: *PyBool = @ptrCast(@alignCast(obj.data));
            break :blk if (bool_data.value) "True" else "False";
        },
        .none => "None",
        .dict => blk: {
            const dict_data: *PyDict = @ptrCast(@alignCast(obj.data));
            break :blk try PyDict_AsString(dict_data, allocator);
        },
        else => try std.fmt.allocPrint(allocator, "<{s} object>", .{@tagName(obj.type_id)}),
    };
}

/// Format a dict as Python-style string
pub fn PyDict_AsString(dict: anytype, allocator: std.mem.Allocator) ![]const u8 {
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    try result.append(allocator, '{');

    const T = @TypeOf(dict);
    const type_info = @typeInfo(T);

    if (type_info == .pointer) {
        const ChildType = type_info.pointer.child;
        if (@hasDecl(ChildType, "iterator")) {
            var iter = dict.iterator();
            var first = true;
            while (iter.next()) |entry| {
                if (!first) {
                    try result.appendSlice(allocator, ", ");
                }
                first = false;

                try result.append(allocator, '\'');
                try result.appendSlice(allocator, entry.key_ptr.*);
                try result.appendSlice(allocator, "': ");

                const val = entry.value_ptr.*;
                const ValType = @TypeOf(val);
                const val_info = @typeInfo(ValType);

                if (ValType == []const u8 or ValType == []u8) {
                    try result.append(allocator, '\'');
                    try result.appendSlice(allocator, val);
                    try result.append(allocator, '\'');
                } else if (val_info == .int or val_info == .comptime_int) {
                    try result.writer(allocator).print("{d}", .{val});
                } else if (val_info == .float or val_info == .comptime_float) {
                    const float_str = try float_format.formatFloat(val, allocator);
                    defer allocator.free(float_str);
                    try result.appendSlice(allocator, float_str);
                } else if (val_info == .bool) {
                    try result.appendSlice(allocator, if (val) "True" else "False");
                } else {
                    try result.writer(allocator).print("{any}", .{val});
                }
            }
        }
    }

    try result.append(allocator, '}');
    return result.toOwnedSlice(allocator);
}

/// Print a value to stdout
pub fn printValue(value: anytype) void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    switch (type_info) {
        .int, .comptime_int => std.debug.print("{d}", .{value}),
        .float, .comptime_float => {
            if (std.math.isNan(value)) {
                std.debug.print("nan", .{});
            } else if (std.math.isInf(value)) {
                std.debug.print("{s}", .{if (value < 0) "-inf" else "inf"});
            } else if (@mod(value, 1.0) == 0.0 and @abs(value) < 1e15) {
                std.debug.print("{d:.1}", .{value});
            } else {
                std.debug.print("{d}", .{value});
            }
        },
        .bool => std.debug.print("{s}", .{if (value) "True" else "False"}),
        .pointer => |ptr| {
            if (ptr.size == .slice) {
                std.debug.print("{s}", .{value});
            } else if (ptr.size == .one) {
                const child_info = @typeInfo(ptr.child);
                if (child_info == .array) {
                    std.debug.print("{s}", .{value});
                } else {
                    std.debug.print("{any}", .{value});
                }
            } else {
                std.debug.print("{any}", .{value});
            }
        },
        .@"struct" => {
            if (@hasDecl(T, "format")) {
                std.debug.print("{}", .{value});
            } else {
                std.debug.print("{any}", .{value});
            }
        },
        .void => std.debug.print("None", .{}),
        else => std.debug.print("{any}", .{value}),
    }
}
