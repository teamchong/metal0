/// _ctypes/cfield - Structure field descriptors
///
/// Implements CPython's Modules/_ctypes/cfield.c
/// Provides CField descriptor for accessing structure fields
///
/// Reference: cpython/Modules/_ctypes/cfield.c
const std = @import("std");
const cpython = @import("../../include/object.zig");
const ctypes = @import("ctypes.zig");

const allocator = ctypes.allocator;

// ============================================================================
// CFIELD METHODS
// ============================================================================

/// CField_new - Create new CField object
fn CField_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    _ = type_obj;

    const mem = allocator.alignedAlloc(u8, @alignOf(ctypes.CFieldObject), @sizeOf(ctypes.CFieldObject)) catch return null;
    const field: *ctypes.CFieldObject = @ptrCast(@alignCast(mem.ptr));

    field.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyCField_Type },
        .offset = 0,
        .size = 0,
        .index = 0,
        .proto = null,
        .getfunc = null,
        .setfunc = null,
        .anonymous = 0,
    };

    return @ptrCast(field);
}

/// CField_dealloc - Destructor
fn CField_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const field: *ctypes.CFieldObject = @ptrCast(@alignCast(self.?));

    if (field.proto) |p| {
        p.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(field);
    allocator.free(ptr[0..@sizeOf(ctypes.CFieldObject)]);
}

/// CField_repr - String representation
fn CField_repr(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const field: *ctypes.CFieldObject = @ptrCast(@alignCast(self.?));
    _ = field;
    return null;
}

/// CField_get - Descriptor __get__
fn CField_get(self: ?*cpython.PyObject, obj: ?*cpython.PyObject, type_obj: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = type_obj;

    if (obj == null) {
        self.?.ob_refcnt += 1;
        return self;
    }

    const field: *ctypes.CFieldObject = @ptrCast(@alignCast(self.?));
    const cdata: *ctypes.CDataObject = @ptrCast(@alignCast(obj.?));

    if (cdata.b_ptr == null) return null;
    const ptr = cdata.b_ptr.? + @as(usize, @intCast(field.offset));

    if (field.getfunc) |getfunc| {
        return getfunc(ptr, field.size);
    }

    return null;
}

/// CField_set - Descriptor __set__
fn CField_set(self: ?*cpython.PyObject, obj: ?*cpython.PyObject, value: ?*cpython.PyObject) callconv(.c) c_int {
    if (self == null or obj == null) return -1;

    const field: *ctypes.CFieldObject = @ptrCast(@alignCast(self.?));
    const cdata: *ctypes.CDataObject = @ptrCast(@alignCast(obj.?));

    if (cdata.b_ptr == null) return -1;
    const ptr = cdata.b_ptr.? + @as(usize, @intCast(field.offset));

    if (field.setfunc) |setfunc| {
        const result = setfunc(ptr, value, field.size);
        if (result == null) return -1;
        result.?.ob_refcnt -= 1;
        return 0;
    }

    return -1;
}

/// CField_get_offset - Get offset property
fn CField_get_offset(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

/// CField_get_size - Get size property
fn CField_get_size(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

// ============================================================================
// METHOD TABLES
// ============================================================================

pub export var cfield_methods: [1]cpython.PyMethodDef = .{
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var cfield_getset: [3]cpython.PyGetSetDef = .{
    .{ .name = "offset", .get = @ptrCast(&CField_get_offset), .set = null, .doc = "offset in bytes of this field", .closure = null },
    .{ .name = "size", .get = @ptrCast(&CField_get_size), .set = null, .doc = "size in bytes of this field", .closure = null },
    .{ .name = null, .get = null, .set = null, .doc = null, .closure = null },
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub export var PyCField_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_ctypes.CField",
    .tp_basicsize = @sizeOf(ctypes.CFieldObject),
    .tp_itemsize = 0,
    .tp_dealloc = CField_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = CField_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "Structure/Union field descriptor",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &cfield_methods,
    .tp_members = null,
    .tp_getset = &cfield_getset,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = CField_get,
    .tp_descr_set = CField_set,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = CField_new,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
};
