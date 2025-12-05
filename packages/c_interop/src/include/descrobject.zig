/// CPython Descriptor Protocol
///
/// Implements descriptors for property-like access.
/// NOTE: Most PyObject_* attr functions are in cpython_misc.zig

const std = @import("std");
const cpython = @import("object.zig");
const traits = @import("../objects/typetraits.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// Descriptor Object Structures
// ============================================================================

/// Method descriptor object
pub const PyMethodDescrObject = extern struct {
    ob_base: cpython.PyObject,
    d_type: *cpython.PyTypeObject,
    d_name: ?*cpython.PyObject,
    d_qualname: ?*cpython.PyObject,
    d_method: *const cpython.PyMethodDef,
};

/// Member descriptor object
pub const PyMemberDescrObject = extern struct {
    ob_base: cpython.PyObject,
    d_type: *cpython.PyTypeObject,
    d_name: ?*cpython.PyObject,
    d_qualname: ?*cpython.PyObject,
    d_member: *const cpython.PyMemberDef,
};

/// GetSet descriptor object
pub const PyGetSetDescrObject = extern struct {
    ob_base: cpython.PyObject,
    d_type: *cpython.PyTypeObject,
    d_name: ?*cpython.PyObject,
    d_qualname: ?*cpython.PyObject,
    d_getset: *const cpython.PyGetSetDef,
};

// ============================================================================
// Descriptor Type Objects
// ============================================================================

fn method_descr_get(descr: *cpython.PyObject, obj: ?*cpython.PyObject, type_obj: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = type_obj;
    const md: *PyMethodDescrObject = @ptrCast(@alignCast(descr));

    if (obj == null) {
        // Unbound access - return the descriptor itself
        return traits.incref(descr);
    }

    // Return bound method
    const pymethod = @import("../objects/methodobject.zig");
    return pymethod.PyCFunction_NewEx(md.d_method, obj, null);
}

/// Descriptor type objects
pub var PyMethodDescr_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "method_descriptor",
    .tp_basicsize = @sizeOf(PyMethodDescrObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_descr_get = method_descr_get,
};

pub var PyClassMethodDescr_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "classmethod_descriptor",
    .tp_basicsize = @sizeOf(PyMethodDescrObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
};

pub var PyMemberDescr_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "member_descriptor",
    .tp_basicsize = @sizeOf(PyMemberDescrObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
};

pub var PyGetSetDescr_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "getset_descriptor",
    .tp_basicsize = @sizeOf(PyGetSetDescrObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
};

pub var PyWrapperDescr_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "wrapper_descriptor",
    .tp_basicsize = @sizeOf(PyMethodDescrObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
};

// ============================================================================
// Descriptor Creation Functions
// ============================================================================

/// Create a new method descriptor
export fn PyDescr_NewMethod(type_obj: *cpython.PyTypeObject, method: *const cpython.PyMethodDef) callconv(.c) ?*cpython.PyObject {
    const pyunicode = @import("../objects/unicodeobject.zig");

    const descr = allocator.create(PyMethodDescrObject) catch return null;
    descr.ob_base.ob_refcnt = 1;
    descr.ob_base.ob_type = &PyMethodDescr_Type;
    descr.d_type = type_obj;
    descr.d_method = method;

    // Create name object
    if (method.ml_name) |name| {
        descr.d_name = pyunicode.PyUnicode_FromString(name);
        descr.d_qualname = descr.d_name;
    } else {
        descr.d_name = null;
        descr.d_qualname = null;
    }

    return @ptrCast(&descr.ob_base);
}

/// Create a new classmethod descriptor
export fn PyDescr_NewClassMethod(type_obj: *cpython.PyTypeObject, method: *const cpython.PyMethodDef) callconv(.c) ?*cpython.PyObject {
    const pyunicode = @import("../objects/unicodeobject.zig");

    const descr = allocator.create(PyMethodDescrObject) catch return null;
    descr.ob_base.ob_refcnt = 1;
    descr.ob_base.ob_type = &PyClassMethodDescr_Type;
    descr.d_type = type_obj;
    descr.d_method = method;

    if (method.ml_name) |name| {
        descr.d_name = pyunicode.PyUnicode_FromString(name);
        descr.d_qualname = descr.d_name;
    } else {
        descr.d_name = null;
        descr.d_qualname = null;
    }

    return @ptrCast(&descr.ob_base);
}

/// Create a new member descriptor
export fn PyDescr_NewMember(type_obj: *cpython.PyTypeObject, member: *const cpython.PyMemberDef) callconv(.c) ?*cpython.PyObject {
    const pyunicode = @import("../objects/unicodeobject.zig");

    const descr = allocator.create(PyMemberDescrObject) catch return null;
    descr.ob_base.ob_refcnt = 1;
    descr.ob_base.ob_type = &PyMemberDescr_Type;
    descr.d_type = type_obj;
    descr.d_member = member;

    if (member.name) |name| {
        descr.d_name = pyunicode.PyUnicode_FromString(name);
        descr.d_qualname = descr.d_name;
    } else {
        descr.d_name = null;
        descr.d_qualname = null;
    }

    return @ptrCast(&descr.ob_base);
}

/// Create a new getset descriptor
export fn PyDescr_NewGetSet(type_obj: *cpython.PyTypeObject, getset: *const cpython.PyGetSetDef) callconv(.c) ?*cpython.PyObject {
    const pyunicode = @import("../objects/unicodeobject.zig");

    const descr = allocator.create(PyGetSetDescrObject) catch return null;
    descr.ob_base.ob_refcnt = 1;
    descr.ob_base.ob_type = &PyGetSetDescr_Type;
    descr.d_type = type_obj;
    descr.d_getset = getset;

    if (getset.name) |name| {
        descr.d_name = pyunicode.PyUnicode_FromString(name);
        descr.d_qualname = descr.d_name;
    } else {
        descr.d_name = null;
        descr.d_qualname = null;
    }

    return @ptrCast(&descr.ob_base);
}

/// Check if object is a descriptor (has __get__)
export fn PyDescr_IsData(descr: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(descr);
    return if (type_obj.tp_descr_set != null) 1 else 0;
}

// Tests
test "descriptor exports" {
    _ = PyDescr_NewMethod;
    _ = PyDescr_IsData;
}
