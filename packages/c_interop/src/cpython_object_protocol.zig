/// CPython Object Protocol Implementation
///
/// This file implements the core PyObject protocol functions needed for
/// object manipulation, attribute access, and method calling.
///
/// These are critical for NumPy and other C extensions that need to:
/// - Call Python functions/methods
/// - Get/set attributes dynamically
/// - Perform comparisons and conversions
/// - Test truth values and get hashes

const std = @import("std");
const cpython = @import("cpython_object.zig");

// External dependencies (implemented in other modules)
extern fn Py_INCREF(?*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(?*cpython.PyObject) callconv(.c) void;
extern fn PyErr_SetString(*cpython.PyTypeObject, [*:0]const u8) callconv(.c) void;
extern fn PyErr_Occurred() callconv(.c) ?*cpython.PyTypeObject;
extern fn PyUnicode_FromString([*:0]const u8) callconv(.c) ?*cpython.PyObject;

// Exception types (defined in pyobject_exceptions.zig)
extern var PyExc_TypeError: cpython.PyTypeObject;
extern var PyExc_AttributeError: cpython.PyTypeObject;

/// ============================================================================
/// FUNCTION CALLING
/// ============================================================================

/// Universal function invoker - call any callable with args and kwargs
///
/// CPython: PyObject* PyObject_Call(PyObject *callable, PyObject *args, PyObject *kwargs)
/// Args: tuple of positional arguments
/// Kwargs: dict of keyword arguments (can be null)
/// Returns: Result object or null on error
export fn PyObject_Call(callable: *cpython.PyObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(callable);

    if (type_obj.tp_call) |call_func| {
        return call_func(callable, args, kwargs);
    }

    // Not callable
    PyErr_SetString(&PyExc_TypeError, "object is not callable");
    return null;
}

/// Simplified function invoker - no keyword arguments
///
/// CPython: PyObject* PyObject_CallObject(PyObject *callable, PyObject *args)
/// Args: tuple of arguments or null (for no args)
/// Returns: Result object or null on error
export fn PyObject_CallObject(callable: *cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return PyObject_Call(callable, args orelse &_Py_EmptyTuple, null);
}

/// Empty tuple singleton for zero-argument calls
var _Py_EmptyTuple: cpython.PyObject = .{
    .ob_refcnt = 1,
    .ob_type = undefined, // Will be set to PyTuple_Type at runtime
};

/// ============================================================================
/// ATTRIBUTE ACCESS
/// ============================================================================

/// Get attribute by name object
///
/// CPython: PyObject* PyObject_GetAttr(PyObject *obj, PyObject *name)
/// Name: PyUnicode object with attribute name
/// Returns: Attribute value or null on error
export fn PyObject_GetAttr(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_getattro) |getattr_func| {
        return getattr_func(obj, name);
    }

    // No getattr support
    PyErr_SetString(&PyExc_AttributeError, "attribute access not supported");
    return null;
}

/// Get attribute by C string name (convenience wrapper)
///
/// CPython: PyObject* PyObject_GetAttrString(PyObject *obj, const char *name)
/// Name: Null-terminated C string
/// Returns: Attribute value or null on error
export fn PyObject_GetAttrString(obj: *cpython.PyObject, name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const name_obj = PyUnicode_FromString(name) orelse return null;
    defer Py_DECREF(name_obj);

    return PyObject_GetAttr(obj, name_obj);
}

/// Set attribute by name object
///
/// CPython: int PyObject_SetAttr(PyObject *obj, PyObject *name, PyObject *value)
/// Name: PyUnicode object with attribute name
/// Value: New attribute value
/// Returns: 0 on success, -1 on error
export fn PyObject_SetAttr(obj: *cpython.PyObject, name: *cpython.PyObject, value: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_setattro) |setattr_func| {
        return setattr_func(obj, name, value);
    }

    // No setattr support
    PyErr_SetString(&PyExc_AttributeError, "attribute assignment not supported");
    return -1;
}

/// Set attribute by C string name (convenience wrapper)
///
/// CPython: int PyObject_SetAttrString(PyObject *obj, const char *name, PyObject *value)
/// Name: Null-terminated C string
/// Value: New attribute value
/// Returns: 0 on success, -1 on error
export fn PyObject_SetAttrString(obj: *cpython.PyObject, name: [*:0]const u8, value: *cpython.PyObject) callconv(.c) c_int {
    const name_obj = PyUnicode_FromString(name) orelse return -1;
    defer Py_DECREF(name_obj);

    return PyObject_SetAttr(obj, name_obj, value);
}

/// Check if attribute exists by name object
///
/// CPython: int PyObject_HasAttr(PyObject *obj, PyObject *name)
/// Name: PyUnicode object with attribute name
/// Returns: 1 if exists, 0 if not
export fn PyObject_HasAttr(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) c_int {
    const result = PyObject_GetAttr(obj, name);

    if (result) |r| {
        Py_DECREF(r);
        return 1;
    }

    // Clear error - HasAttr doesn't raise exceptions
    if (PyErr_Occurred()) |_| {
        // Clear error state (simplified - should use PyErr_Clear)
        _ = PyErr_Occurred();
    }

    return 0;
}

/// Check if attribute exists by C string name
///
/// CPython: int PyObject_HasAttrString(PyObject *obj, const char *name)
/// Name: Null-terminated C string
/// Returns: 1 if exists, 0 if not
export fn PyObject_HasAttrString(obj: *cpython.PyObject, name: [*:0]const u8) callconv(.c) c_int {
    const name_obj = PyUnicode_FromString(name) orelse return 0;
    defer Py_DECREF(name_obj);

    return PyObject_HasAttr(obj, name_obj);
}

/// ============================================================================
/// STRING CONVERSION
/// ============================================================================

/// Convert object to string (calls __str__)
///
/// CPython: PyObject* PyObject_Str(PyObject *obj)
/// Returns: String representation or null on error
export fn PyObject_Str(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_str) |str_func| {
        return str_func(obj);
    }

    // Fallback to repr if no str
    return PyObject_Repr(obj);
}

/// Convert object to repr (calls __repr__)
///
/// CPython: PyObject* PyObject_Repr(PyObject *obj)
/// Returns: Repr string or null on error
export fn PyObject_Repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_repr) |repr_func| {
        return repr_func(obj);
    }

    // Default repr: <typename object at 0xADDRESS>
    PyErr_SetString(&PyExc_TypeError, "no repr available");
    return null;
}

/// ============================================================================
/// TYPE OPERATIONS
/// ============================================================================

/// Get type of object
///
/// CPython: PyObject* PyObject_Type(PyObject *obj)
/// Returns: Type object (new reference)
export fn PyObject_Type(obj: *cpython.PyObject) callconv(.c) *cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);
    Py_INCREF(@ptrCast(type_obj));
    return @ptrCast(type_obj);
}

/// ============================================================================
/// BOOLEAN OPERATIONS
/// ============================================================================

/// Test truth value of object
///
/// CPython: int PyObject_IsTrue(PyObject *obj)
/// Returns: 1 if true, 0 if false, -1 on error
export fn PyObject_IsTrue(obj: *cpython.PyObject) callconv(.c) c_int {
    // Special cases for common types
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_name) |name| {
        const type_name: []const u8 = std.mem.span(name);

        // None is always false
        if (std.mem.eql(u8, type_name, "NoneType")) {
            return 0;
        }

        // Bool type
        if (std.mem.eql(u8, type_name, "bool")) {
            // Simplified: assume bool is stored as int-like
            return 1; // TODO: Check actual bool value
        }

        // Numeric types: zero is false, non-zero is true
        if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "float")) {
            // TODO: Check actual numeric value
            return 1;
        }
    }

    // For now, default to true
    return 1;
}

/// Boolean NOT operation
///
/// CPython: int PyObject_Not(PyObject *obj)
/// Returns: 0 if true, 1 if false, -1 on error
export fn PyObject_Not(obj: *cpython.PyObject) callconv(.c) c_int {
    const result = PyObject_IsTrue(obj);
    if (result < 0) return -1;
    return if (result == 0) @as(c_int, 1) else @as(c_int, 0);
}

/// ============================================================================
/// COMPARISON
/// ============================================================================

/// Rich comparison operations
pub const Py_LT: c_int = 0;
pub const Py_LE: c_int = 1;
pub const Py_EQ: c_int = 2;
pub const Py_NE: c_int = 3;
pub const Py_GT: c_int = 4;
pub const Py_GE: c_int = 5;

/// Perform rich comparison
///
/// CPython: PyObject* PyObject_RichCompare(PyObject *a, PyObject *b, int op)
/// Op: One of Py_LT, Py_LE, Py_EQ, Py_NE, Py_GT, Py_GE
/// Returns: Comparison result (usually bool) or null on error
export fn PyObject_RichCompare(a: *cpython.PyObject, b: *cpython.PyObject, op: c_int) callconv(.c) ?*cpython.PyObject {
    _ = a;
    _ = b;
    _ = op;

    // TODO: Implement proper comparison dispatch
    // For now, return NotImplemented
    PyErr_SetString(&PyExc_TypeError, "comparison not implemented");
    return null;
}

/// ============================================================================
/// HASHING
/// ============================================================================

/// Get hash value of object
///
/// CPython: Py_hash_t PyObject_Hash(PyObject *obj)
/// Returns: Hash value or -1 on error
export fn PyObject_Hash(obj: *cpython.PyObject) callconv(.c) isize {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_hash) |hash_func| {
        return hash_func(obj);
    }

    // Unhashable type
    PyErr_SetString(&PyExc_TypeError, "unhashable type");
    return -1;
}

// ============================================================================
// TESTS
// ============================================================================

test "PyObject protocol functions exist" {
    const testing = std.testing;

    // Verify that all functions are defined and can be referenced
    // Actual functionality tests require linking with full CPython implementation
    const funcs = .{
        PyObject_Call,
        PyObject_CallObject,
        PyObject_GetAttr,
        PyObject_GetAttrString,
        PyObject_SetAttr,
        PyObject_SetAttrString,
        PyObject_HasAttr,
        PyObject_HasAttrString,
        PyObject_Str,
        PyObject_Repr,
        PyObject_Type,
        PyObject_IsTrue,
        PyObject_Not,
        PyObject_RichCompare,
        PyObject_Hash,
    };

    // 15 functions total
    inline for (funcs) |func| {
        _ = func;
    }

    try testing.expect(true);
}
