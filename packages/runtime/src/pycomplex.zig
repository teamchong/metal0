/// Python complex type implementation (CPython ABI compatible)
const std = @import("std");
const runtime = @import("runtime.zig");

pub const PyObject = runtime.PyObject;
pub const PyComplexObject = runtime.PyComplexObject;
pub const PyComplex_Type = &runtime.PyComplex_Type;

/// Python complex type - wrapper around CPython-compatible PyComplexObject
pub const PyComplex = struct {
    /// Create a new PyComplexObject with the given real and imaginary parts
    pub fn create(allocator: std.mem.Allocator, real: f64, imag: f64) !*PyObject {
        const complex_obj = try allocator.create(PyComplexObject);
        complex_obj.* = PyComplexObject{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = PyComplex_Type,
            },
            .cval_real = real,
            .cval_imag = imag,
        };
        return @ptrCast(complex_obj);
    }

    /// Get the real part from a PyComplexObject
    pub fn getReal(obj: *PyObject) f64 {
        std.debug.assert(runtime.PyComplex_Check(obj));
        const complex_obj: *PyComplexObject = @ptrCast(@alignCast(obj));
        return complex_obj.cval_real;
    }

    /// Get the imaginary part from a PyComplexObject
    pub fn getImag(obj: *PyObject) f64 {
        std.debug.assert(runtime.PyComplex_Check(obj));
        const complex_obj: *PyComplexObject = @ptrCast(@alignCast(obj));
        return complex_obj.cval_imag;
    }
};
