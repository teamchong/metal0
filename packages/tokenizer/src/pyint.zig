/// Python integer type implementation
const std = @import("std");

// Forward declare PyObject to avoid circular dependency
pub const PyObject = @import("runtime.zig").PyObject;

/// Python integer type
pub const PyInt = struct {
    value: i64,

    pub fn create(allocator: std.mem.Allocator, val: i64) !*PyObject {
        const obj = try allocator.create(PyObject);
        const int_data = try allocator.create(PyInt);
        int_data.value = val;

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .int,
            .data = int_data,
        };
        return obj;
    }

    pub fn getValue(obj: *PyObject) i64 {
        std.debug.assert(obj.type_id == .int);
        const data: *PyInt = @ptrCast(@alignCast(obj.data));
        return data.value;
    }

    pub fn toString(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        const runtime = @import("runtime.zig");
        const val = getValue(obj);
        const str = try std.fmt.allocPrint(allocator, "{}", .{val});
        return try runtime.PyString.create(allocator, str);
    }
};
