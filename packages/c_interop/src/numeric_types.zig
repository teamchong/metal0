const std = @import("std");
const numeric_impl = @import("collections");

// Type configs for NumericImpl

const PyIntConfig = struct {
    pub const ValueType = i64;
    pub const name = "int";
    pub const is_integer = true;
    pub const is_complex = false;
    pub const is_signed = true;
    pub const min_value: i64 = std.math.minInt(i64);
    pub const max_value: i64 = std.math.maxInt(i64);
};

const PyInt32Config = struct {
    pub const ValueType = i32;
    pub const name = "int32";
    pub const is_integer = true;
    pub const is_complex = false;
    pub const is_signed = true;
    pub const min_value: i32 = std.math.minInt(i32);
    pub const max_value: i32 = std.math.maxInt(i32);
};

const PyInt16Config = struct {
    pub const ValueType = i16;
    pub const name = "int16";
    pub const is_integer = true;
    pub const is_complex = false;
    pub const is_signed = true;
    pub const min_value: i16 = std.math.minInt(i16);
    pub const max_value: i16 = std.math.maxInt(i16);
};

const PyInt8Config = struct {
    pub const ValueType = i8;
    pub const name = "int8";
    pub const is_integer = true;
    pub const is_complex = false;
    pub const is_signed = true;
    pub const min_value: i8 = std.math.minInt(i8);
    pub const max_value: i8 = std.math.maxInt(i8);
};

const PyFloatConfig = struct {
    pub const ValueType = f64;
    pub const name = "float";
    pub const is_integer = false;
    pub const is_complex = false;
    pub const is_signed = true;
    pub const min_value: f64 = -std.math.inf(f64);
    pub const max_value: f64 = std.math.inf(f64);
};

const PyFloat32Config = struct {
    pub const ValueType = f32;
    pub const name = "float32";
    pub const is_integer = false;
    pub const is_complex = false;
    pub const is_signed = true;
    pub const min_value: f32 = -std.math.inf(f32);
    pub const max_value: f32 = std.math.inf(f32);
};

const PyComplexConfig = struct {
    pub const ValueType = f64;
    pub const name = "complex";
    pub const is_integer = false;
    pub const is_complex = true;
    pub const is_signed = true;
    pub const min_value: f64 = -std.math.inf(f64);
    pub const max_value: f64 = std.math.inf(f64);
};

const PyBoolConfig = struct {
    pub const ValueType = i8;
    pub const name = "bool";
    pub const is_integer = true;
    pub const is_complex = false;
    pub const is_signed = false;
    pub const min_value: i8 = 0;
    pub const max_value: i8 = 1;
};

// Public numeric types using comptime instantiation
pub const PyInt = numeric_impl.NumericImpl(PyIntConfig);
pub const PyInt32 = numeric_impl.NumericImpl(PyInt32Config);
pub const PyInt16 = numeric_impl.NumericImpl(PyInt16Config);
pub const PyInt8 = numeric_impl.NumericImpl(PyInt8Config);
pub const PyFloat = numeric_impl.NumericImpl(PyFloatConfig);
pub const PyFloat32 = numeric_impl.NumericImpl(PyFloat32Config);
pub const PyComplex = numeric_impl.NumericImpl(PyComplexConfig);
pub const PyBool = numeric_impl.NumericImpl(PyBoolConfig);

// Python C API types (minimal definitions for compatibility)
pub const PyObject = extern struct {
    ob_refcnt: i64,
    ob_type: ?*PyTypeObject,
};

pub const PyVarObject = extern struct {
    ob_base: PyObject,
    ob_size: i64,
};

pub const PyTypeObject = extern struct {
    ob_base: PyVarObject,
    tp_name: [*:0]const u8,
    tp_basicsize: i64,
    tp_itemsize: i64,
    tp_dealloc: ?*const fn (?*PyObject) callconv(.C) void,
    tp_repr: ?*anyopaque,
    tp_as_number: ?*anyopaque,
    tp_as_sequence: ?*anyopaque,
    tp_as_mapping: ?*anyopaque,
    tp_hash: ?*anyopaque,
    tp_call: ?*anyopaque,
    tp_str: ?*anyopaque,
};

// Type objects for each numeric type
pub var PyInt_Type: PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "int",
    .tp_basicsize = @sizeOf(PyInt),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
};

pub var PyFloat_Type: PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "float",
    .tp_basicsize = @sizeOf(PyFloat),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
};

pub var PyComplex_Type: PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "complex",
    .tp_basicsize = @sizeOf(PyComplex),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
};

pub var PyBool_Type: PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "bool",
    .tp_basicsize = @sizeOf(PyBool),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
};

// Bool singletons (True/False are always the same object)
pub var Py_True: PyBool = undefined;
pub var Py_False: PyBool = undefined;

pub fn initBoolSingletons() void {
    Py_True = PyBool{
        .ob_base = .{ .ob_refcnt = 999999, .ob_type = &PyBool_Type },
        .value = 1,
        .imag = {},
    };

    Py_False = PyBool{
        .ob_base = .{ .ob_refcnt = 999999, .ob_type = &PyBool_Type },
        .value = 0,
        .imag = {},
    };
}

// C API exports

/// Create PyInt from long
export fn PyInt_FromLong(value: c_long) ?*PyObject {
    const allocator = std.heap.c_allocator;
    const int = PyInt.init(allocator, @intCast(value)) catch return null;
    return @ptrCast(int);
}

/// Extract long from PyInt
export fn PyInt_AsLong(obj: ?*PyObject) c_long {
    if (obj == null) return 0;
    const int: *PyInt = @ptrCast(@alignCast(obj.?));
    return @intCast(int.value);
}

/// Check if object is PyInt
export fn PyInt_Check(obj: ?*PyObject) c_int {
    if (obj == null) return 0;
    return if (obj.?.ob_type == &PyInt_Type) 1 else 0;
}

/// Create PyFloat from double
export fn PyFloat_FromDouble(value: f64) ?*PyObject {
    const allocator = std.heap.c_allocator;
    const float = PyFloat.init(allocator, value) catch return null;
    return @ptrCast(float);
}

/// Extract double from PyFloat
export fn PyFloat_AsDouble(obj: ?*PyObject) f64 {
    if (obj == null) return 0.0;
    const float: *PyFloat = @ptrCast(@alignCast(obj.?));
    return float.value;
}

/// Check if object is PyFloat
export fn PyFloat_Check(obj: ?*PyObject) c_int {
    if (obj == null) return 0;
    return if (obj.?.ob_type == &PyFloat_Type) 1 else 0;
}

/// Create PyComplex from doubles
export fn PyComplex_FromDoubles(real: f64, imag: f64) ?*PyObject {
    const allocator = std.heap.c_allocator;
    const complex = PyComplex.initComplex(allocator, real, imag) catch return null;
    return @ptrCast(complex);
}

/// Extract real part from PyComplex
export fn PyComplex_RealAsDouble(obj: ?*PyObject) f64 {
    if (obj == null) return 0.0;
    const complex: *PyComplex = @ptrCast(@alignCast(obj.?));
    return complex.value;
}

/// Extract imaginary part from PyComplex
export fn PyComplex_ImagAsDouble(obj: ?*PyObject) f64 {
    if (obj == null) return 0.0;
    const complex: *PyComplex = @ptrCast(@alignCast(obj.?));
    return complex.imag;
}

/// Create PyBool from long
export fn PyBool_FromLong(value: c_long) ?*PyObject {
    return if (value != 0) @ptrCast(&Py_True) else @ptrCast(&Py_False);
}

/// Generic number addition
export fn PyNumber_Add(a: ?*PyObject, b: ?*PyObject) ?*PyObject {
    if (a == null or b == null) return null;

    const allocator = std.heap.c_allocator;

    // Try PyInt
    if (PyInt_Check(a) == 1 and PyInt_Check(b) == 1) {
        const int_a: *PyInt = @ptrCast(@alignCast(a.?));
        const int_b: *PyInt = @ptrCast(@alignCast(b.?));
        const result = int_a.add(int_b);
        const new_int = PyInt.init(allocator, result) catch return null;
        return @ptrCast(new_int);
    }

    // Try PyFloat
    if (PyFloat_Check(a) == 1 and PyFloat_Check(b) == 1) {
        const float_a: *PyFloat = @ptrCast(@alignCast(a.?));
        const float_b: *PyFloat = @ptrCast(@alignCast(b.?));
        const result = float_a.add(float_b);
        const new_float = PyFloat.init(allocator, result) catch return null;
        return @ptrCast(new_float);
    }

    return null;
}

/// Generic number subtraction
export fn PyNumber_Subtract(a: ?*PyObject, b: ?*PyObject) ?*PyObject {
    if (a == null or b == null) return null;

    const allocator = std.heap.c_allocator;

    if (PyInt_Check(a) == 1 and PyInt_Check(b) == 1) {
        const int_a: *PyInt = @ptrCast(@alignCast(a.?));
        const int_b: *PyInt = @ptrCast(@alignCast(b.?));
        const result = int_a.sub(int_b);
        const new_int = PyInt.init(allocator, result) catch return null;
        return @ptrCast(new_int);
    }

    if (PyFloat_Check(a) == 1 and PyFloat_Check(b) == 1) {
        const float_a: *PyFloat = @ptrCast(@alignCast(a.?));
        const float_b: *PyFloat = @ptrCast(@alignCast(b.?));
        const result = float_a.sub(float_b);
        const new_float = PyFloat.init(allocator, result) catch return null;
        return @ptrCast(new_float);
    }

    return null;
}

/// Generic number multiplication
export fn PyNumber_Multiply(a: ?*PyObject, b: ?*PyObject) ?*PyObject {
    if (a == null or b == null) return null;

    const allocator = std.heap.c_allocator;

    if (PyInt_Check(a) == 1 and PyInt_Check(b) == 1) {
        const int_a: *PyInt = @ptrCast(@alignCast(a.?));
        const int_b: *PyInt = @ptrCast(@alignCast(b.?));
        const result = int_a.mul(int_b);
        const new_int = PyInt.init(allocator, result) catch return null;
        return @ptrCast(new_int);
    }

    if (PyFloat_Check(a) == 1 and PyFloat_Check(b) == 1) {
        const float_a: *PyFloat = @ptrCast(@alignCast(a.?));
        const float_b: *PyFloat = @ptrCast(@alignCast(b.?));
        const result = float_a.mul(float_b);
        const new_float = PyFloat.init(allocator, result) catch return null;
        return @ptrCast(new_float);
    }

    return null;
}

/// Generic number division
export fn PyNumber_Divide(a: ?*PyObject, b: ?*PyObject) ?*PyObject {
    if (a == null or b == null) return null;

    const allocator = std.heap.c_allocator;

    if (PyInt_Check(a) == 1 and PyInt_Check(b) == 1) {
        const int_a: *PyInt = @ptrCast(@alignCast(a.?));
        const int_b: *PyInt = @ptrCast(@alignCast(b.?));
        if (int_b.value == 0) return null; // Division by zero
        const result = int_a.div(int_b);
        const new_int = PyInt.init(allocator, result) catch return null;
        return @ptrCast(new_int);
    }

    if (PyFloat_Check(a) == 1 and PyFloat_Check(b) == 1) {
        const float_a: *PyFloat = @ptrCast(@alignCast(a.?));
        const float_b: *PyFloat = @ptrCast(@alignCast(b.?));
        if (float_b.value == 0.0) return null; // Division by zero
        const result = float_a.div(float_b);
        const new_float = PyFloat.init(allocator, result) catch return null;
        return @ptrCast(new_float);
    }

    return null;
}
