/// Exception exports - Unified C API for error handling
///
/// This file re-exports all exception-related symbols from our comptime implementations
/// - PyErr_* functions (from pyobject_exceptions.zig)
/// - PyExc_* type objects (from pyobject_exceptions.zig and exception_types.zig)
/// - Py_INCREF/Py_DECREF (from cpython_object.zig)
///
/// Import this file to get all exception functionality!

const pyobject_exceptions = @import("objects/exceptions.zig");
const cpython = @import("include/object.zig");

// Re-export PyErr_* functions
pub const PyErr_SetString = pyobject_exceptions.PyErr_SetString;
pub const PyErr_SetObject = pyobject_exceptions.PyErr_SetObject;
pub const PyErr_Occurred = pyobject_exceptions.PyErr_Occurred;
pub const PyErr_Clear = pyobject_exceptions.PyErr_Clear;
pub const PyErr_Print = pyobject_exceptions.PyErr_Print;
pub const PyErr_Format = pyobject_exceptions.PyErr_Format;
pub const PyErr_ExceptionMatches = pyobject_exceptions.PyErr_ExceptionMatches;
pub const PyErr_GivenExceptionMatches = pyobject_exceptions.PyErr_GivenExceptionMatches;
pub const PyErr_Restore = pyobject_exceptions.PyErr_Restore;
pub const PyErr_Fetch = pyobject_exceptions.PyErr_Fetch;
pub const PyErr_NormalizeException = pyobject_exceptions.PyErr_NormalizeException;

// Re-export exception type objects
pub const PyExc_BaseException = &pyobject_exceptions.PyExc_BaseException;
pub const PyExc_Exception = &pyobject_exceptions.PyExc_Exception;
pub const PyExc_ValueError = &pyobject_exceptions.PyExc_ValueError;
pub const PyExc_TypeError = &pyobject_exceptions.PyExc_TypeError;
pub const PyExc_RuntimeError = &pyobject_exceptions.PyExc_RuntimeError;
pub const PyExc_AttributeError = &pyobject_exceptions.PyExc_AttributeError;
pub const PyExc_KeyError = &pyobject_exceptions.PyExc_KeyError;

// Re-export reference counting
pub const Py_INCREF = cpython.Py_INCREF;
pub const Py_DECREF = cpython.Py_DECREF;

// Re-export PyUnicode_FromString (needed for PyErr_SetString)
pub const PyUnicode_FromString = @import("include/unicodeobject.zig").PyUnicode_FromString;
