/// PyLongObject - Arbitrary Precision Integer Implementation
///
/// Implements CPython-compatible long integer with:
/// - Small integer cache (-5 to 256)
/// - Number protocol for arithmetic
/// - Conversion functions (From/As)
/// - Simplified i64 storage (full bigint later)

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

/// ============================================================================
/// SMALL INTEGER CACHE
/// ============================================================================

/// Small integers cache (-5 to 256)
const SMALL_INT_MIN: i64 = -5;
const SMALL_INT_MAX: i64 = 256;
const SMALL_INT_COUNT: usize = @intCast(SMALL_INT_MAX - SMALL_INT_MIN + 1);

/// Pre-allocated small integers
var small_ints: [SMALL_INT_COUNT]cpython.PyLongObject = undefined;
var small_ints_initialized = false;

/// Initialize small integer cache
fn initSmallInts() void {
    if (small_ints_initialized) return;

    for (0..SMALL_INT_COUNT) |i| {
        const value: i64 = SMALL_INT_MIN + @as(i64, @intCast(i));
        small_ints[i] = cpython.PyLongObject{
            .ob_base = .{
                .ob_base = .{
                    .ob_refcnt = 1000000, // Immortal reference count
                    .ob_type = &PyLong_Type,
                },
                .ob_size = 1,
            },
            .lv_tag = @bitCast(value),
        };
    }

    small_ints_initialized = true;
}

/// Get cached small integer
fn getSmallInt(value: i64) ?*cpython.PyObject {
    if (value < SMALL_INT_MIN or value > SMALL_INT_MAX) return null;

    if (!small_ints_initialized) initSmallInts();

    const idx: usize = @intCast(value - SMALL_INT_MIN);
    return @ptrCast(&small_ints[idx].ob_base.ob_base);
}

/// ============================================================================
/// NUMBER PROTOCOL IMPLEMENTATION
/// ============================================================================

fn long_add(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_long = @as(*cpython.PyLongObject, @ptrCast(a));
    const b_long = @as(*cpython.PyLongObject, @ptrCast(b));

    const a_val: i64 = @bitCast(a_long.lv_tag);
    const b_val: i64 = @bitCast(b_long.lv_tag);

    const result = a_val +% b_val; // Wrapping add for now
    return PyLong_FromLongLong(result);
}

fn long_subtract(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_long = @as(*cpython.PyLongObject, @ptrCast(a));
    const b_long = @as(*cpython.PyLongObject, @ptrCast(b));

    const a_val: i64 = @bitCast(a_long.lv_tag);
    const b_val: i64 = @bitCast(b_long.lv_tag);

    const result = a_val -% b_val;
    return PyLong_FromLongLong(result);
}

fn long_multiply(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_long = @as(*cpython.PyLongObject, @ptrCast(a));
    const b_long = @as(*cpython.PyLongObject, @ptrCast(b));

    const a_val: i64 = @bitCast(a_long.lv_tag);
    const b_val: i64 = @bitCast(b_long.lv_tag);

    const result = a_val *% b_val;
    return PyLong_FromLongLong(result);
}

fn long_floor_divide(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_long = @as(*cpython.PyLongObject, @ptrCast(a));
    const b_long = @as(*cpython.PyLongObject, @ptrCast(b));

    const a_val: i64 = @bitCast(a_long.lv_tag);
    const b_val: i64 = @bitCast(b_long.lv_tag);

    if (b_val == 0) return null; // Division by zero

    const result = @divFloor(a_val, b_val);
    return PyLong_FromLongLong(result);
}

fn long_remainder(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_long = @as(*cpython.PyLongObject, @ptrCast(a));
    const b_long = @as(*cpython.PyLongObject, @ptrCast(b));

    const a_val: i64 = @bitCast(a_long.lv_tag);
    const b_val: i64 = @bitCast(b_long.lv_tag);

    if (b_val == 0) return null;

    const result = @mod(a_val, b_val);
    return PyLong_FromLongLong(result);
}

fn long_divmod(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Returns tuple (quotient, remainder)
    _ = a;
    _ = b;
    return null; // TODO: Need tuple support
}

fn long_power(a: *cpython.PyObject, b: *cpython.PyObject, c: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = a;
    _ = b;
    _ = c;
    return null; // TODO: Implement power
}

fn long_negative(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    const val: i64 = @bitCast(long_obj.lv_tag);
    return PyLong_FromLongLong(-val);
}

fn long_positive(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Just return a new reference to the same object
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    const val: i64 = @bitCast(long_obj.lv_tag);
    return PyLong_FromLongLong(val);
}

fn long_absolute(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    const val: i64 = @bitCast(long_obj.lv_tag);
    return PyLong_FromLongLong(@as(i64, @intCast(@abs(val))));
}

fn long_bool(obj: *cpython.PyObject) callconv(.c) c_int {
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    const val: i64 = @bitCast(long_obj.lv_tag);
    return if (val != 0) 1 else 0;
}

fn long_int(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Return new reference to itself
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    const val: i64 = @bitCast(long_obj.lv_tag);
    return PyLong_FromLongLong(val);
}

fn long_float(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = obj;
    // TODO: Implement when PyFloat is available
    // const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    // const val: i64 = @bitCast(long_obj.lv_tag);
    // const float_val: f64 = @floatFromInt(val);
    // return PyFloat_FromDouble(float_val);
    return null;
}

fn long_invert(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    const val: i64 = @bitCast(long_obj.lv_tag);
    return PyLong_FromLongLong(~val);
}

fn long_lshift(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_long = @as(*cpython.PyLongObject, @ptrCast(a));
    const b_long = @as(*cpython.PyLongObject, @ptrCast(b));

    const a_val: i64 = @bitCast(a_long.lv_tag);
    const b_val: i64 = @bitCast(b_long.lv_tag);

    if (b_val < 0 or b_val >= 64) return null;

    const shift: u6 = @intCast(b_val);
    const result = a_val << shift;
    return PyLong_FromLongLong(result);
}

fn long_rshift(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_long = @as(*cpython.PyLongObject, @ptrCast(a));
    const b_long = @as(*cpython.PyLongObject, @ptrCast(b));

    const a_val: i64 = @bitCast(a_long.lv_tag);
    const b_val: i64 = @bitCast(b_long.lv_tag);

    if (b_val < 0 or b_val >= 64) return null;

    const shift: u6 = @intCast(b_val);
    const result = a_val >> shift;
    return PyLong_FromLongLong(result);
}

fn long_and(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_long = @as(*cpython.PyLongObject, @ptrCast(a));
    const b_long = @as(*cpython.PyLongObject, @ptrCast(b));

    const a_val: i64 = @bitCast(a_long.lv_tag);
    const b_val: i64 = @bitCast(b_long.lv_tag);

    return PyLong_FromLongLong(a_val & b_val);
}

fn long_xor(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_long = @as(*cpython.PyLongObject, @ptrCast(a));
    const b_long = @as(*cpython.PyLongObject, @ptrCast(b));

    const a_val: i64 = @bitCast(a_long.lv_tag);
    const b_val: i64 = @bitCast(b_long.lv_tag);

    return PyLong_FromLongLong(a_val ^ b_val);
}

fn long_or(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_long = @as(*cpython.PyLongObject, @ptrCast(a));
    const b_long = @as(*cpython.PyLongObject, @ptrCast(b));

    const a_val: i64 = @bitCast(a_long.lv_tag);
    const b_val: i64 = @bitCast(b_long.lv_tag);

    return PyLong_FromLongLong(a_val | b_val);
}

/// Number protocol methods table
const PyNumberMethods = extern struct {
    nb_add: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_subtract: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_multiply: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_remainder: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_divmod: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_power: ?*const fn (*cpython.PyObject, *cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_negative: ?*const fn (*cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_positive: ?*const fn (*cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_absolute: ?*const fn (*cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_bool: ?*const fn (*cpython.PyObject) callconv(.c) c_int,
    nb_invert: ?*const fn (*cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_lshift: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_rshift: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_and: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_xor: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_or: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_int: ?*const fn (*cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    reserved: ?*anyopaque,
    nb_float: ?*const fn (*cpython.PyObject) callconv(.c) ?*cpython.PyObject,

    nb_inplace_add: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_subtract: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_multiply: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_remainder: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_power: ?*const fn (*cpython.PyObject, *cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_lshift: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_rshift: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_and: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_xor: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_or: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,

    nb_floor_divide: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_true_divide: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_floor_divide: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_true_divide: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,

    nb_index: ?*const fn (*cpython.PyObject) callconv(.c) ?*cpython.PyObject,

    nb_matrix_multiply: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    nb_inplace_matrix_multiply: ?*const fn (*cpython.PyObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,
};

var long_as_number = PyNumberMethods{
    .nb_add = long_add,
    .nb_subtract = long_subtract,
    .nb_multiply = long_multiply,
    .nb_remainder = long_remainder,
    .nb_divmod = long_divmod,
    .nb_power = long_power,
    .nb_negative = long_negative,
    .nb_positive = long_positive,
    .nb_absolute = long_absolute,
    .nb_bool = long_bool,
    .nb_invert = long_invert,
    .nb_lshift = long_lshift,
    .nb_rshift = long_rshift,
    .nb_and = long_and,
    .nb_xor = long_xor,
    .nb_or = long_or,
    .nb_int = long_int,
    .reserved = null,
    .nb_float = long_float,

    .nb_inplace_add = long_add, // Same as regular for immutable type
    .nb_inplace_subtract = long_subtract,
    .nb_inplace_multiply = long_multiply,
    .nb_inplace_remainder = long_remainder,
    .nb_inplace_power = long_power,
    .nb_inplace_lshift = long_lshift,
    .nb_inplace_rshift = long_rshift,
    .nb_inplace_and = long_and,
    .nb_inplace_xor = long_xor,
    .nb_inplace_or = long_or,

    .nb_floor_divide = long_floor_divide,
    .nb_true_divide = null, // TODO: Convert to float
    .nb_inplace_floor_divide = long_floor_divide,
    .nb_inplace_true_divide = null,

    .nb_index = long_int,

    .nb_matrix_multiply = null,
    .nb_inplace_matrix_multiply = null,
};

/// ============================================================================
/// PYLONG_TYPE OBJECT
/// ============================================================================

fn long_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    // Don't free small ints
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    const val: i64 = @bitCast(long_obj.lv_tag);

    if (val >= SMALL_INT_MIN and val <= SMALL_INT_MAX) return;

    allocator.destroy(long_obj);
}

// PyFloat forward declaration removed - not needed for now

var PyLong_Type = cpython.PyTypeObject{
    .ob_base = .{
        .ob_base = .{
            .ob_refcnt = 1000000, // Immortal
            .ob_type = undefined, // Will be &PyType_Type when available
        },
        .ob_size = 0,
    },
    .tp_name = "int",
    .tp_basicsize = @sizeOf(cpython.PyLongObject),
    .tp_itemsize = 0,
    .tp_dealloc = long_dealloc,
    .tp_repr = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_number = @ptrCast(&long_as_number),
    .tp_as_sequence = null,
};

/// ============================================================================
/// CREATION FUNCTIONS
/// ============================================================================

pub export fn PyLong_FromLong(value: c_long) callconv(.c) ?*cpython.PyObject {
    const i64_val: i64 = @intCast(value);

    // Try small int cache
    if (getSmallInt(i64_val)) |cached| return cached;

    const obj = allocator.create(cpython.PyLongObject) catch return null;
    obj.* = cpython.PyLongObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &PyLong_Type,
            },
            .ob_size = 1,
        },
        .lv_tag = @bitCast(i64_val),
    };

    return @ptrCast(&obj.ob_base.ob_base);
}

export fn PyLong_FromUnsignedLong(value: c_ulong) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(cpython.PyLongObject) catch return null;
    obj.* = cpython.PyLongObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &PyLong_Type,
            },
            .ob_size = 1,
        },
        .lv_tag = value,
    };

    return @ptrCast(&obj.ob_base.ob_base);
}

export fn PyLong_FromLongLong(value: c_longlong) callconv(.c) ?*cpython.PyObject {
    const i64_val: i64 = @intCast(value);

    // Try small int cache
    if (getSmallInt(i64_val)) |cached| return cached;

    const obj = allocator.create(cpython.PyLongObject) catch return null;
    obj.* = cpython.PyLongObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &PyLong_Type,
            },
            .ob_size = 1,
        },
        .lv_tag = @bitCast(i64_val),
    };

    return @ptrCast(&obj.ob_base.ob_base);
}

export fn PyLong_FromUnsignedLongLong(value: c_ulonglong) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(cpython.PyLongObject) catch return null;
    obj.* = cpython.PyLongObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &PyLong_Type,
            },
            .ob_size = 1,
        },
        .lv_tag = value,
    };

    return @ptrCast(&obj.ob_base.ob_base);
}

export fn PyLong_FromDouble(value: f64) callconv(.c) ?*cpython.PyObject {
    const i64_val: i64 = @intFromFloat(value);
    return PyLong_FromLongLong(i64_val);
}

export fn PyLong_FromString(str: [*:0]const u8, pend: ?*[*:0]u8, base: c_int) callconv(.c) ?*cpython.PyObject {
    _ = pend;
    _ = base;

    // Simple implementation - just parse as i64
    const len = std.mem.len(str);
    const value = std.fmt.parseInt(i64, str[0..len], 10) catch return null;

    return PyLong_FromLongLong(value);
}

export fn PyLong_FromSize_t(value: usize) callconv(.c) ?*cpython.PyObject {
    return PyLong_FromUnsignedLongLong(value);
}

export fn PyLong_FromSsize_t(value: isize) callconv(.c) ?*cpython.PyObject {
    return PyLong_FromLongLong(value);
}

/// ============================================================================
/// CONVERSION FUNCTIONS
/// ============================================================================

pub export fn PyLong_AsLong(obj: *cpython.PyObject) callconv(.c) c_long {
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    const value: i64 = @bitCast(long_obj.lv_tag);
    return @intCast(value);
}

export fn PyLong_AsLongLong(obj: *cpython.PyObject) callconv(.c) c_longlong {
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    return @bitCast(long_obj.lv_tag);
}

export fn PyLong_AsUnsignedLong(obj: *cpython.PyObject) callconv(.c) c_ulong {
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    return long_obj.lv_tag;
}

export fn PyLong_AsUnsignedLongLong(obj: *cpython.PyObject) callconv(.c) c_ulonglong {
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    return long_obj.lv_tag;
}

export fn PyLong_AsDouble(obj: *cpython.PyObject) callconv(.c) f64 {
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    const value: i64 = @bitCast(long_obj.lv_tag);
    return @floatFromInt(value);
}

export fn PyLong_AsSize_t(obj: *cpython.PyObject) callconv(.c) usize {
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    return long_obj.lv_tag;
}

export fn PyLong_AsSsize_t(obj: *cpython.PyObject) callconv(.c) isize {
    const long_obj = @as(*cpython.PyLongObject, @ptrCast(obj));
    const value: i64 = @bitCast(long_obj.lv_tag);
    return @intCast(value);
}

/// ============================================================================
/// TYPE CHECKING
/// ============================================================================

pub export fn PyLong_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyLong_Type) 1 else 0;
}

export fn PyLong_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyLong_Type) 1 else 0;
}

// ============================================================================
// TESTS
// ============================================================================

test "PyLong creation and conversion" {
    const obj = PyLong_FromLong(42);
    try std.testing.expect(obj != null);

    const value = PyLong_AsLong(obj.?);
    try std.testing.expectEqual(@as(c_long, 42), value);
}

test "PyLong small int cache" {
    const obj1 = PyLong_FromLong(100);
    const obj2 = PyLong_FromLong(100);

    // Should be same object from cache
    try std.testing.expectEqual(obj1, obj2);

    const obj3 = PyLong_FromLong(300);
    const obj4 = PyLong_FromLong(300);

    // Outside cache range, should be different
    try std.testing.expect(obj3 != obj4);
}

test "PyLong arithmetic" {
    const a = PyLong_FromLong(10);
    const b = PyLong_FromLong(5);

    const sum = long_add(a.?, b.?);
    try std.testing.expectEqual(@as(c_long, 15), PyLong_AsLong(sum.?));

    const diff = long_subtract(a.?, b.?);
    try std.testing.expectEqual(@as(c_long, 5), PyLong_AsLong(diff.?));

    const prod = long_multiply(a.?, b.?);
    try std.testing.expectEqual(@as(c_long, 50), PyLong_AsLong(prod.?));
}
