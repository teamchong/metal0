/// CPython-Compatible Type System
/// This module contains all CPython-compatible types, type objects, type checks,
/// and reference counting functionality.
///
/// Other modules should import this directly or access via runtime.cpython.*
const std = @import("std");
const bigint = @import("bigint");
const BigInt = bigint.BigInt;

// =============================================================================
// CPython-Compatible PyObject Layout
// =============================================================================
// These structures use `extern struct` for C ABI compatibility.
// Field order and sizes MUST match CPython exactly for C extension compatibility.
// Reference: https://github.com/python/cpython/blob/main/Include/object.h
// =============================================================================

/// Py_ssize_t equivalent - signed size type matching C's ssize_t
pub const Py_ssize_t = isize;

/// PyObject - Base object header (CPython compatible)
/// Layout: ob_refcnt (8 bytes) + ob_type (8 bytes) = 16 bytes
pub const PyObject = extern struct {
    ob_refcnt: Py_ssize_t,
    ob_type: *PyTypeObject,

    /// Value type for initializing lists/tuples from literals (backwards compat)
    pub const Value = struct {
        int: i64,
    };
};

/// PyVarObject - Variable-size object header (CPython compatible)
/// Used for list, tuple, string, etc.
pub const PyVarObject = extern struct {
    ob_base: PyObject,
    ob_size: Py_ssize_t,
};

/// Type object flags (subset of CPython's Py_TPFLAGS_*)
pub const Py_TPFLAGS = struct {
    pub const HEAPTYPE: u64 = 1 << 9;
    pub const BASETYPE: u64 = 1 << 10;
    pub const HAVE_GC: u64 = 1 << 14;
    pub const DEFAULT: u64 = 0;
};

/// PyTypeObject - Type descriptor (simplified CPython compatible)
/// Full CPython PyTypeObject has ~50 fields; we implement the critical ones
pub const PyTypeObject = extern struct {
    ob_base: PyVarObject,
    tp_name: [*:0]const u8,
    tp_basicsize: Py_ssize_t,
    tp_itemsize: Py_ssize_t,
    // Destructor
    tp_dealloc: ?*const fn (*PyObject) callconv(.c) void,
    // Offset to vectorcall function pointer (PEP 590)
    tp_vectorcall_offset: Py_ssize_t,
    // Reserved slots (for getattr, setattr, etc.)
    tp_getattr: ?*anyopaque,
    tp_setattr: ?*anyopaque,
    tp_as_async: ?*anyopaque,
    tp_repr: ?*const fn (*PyObject) callconv(.c) *PyObject,
    // Number/sequence/mapping protocols
    tp_as_number: ?*anyopaque,
    tp_as_sequence: ?*anyopaque,
    tp_as_mapping: ?*anyopaque,
    tp_hash: ?*const fn (*PyObject) callconv(.c) Py_ssize_t,
    tp_call: ?*anyopaque,
    tp_str: ?*const fn (*PyObject) callconv(.c) *PyObject,
    tp_getattro: ?*anyopaque,
    tp_setattro: ?*anyopaque,
    tp_as_buffer: ?*anyopaque,
    tp_flags: u64,
    tp_doc: ?[*:0]const u8,
    // Traversal and clear for GC
    tp_traverse: ?*anyopaque,
    tp_clear: ?*anyopaque,
    tp_richcompare: ?*anyopaque,
    tp_weaklistoffset: Py_ssize_t,
    tp_iter: ?*anyopaque,
    tp_iternext: ?*anyopaque,
    tp_methods: ?*anyopaque,
    tp_members: ?*anyopaque,
    tp_getset: ?*anyopaque,
    tp_base: ?*PyTypeObject,
    tp_dict: ?*PyObject,
    tp_descr_get: ?*anyopaque,
    tp_descr_set: ?*anyopaque,
    tp_dictoffset: Py_ssize_t,
    tp_init: ?*anyopaque,
    tp_alloc: ?*anyopaque,
    tp_new: ?*anyopaque,
    tp_free: ?*anyopaque,
    tp_is_gc: ?*anyopaque,
    tp_bases: ?*PyObject,
    tp_mro: ?*PyObject,
    tp_cache: ?*PyObject,
    tp_subclasses: ?*anyopaque,
    tp_weaklist: ?*PyObject,
    tp_del: ?*anyopaque,
    tp_version_tag: u32,
    tp_finalize: ?*anyopaque,
    tp_vectorcall: ?*anyopaque,
};

// =============================================================================
// Concrete Python Type Objects (CPython ABI compatible)
// =============================================================================

/// PyLongObject - Python integer (CPython compatible)
/// CPython uses variable-length digit array; we use fixed i64 for simplicity
/// Note: For full bigint support, may need variable-length digits later
pub const PyLongObject = extern struct {
    ob_base: PyVarObject,
    // In CPython this is a variable-length digit array
    // We simplify to a single i64 for now (covers most use cases)
    ob_digit: i64,
};

/// PyFloatObject - Python float (CPython compatible)
pub const PyFloatObject = extern struct {
    ob_base: PyObject,
    ob_fval: f64,
};

/// PyComplexObject - Python complex number (CPython compatible)
pub const PyComplexObject = extern struct {
    ob_base: PyObject,
    cval_real: f64,
    cval_imag: f64,
};

/// PyBoolObject - Python bool (same layout as PyLongObject in CPython)
pub const PyBoolObject = extern struct {
    ob_base: PyVarObject,
    ob_digit: i64, // 0 for False, 1 for True
};

/// PyBigIntObject - Python int for arbitrary precision (when > i64 range)
/// Used by bytecode VM for eval() with large integers
pub const PyBigIntObject = struct {
    ob_base: PyVarObject,
    value: BigInt, // Heap-allocated arbitrary precision integer
};

/// PyListObject - Python list (CPython compatible)
pub const PyListObject = extern struct {
    ob_base: PyVarObject,
    ob_item: [*]*PyObject, // Array of PyObject pointers
    allocated: Py_ssize_t, // Allocated capacity
};

/// PyTupleObject - Python tuple (CPython compatible)
pub const PyTupleObject = extern struct {
    ob_base: PyVarObject,
    ob_item: [*]*PyObject, // Inline array of PyObject pointers
};

/// PyDictObject - Python dict (simplified, not full CPython layout)
/// CPython's dict is complex with compact dict + indices; we use simpler layout
pub const PyDictObject = extern struct {
    ob_base: PyObject,
    ma_used: Py_ssize_t, // Number of items
    // Internal hash map storage (not CPython compatible, but functional)
    ma_keys: ?*anyopaque, // Pointer to our hashmap
    ma_values: ?*anyopaque, // Reserved for split-table dict
};

/// PyBytesObject - Python bytes (CPython compatible)
pub const PyBytesObject = extern struct {
    ob_base: PyVarObject,
    ob_shash: Py_ssize_t, // Cached hash (-1 if not computed)
    ob_sval: [1]u8, // Variable-length byte array (at least 1 byte)
};

/// PyUnicodeObject - Python string (simplified)
/// Full CPython Unicode is very complex (compact/legacy/etc.)
/// We use a simplified UTF-8 representation
pub const PyUnicodeObject = extern struct {
    ob_base: PyObject,
    length: Py_ssize_t, // Number of code points
    hash: Py_ssize_t, // Cached hash (-1 if not computed)
    // State flags (interned, kind, compact, ascii, ready)
    state: u32,
    _padding: u32, // Alignment padding
    // UTF-8 data pointer (simplified from CPython's complex union)
    data: [*]const u8,
};

/// PyNoneStruct - The None singleton
pub const PyNoneStruct = extern struct {
    ob_base: PyObject,
};

/// PyFileObject - File handle (metal0 specific, not CPython compatible)
pub const PyFileObject = extern struct {
    ob_base: PyObject,
    // File-specific fields (not matching CPython's io module)
    fd: i32,
    mode: u32,
    name: ?[*:0]const u8,
};

/// PySet minimum size (matches CPython)
pub const PySet_MINSIZE: usize = 8;

/// Set entry - key + cached hash
pub const setentry = extern struct {
    key: ?*PyObject,
    hash: Py_ssize_t, // Cached hash of key
};

/// PySetObject - Python set/frozenset (CPython compatible layout)
pub const PySetObject = extern struct {
    ob_base: PyObject, // 16 bytes
    fill: Py_ssize_t, // Number of active + dummy entries
    used: Py_ssize_t, // Number of active entries
    mask: Py_ssize_t, // Table size - 1 (always power of 2 - 1)
    table: ?[*]setentry, // Points to smalltable or malloc'd memory
    hash: Py_ssize_t, // Only used by frozenset, -1 for set
    finger: Py_ssize_t, // Search finger for pop()
    smalltable: [PySet_MINSIZE]setentry, // Inline storage for small sets
    weakreflist: ?*PyObject, // List of weak references
};

/// Deque block size (matches CPython)
pub const DEQUE_BLOCKLEN: usize = 64;

/// DequeBlock - linked list node for deque
pub const DequeBlock = extern struct {
    data: [DEQUE_BLOCKLEN]?*PyObject,
    prev: ?*DequeBlock,
    next: ?*DequeBlock,
};

/// PyDequeObject - Double-ended queue
pub const PyDequeObject = extern struct {
    ob_base: PyObject,
    leftblock: ?*DequeBlock,
    rightblock: ?*DequeBlock,
    leftindex: usize, // Index in leftblock
    rightindex: usize, // Index in rightblock
    len: Py_ssize_t, // Number of items
    maxlen: Py_ssize_t, // Maximum length (-1 for unbounded)
    weakreflist: ?*PyObject,
};

// =============================================================================
// Global Type Objects (singletons)
// =============================================================================

/// Forward declaration for type object initialization
fn nullDealloc(_: *PyObject) callconv(.c) void {}

/// Base type object template
fn makeTypeObject(comptime name: [*:0]const u8, comptime basicsize: Py_ssize_t, comptime itemsize: Py_ssize_t) PyTypeObject {
    return PyTypeObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1, // Immortal
                .ob_type = undefined, // Will be set to &PyType_Type
            },
            .ob_size = 0,
        },
        .tp_name = name,
        .tp_basicsize = basicsize,
        .tp_itemsize = itemsize,
        .tp_dealloc = nullDealloc,
        .tp_vectorcall_offset = 0,
        .tp_getattr = null,
        .tp_setattr = null,
        .tp_as_async = null,
        .tp_repr = null,
        .tp_as_number = null,
        .tp_as_sequence = null,
        .tp_as_mapping = null,
        .tp_hash = null,
        .tp_call = null,
        .tp_str = null,
        .tp_getattro = null,
        .tp_setattro = null,
        .tp_as_buffer = null,
        .tp_flags = Py_TPFLAGS.DEFAULT,
        .tp_doc = null,
        .tp_traverse = null,
        .tp_clear = null,
        .tp_richcompare = null,
        .tp_weaklistoffset = 0,
        .tp_iter = null,
        .tp_iternext = null,
        .tp_methods = null,
        .tp_members = null,
        .tp_getset = null,
        .tp_base = null,
        .tp_dict = null,
        .tp_descr_get = null,
        .tp_descr_set = null,
        .tp_dictoffset = 0,
        .tp_init = null,
        .tp_alloc = null,
        .tp_new = null,
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
}

// Type object singletons
pub var PyLong_Type: PyTypeObject = makeTypeObject("int", @sizeOf(PyLongObject), 0);
pub var PyFloat_Type: PyTypeObject = makeTypeObject("float", @sizeOf(PyFloatObject), 0);
pub var PyComplex_Type: PyTypeObject = makeTypeObject("complex", @sizeOf(PyComplexObject), 0);
pub var PyBool_Type: PyTypeObject = makeTypeObject("bool", @sizeOf(PyBoolObject), 0);
pub var PyList_Type: PyTypeObject = makeTypeObject("list", @sizeOf(PyListObject), @sizeOf(*PyObject));
pub var PyTuple_Type: PyTypeObject = makeTypeObject("tuple", @sizeOf(PyTupleObject), @sizeOf(*PyObject));
pub var PyDict_Type: PyTypeObject = makeTypeObject("dict", @sizeOf(PyDictObject), 0);
pub var PyUnicode_Type: PyTypeObject = makeTypeObject("str", @sizeOf(PyUnicodeObject), 0);
pub var PyBytes_Type: PyTypeObject = makeTypeObject("bytes", @sizeOf(PyBytesObject), 1);
pub var PyNone_Type: PyTypeObject = makeTypeObject("NoneType", @sizeOf(PyNoneStruct), 0);
pub var PyType_Type: PyTypeObject = makeTypeObject("type", @sizeOf(PyTypeObject), 0);
pub var PyFile_Type: PyTypeObject = makeTypeObject("file", @sizeOf(PyFileObject), 0);
pub var PyBigInt_Type: PyTypeObject = makeTypeObject("int", @sizeOf(PyBigIntObject), 0);
pub var PySet_Type: PyTypeObject = makeTypeObject("set", @sizeOf(PySetObject), 0);
pub var PyFrozenSet_Type: PyTypeObject = makeTypeObject("frozenset", @sizeOf(PySetObject), 0);
pub var PyDeque_Type: PyTypeObject = makeTypeObject("collections.deque", @sizeOf(PyDequeObject), 0);

// None singleton
pub var _Py_NoneStruct: PyNoneStruct = .{
    .ob_base = .{
        .ob_refcnt = 1, // Immortal
        .ob_type = &PyNone_Type,
    },
};
pub const Py_None: *PyObject = @ptrCast(&_Py_NoneStruct);

// =============================================================================
// CPython-compatible Reference Counting Macros
// =============================================================================

pub inline fn Py_INCREF(op: *PyObject) void {
    op.ob_refcnt += 1;
}

pub inline fn Py_DECREF(op: *PyObject) void {
    op.ob_refcnt -= 1;
    if (op.ob_refcnt == 0) {
        if (op.ob_type.tp_dealloc) |dealloc| {
            dealloc(op);
        }
    }
}

pub inline fn Py_XINCREF(op: ?*PyObject) void {
    if (op) |o| Py_INCREF(o);
}

pub inline fn Py_XDECREF(op: ?*PyObject) void {
    if (op) |o| Py_DECREF(o);
}

/// Type checking macros
pub inline fn Py_TYPE(op: *PyObject) *PyTypeObject {
    return op.ob_type;
}

pub inline fn Py_IS_TYPE(op: *PyObject, typ: *PyTypeObject) bool {
    return Py_TYPE(op) == typ;
}

pub inline fn PyLong_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyLong_Type);
}

pub inline fn PyFloat_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyFloat_Type);
}

pub inline fn PyComplex_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyComplex_Type);
}

pub inline fn PyBool_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyBool_Type);
}

pub inline fn PyList_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyList_Type);
}

pub inline fn PyTuple_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyTuple_Type);
}

pub inline fn PyDict_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyDict_Type);
}

pub inline fn PyUnicode_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyUnicode_Type);
}

pub inline fn PyBytes_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyBytes_Type);
}

pub inline fn PyBigInt_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyBigInt_Type);
}

pub inline fn PySet_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PySet_Type);
}

pub inline fn PyFrozenSet_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyFrozenSet_Type);
}

pub inline fn PyAnySet_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PySet_Type) or Py_IS_TYPE(op, &PyFrozenSet_Type);
}

pub inline fn PyDeque_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyDeque_Type);
}

/// Get ob_size from PyVarObject
pub inline fn Py_SIZE(op: *PyObject) Py_ssize_t {
    const var_obj: *PyVarObject = @ptrCast(@alignCast(op));
    return var_obj.ob_size;
}

/// Set ob_size on PyVarObject
pub inline fn Py_SET_SIZE(op: *PyObject, size: Py_ssize_t) void {
    const var_obj: *PyVarObject = @ptrCast(@alignCast(op));
    var_obj.ob_size = size;
}
