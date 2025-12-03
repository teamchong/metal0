/// PyComplexObject - EXACT CPython 3.12 memory layout
///
/// Reference: cpython/Include/cpython/complexobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPES
// ============================================================================

/// Py_complex - complex number value
pub const Py_complex = extern struct {
    real: f64,
    imag: f64,
};

/// PyComplexObject - EXACT CPython layout
pub const PyComplexObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    cval: Py_complex, // 16 bytes
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub var PyComplex_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "complex",
    .tp_basicsize = @sizeOf(PyComplexObject),
    .tp_itemsize = 0,
    .tp_dealloc = complex_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = complex_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "complex(real=0, imag=0)",
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

// ============================================================================
// API FUNCTIONS
// ============================================================================

/// Create complex from Py_complex
pub export fn PyComplex_FromCComplex(cval: Py_complex) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PyComplexObject) catch return null;
    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyComplex_Type;
    obj.cval = cval;
    return @ptrCast(&obj.ob_base);
}

/// Create complex from doubles
pub export fn PyComplex_FromDoubles(real: f64, imag: f64) callconv(.c) ?*cpython.PyObject {
    return PyComplex_FromCComplex(.{ .real = real, .imag = imag });
}

/// Get real part
pub export fn PyComplex_RealAsDouble(obj: *cpython.PyObject) callconv(.c) f64 {
    const c: *PyComplexObject = @ptrCast(@alignCast(obj));
    return c.cval.real;
}

/// Get imaginary part
pub export fn PyComplex_ImagAsDouble(obj: *cpython.PyObject) callconv(.c) f64 {
    const c: *PyComplexObject = @ptrCast(@alignCast(obj));
    return c.cval.imag;
}

/// Get as Py_complex
pub export fn PyComplex_AsCComplex(obj: *cpython.PyObject) callconv(.c) Py_complex {
    const c: *PyComplexObject = @ptrCast(@alignCast(obj));
    return c.cval;
}

/// Type check
pub export fn PyComplex_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyComplex_Type) 1 else 0;
}

pub export fn PyComplex_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyComplex_Type) 1 else 0;
}

// ============================================================================
// INTERNAL FUNCTIONS
// ============================================================================

fn complex_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const c: *PyComplexObject = @ptrCast(@alignCast(obj));
    allocator.destroy(c);
}

fn complex_hash(obj: *cpython.PyObject) callconv(.c) isize {
    const c: *PyComplexObject = @ptrCast(@alignCast(obj));
    // Simple hash combining real and imag
    const real_bits: u64 = @bitCast(c.cval.real);
    const imag_bits: u64 = @bitCast(c.cval.imag);
    return @intCast((real_bits ^ (imag_bits *% 1000003)) & 0x7FFFFFFFFFFFFFFF);
}

// ============================================================================
// TESTS
// ============================================================================

test "PyComplexObject layout" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(PyComplexObject));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyComplexObject, "cval"));
}
