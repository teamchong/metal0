/// _decimal/decimal - Decimal object types
///
/// Implements CPython's Modules/_decimal/_decimal.c types
/// Provides PyDecObject, PyDecContextObject, etc.
///
/// Reference: cpython/Modules/_decimal/_decimal.c
const std = @import("std");
const cpython = @import("../../include/object.zig");
const mpdecimal = @import("mpdecimal.zig");

const allocator = mpdecimal.allocator;

// ============================================================================
// CONSTANTS
// ============================================================================

pub const _Py_DEC_MINALLOC: usize = 4;
pub const MPD_SPEC_VERSION: [:0]const u8 = "1.70";

// ============================================================================
// DECIMAL OBJECT
// ============================================================================

/// PyDecObject - Decimal number
/// Matches CPython's PyDecObject exactly
pub const PyDecObject = extern struct {
    ob_base: cpython.PyObject,
    hash: isize, // Cached hash value
    dec: mpdecimal.mpd_t, // Embedded mpd_t
    data: [_Py_DEC_MINALLOC]mpdecimal.mpd_uint_t, // Inline data for small decimals
};

// ============================================================================
// CONTEXT OBJECT
// ============================================================================

/// PyDecContextObject - Decimal context
/// Matches CPython's PyDecContextObject exactly
pub const PyDecContextObject = extern struct {
    ob_base: cpython.PyObject,
    ctx: mpdecimal.mpd_context_t, // The actual context
    traps: ?*cpython.PyObject, // Signal dict for traps
    flags: ?*cpython.PyObject, // Signal dict for flags
    capitals: c_int, // Use capital E in exponent
    tstate: ?*anyopaque, // PyThreadState*
    modstate: ?*decimal_state, // Module state pointer
};

// ============================================================================
// SIGNAL DICT OBJECT
// ============================================================================

/// PyDecSignalDictObject - Dict for signals
pub const PyDecSignalDictObject = extern struct {
    ob_base: cpython.PyObject,
    flags: ?*u32, // Pointer to status flags
};

// ============================================================================
// CONTEXT MANAGER
// ============================================================================

/// PyDecContextManagerObject - Context manager for localcontext()
pub const PyDecContextManagerObject = extern struct {
    ob_base: cpython.PyObject,
    local: ?*cpython.PyObject, // Local context
    global: ?*cpython.PyObject, // Previous context
};

// ============================================================================
// CONDITION MAP
// ============================================================================

/// DecCondMap - Maps condition names to flags
pub const DecCondMap = extern struct {
    name: ?[*:0]const u8, // condition or signal name
    fqname: ?[*:0]const u8, // fully qualified name
    flag: u32, // libmpdec flag
    ex: ?*cpython.PyObject, // corresponding exception
};

// ============================================================================
// MODULE STATE
// ============================================================================

/// decimal_state - Module state
pub const decimal_state = extern struct {
    PyDecContextManager_Type: ?*cpython.PyTypeObject,
    PyDecContext_Type: ?*cpython.PyTypeObject,
    PyDecSignalDictMixin_Type: ?*cpython.PyTypeObject,
    PyDec_Type: ?*cpython.PyTypeObject,
    PyDecSignalDict_Type: ?*cpython.PyTypeObject,
    DecimalTuple: ?*cpython.PyTypeObject,
    DecimalException: ?*cpython.PyObject,
    current_context_var: ?*cpython.PyObject,
    default_context_template: ?*cpython.PyObject,
    basic_context_template: ?*cpython.PyObject,
    extended_context_template: ?*cpython.PyObject,
    round_map: [mpdecimal.MPD_ROUND_GUARD]?*cpython.PyObject,
    Rational: ?*cpython.PyObject,
    PyDecimal: ?*cpython.PyObject,
    SignalTuple: ?*cpython.PyObject,
    signal_map: ?*DecCondMap,
    cond_map: ?*DecCondMap,
    _py_long_multiply: ?*anyopaque,
    _py_long_floor_divide: ?*anyopaque,
    _py_long_power: ?*anyopaque,
    _py_float_abs: ?*anyopaque,
    _py_long_bit_length: ?*anyopaque,
    _py_float_as_integer_ratio: ?*anyopaque,
};

/// Global module state
pub var _decimal_state: decimal_state = .{
    .PyDecContextManager_Type = null,
    .PyDecContext_Type = null,
    .PyDecSignalDictMixin_Type = null,
    .PyDec_Type = null,
    .PyDecSignalDict_Type = null,
    .DecimalTuple = null,
    .DecimalException = null,
    .current_context_var = null,
    .default_context_template = null,
    .basic_context_template = null,
    .extended_context_template = null,
    .round_map = .{null} ** mpdecimal.MPD_ROUND_GUARD,
    .Rational = null,
    .PyDecimal = null,
    .SignalTuple = null,
    .signal_map = null,
    .cond_map = null,
    ._py_long_multiply = null,
    ._py_long_floor_divide = null,
    ._py_long_power = null,
    ._py_float_abs = null,
    ._py_long_bit_length = null,
    ._py_float_as_integer_ratio = null,
};

// ============================================================================
// DECIMAL OBJECT METHODS
// ============================================================================

/// Dec_new - Create new Decimal
fn Dec_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyDecObject), @sizeOf(PyDecObject)) catch return null;
    const dec: *PyDecObject = @ptrCast(@alignCast(mem.ptr));

    dec.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = type_obj orelse &PyDec_Type },
        .hash = -1,
        .dec = .{
            .flags = 0,
            .exp = 0,
            .digits = 1,
            .len = 1,
            .alloc = _Py_DEC_MINALLOC,
            .data = &dec.data,
        },
        .data = .{0} ** _Py_DEC_MINALLOC,
    };

    return @ptrCast(dec);
}

/// Dec_dealloc - Destructor
fn Dec_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const dec: *PyDecObject = @ptrCast(@alignCast(self.?));

    // Free external data if not using inline buffer
    if (dec.dec.data != &dec.data and dec.dec.data != null) {
        if ((dec.dec.flags & mpdecimal.MPD_DATAFLAGS) == 0) {
            allocator.free(dec.dec.data.?[0..@intCast(dec.dec.alloc)]);
        }
    }

    const ptr: [*]u8 = @ptrCast(dec);
    allocator.free(ptr[0..@sizeOf(PyDecObject)]);
}

/// Dec_repr - String representation
fn Dec_repr(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    // Return "Decimal('value')"
    return null;
}

/// Dec_str - String conversion
fn Dec_str(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    // Return string representation of value
    return null;
}

/// Dec_hash - Hash function
fn Dec_hash(self: ?*cpython.PyObject) callconv(.c) isize {
    if (self == null) return -1;
    const dec: *PyDecObject = @ptrCast(@alignCast(self.?));

    if (dec.hash != -1) return dec.hash;

    // Compute and cache hash
    // For now return a placeholder
    dec.hash = 0;
    return dec.hash;
}

/// Dec_richcompare - Rich comparison
fn Dec_richcompare(self: ?*cpython.PyObject, other: ?*cpython.PyObject, op: c_int) callconv(.c) ?*cpython.PyObject {
    if (self == null or other == null) return null;
    _ = op;
    return null;
}

/// Dec_neg - Negation
fn Dec_neg(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

/// Dec_pos - Positive
fn Dec_pos(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

/// Dec_abs - Absolute value
fn Dec_abs(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

/// Dec_bool - Boolean conversion
fn Dec_bool(self: ?*cpython.PyObject) callconv(.c) c_int {
    if (self == null) return 0;
    const dec: *PyDecObject = @ptrCast(@alignCast(self.?));
    return if (mpdecimal.mpd_iszero(&dec.dec) != 0) 0 else 1;
}

/// Dec_add - Addition
fn Dec_add(self: ?*cpython.PyObject, other: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or other == null) return null;
    _ = self;
    _ = other;
    return null;
}

/// Dec_sub - Subtraction
fn Dec_sub(self: ?*cpython.PyObject, other: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or other == null) return null;
    _ = self;
    _ = other;
    return null;
}

/// Dec_mul - Multiplication
fn Dec_mul(self: ?*cpython.PyObject, other: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or other == null) return null;
    _ = self;
    _ = other;
    return null;
}

/// Dec_truediv - True division
fn Dec_truediv(self: ?*cpython.PyObject, other: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or other == null) return null;
    _ = self;
    _ = other;
    return null;
}

/// Dec_floordiv - Floor division
fn Dec_floordiv(self: ?*cpython.PyObject, other: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or other == null) return null;
    _ = self;
    _ = other;
    return null;
}

/// Dec_mod - Modulo
fn Dec_mod(self: ?*cpython.PyObject, other: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or other == null) return null;
    _ = self;
    _ = other;
    return null;
}

/// Dec_pow - Power
fn Dec_pow(base: ?*cpython.PyObject, exp: ?*cpython.PyObject, mod: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (base == null or exp == null) return null;
    _ = mod;
    return null;
}

// ============================================================================
// NUMBER METHODS
// ============================================================================

pub export var Dec_as_number: cpython.PyNumberMethods = .{
    .nb_add = Dec_add,
    .nb_subtract = Dec_sub,
    .nb_multiply = Dec_mul,
    .nb_remainder = Dec_mod,
    .nb_divmod = null,
    .nb_power = Dec_pow,
    .nb_negative = Dec_neg,
    .nb_positive = Dec_pos,
    .nb_absolute = Dec_abs,
    .nb_bool = Dec_bool,
    .nb_invert = null,
    .nb_lshift = null,
    .nb_rshift = null,
    .nb_and = null,
    .nb_xor = null,
    .nb_or = null,
    .nb_int = null,
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
    .nb_floor_divide = Dec_floordiv,
    .nb_true_divide = Dec_truediv,
    .nb_inplace_floor_divide = null,
    .nb_inplace_true_divide = null,
    .nb_index = null,
    .nb_matrix_multiply = null,
    .nb_inplace_matrix_multiply = null,
};

// ============================================================================
// METHOD TABLE
// ============================================================================

pub export var Dec_methods: [1]cpython.PyMethodDef = .{
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub export var PyDec_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "decimal.Decimal",
    .tp_basicsize = @sizeOf(PyDecObject),
    .tp_itemsize = 0,
    .tp_dealloc = Dec_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = Dec_repr,
    .tp_as_number = &Dec_as_number,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = Dec_hash,
    .tp_call = null,
    .tp_str = Dec_str,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "Decimal(value=\"0\", context=None)\n\nConstruct a new Decimal object.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = Dec_richcompare,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &Dec_methods,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = Dec_new,
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
