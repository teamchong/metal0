/// CPython C API - Generic exports for ALL C extensions
///
/// This file provides a unified export point for all CPython C API symbols
/// that C extensions might need. This is NOT numpy-specific - it handles
/// ANY C extension that uses the stable Python C API.
///
/// Key categories:
/// 1. Type objects (PyBool_Type, PyLong_Type, PyDict_Type, etc.)
/// 2. Exception types (PyExc_TypeError, PyExc_ValueError, etc.)
/// 3. API functions (PyBool_FromLong, PyDict_New, etc.)
/// 4. Singletons (_Py_TrueStruct, _Py_FalseStruct, _Py_NoneStruct)
///
/// Split into modular files under cpython_api/ for maintainability.

// Re-export all submodules - the exports are defined with `export` in each file
// so they will be linked into the final binary.

pub const type_exports = @import("cpython_api/type_exports.zig");
pub const exception_exports = @import("cpython_api/exception_exports.zig");
pub const singleton_exports = @import("cpython_api/singleton_exports.zig");
pub const core_functions = @import("cpython_api/core_functions.zig");
pub const arg_functions = @import("cpython_api/arg_functions.zig");
pub const buffer_bytes = @import("cpython_api/buffer_bytes.zig");
pub const dict_err_eval = @import("cpython_api/dict_err_eval.zig");
pub const import_interp = @import("cpython_api/import_interp.zig");
pub const object_functions = @import("cpython_api/object_functions.zig");
pub const thread_functions = @import("cpython_api/thread_functions.zig");
pub const type_functions = @import("cpython_api/type_functions.zig");
pub const unicode_functions = @import("cpython_api/unicode_functions.zig");
pub const unicode_errors = @import("cpython_api/unicode_errors.zig");
pub const misc_functions = @import("cpython_api/misc_functions.zig");

// Re-export key types for external use
pub const PyUnicodeErrorObject = dict_err_eval.PyUnicodeErrorObject;
pub const PyMutex = thread_functions.PyMutex;
pub const PyDictProxy_Type = misc_functions.PyDictProxy_Type;
pub const PyWrapperDescr_Type = misc_functions.PyWrapperDescr_Type;
pub const PyExc_RuntimeWarning = misc_functions.PyExc_RuntimeWarning;
pub const PyExc_FutureWarning = misc_functions.PyExc_FutureWarning;
pub const PyExc_ImportWarning = misc_functions.PyExc_ImportWarning;

// Force include all modules to ensure exports are linked
comptime {
    _ = type_exports;
    _ = exception_exports;
    _ = singleton_exports;
    _ = core_functions;
    _ = arg_functions;
    _ = buffer_bytes;
    _ = dict_err_eval;
    _ = import_interp;
    _ = object_functions;
    _ = thread_functions;
    _ = type_functions;
    _ = unicode_functions;
    _ = unicode_errors;
    _ = misc_functions;
}
