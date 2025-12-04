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
    const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
    const value = float_obj.ob_fval;

    // Format float to string
    var buf: [64]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return null;

    // Create unicode string
    const unicode = @import("cpython_unicode.zig");
    return unicode.PyUnicode_FromStringAndSize(result.ptr, @intCast(result.len));
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
    const a_val = getFloatValue(@ptrCast(@alignCast(a)));
    const b_val = getFloatValue(@ptrCast(@alignCast(b)));
    if (b_val == 0.0) return null;

    const quotient = @floor(a_val / b_val);
    const remainder = a_val - quotient * b_val;

    // Create tuple (quotient, remainder)
    const tuple = @import("pyobject_tuple.zig");
    const result = tuple.PyTuple_New(2) orelse return null;

    const q_obj = createFloat(quotient) orelse return null;
    const r_obj = createFloat(remainder) orelse return null;

    _ = tuple.PyTuple_SetItem(result, 0, q_obj);
    _ = tuple.PyTuple_SetItem(result, 1, r_obj);

    return result;
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
    const val = getFloatValue(@ptrCast(@alignCast(obj)));
    const long = @import("pyobject_long.zig");
    return long.PyLong_FromDouble(val);
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
    const unicode = @import("cpython_unicode.zig");

    // Get string content
    const c_str = unicode.PyUnicode_AsUTF8(str) orelse return null;
    const slice = std.mem.span(c_str);

    // Trim whitespace
    const trimmed = std.mem.trim(u8, slice, " \t\n\r");
    if (trimmed.len == 0) return null;

    // Parse float
    const value = std.fmt.parseFloat(f64, trimmed) catch return null;
    return createFloat(value);
}

// ============================================================================
// CONVERSION FUNCTIONS (Exported)
// ============================================================================

pub export fn PyFloat_AsDouble(obj: *cpython.PyObject) callconv(.c) f64 {
    if (PyFloat_Check(obj) == 0) return -1.0;
    return getFloatValue(@ptrCast(@alignCast(obj)));
}

export fn PyFloat_GetInfo() callconv(.c) ?*cpython.PyObject {
    // Return a tuple with float info (simplified version)
    // CPython returns a named tuple, we return a regular tuple with key values
    const tuple = @import("pyobject_tuple.zig");
    const result = tuple.PyTuple_New(11) orelse return null;

    // max, max_exp, max_10_exp, min, min_exp, min_10_exp, dig, mant_dig, epsilon, radix, rounds
    _ = tuple.PyTuple_SetItem(result, 0, createFloat(std.math.floatMax(f64)));
    _ = tuple.PyTuple_SetItem(result, 1, @import("pyobject_long.zig").PyLong_FromLong(1024)); // max_exp
    _ = tuple.PyTuple_SetItem(result, 2, @import("pyobject_long.zig").PyLong_FromLong(308)); // max_10_exp
    _ = tuple.PyTuple_SetItem(result, 3, createFloat(std.math.floatMin(f64)));
    _ = tuple.PyTuple_SetItem(result, 4, @import("pyobject_long.zig").PyLong_FromLong(-1021)); // min_exp
    _ = tuple.PyTuple_SetItem(result, 5, @import("pyobject_long.zig").PyLong_FromLong(-307)); // min_10_exp
    _ = tuple.PyTuple_SetItem(result, 6, @import("pyobject_long.zig").PyLong_FromLong(15)); // dig
    _ = tuple.PyTuple_SetItem(result, 7, @import("pyobject_long.zig").PyLong_FromLong(53)); // mant_dig
    _ = tuple.PyTuple_SetItem(result, 8, createFloat(std.math.floatEps(f64)));
    _ = tuple.PyTuple_SetItem(result, 9, @import("pyobject_long.zig").PyLong_FromLong(2)); // radix
    _ = tuple.PyTuple_SetItem(result, 10, @import("pyobject_long.zig").PyLong_FromLong(1)); // rounds

    return result;
}

export fn PyFloat_GetMax() callconv(.c) f64 {
    return std.math.floatMax(f64);
}

export fn PyFloat_GetMin() callconv(.c) f64 {
    return std.math.floatMin(f64);
}

// ============================================================================
// PACK/UNPACK FUNCTIONS (IEEE 754 binary format)
// ============================================================================

/// PyFloat_Pack2 - Pack f64 to IEEE 754 half-precision (2 bytes)
export fn PyFloat_Pack2(x: f64, p: [*]u8, le: c_int) callconv(.c) c_int {
    // Convert to f16 and store
    const f16_val: f16 = @floatCast(x);
    const bits: u16 = @bitCast(f16_val);

    if (le != 0) {
        // Little endian
        p[0] = @truncate(bits);
        p[1] = @truncate(bits >> 8);
    } else {
        // Big endian
        p[0] = @truncate(bits >> 8);
        p[1] = @truncate(bits);
    }
    return 0;
}

/// PyFloat_Pack4 - Pack f64 to IEEE 754 single-precision (4 bytes)
export fn PyFloat_Pack4(x: f64, p: [*]u8, le: c_int) callconv(.c) c_int {
    const f32_val: f32 = @floatCast(x);
    const bits: u32 = @bitCast(f32_val);

    if (le != 0) {
        p[0] = @truncate(bits);
        p[1] = @truncate(bits >> 8);
        p[2] = @truncate(bits >> 16);
        p[3] = @truncate(bits >> 24);
    } else {
        p[0] = @truncate(bits >> 24);
        p[1] = @truncate(bits >> 16);
        p[2] = @truncate(bits >> 8);
        p[3] = @truncate(bits);
    }
    return 0;
}

/// PyFloat_Pack8 - Pack f64 to IEEE 754 double-precision (8 bytes)
export fn PyFloat_Pack8(x: f64, p: [*]u8, le: c_int) callconv(.c) c_int {
    const bits: u64 = @bitCast(x);

    if (le != 0) {
        p[0] = @truncate(bits);
        p[1] = @truncate(bits >> 8);
        p[2] = @truncate(bits >> 16);
        p[3] = @truncate(bits >> 24);
        p[4] = @truncate(bits >> 32);
        p[5] = @truncate(bits >> 40);
        p[6] = @truncate(bits >> 48);
        p[7] = @truncate(bits >> 56);
    } else {
        p[0] = @truncate(bits >> 56);
        p[1] = @truncate(bits >> 48);
        p[2] = @truncate(bits >> 40);
        p[3] = @truncate(bits >> 32);
        p[4] = @truncate(bits >> 24);
        p[5] = @truncate(bits >> 16);
        p[6] = @truncate(bits >> 8);
        p[7] = @truncate(bits);
    }
    return 0;
}

/// PyFloat_Unpack2 - Unpack IEEE 754 half-precision (2 bytes) to f64
export fn PyFloat_Unpack2(p: [*]const u8, le: c_int) callconv(.c) f64 {
    var bits: u16 = undefined;
    if (le != 0) {
        bits = @as(u16, p[0]) | (@as(u16, p[1]) << 8);
    } else {
        bits = (@as(u16, p[0]) << 8) | @as(u16, p[1]);
    }
    const f16_val: f16 = @bitCast(bits);
    return @floatCast(f16_val);
}

/// PyFloat_Unpack4 - Unpack IEEE 754 single-precision (4 bytes) to f64
export fn PyFloat_Unpack4(p: [*]const u8, le: c_int) callconv(.c) f64 {
    var bits: u32 = undefined;
    if (le != 0) {
        bits = @as(u32, p[0]) | (@as(u32, p[1]) << 8) | (@as(u32, p[2]) << 16) | (@as(u32, p[3]) << 24);
    } else {
        bits = (@as(u32, p[0]) << 24) | (@as(u32, p[1]) << 16) | (@as(u32, p[2]) << 8) | @as(u32, p[3]);
    }
    const f32_val: f32 = @bitCast(bits);
    return @floatCast(f32_val);
}

/// PyFloat_Unpack8 - Unpack IEEE 754 double-precision (8 bytes) to f64
export fn PyFloat_Unpack8(p: [*]const u8, le: c_int) callconv(.c) f64 {
    var bits: u64 = undefined;
    if (le != 0) {
        bits = @as(u64, p[0]) | (@as(u64, p[1]) << 8) | (@as(u64, p[2]) << 16) | (@as(u64, p[3]) << 24) |
            (@as(u64, p[4]) << 32) | (@as(u64, p[5]) << 40) | (@as(u64, p[6]) << 48) | (@as(u64, p[7]) << 56);
    } else {
        bits = (@as(u64, p[0]) << 56) | (@as(u64, p[1]) << 48) | (@as(u64, p[2]) << 40) | (@as(u64, p[3]) << 32) |
            (@as(u64, p[4]) << 24) | (@as(u64, p[5]) << 16) | (@as(u64, p[6]) << 8) | @as(u64, p[7]);
    }
    return @bitCast(bits);
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
