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
const traits = @import("pyobject_traits.zig");

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
    traits.setError("TypeError", "object is not callable");
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

// NOTE: Attribute access functions (PyObject_GetAttr, PyObject_SetAttr, etc.)
// are implemented in cpython_misc.zig with full descriptor protocol support

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
    traits.setError("TypeError", "no repr available");
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
    return traits.incref(@as(*cpython.PyObject, @ptrCast(type_obj)));
}

/// ============================================================================
/// BOOLEAN OPERATIONS
/// ============================================================================

/// Test truth value of object
///
/// CPython: int PyObject_IsTrue(PyObject *obj)
/// Returns: 1 if true, 0 if false, -1 on error
export fn PyObject_IsTrue(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (traits.toBool(obj)) 1 else 0;
}

/// Boolean NOT operation
///
/// CPython: int PyObject_Not(PyObject *obj)
/// Returns: 0 if true, 1 if false, -1 on error
export fn PyObject_Not(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (traits.toBool(obj)) 0 else 1;
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
    const bool_mod = @import("pyobject_bool.zig");

    // Try a's tp_richcompare first
    const type_a = cpython.Py_TYPE(a);
    if (type_a.tp_richcompare) |cmp_func| {
        const result = cmp_func(a, b, op);
        if (result != null) return result;
    }

    // Try b's tp_richcompare with swapped comparison
    const type_b = cpython.Py_TYPE(b);
    if (type_b.tp_richcompare) |cmp_func| {
        // Swap comparison: < becomes >, <= becomes >=, etc.
        const swapped_op: c_int = switch (op) {
            Py_LT => Py_GT,
            Py_LE => Py_GE,
            Py_GT => Py_LT,
            Py_GE => Py_LE,
            else => op, // EQ and NE are symmetric
        };
        const result = cmp_func(b, a, swapped_op);
        if (result != null) return result;
    }

    // Fallback: identity comparison for EQ/NE
    if (op == Py_EQ) {
        return bool_mod.PyBool_FromLong(if (a == b) 1 else 0);
    }
    if (op == Py_NE) {
        return bool_mod.PyBool_FromLong(if (a != b) 1 else 0);
    }

    // No comparison defined
    traits.setError("TypeError", "comparison not supported");
    return null;
}

/// Rich comparison returning boolean
///
/// CPython: int PyObject_RichCompareBool(PyObject *a, PyObject *b, int op)
/// Returns: 1 if true, 0 if false, -1 on error
export fn PyObject_RichCompareBool(a: *cpython.PyObject, b: *cpython.PyObject, op: c_int) callconv(.c) c_int {
    // Fast path for identity
    if (a == b) {
        return switch (op) {
            Py_EQ, Py_LE, Py_GE => 1,
            Py_NE, Py_LT, Py_GT => 0,
            else => -1,
        };
    }

    const result = PyObject_RichCompare(a, b, op) orelse return -1;
    defer traits.decref(result);

    return PyObject_IsTrue(result);
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
    traits.setError("TypeError", "unhashable type");
    return -1;
}

/// ============================================================================
/// LENGTH/SIZE
/// ============================================================================

/// Get length of object (sequence or mapping)
///
/// CPython: Py_ssize_t PyObject_Length(PyObject *obj)
/// Returns: Length or -1 on error
export fn PyObject_Length(obj: *cpython.PyObject) callconv(.c) isize {
    if (traits.getLength(obj)) |len| {
        return len;
    }
    traits.setError("TypeError", "object has no len()");
    return -1;
}

/// Alias for PyObject_Length
export fn PyObject_Size(obj: *cpython.PyObject) callconv(.c) isize {
    return PyObject_Length(obj);
}

/// ============================================================================
/// SUBSCRIPT (ITEM ACCESS)
/// ============================================================================

/// Get item by key (subscript: obj[key])
///
/// CPython: PyObject* PyObject_GetItem(PyObject *obj, PyObject *key)
/// Returns: Item value or null on error
export fn PyObject_GetItem(obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Try mapping protocol first
    if (traits.getItemByKey(obj, key)) |item| {
        return item;
    }

    // Try sequence protocol with integer key
    if (traits.isInt(key)) {
        if (traits.toInt(key)) |idx| {
            if (traits.getItem(obj, @intCast(idx))) |item| {
                return item;
            }
        }
    }

    traits.setError("TypeError", "object is not subscriptable");
    return null;
}

/// Set item by key (subscript: obj[key] = value)
///
/// CPython: int PyObject_SetItem(PyObject *obj, PyObject *key, PyObject *value)
/// Returns: 0 on success, -1 on error
export fn PyObject_SetItem(obj: *cpython.PyObject, key: *cpython.PyObject, value: *cpython.PyObject) callconv(.c) c_int {
    // Try mapping protocol first
    if (traits.setItemByKey(obj, key, value)) {
        return 0;
    }

    // Try sequence protocol with integer key
    if (traits.isInt(key)) {
        if (traits.toInt(key)) |idx| {
            if (traits.setItem(obj, @intCast(idx), value)) {
                return 0;
            }
        }
    }

    traits.setError("TypeError", "object does not support item assignment");
    return -1;
}

/// Delete item by key (del obj[key])
///
/// CPython: int PyObject_DelItem(PyObject *obj, PyObject *key)
/// Returns: 0 on success, -1 on error
export fn PyObject_DelItem(obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    // Try mapping protocol first (pass null for value = deletion)
    if (traits.setItemByKey(obj, key, null)) {
        return 0;
    }

    // Try sequence protocol with integer key
    if (traits.isInt(key)) {
        const type_obj = cpython.Py_TYPE(obj);
        if (type_obj.tp_as_sequence) |seq| {
            if (seq.sq_ass_item) |ass_fn| {
                if (traits.toInt(key)) |idx| {
                    return ass_fn(obj, @intCast(idx), null);
                }
            }
        }
    }

    traits.setError("TypeError", "object does not support item deletion");
    return -1;
}

/// ============================================================================
/// ASCII / BYTES CONVERSION
/// ============================================================================

/// Convert object to ASCII string (escapes non-ASCII)
///
/// CPython: PyObject* PyObject_ASCII(PyObject *obj)
/// Returns: ASCII string representation or null on error
export fn PyObject_ASCII(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Get repr first
    const repr = PyObject_Repr(obj) orelse return null;

    // For now, just return repr (full impl would escape non-ASCII)
    // TODO: Escape non-ASCII characters to \xNN or \uNNNN
    return repr;
}

/// Convert object to bytes
///
/// CPython: PyObject* PyObject_Bytes(PyObject *obj)
/// Returns: Bytes object or null on error
export fn PyObject_Bytes(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // If already bytes, incref and return
    if (traits.isBytes(obj)) {
        return traits.incref(obj);
    }

    // Get string and encode to UTF-8
    const str_obj = PyObject_Str(obj) orelse return null;
    defer traits.decref(str_obj);

    const unicode = @import("cpython_unicode.zig");
    var size: isize = 0;
    const data = unicode.PyUnicode_AsUTF8AndSize(str_obj, &size) orelse return null;

    return traits.createBytes(data[0..@intCast(size)]);
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
        PyObject_Str,
        PyObject_Repr,
        PyObject_Type,
        PyObject_IsTrue,
        PyObject_Not,
        PyObject_RichCompare,
        PyObject_RichCompareBool,
        PyObject_Hash,
        PyObject_Length,
        PyObject_Size,
        PyObject_GetItem,
        PyObject_SetItem,
        PyObject_DelItem,
        PyObject_ASCII,
        PyObject_Bytes,
    };

    // 16 functions total
    inline for (funcs) |func| {
        _ = func;
    }

    try testing.expect(true);
}
