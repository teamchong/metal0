/// PyFloatObject - Python float Implementation
///
/// Implements CPython compatible float with EXACT memory layout.
///
/// Reference: cpython/Include/cpython/floatobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// Re-export types from cpython_object
pub const PyFloatObject = cpython.PyFloatObject;

// ============================================================================
// PYFLOAT_TYPE OBJECT
// ============================================================================

fn float_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    allocator.destroy(@as(*PyFloatObject, @ptrCast(@alignCast(obj))));
}

fn float_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = obj;
    return null; // TODO: Implement string conversion
}

fn float_hash(obj: *cpython.PyObject) callconv(.c) isize {
    const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
    const bits: u64 = @bitCast(float_obj.ob_fval);
    return @intCast(bits ^ (bits >> 32));
}

var float_as_number: cpython.PyNumberMethods = .{
    .nb_add = float_add,
    .nb_subtract = float_subtract,
    .nb_multiply = float_multiply,
    .nb_remainder = float_remainder,
    .nb_divmod = float_divmod,
    .nb_power = float_power,
    .nb_negative = float_negative,
    .nb_positive = float_positive,
    .nb_absolute = float_absolute,
    .nb_bool = float_bool,
    .nb_invert = null,
    .nb_lshift = null,
    .nb_rshift = null,
    .nb_and = null,
    .nb_xor = null,
    .nb_or = null,
    .nb_int = float_int,
    .nb_reserved = null,
    .nb_float = float_float,
    .nb_inplace_add = null,
    .nb_inplace_subtract = null,
    .nb_inplace_multiply = null,
    .nb_inplace_remainder = null,
    .nb_inplace_power = null,
    .nb_inplace_lshift = null,
    .nb_inplace_rshift = null,
    .nb_inplace_and = null,
    .nb_inplace_xor = null,
    .nb_inplace_or = null,
    .nb_floor_divide = float_floor_divide,
    .nb_true_divide = float_true_divide,
    .nb_inplace_floor_divide = null,
    .nb_inplace_true_divide = null,
    .nb_index = null,
    .nb_matrix_multiply = null,
    .nb_inplace_matrix_multiply = null,
};

pub var PyFloat_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{
            .ob_refcnt = 1000000, // Immortal
            .ob_type = undefined, // Will be &PyType_Type when available
        },
        .ob_size = 0,
    },
    .tp_name = "float",
    .tp_basicsize = @sizeOf(PyFloatObject),
    .tp_itemsize = 0,
    .tp_dealloc = float_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = float_repr,
    .tp_as_number = &float_as_number,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = float_hash,
    .tp_call = null,
    .tp_str = float_repr,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "float(x=0.0) -> floating point number",
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
// HELPER FUNCTIONS
// ============================================================================

inline fn getFloatValue(obj: *const PyFloatObject) f64 {
    return obj.ob_fval;
}

fn createFloat(value: f64) ?*cpython.PyObject {
    const obj = allocator.create(PyFloatObject) catch return null;
    obj.* = PyFloatObject{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyFloat_Type,
        },
        .ob_fval = value,
    };
    return @ptrCast(&obj.ob_base);
}

// ============================================================================
// NUMBER PROTOCOL IMPLEMENTATION
// ============================================================================

fn float_add(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getFloatValue(@ptrCast(@alignCast(a)));
    const b_val = getFloatValue(@ptrCast(@alignCast(b)));
    return createFloat(a_val + b_val);
}

fn float_subtract(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getFloatValue(@ptrCast(@alignCast(a)));
    const b_val = getFloatValue(@ptrCast(@alignCast(b)));
    return createFloat(a_val - b_val);
}

fn float_multiply(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getFloatValue(@ptrCast(@alignCast(a)));
    const b_val = getFloatValue(@ptrCast(@alignCast(b)));
    return createFloat(a_val * b_val);
}

fn float_true_divide(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getFloatValue(@ptrCast(@alignCast(a)));
    const b_val = getFloatValue(@ptrCast(@alignCast(b)));
    if (b_val == 0.0) return null;
    return createFloat(a_val / b_val);
}

fn float_floor_divide(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getFloatValue(@ptrCast(@alignCast(a)));
    const b_val = getFloatValue(@ptrCast(@alignCast(b)));
    if (b_val == 0.0) return null;
    return createFloat(@floor(a_val / b_val));
}

fn float_remainder(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getFloatValue(@ptrCast(@alignCast(a)));
    const b_val = getFloatValue(@ptrCast(@alignCast(b)));
    if (b_val == 0.0) return null;
    return createFloat(@mod(a_val, b_val));
}

fn float_divmod(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = a;
    _ = b;
    return null; // TODO: Need tuple support
}

fn float_power(a: *cpython.PyObject, b: *cpython.PyObject, c: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = c;
    const base = getFloatValue(@ptrCast(@alignCast(a)));
    const exp = getFloatValue(@ptrCast(@alignCast(b)));
    return createFloat(std.math.pow(f64, base, exp));
}

fn float_negative(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = getFloatValue(@ptrCast(@alignCast(obj)));
    return createFloat(-val);
}

fn float_positive(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = getFloatValue(@ptrCast(@alignCast(obj)));
    return createFloat(val);
}

fn float_absolute(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = getFloatValue(@ptrCast(@alignCast(obj)));
    return createFloat(@abs(val));
}

fn float_bool(obj: *cpython.PyObject) callconv(.c) c_int {
    const val = getFloatValue(@ptrCast(@alignCast(obj)));
    return if (val != 0.0) 1 else 0;
}

fn float_int(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = obj;
    return null; // TODO: Return PyLong
}

fn float_float(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Return new reference
    const val = getFloatValue(@ptrCast(@alignCast(obj)));
    return createFloat(val);
}

// ============================================================================
// CREATION FUNCTIONS (Exported)
// ============================================================================

pub export fn PyFloat_FromDouble(value: f64) callconv(.c) ?*cpython.PyObject {
    return createFloat(value);
}

export fn PyFloat_FromString(str: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = str;
    return null; // TODO: Parse string to float
}

// ============================================================================
// CONVERSION FUNCTIONS (Exported)
// ============================================================================

pub export fn PyFloat_AsDouble(obj: *cpython.PyObject) callconv(.c) f64 {
    if (PyFloat_Check(obj) == 0) return -1.0;
    return getFloatValue(@ptrCast(@alignCast(obj)));
}

export fn PyFloat_GetInfo() callconv(.c) ?*cpython.PyObject {
    return null; // TODO: Return sys.float_info
}

export fn PyFloat_GetMax() callconv(.c) f64 {
    return std.math.floatMax(f64);
}

export fn PyFloat_GetMin() callconv(.c) f64 {
    return std.math.floatMin(f64);
}

// ============================================================================
// TYPE CHECKING
// ============================================================================

pub export fn PyFloat_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyFloat_Type) 1 else 0;
}

export fn PyFloat_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyFloat_Type) 1 else 0;
}

// ============================================================================
// TESTS
// ============================================================================

test "PyFloatObject layout matches CPython" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(PyFloatObject));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PyFloatObject, "ob_base"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyFloatObject, "ob_fval"));
}

test "PyFloat creation and conversion" {
    const obj = PyFloat_FromDouble(3.14);
    try std.testing.expect(obj != null);

    const value = PyFloat_AsDouble(obj.?);
    try std.testing.expectApproxEqRel(@as(f64, 3.14), value, 0.001);
}

test "PyFloat arithmetic" {
    const a = PyFloat_FromDouble(10.0);
    const b = PyFloat_FromDouble(3.0);

    const sum = float_add(a.?, b.?);
    try std.testing.expectApproxEqRel(@as(f64, 13.0), PyFloat_AsDouble(sum.?), 0.001);

    const diff = float_subtract(a.?, b.?);
    try std.testing.expectApproxEqRel(@as(f64, 7.0), PyFloat_AsDouble(diff.?), 0.001);

    const prod = float_multiply(a.?, b.?);
    try std.testing.expectApproxEqRel(@as(f64, 30.0), PyFloat_AsDouble(prod.?), 0.001);

    const quot = float_true_divide(a.?, b.?);
    try std.testing.expectApproxEqRel(@as(f64, 3.333), PyFloat_AsDouble(quot.?), 0.01);
}
