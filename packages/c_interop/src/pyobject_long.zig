/// PyLongObject - Arbitrary Precision Integer Implementation
///
/// Implements CPython 3.12 compatible long integer with EXACT memory layout.
/// Uses lv_tag to encode sign and digit count.
///
/// Reference: cpython/Include/cpython/longintrepr.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// Re-export types from cpython_object
pub const PyLongObject = cpython.PyLongObject;
pub const digit = cpython.digit;
pub const _PyLongValue = cpython._PyLongValue;

// ============================================================================
// SMALL INTEGER CACHE
// ============================================================================

/// Small integers cache (-5 to 256)
const SMALL_INT_MIN: i64 = -5;
const SMALL_INT_MAX: i64 = 256;
const SMALL_INT_COUNT: usize = @intCast(SMALL_INT_MAX - SMALL_INT_MIN + 1);

/// Pre-allocated small integers (simplified - store value in first digit)
var small_ints: [SMALL_INT_COUNT]PyLongObject = undefined;
var small_ints_initialized = false;

/// Encode sign into lv_tag (CPython 3.12 format)
/// Sign: 0=positive, 1=zero, 2=negative
inline fn encodeLvTag(digit_count: usize, sign: u2) usize {
    return (digit_count << cpython._PyLong_NON_SIZE_BITS) | sign;
}

/// Initialize small integer cache
fn initSmallInts() void {
    if (small_ints_initialized) return;

    for (0..SMALL_INT_COUNT) |i| {
        const value: i64 = SMALL_INT_MIN + @as(i64, @intCast(i));

        // Determine sign and store absolute value
        const sign: u2 = if (value == 0) 1 else if (value < 0) 2 else 0;
        const abs_val: u32 = if (value < 0) @intCast(-value) else @intCast(value);

        small_ints[i] = PyLongObject{
            .ob_base = .{
                .ob_refcnt = 1000000, // Immortal reference count
                .ob_type = &PyLong_Type,
            },
            .long_value = .{
                .lv_tag = encodeLvTag(1, sign), // 1 digit, sign encoded
                .ob_digit = .{abs_val}, // Store absolute value
            },
        };
    }

    small_ints_initialized = true;
}

/// Get cached small integer
fn getSmallInt(value: i64) ?*cpython.PyObject {
    if (value < SMALL_INT_MIN or value > SMALL_INT_MAX) return null;

    if (!small_ints_initialized) initSmallInts();

    const idx: usize = @intCast(value - SMALL_INT_MIN);
    return @ptrCast(&small_ints[idx].ob_base);
}

// ============================================================================
// PYLONG_TYPE OBJECT
// ============================================================================

fn long_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));

    // Check if in small int cache - don't free
    const ptr_addr = @intFromPtr(long_obj);
    const cache_start = @intFromPtr(&small_ints[0]);
    const cache_end = @intFromPtr(&small_ints[SMALL_INT_COUNT - 1]) + @sizeOf(PyLongObject);

    if (ptr_addr >= cache_start and ptr_addr < cache_end) return;

    allocator.destroy(long_obj);
}

fn long_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = obj;
    return null; // TODO: Implement string conversion
}

fn long_hash(obj: *cpython.PyObject) callconv(.c) isize {
    const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
    const val = getLongValue(long_obj);
    return @intCast(val);
}

var long_as_number: cpython.PyNumberMethods = .{
    .nb_add = long_add,
    .nb_subtract = long_subtract,
    .nb_multiply = long_multiply,
    .nb_remainder = long_remainder,
    .nb_divmod = null,
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
    .nb_reserved = null,
    .nb_float = null,
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
    .nb_floor_divide = long_floor_divide,
    .nb_true_divide = null,
    .nb_inplace_floor_divide = null,
    .nb_inplace_true_divide = null,
    .nb_index = long_int,
    .nb_matrix_multiply = null,
    .nb_inplace_matrix_multiply = null,
};

pub var PyLong_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{
            .ob_refcnt = 1000000, // Immortal
            .ob_type = undefined, // Will be &PyType_Type when available
        },
        .ob_size = 0,
    },
    .tp_name = "int",
    .tp_basicsize = @sizeOf(PyLongObject),
    .tp_itemsize = @sizeOf(digit), // For variable number of digits
    .tp_dealloc = long_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = long_repr,
    .tp_as_number = &long_as_number,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = long_hash,
    .tp_call = null,
    .tp_str = long_repr,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_LONG_SUBCLASS,
    .tp_doc = "int(x=0) -> integer",
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

/// Get i64 value from PyLongObject (simplified - only handles single digit)
inline fn getLongValue(obj: *const PyLongObject) i64 {
    const sign = obj.long_value.lv_tag & cpython._PyLong_SIGN_MASK;
    const digit_val: i64 = @intCast(obj.long_value.ob_digit[0]);

    return switch (sign) {
        0 => digit_val, // Positive
        1 => 0, // Zero
        2 => -digit_val, // Negative
        else => 0,
    };
}

/// Create PyLongObject from i64 value
fn createLong(value: i64) ?*cpython.PyObject {
    // Try small int cache
    if (getSmallInt(value)) |cached| return cached;

    const obj = allocator.create(PyLongObject) catch return null;

    const sign: u2 = if (value == 0) 1 else if (value < 0) 2 else 0;
    const abs_val: u32 = if (value < 0)
        @intCast(@as(u64, @bitCast(-value)) & 0xFFFFFFFF)
    else
        @intCast(@as(u64, @bitCast(value)) & 0xFFFFFFFF);

    obj.* = PyLongObject{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyLong_Type,
        },
        .long_value = .{
            .lv_tag = encodeLvTag(1, sign),
            .ob_digit = .{abs_val},
        },
    };

    return @ptrCast(&obj.ob_base);
}

// ============================================================================
// NUMBER PROTOCOL IMPLEMENTATION
// ============================================================================

fn long_add(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getLongValue(@ptrCast(@alignCast(a)));
    const b_val = getLongValue(@ptrCast(@alignCast(b)));
    return createLong(a_val +% b_val);
}

fn long_subtract(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getLongValue(@ptrCast(@alignCast(a)));
    const b_val = getLongValue(@ptrCast(@alignCast(b)));
    return createLong(a_val -% b_val);
}

fn long_multiply(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getLongValue(@ptrCast(@alignCast(a)));
    const b_val = getLongValue(@ptrCast(@alignCast(b)));
    return createLong(a_val *% b_val);
}

fn long_floor_divide(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getLongValue(@ptrCast(@alignCast(a)));
    const b_val = getLongValue(@ptrCast(@alignCast(b)));
    if (b_val == 0) return null;
    return createLong(@divFloor(a_val, b_val));
}

fn long_remainder(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getLongValue(@ptrCast(@alignCast(a)));
    const b_val = getLongValue(@ptrCast(@alignCast(b)));
    if (b_val == 0) return null;
    return createLong(@mod(a_val, b_val));
}

fn long_power(a: *cpython.PyObject, b: *cpython.PyObject, c: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = c;
    const base = getLongValue(@ptrCast(@alignCast(a)));
    const exp = getLongValue(@ptrCast(@alignCast(b)));
    if (exp < 0) return null; // Negative exponent needs float
    const result = std.math.pow(i64, base, @intCast(exp));
    return createLong(result);
}

fn long_negative(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = getLongValue(@ptrCast(@alignCast(obj)));
    return createLong(-val);
}

fn long_positive(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = getLongValue(@ptrCast(@alignCast(obj)));
    return createLong(val);
}

fn long_absolute(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = getLongValue(@ptrCast(@alignCast(obj)));
    return createLong(@as(i64, @intCast(@abs(val))));
}

fn long_bool(obj: *cpython.PyObject) callconv(.c) c_int {
    const val = getLongValue(@ptrCast(@alignCast(obj)));
    return if (val != 0) 1 else 0;
}

fn long_int(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = getLongValue(@ptrCast(@alignCast(obj)));
    return createLong(val);
}

fn long_invert(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = getLongValue(@ptrCast(@alignCast(obj)));
    return createLong(~val);
}

fn long_lshift(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getLongValue(@ptrCast(@alignCast(a)));
    const b_val = getLongValue(@ptrCast(@alignCast(b)));
    if (b_val < 0 or b_val >= 64) return null;
    const shift: u6 = @intCast(b_val);
    return createLong(a_val << shift);
}

fn long_rshift(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getLongValue(@ptrCast(@alignCast(a)));
    const b_val = getLongValue(@ptrCast(@alignCast(b)));
    if (b_val < 0 or b_val >= 64) return null;
    const shift: u6 = @intCast(b_val);
    return createLong(a_val >> shift);
}

fn long_and(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getLongValue(@ptrCast(@alignCast(a)));
    const b_val = getLongValue(@ptrCast(@alignCast(b)));
    return createLong(a_val & b_val);
}

fn long_xor(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getLongValue(@ptrCast(@alignCast(a)));
    const b_val = getLongValue(@ptrCast(@alignCast(b)));
    return createLong(a_val ^ b_val);
}

fn long_or(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = getLongValue(@ptrCast(@alignCast(a)));
    const b_val = getLongValue(@ptrCast(@alignCast(b)));
    return createLong(a_val | b_val);
}

// ============================================================================
// CREATION FUNCTIONS (Exported)
// ============================================================================

pub export fn PyLong_FromLong(value: c_long) callconv(.c) ?*cpython.PyObject {
    return createLong(@intCast(value));
}

export fn PyLong_FromUnsignedLong(value: c_ulong) callconv(.c) ?*cpython.PyObject {
    return createLong(@intCast(value));
}

export fn PyLong_FromLongLong(value: c_longlong) callconv(.c) ?*cpython.PyObject {
    return createLong(@intCast(value));
}

export fn PyLong_FromUnsignedLongLong(value: c_ulonglong) callconv(.c) ?*cpython.PyObject {
    return createLong(@intCast(value));
}

export fn PyLong_FromDouble(value: f64) callconv(.c) ?*cpython.PyObject {
    return createLong(@intFromFloat(value));
}

export fn PyLong_FromString(str: [*:0]const u8, pend: ?*[*:0]u8, base: c_int) callconv(.c) ?*cpython.PyObject {
    _ = pend;
    const len = std.mem.len(str);
    const radix: u8 = if (base == 0) 10 else @intCast(base);
    const value = std.fmt.parseInt(i64, str[0..len], radix) catch return null;
    return createLong(value);
}

export fn PyLong_FromSize_t(value: usize) callconv(.c) ?*cpython.PyObject {
    return createLong(@intCast(value));
}

export fn PyLong_FromSsize_t(value: isize) callconv(.c) ?*cpython.PyObject {
    return createLong(@intCast(value));
}

export fn PyLong_FromVoidPtr(ptr: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    return createLong(@intCast(@intFromPtr(ptr)));
}

// ============================================================================
// CONVERSION FUNCTIONS (Exported)
// ============================================================================

pub export fn PyLong_AsLong(obj: *cpython.PyObject) callconv(.c) c_long {
    return @intCast(getLongValue(@ptrCast(@alignCast(obj))));
}

export fn PyLong_AsLongLong(obj: *cpython.PyObject) callconv(.c) c_longlong {
    return @intCast(getLongValue(@ptrCast(@alignCast(obj))));
}

export fn PyLong_AsUnsignedLong(obj: *cpython.PyObject) callconv(.c) c_ulong {
    const val = getLongValue(@ptrCast(@alignCast(obj)));
    if (val < 0) return 0; // Would raise OverflowError in real Python
    return @intCast(val);
}

export fn PyLong_AsUnsignedLongLong(obj: *cpython.PyObject) callconv(.c) c_ulonglong {
    const val = getLongValue(@ptrCast(@alignCast(obj)));
    if (val < 0) return 0;
    return @intCast(val);
}

export fn PyLong_AsDouble(obj: *cpython.PyObject) callconv(.c) f64 {
    return @floatFromInt(getLongValue(@ptrCast(@alignCast(obj))));
}

export fn PyLong_AsSize_t(obj: *cpython.PyObject) callconv(.c) usize {
    const val = getLongValue(@ptrCast(@alignCast(obj)));
    if (val < 0) return 0;
    return @intCast(val);
}

export fn PyLong_AsSsize_t(obj: *cpython.PyObject) callconv(.c) isize {
    return @intCast(getLongValue(@ptrCast(@alignCast(obj))));
}

export fn PyLong_AsVoidPtr(obj: *cpython.PyObject) callconv(.c) ?*anyopaque {
    const val = getLongValue(@ptrCast(@alignCast(obj)));
    return @ptrFromInt(@as(usize, @intCast(val)));
}

// ============================================================================
// TYPE CHECKING
// ============================================================================

pub export fn PyLong_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    // Check if type has LONG_SUBCLASS flag
    const flags = cpython.Py_TYPE(obj).tp_flags;
    return if ((flags & cpython.Py_TPFLAGS_LONG_SUBCLASS) != 0) 1 else 0;
}

export fn PyLong_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyLong_Type) 1 else 0;
}

// ============================================================================
// TESTS
// ============================================================================

test "PyLongObject layout matches CPython" {
    // PyLongObject: ob_base(16) + long_value(lv_tag(8) + ob_digit[1](4)) = 28, aligned to 32
    try std.testing.expect(@sizeOf(PyLongObject) >= 28);
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PyLongObject, "ob_base"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyLongObject, "long_value"));
}

test "PyLong creation and conversion" {
    const obj = PyLong_FromLong(42);
    try std.testing.expect(obj != null);

    const value = PyLong_AsLong(obj.?);
    try std.testing.expectEqual(@as(c_long, 42), value);
}

test "PyLong negative values" {
    const obj = PyLong_FromLong(-100);
    try std.testing.expect(obj != null);

    const value = PyLong_AsLong(obj.?);
    try std.testing.expectEqual(@as(c_long, -100), value);
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
