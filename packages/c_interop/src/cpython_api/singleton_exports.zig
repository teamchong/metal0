/// Singleton Exports
/// C extensions access singletons as `extern PyObject *Py_None` etc.
/// We export both the internal struct (for direct access) and getter functions.

const cpython = @import("../include/object.zig");
const pybool = @import("../objects/boolobject.zig");
const pynone = @import("../objects/noneobject.zig");
const pyslice = @import("../objects/sliceobject.zig");

// Getter functions (for dlsym lookup)
pub export fn _get_Py_True() callconv(.c) *cpython.PyObject {
    return @ptrCast(&pybool._Py_TrueStruct);
}

pub export fn _get_Py_False() callconv(.c) *cpython.PyObject {
    return @ptrCast(&pybool._Py_FalseStruct);
}

pub export fn _get_Py_None() callconv(.c) *cpython.PyObject {
    return pynone.Py_None();
}

// Direct symbol exports as pointers - for C code that uses `extern PyObject *Py_None`
// These are exported as global const pointers which match C's `extern PyObject *`
export const Py_None: *cpython.PyObject = &pynone._Py_NoneStruct;
export const Py_True: *cpython.PyObject = @ptrCast(&pybool._Py_TrueStruct);
export const Py_False: *cpython.PyObject = @ptrCast(&pybool._Py_FalseStruct);

// Also export the NotImplemented and Ellipsis singletons
export const Py_Ellipsis: *cpython.PyObject = &pyslice._Py_EllipsisObject;
