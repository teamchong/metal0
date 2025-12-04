/// CPython Descriptor Protocol
///
/// Implements descriptors for property-like access.
/// NOTE: Most PyObject_* attr functions are in cpython_misc.zig

const std = @import("std");
const cpython = @import("cpython_object.zig");

// Re-export from cpython_misc for compatibility
// The actual implementations are in cpython_misc.zig

/// Descriptor type object
pub var PyClassMethodDescr_Type: cpython.PyTypeObject = undefined;
pub var PyGetSetDescr_Type: cpython.PyTypeObject = undefined;
pub var PyMemberDescr_Type: cpython.PyTypeObject = undefined;
pub var PyMethodDescr_Type: cpython.PyTypeObject = undefined;
pub var PyWrapperDescr_Type: cpython.PyTypeObject = undefined;

/// Create a new method descriptor
export fn PyDescr_NewMethod(type_obj: *cpython.PyTypeObject, method: *cpython.PyMethodDef) callconv(.c) ?*cpython.PyObject {
    _ = type_obj;
    _ = method;
    // TODO: Create method descriptor object
    return null;
}

/// Create a new classmethod descriptor
export fn PyDescr_NewClassMethod(type_obj: *cpython.PyTypeObject, method: *cpython.PyMethodDef) callconv(.c) ?*cpython.PyObject {
    _ = type_obj;
    _ = method;
    return null;
}

/// Create a new member descriptor
export fn PyDescr_NewMember(type_obj: *cpython.PyTypeObject, member: *cpython.PyMemberDef) callconv(.c) ?*cpython.PyObject {
    _ = type_obj;
    _ = member;
    return null;
}

/// Create a new getset descriptor
export fn PyDescr_NewGetSet(type_obj: *cpython.PyTypeObject, getset: *cpython.PyGetSetDef) callconv(.c) ?*cpython.PyObject {
    _ = type_obj;
    _ = getset;
    return null;
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
