/// Python bool type implementation
const std = @import("std");

pub const PyObject = @import("runtime.zig").PyObject;

/// Python bool type
pub const PyBool = struct {
    value: bool,

    pub fn create(allocator: std.mem.Allocator, val: bool) !*PyObject {
        const obj = try allocator.create(PyObject);
        const bool_data = try allocator.create(PyBool);
        bool_data.value = val;

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .bool,
            .data = bool_data,
        };
        return obj;
    }

    pub fn getValue(obj: *PyObject) bool {
        std.debug.assert(obj.type_id == .bool);
        const data: *PyBool = @ptrCast(@alignCast(obj.data));
        return data.value;
    }

    pub fn toString(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        const runtime = @import("runtime.zig");
        const val = getValue(obj);
        const str = if (val) "True" else "False";
        return try runtime.PyString.create(allocator, str);
    }
};
