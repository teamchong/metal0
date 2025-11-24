/// Python float object implementation
///
/// Simple f64 wrapper with number protocol support

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

/// PyFloatObject - Python float (wraps f64)
pub const PyFloatObject = extern struct {
    ob_base: cpython.PyObject,
    ob_fval: f64,
};

// Forward declarations
fn float_dealloc(obj: *cpython.PyObject) callconv(.c) void;
fn float_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_str(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_hash(obj: *cpython.PyObject) callconv(.c) isize;

// Number protocol methods
fn float_add(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_subtract(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_multiply(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_divide(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_remainder(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_divmod(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_power(a: *cpython.PyObject, b: *cpython.PyObject, c: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_negative(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_positive(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_absolute(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_bool(obj: *cpython.PyObject) callconv(.c) c_int;
fn float_int(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn float_float(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;

/// Number protocol for floats
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
    .nb_int = float_int,
    .nb_float = float_float,
    .nb_floor_divide = float_divide, // Use same as true divide for now
    .nb_true_divide = float_divide,
    // Other methods null
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
    .nb_inplace_floor_divide = null,
    .nb_inplace_true_divide = null,
    .nb_index = null,
    .nb_matrix_multiply = null,
    .nb_inplace_matrix_multiply = null,
    .nb_lshift = null,
    .nb_rshift = null,
    .nb_and = null,
    .nb_xor = null,
    .nb_or = null,
    .nb_invert = null,
};

/// PyFloat_Type - the 'float' type
pub var PyFloat_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, // Will be set to &PyType_Type
        .ob_size = 0,
    },
    .tp_name = "float",
    .tp_basicsize = @sizeOf(PyFloatObject),
    .tp_itemsize = 0,
    .tp_dealloc = float_dealloc,
    .tp_repr = float_repr,
    .tp_as_number = &float_as_number,
    .tp_hash = float_hash,
    .tp_str = float_str,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "float(x) -> floating point number",
    // Other slots null
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_call = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
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

// ============================================================================
// Core API Functions
// ============================================================================

/// Create float from double
export fn PyFloat_FromDouble(value: f64) callconv(.c) ?*cpython.PyObject {
    const obj = allocator.create(PyFloatObject) catch return null;
    
    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyFloat_Type;
    obj.ob_fval = value;
    
    return @ptrCast(&obj.ob_base);
}

/// Get double from float object
export fn PyFloat_AsDouble(obj: *cpython.PyObject) callconv(.c) f64 {
    if (PyFloat_Check(obj) == 0) return -1.0;
    
    const float_obj = @as(*PyFloatObject, @ptrCast(obj));
    return float_obj.ob_fval;
}

/// Type check - is this a float?
export fn PyFloat_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj == &PyFloat_Type) 1 else 0;
}

/// Type check - exact float type?
export fn PyFloat_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj == &PyFloat_Type) 1 else 0;
}

/// Get float info
export fn PyFloat_GetInfo() callconv(.c) ?*cpython.PyObject {
    // TODO: Return sys.float_info object
    return null;
}

/// Get max float value
export fn PyFloat_GetMax() callconv(.c) f64 {
    return std.math.floatMax(f64);
}

/// Get min float value
export fn PyFloat_GetMin() callconv(.c) f64 {
    return std.math.floatMin(f64);
}

/// Create float from string
export fn PyFloat_FromString(str: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // TODO: Parse string to float
    _ = str;
    return null;
}

// ============================================================================
// Number Protocol Implementation
// ============================================================================

fn float_add(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = PyFloat_AsDouble(a);
    const b_val = PyFloat_AsDouble(b);
    return PyFloat_FromDouble(a_val + b_val);
}

fn float_subtract(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = PyFloat_AsDouble(a);
    const b_val = PyFloat_AsDouble(b);
    return PyFloat_FromDouble(a_val - b_val);
}

fn float_multiply(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = PyFloat_AsDouble(a);
    const b_val = PyFloat_AsDouble(b);
    return PyFloat_FromDouble(a_val * b_val);
}

fn float_divide(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = PyFloat_AsDouble(a);
    const b_val = PyFloat_AsDouble(b);
    
    if (b_val == 0.0) {
        // TODO: Set ZeroDivisionError
        return null;
    }
    
    return PyFloat_FromDouble(a_val / b_val);
}

fn float_remainder(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = PyFloat_AsDouble(a);
    const b_val = PyFloat_AsDouble(b);
    
    if (b_val == 0.0) {
        return null;
    }
    
    return PyFloat_FromDouble(@mod(a_val, b_val));
}

fn float_divmod(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_val = PyFloat_AsDouble(a);
    const b_val = PyFloat_AsDouble(b);
    
    if (b_val == 0.0) {
        return null;
    }
    
    const div = @floor(a_val / b_val);
    const mod = a_val - (div * b_val);
    
    // TODO: Return tuple (div, mod)
    _ = div;
    _ = mod;
    return null;
}

fn float_power(a: *cpython.PyObject, b: *cpython.PyObject, c: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = c; // Modulo not supported for floats
    
    const a_val = PyFloat_AsDouble(a);
    const b_val = PyFloat_AsDouble(b);
    
    const result = std.math.pow(f64, a_val, b_val);
    return PyFloat_FromDouble(result);
}

fn float_negative(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = PyFloat_AsDouble(obj);
    return PyFloat_FromDouble(-val);
}

fn float_positive(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = PyFloat_AsDouble(obj);
    return PyFloat_FromDouble(val);
}

fn float_absolute(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = PyFloat_AsDouble(obj);
    return PyFloat_FromDouble(@abs(val));
}

fn float_bool(obj: *cpython.PyObject) callconv(.c) c_int {
    const val = PyFloat_AsDouble(obj);
    return if (val != 0.0) 1 else 0;
}

fn float_int(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const val = PyFloat_AsDouble(obj);
    // TODO: Call PyLong_FromDouble(val)
    _ = val;
    return null;
}

fn float_float(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Already a float, just incref
    obj.ob_refcnt += 1;
    return obj;
}

// ============================================================================
// Type Methods
// ============================================================================

fn float_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    allocator.destroy(@as(*PyFloatObject, @ptrCast(obj)));
}

fn float_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const float_obj = @as(*PyFloatObject, @ptrCast(obj));
    // TODO: Format as string and return PyUnicodeObject
    _ = float_obj;
    return null;
}

fn float_str(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return float_repr(obj);
}

fn float_hash(obj: *cpython.PyObject) callconv(.c) isize {
    const float_obj = @as(*PyFloatObject, @ptrCast(obj));
    // Simple hash: reinterpret bits as integer
    const bits: u64 = @bitCast(float_obj.ob_fval);
    return @intCast(bits);
}

// Tests
test "float exports" {
    _ = PyFloat_FromDouble;
    _ = PyFloat_AsDouble;
    _ = PyFloat_Check;
}
