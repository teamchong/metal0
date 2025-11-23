/// Python float type implementation
const std = @import("std");

pub const PyObject = @import("runtime.zig").PyObject;

/// Python float type
pub const PyFloat = struct {
    value: f64,

    pub fn create(allocator: std.mem.Allocator, val: f64) !*PyObject {
        const obj = try allocator.create(PyObject);
        const float_data = try allocator.create(PyFloat);
        float_data.value = val;

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .float,
            .data = float_data,
        };
        return obj;
    }

    pub fn getValue(obj: *PyObject) f64 {
        std.debug.assert(obj.type_id == .float);
        const data: *PyFloat = @ptrCast(@alignCast(obj.data));
        return data.value;
    }

    pub fn toString(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        const runtime = @import("runtime.zig");
        const val = getValue(obj);
        const str = try std.fmt.allocPrint(allocator, "{d}", .{val});
        return try runtime.PyString.create(allocator, str);
    }
};
