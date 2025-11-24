/// CPython-Compatible Object Layout
///
/// This file defines PyObject with EXACT CPython binary layout
/// so external C extensions can use it.
///
/// Key differences from our internal PyObject:
/// 1. Uses extern struct (C-compatible layout)
/// 2. Matches CPython field names (ob_refcnt, ob_type)
/// 3. Supports dead code elimination (only compile what's used)

const std = @import("std");

/// ============================================================================
/// CPYTHON OBJECT LAYOUT (Binary Compatible)
/// ============================================================================

/// PyObject - The base object type
///
/// Must match CPython's layout EXACTLY:
/// ```c
/// typedef struct _object {
///     Py_ssize_t ob_refcnt;
///     PyTypeObject *ob_type;
/// } PyObject;
/// ```
pub const PyObject = extern struct {
    ob_refcnt: isize,
    ob_type: *PyTypeObject,
};

/// PyVarObject - Variable-size object (lists, tuples, strings)
///
/// CPython layout:
/// ```c
/// typedef struct {
///     PyObject ob_base;
///     Py_ssize_t ob_size;
/// } PyVarObject;
/// ```
pub const PyVarObject = extern struct {
    ob_base: PyObject,
    ob_size: isize,
};

/// ============================================================================
/// PYTYPE OBJECT (Type metadata)
/// ============================================================================

/// Forward declarations for protocol structs
pub const PyNumberMethods = anyopaque;
pub const PySequenceMethods = anyopaque;

/// Buffer protocol methods
pub const PyBufferProcs = extern struct {
    bf_getbuffer: ?*const fn (*PyObject, *Py_buffer, c_int) callconv(.c) c_int,
    bf_releasebuffer: ?*const fn (*PyObject, *Py_buffer) callconv(.c) void,
};

/// Buffer protocol flags
pub const PyBUF_SIMPLE: c_int = 0;
pub const PyBUF_WRITABLE: c_int = 0x0001;
pub const PyBUF_FORMAT: c_int = 0x0004;
pub const PyBUF_ND: c_int = 0x0008;
pub const PyBUF_STRIDES: c_int = 0x0010 | PyBUF_ND;
pub const PyBUF_C_CONTIGUOUS: c_int = 0x0020 | PyBUF_STRIDES;
pub const PyBUF_F_CONTIGUOUS: c_int = 0x0040 | PyBUF_STRIDES;
pub const PyBUF_ANY_CONTIGUOUS: c_int = 0x0080 | PyBUF_STRIDES;
pub const PyBUF_INDIRECT: c_int = 0x0100 | PyBUF_STRIDES;

/// CPython buffer view
pub const Py_buffer = extern struct {
    buf: ?*anyopaque,
    obj: ?*PyObject,
    len: isize,
    itemsize: isize,
    readonly: c_int,
    ndim: c_int,
    format: ?[*:0]u8,
    shape: ?[*]isize,
    strides: ?[*]isize,
    suboffsets: ?[*]isize,
    internal: ?*anyopaque,
};

/// Simplified PyTypeObject for now
/// Full version has ~50 function pointer slots!
pub const PyTypeObject = extern struct {
    ob_base: PyVarObject,
    tp_name: [*:0]const u8,
    tp_basicsize: isize,
    tp_itemsize: isize,

    // Function pointers (simplified - will expand as needed)
    tp_dealloc: ?*const fn (*PyObject) callconv(.c) void,
    tp_repr: ?*const fn (*PyObject) callconv(.c) *PyObject,
    tp_hash: ?*const fn (*PyObject) callconv(.c) isize,
    tp_call: ?*const fn (*PyObject, *PyObject, ?*PyObject) callconv(.c) *PyObject,
    tp_str: ?*const fn (*PyObject) callconv(.c) *PyObject,
    tp_getattro: ?*const fn (*PyObject, *PyObject) callconv(.c) *PyObject,
    tp_setattro: ?*const fn (*PyObject, *PyObject, *PyObject) callconv(.c) c_int,

    // Protocol slots
    tp_as_number: ?*PyNumberMethods,
    tp_as_sequence: ?*PySequenceMethods,
    tp_as_buffer: ?*PyBufferProcs,

    // TODO: Add remaining ~40 slots as needed
    // Dead code elimination ensures unused slots don't bloat binary
};

/// ============================================================================
/// CONCRETE TYPE OBJECTS
/// ============================================================================

/// PyLongObject - Arbitrary precision integer
///
/// CPython uses a flexible array for digits, we simplify for now
pub const PyLongObject = extern struct {
    ob_base: PyVarObject,
    // For now, store as i64 (will expand to arbitrary precision later)
    lv_tag: u64, // CPython 3.12+ uses tagged representation
};

/// PyFloatObject - IEEE 754 double wrapper
pub const PyFloatObject = extern struct {
    ob_base: PyObject,
    fval: f64,
};

/// PyBytesObject - Immutable byte string
pub const PyBytesObject = extern struct {
    ob_base: PyVarObject,
    ob_shash: isize, // Cached hash value
    // ob_sval follows in memory (char array)
    // We handle this with allocation, not in struct
};

/// PyListObject - Dynamic array of PyObject pointers
pub const PyListObject = extern struct {
    ob_base: PyVarObject,
    ob_item: [*]?*PyObject, // Array of object pointers
    allocated: isize, // Number of slots allocated
};

/// PyTupleObject - Fixed-size array of PyObject pointers
pub const PyTupleObject = extern struct {
    ob_base: PyVarObject,
    // ob_item follows in memory (PyObject* array)
    // Like PyBytesObject, handled via allocation
};

/// PyDictObject - Hash table
///
/// CPython has complex "combined table" vs "split table" optimization
/// We simplify for now
pub const PyDictObject = extern struct {
    ob_base: PyObject,
    ma_used: isize, // Number of items
    ma_version_tag: u64, // Version for cache invalidation
    ma_keys: ?*anyopaque, // Pointer to keys table (opaque for now)
    ma_values: ?*anyopaque, // Pointer to values (for split tables)
};

/// ============================================================================
/// BRIDGE TO OUR INTERNAL TYPES
/// ============================================================================

// Note: Runtime import is optional - only needed when bridging is used
// This keeps the module testable in isolation

/// Convert CPython PyObject to our internal PyObject
pub fn fromCPython(cpython_obj: *PyObject) !*anyopaque {
    // TODO: Implement conversion with runtime.PyObject
    // For now, just validate it's not null
    _ = cpython_obj;
    return error.NotImplemented;
}

/// Convert our internal PyObject to CPython PyObject
pub fn toCPython(our_obj: *anyopaque) !*PyObject {
    // TODO: Implement conversion with runtime.PyObject
    _ = our_obj;
    return error.NotImplemented;
}

/// ============================================================================
/// TYPE CHECKING MACROS (CPython compatibility)
/// ============================================================================

/// Check if object is of a specific type
pub inline fn Py_TYPE(op: *PyObject) *PyTypeObject {
    return op.ob_type;
}

/// Get reference count
pub inline fn Py_REFCNT(op: *PyObject) isize {
    return op.ob_refcnt;
}

/// Get size for variable-size objects
pub inline fn Py_SIZE(op: *PyVarObject) isize {
    return op.ob_size;
}

// ============================================================================
// DEAD CODE ELIMINATION SUPPORT
// ============================================================================
//
// All functions are marked inline or use callconv(.c) export
// Zig's dead code elimination will:
// 1. Only compile types that are actually used
// 2. Only include function pointer slots that are referenced
// 3. Strip unused conversion functions
//
// Example: If user code never uses PyDict, PyDictObject won't be in binary!

// Tests
test "PyObject layout matches CPython" {
    // Verify size and alignment
    const cpython_pyobject_size = 16; // 8 bytes refcnt + 8 bytes type ptr
    try std.testing.expectEqual(@as(usize, cpython_pyobject_size), @sizeOf(PyObject));

    // Verify alignment (should be pointer-aligned)
    try std.testing.expect(@alignOf(PyObject) == @alignOf(*anyopaque));
}

test "PyVarObject layout" {
    const expected_size = @sizeOf(PyObject) + @sizeOf(isize);
    try std.testing.expectEqual(expected_size, @sizeOf(PyVarObject));
}

test "type checking macros" {
    // Create a dummy type
    var dummy_type = PyTypeObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = undefined, // Self-reference not needed for test
            },
            .ob_size = 0,
        },
        .tp_name = "test",
        .tp_basicsize = @sizeOf(PyObject),
        .tp_itemsize = 0,
        .tp_dealloc = null,
        .tp_repr = null,
        .tp_hash = null,
        .tp_call = null,
        .tp_str = null,
        .tp_getattro = null,
        .tp_setattro = null,
    };

    var obj = PyObject{
        .ob_refcnt = 42,
        .ob_type = &dummy_type,
    };

    try std.testing.expectEqual(@as(isize, 42), Py_REFCNT(&obj));
    try std.testing.expectEqual(&dummy_type, Py_TYPE(&obj));
}
