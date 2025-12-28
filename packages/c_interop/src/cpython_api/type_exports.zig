/// Type Object Exports
/// C extensions access type objects via global symbol lookup.
/// We export functions that return pointers to our type objects.

const cpython = @import("../include/object.zig");

// Import all modules that have type exports
const pylong = @import("../objects/longobject.zig");
const pyfloat = @import("../objects/floatobject.zig");
const pybool = @import("../objects/boolobject.zig");
const pybytes = @import("../objects/bytesobject.zig");
const pyunicode = @import("../objects/unicodeobject.zig");
const pylist = @import("../objects/listobject.zig");
const pytuple = @import("../objects/tupleobject.zig");
const pydict = @import("../objects/dictobject.zig");
const pyset = @import("../objects/setobject.zig");
const pycomplex = @import("../objects/complexobject.zig");
const pyslice = @import("../objects/sliceobject.zig");
const pymethod = @import("../objects/methodobject.zig");
const type_ = @import("../include/typeslots.zig");
const buffer = @import("../include/buffer.zig");

// Basic type exports
pub export fn _get_PyLong_Type() callconv(.c) *cpython.PyTypeObject {
    return &pylong.PyLong_Type;
}

pub export fn _get_PyFloat_Type() callconv(.c) *cpython.PyTypeObject {
    return &pyfloat.PyFloat_Type;
}

pub export fn _get_PyBool_Type() callconv(.c) *cpython.PyTypeObject {
    return &pybool.PyBool_Type;
}

pub export fn _get_PyBytes_Type() callconv(.c) *cpython.PyTypeObject {
    return &pybytes.PyBytes_Type;
}

pub export fn _get_PyUnicode_Type() callconv(.c) *cpython.PyTypeObject {
    return &pyunicode.PyUnicode_Type;
}

pub export fn _get_PyList_Type() callconv(.c) *cpython.PyTypeObject {
    return &pylist.PyList_Type;
}

pub export fn _get_PyTuple_Type() callconv(.c) *cpython.PyTypeObject {
    return &pytuple.PyTuple_Type;
}

pub export fn _get_PyDict_Type() callconv(.c) *cpython.PyTypeObject {
    return &pydict.PyDict_Type;
}

pub export fn _get_PySet_Type() callconv(.c) *cpython.PyTypeObject {
    return &pyset.PySet_Type;
}

pub export fn _get_PyFrozenSet_Type() callconv(.c) *cpython.PyTypeObject {
    return &pyset.PyFrozenSet_Type;
}

pub export fn _get_PySlice_Type() callconv(.c) *cpython.PyTypeObject {
    return &pyslice.PySlice_Type;
}

pub export fn _get_PyType_Type() callconv(.c) *cpython.PyTypeObject {
    return &type_.PyType_Type;
}

pub export fn _get_PyBaseObject_Type() callconv(.c) *cpython.PyTypeObject {
    return &type_.PyBaseObject_Type;
}

// CFunction and Method types
pub export fn _get_PyCFunction_Type() callconv(.c) *cpython.PyTypeObject {
    return &pymethod.PyCFunction_Type;
}

pub export fn _get_PyMethodDescr_Type() callconv(.c) *cpython.PyTypeObject {
    return &pymethod.PyMethodDescr_Type;
}

pub export fn _get_PyMemberDescr_Type() callconv(.c) *cpython.PyTypeObject {
    return &pymethod.PyMemberDescr_Type;
}

pub export fn _get_PyGetSetDescr_Type() callconv(.c) *cpython.PyTypeObject {
    return &pymethod.PyGetSetDescr_Type;
}

// Complex type
pub export fn _get_PyComplex_Type() callconv(.c) *cpython.PyTypeObject {
    return &pycomplex.PyComplex_Type;
}

// MemoryView type export
pub export fn _get_PyMemoryView_Type() callconv(.c) *cpython.PyTypeObject {
    return &buffer.PyMemoryView_Type;
}
