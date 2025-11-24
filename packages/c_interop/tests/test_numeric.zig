const std = @import("std");
const testing = std.testing;

// Import collections (includes numeric_impl)
const collections = @import("collections");
const numeric_impl = collections.numeric_impl;

// Import numeric_types from source directory
const numeric_types = struct {
    pub const PyInt = numeric_impl.NumericImpl(PyIntConfig);
    pub const PyInt32 = numeric_impl.NumericImpl(PyInt32Config);
    pub const PyInt16 = numeric_impl.NumericImpl(PyInt16Config);
    pub const PyInt8 = numeric_impl.NumericImpl(PyInt8Config);
    pub const PyFloat = numeric_impl.NumericImpl(PyFloatConfig);
    pub const PyFloat32 = numeric_impl.NumericImpl(PyFloat32Config);
    pub const PyComplex = numeric_impl.NumericImpl(PyComplexConfig);
    pub const PyBool = numeric_impl.NumericImpl(PyBoolConfig);

    pub var Py_True: PyBool = undefined;
    pub var Py_False: PyBool = undefined;

    pub fn initBoolSingletons() void {
        Py_True = PyBool{
            .ob_base = .{ .ob_refcnt = 999999, .ob_type = null },
            .value = 1,
            .imag = {},
        };
        Py_False = PyBool{
            .ob_base = .{ .ob_refcnt = 999999, .ob_type = null },
            .value = 0,
            .imag = {},
        };
    }

    pub const PyObject = struct {
        ob_refcnt: i64,
        ob_type: ?*anyopaque,
    };

    pub fn PyInt_FromLong(value: c_long) ?*PyObject {
        const allocator = std.heap.c_allocator;
        const int = PyInt.init(allocator, @intCast(value)) catch return null;
        return @ptrCast(int);
    }

    pub fn PyInt_AsLong(obj: ?*PyObject) c_long {
        if (obj == null) return 0;
        const int: *PyInt = @ptrCast(@alignCast(obj.?));
        return @intCast(int.value);
    }

    pub fn PyFloat_FromDouble(value: f64) ?*PyObject {
        const allocator = std.heap.c_allocator;
        const float = PyFloat.init(allocator, value) catch return null;
        return @ptrCast(float);
    }

    pub fn PyFloat_AsDouble(obj: ?*PyObject) f64 {
        if (obj == null) return 0.0;
        const float: *PyFloat = @ptrCast(@alignCast(obj.?));
        return float.value;
    }

    pub fn PyComplex_FromDoubles(real: f64, imag: f64) ?*PyObject {
        const allocator = std.heap.c_allocator;
        const complex = PyComplex.initComplex(allocator, real, imag) catch return null;
        return @ptrCast(complex);
    }

    pub fn PyComplex_RealAsDouble(obj: ?*PyObject) f64 {
        if (obj == null) return 0.0;
        const complex: *PyComplex = @ptrCast(@alignCast(obj.?));
        return complex.value;
    }

    pub fn PyComplex_ImagAsDouble(obj: ?*PyObject) f64 {
        if (obj == null) return 0.0;
        const complex: *PyComplex = @ptrCast(@alignCast(obj.?));
        return complex.imag;
    }

    pub fn PyBool_FromLong(value: c_long) ?*PyObject {
        return if (value != 0) @ptrCast(&Py_True) else @ptrCast(&Py_False);
    }

    pub fn PyNumber_Add(a: ?*PyObject, b: ?*PyObject) ?*PyObject {
        if (a == null or b == null) return null;
        const allocator = std.heap.c_allocator;
        const int_a: *PyInt = @ptrCast(@alignCast(a.?));
        const int_b: *PyInt = @ptrCast(@alignCast(b.?));
        const result = int_a.add(int_b);
        const new_int = PyInt.init(allocator, result) catch return null;
        return @ptrCast(new_int);
    }

    pub fn PyNumber_Subtract(a: ?*PyObject, b: ?*PyObject) ?*PyObject {
        if (a == null or b == null) return null;
        const allocator = std.heap.c_allocator;
        const int_a: *PyInt = @ptrCast(@alignCast(a.?));
        const int_b: *PyInt = @ptrCast(@alignCast(b.?));
        const result = int_a.sub(int_b);
        const new_int = PyInt.init(allocator, result) catch return null;
        return @ptrCast(new_int);
    }

    pub fn PyNumber_Multiply(a: ?*PyObject, b: ?*PyObject) ?*PyObject {
        if (a == null or b == null) return null;
        const allocator = std.heap.c_allocator;
        const int_a: *PyInt = @ptrCast(@alignCast(a.?));
        const int_b: *PyInt = @ptrCast(@alignCast(b.?));
        const result = int_a.mul(int_b);
        const new_int = PyInt.init(allocator, result) catch return null;
        return @ptrCast(new_int);
    }

    pub fn PyNumber_Divide(a: ?*PyObject, b: ?*PyObject) ?*PyObject {
        if (a == null or b == null) return null;
        const allocator = std.heap.c_allocator;
        const int_a: *PyInt = @ptrCast(@alignCast(a.?));
        const int_b: *PyInt = @ptrCast(@alignCast(b.?));
        if (int_b.value == 0) return null;
        const result = int_a.div(int_b);
        const new_int = PyInt.init(allocator, result) catch return null;
        return @ptrCast(new_int);
    }
};

// Type configs
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

test "PyInt - basic arithmetic" {
    const PyInt = numeric_types.PyInt;
    var a = try PyInt.init(testing.allocator, 10);
    defer a.deinit(testing.allocator);

    var b = try PyInt.init(testing.allocator, 3);
    defer b.deinit(testing.allocator);

    try testing.expectEqual(@as(i64, 13), a.add(b));
    try testing.expectEqual(@as(i64, 7), a.sub(b));
    try testing.expectEqual(@as(i64, 30), a.mul(b));
    try testing.expectEqual(@as(i64, 3), a.div(b));
    try testing.expectEqual(@as(i64, 1), a.mod(b));
}

test "PyInt - bitwise operations" {
    const PyInt = numeric_types.PyInt;
    var a = try PyInt.init(testing.allocator, 12);
    defer a.deinit(testing.allocator);

    var b = try PyInt.init(testing.allocator, 5);
    defer b.deinit(testing.allocator);

    try testing.expectEqual(@as(i64, 4), a.bitwiseAnd(b)); // 12 & 5 = 4
    try testing.expectEqual(@as(i64, 13), a.bitwiseOr(b)); // 12 | 5 = 13
    try testing.expectEqual(@as(i64, 9), a.bitwiseXor(b)); // 12 ^ 5 = 9
    try testing.expectEqual(@as(i64, ~@as(i64, 12)), a.bitwiseNot()); // ~12
    try testing.expectEqual(@as(i64, 24), a.shiftLeft(1)); // 12 << 1 = 24
    try testing.expectEqual(@as(i64, 6), a.shiftRight(1)); // 12 >> 1 = 6
}

test "PyInt - comparison" {
    const PyInt = numeric_types.PyInt;
    var a = try PyInt.init(testing.allocator, 10);
    defer a.deinit(testing.allocator);

    var b = try PyInt.init(testing.allocator, 5);
    defer b.deinit(testing.allocator);

    var c = try PyInt.init(testing.allocator, 10);
    defer c.deinit(testing.allocator);

    try testing.expectEqual(@as(i8, 1), a.compare(b)); // 10 > 5
    try testing.expectEqual(@as(i8, 0), a.compare(c)); // 10 == 10
    try testing.expectEqual(@as(i8, -1), b.compare(a)); // 5 < 10

    try testing.expect(a.eql(c));
    try testing.expect(!a.eql(b));
}

test "PyInt - negation and absolute value" {
    const PyInt = numeric_types.PyInt;
    var a = try PyInt.init(testing.allocator, -42);
    defer a.deinit(testing.allocator);

    try testing.expectEqual(@as(i64, 42), a.neg());
    try testing.expectEqual(@as(i64, 42), a.abs());

    var b = try PyInt.init(testing.allocator, 42);
    defer b.deinit(testing.allocator);

    try testing.expectEqual(@as(i64, -42), b.neg());
    try testing.expectEqual(@as(i64, 42), b.abs());
}

test "PyInt - hash" {
    const PyInt = numeric_types.PyInt;
    var a = try PyInt.init(testing.allocator, 42);
    defer a.deinit(testing.allocator);

    const hash_val = a.hash();
    try testing.expectEqual(@as(u64, 42), hash_val);
}

test "PyInt - string conversion" {
    const PyInt = numeric_types.PyInt;
    var a = try PyInt.init(testing.allocator, 42);
    defer a.deinit(testing.allocator);

    const str = try a.toString(testing.allocator);
    defer testing.allocator.free(str);

    try testing.expectEqualStrings("42", str);
}

test "PyFloat - basic arithmetic" {
    const PyFloat = numeric_types.PyFloat;
    var a = try PyFloat.init(testing.allocator, 10.5);
    defer a.deinit(testing.allocator);

    var b = try PyFloat.init(testing.allocator, 2.5);
    defer b.deinit(testing.allocator);

    try testing.expectEqual(@as(f64, 13.0), a.add(b));
    try testing.expectEqual(@as(f64, 8.0), a.sub(b));
    try testing.expectEqual(@as(f64, 26.25), a.mul(b));
    try testing.expectApproxEqRel(@as(f64, 4.2), a.div(b), 0.0001);
}

test "PyFloat - comparison" {
    const PyFloat = numeric_types.PyFloat;
    var a = try PyFloat.init(testing.allocator, 10.5);
    defer a.deinit(testing.allocator);

    var b = try PyFloat.init(testing.allocator, 5.5);
    defer b.deinit(testing.allocator);

    var c = try PyFloat.init(testing.allocator, 10.5);
    defer c.deinit(testing.allocator);

    try testing.expectEqual(@as(i8, 1), a.compare(b));
    try testing.expectEqual(@as(i8, 0), a.compare(c));
    try testing.expectEqual(@as(i8, -1), b.compare(a));

    try testing.expect(a.eql(c));
    try testing.expect(!a.eql(b));
}

test "PyFloat - negation and absolute value" {
    const PyFloat = numeric_types.PyFloat;
    var a = try PyFloat.init(testing.allocator, -3.14);
    defer a.deinit(testing.allocator);

    try testing.expectApproxEqRel(@as(f64, 3.14), a.neg(), 0.0001);
    try testing.expectApproxEqRel(@as(f64, 3.14), a.abs(), 0.0001);
}

test "PyFloat - string conversion" {
    const PyFloat = numeric_types.PyFloat;
    var a = try PyFloat.init(testing.allocator, 3.14);
    defer a.deinit(testing.allocator);

    const str = try a.toString(testing.allocator);
    defer testing.allocator.free(str);

    try testing.expect(std.mem.startsWith(u8, str, "3.14"));
}

test "PyComplex - creation" {
    const PyComplex = numeric_types.PyComplex;
    var c = try PyComplex.initComplex(testing.allocator, 3.0, 4.0);
    defer c.deinit(testing.allocator);

    try testing.expectEqual(@as(f64, 3.0), c.value);
    try testing.expectEqual(@as(f64, 4.0), c.imag);
}

test "PyComplex - addition" {
    const PyComplex = numeric_types.PyComplex;
    var a = try PyComplex.initComplex(testing.allocator, 3.0, 4.0);
    defer a.deinit(testing.allocator);

    var b = try PyComplex.initComplex(testing.allocator, 1.0, 2.0);
    defer b.deinit(testing.allocator);

    const sum = a.addComplex(b);
    try testing.expectEqual(@as(f64, 4.0), sum.real);
    try testing.expectEqual(@as(f64, 6.0), sum.imag);
}

test "PyComplex - subtraction" {
    const PyComplex = numeric_types.PyComplex;
    var a = try PyComplex.initComplex(testing.allocator, 3.0, 4.0);
    defer a.deinit(testing.allocator);

    var b = try PyComplex.initComplex(testing.allocator, 1.0, 2.0);
    defer b.deinit(testing.allocator);

    const diff = a.subComplex(b);
    try testing.expectEqual(@as(f64, 2.0), diff.real);
    try testing.expectEqual(@as(f64, 2.0), diff.imag);
}

test "PyComplex - multiplication" {
    const PyComplex = numeric_types.PyComplex;
    var a = try PyComplex.initComplex(testing.allocator, 3.0, 4.0);
    defer a.deinit(testing.allocator);

    var b = try PyComplex.initComplex(testing.allocator, 1.0, 2.0);
    defer b.deinit(testing.allocator);

    // (3+4i)(1+2i) = (3-8) + (6+4)i = -5 + 10i
    const prod = a.mulComplex(b);
    try testing.expectEqual(@as(f64, -5.0), prod.real);
    try testing.expectEqual(@as(f64, 10.0), prod.imag);
}

test "PyComplex - division" {
    const PyComplex = numeric_types.PyComplex;
    var a = try PyComplex.initComplex(testing.allocator, 4.0, 2.0);
    defer a.deinit(testing.allocator);

    var b = try PyComplex.initComplex(testing.allocator, 2.0, 0.0);
    defer b.deinit(testing.allocator);

    // (4+2i)/(2+0i) = 2 + 1i
    const quot = a.divComplex(b);
    try testing.expectApproxEqRel(@as(f64, 2.0), quot.real, 0.0001);
    try testing.expectApproxEqRel(@as(f64, 1.0), quot.imag, 0.0001);
}

test "PyComplex - absolute value" {
    const PyComplex = numeric_types.PyComplex;
    var c = try PyComplex.initComplex(testing.allocator, 3.0, 4.0);
    defer c.deinit(testing.allocator);

    // |3+4i| = sqrt(9+16) = 5
    try testing.expectApproxEqRel(@as(f64, 5.0), c.absComplex(), 0.0001);
}

test "PyComplex - negation" {
    const PyComplex = numeric_types.PyComplex;
    var c = try PyComplex.initComplex(testing.allocator, 3.0, 4.0);
    defer c.deinit(testing.allocator);

    const neg = c.negComplex();
    try testing.expectEqual(@as(f64, -3.0), neg.real);
    try testing.expectEqual(@as(f64, -4.0), neg.imag);
}

test "PyComplex - string conversion" {
    const PyComplex = numeric_types.PyComplex;
    var c = try PyComplex.initComplex(testing.allocator, 3.0, 4.0);
    defer c.deinit(testing.allocator);

    const str = try c.toString(testing.allocator);
    defer testing.allocator.free(str);

    try testing.expect(std.mem.indexOf(u8, str, "3") != null);
    try testing.expect(std.mem.indexOf(u8, str, "4") != null);
}

test "PyBool - singletons" {
    numeric_types.initBoolSingletons();

    try testing.expectEqual(@as(i8, 1), numeric_types.Py_True.value);
    try testing.expectEqual(@as(i8, 0), numeric_types.Py_False.value);

    // Singletons have high refcount (immortal)
    try testing.expect(numeric_types.Py_True.ob_base.ob_refcnt > 1000);
    try testing.expect(numeric_types.Py_False.ob_base.ob_refcnt > 1000);
}

test "Size optimization - comptime conditional fields" {
    const PyInt = numeric_types.PyInt;
    const PyFloat = numeric_types.PyFloat;
    const PyComplex = numeric_types.PyComplex;

    const int_size = @sizeOf(PyInt);
    const float_size = @sizeOf(PyFloat);
    const complex_size = @sizeOf(PyComplex);

    // Complex should be larger (has imag field)
    try testing.expect(complex_size > int_size);
    try testing.expect(complex_size > float_size);
}

test "C API - PyInt_FromLong/PyInt_AsLong" {
    const PyInt = numeric_types.PyInt;
    const obj = numeric_types.PyInt_FromLong(42);
    try testing.expect(obj != null);

    const val = numeric_types.PyInt_AsLong(obj);
    try testing.expectEqual(@as(c_long, 42), val);

    // Cleanup
    const int: *PyInt = @ptrCast(@alignCast(obj.?));
    int.deinit(std.heap.c_allocator);
}

test "C API - PyFloat_FromDouble/PyFloat_AsDouble" {
    const PyFloat = numeric_types.PyFloat;
    const obj = numeric_types.PyFloat_FromDouble(3.14);
    try testing.expect(obj != null);

    const val = numeric_types.PyFloat_AsDouble(obj);
    try testing.expectApproxEqRel(@as(f64, 3.14), val, 0.0001);

    // Cleanup
    const float: *PyFloat = @ptrCast(@alignCast(obj.?));
    float.deinit(std.heap.c_allocator);
}

test "C API - PyComplex_FromDoubles" {
    const PyComplex = numeric_types.PyComplex;
    const obj = numeric_types.PyComplex_FromDoubles(3.0, 4.0);
    try testing.expect(obj != null);

    const real = numeric_types.PyComplex_RealAsDouble(obj);
    const imag = numeric_types.PyComplex_ImagAsDouble(obj);

    try testing.expectEqual(@as(f64, 3.0), real);
    try testing.expectEqual(@as(f64, 4.0), imag);

    // Cleanup
    const complex: *PyComplex = @ptrCast(@alignCast(obj.?));
    complex.deinit(std.heap.c_allocator);
}

test "C API - PyBool_FromLong" {
    const true_obj = numeric_types.PyBool_FromLong(1);
    const false_obj = numeric_types.PyBool_FromLong(0);

    try testing.expect(true_obj == @as(*numeric_types.PyObject, @ptrCast(&numeric_types.Py_True)));
    try testing.expect(false_obj == @as(*numeric_types.PyObject, @ptrCast(&numeric_types.Py_False)));
}

test "C API - PyNumber_Add (int)" {
    const PyInt = numeric_types.PyInt;
    const a = numeric_types.PyInt_FromLong(10);
    const b = numeric_types.PyInt_FromLong(5);

    const result = numeric_types.PyNumber_Add(a, b);
    try testing.expect(result != null);

    const val = numeric_types.PyInt_AsLong(result);
    try testing.expectEqual(@as(c_long, 15), val);

    // Cleanup
    const int_a: *PyInt = @ptrCast(@alignCast(a.?));
    const int_b: *PyInt = @ptrCast(@alignCast(b.?));
    const int_result: *PyInt = @ptrCast(@alignCast(result.?));
    int_a.deinit(std.heap.c_allocator);
    int_b.deinit(std.heap.c_allocator);
    int_result.deinit(std.heap.c_allocator);
}

test "C API - PyNumber_Add (float)" {
    const PyFloat = numeric_types.PyFloat;
    const a = numeric_types.PyFloat_FromDouble(10.5);
    const b = numeric_types.PyFloat_FromDouble(2.5);

    const result = numeric_types.PyNumber_Add(a, b);
    try testing.expect(result != null);

    const val = numeric_types.PyFloat_AsDouble(result);
    try testing.expectApproxEqRel(@as(f64, 13.0), val, 0.0001);

    // Cleanup
    const float_a: *PyFloat = @ptrCast(@alignCast(a.?));
    const float_b: *PyFloat = @ptrCast(@alignCast(b.?));
    const float_result: *PyFloat = @ptrCast(@alignCast(result.?));
    float_a.deinit(std.heap.c_allocator);
    float_b.deinit(std.heap.c_allocator);
    float_result.deinit(std.heap.c_allocator);
}

test "C API - PyNumber_Subtract (int)" {
    const PyInt = numeric_types.PyInt;
    const a = numeric_types.PyInt_FromLong(10);
    const b = numeric_types.PyInt_FromLong(5);

    const result = numeric_types.PyNumber_Subtract(a, b);
    try testing.expect(result != null);

    const val = numeric_types.PyInt_AsLong(result);
    try testing.expectEqual(@as(c_long, 5), val);

    // Cleanup
    const int_a: *PyInt = @ptrCast(@alignCast(a.?));
    const int_b: *PyInt = @ptrCast(@alignCast(b.?));
    const int_result: *PyInt = @ptrCast(@alignCast(result.?));
    int_a.deinit(std.heap.c_allocator);
    int_b.deinit(std.heap.c_allocator);
    int_result.deinit(std.heap.c_allocator);
}

test "C API - PyNumber_Multiply (int)" {
    const PyInt = numeric_types.PyInt;
    const a = numeric_types.PyInt_FromLong(10);
    const b = numeric_types.PyInt_FromLong(5);

    const result = numeric_types.PyNumber_Multiply(a, b);
    try testing.expect(result != null);

    const val = numeric_types.PyInt_AsLong(result);
    try testing.expectEqual(@as(c_long, 50), val);

    // Cleanup
    const int_a: *PyInt = @ptrCast(@alignCast(a.?));
    const int_b: *PyInt = @ptrCast(@alignCast(b.?));
    const int_result: *PyInt = @ptrCast(@alignCast(result.?));
    int_a.deinit(std.heap.c_allocator);
    int_b.deinit(std.heap.c_allocator);
    int_result.deinit(std.heap.c_allocator);
}

test "C API - PyNumber_Divide (int)" {
    const PyInt = numeric_types.PyInt;
    const a = numeric_types.PyInt_FromLong(10);
    const b = numeric_types.PyInt_FromLong(5);

    const result = numeric_types.PyNumber_Divide(a, b);
    try testing.expect(result != null);

    const val = numeric_types.PyInt_AsLong(result);
    try testing.expectEqual(@as(c_long, 2), val);

    // Cleanup
    const int_a: *PyInt = @ptrCast(@alignCast(a.?));
    const int_b: *PyInt = @ptrCast(@alignCast(b.?));
    const int_result: *PyInt = @ptrCast(@alignCast(result.?));
    int_a.deinit(std.heap.c_allocator);
    int_b.deinit(std.heap.c_allocator);
    int_result.deinit(std.heap.c_allocator);
}

test "C API - PyNumber_Divide by zero" {
    const PyInt = numeric_types.PyInt;
    const a = numeric_types.PyInt_FromLong(10);
    const b = numeric_types.PyInt_FromLong(0);

    const result = numeric_types.PyNumber_Divide(a, b);
    try testing.expect(result == null); // Should return null on division by zero

    // Cleanup
    const int_a: *PyInt = @ptrCast(@alignCast(a.?));
    const int_b: *PyInt = @ptrCast(@alignCast(b.?));
    int_a.deinit(std.heap.c_allocator);
    int_b.deinit(std.heap.c_allocator);
}
