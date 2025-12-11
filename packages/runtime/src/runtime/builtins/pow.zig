/// Power function with complex number support
const std = @import("std");
const PythonError = @import("../../runtime.zig").PythonError;

/// Result type for pow() that can be either float or complex
/// Python: pow(negative, non_integer) returns complex
pub const PyPowResult = union(enum) {
    float_val: f64,
    complex_val: struct { real: f64, imag: f64 },

    /// Check if this is a float result
    pub fn isFloat(self: PyPowResult) bool {
        return self == .float_val;
    }

    /// Check if this is a complex result
    pub fn isComplex(self: PyPowResult) bool {
        return self == .complex_val;
    }

    /// Get the float value (panics if complex)
    pub fn asFloat(self: PyPowResult) f64 {
        return self.float_val;
    }

    /// Get as f64 - returns float value or NaN for complex
    pub fn toFloat(self: PyPowResult) f64 {
        return switch (self) {
            .float_val => |v| v,
            .complex_val => std.math.nan(f64), // complex can't be converted to float
        };
    }

    /// Get the complex value as (real, imag) tuple
    pub fn asComplex(self: PyPowResult) struct { real: f64, imag: f64 } {
        return self.complex_val;
    }

    /// Get the type name for type() builtin
    pub fn typeName(self: PyPowResult) []const u8 {
        return switch (self) {
            .float_val => "float",
            .complex_val => "complex",
        };
    }

    /// Check if this is NaN (only possible for float variant)
    pub fn isNan(self: PyPowResult) bool {
        return switch (self) {
            .float_val => |v| std.math.isNan(v),
            .complex_val => |c| std.math.isNan(c.real) or std.math.isNan(c.imag),
        };
    }

    /// Check if this is infinite
    pub fn isInf(self: PyPowResult) bool {
        return switch (self) {
            .float_val => |v| std.math.isInf(v),
            .complex_val => |c| std.math.isInf(c.real) or std.math.isInf(c.imag),
        };
    }

    /// Equality comparison with f64
    pub fn eql(self: PyPowResult, other: f64) bool {
        return switch (self) {
            .float_val => |v| v == other,
            .complex_val => false, // complex != float
        };
    }

    /// Equality comparison with another PyPowResult
    pub fn eqlResult(self: PyPowResult, other: PyPowResult) bool {
        return switch (self) {
            .float_val => |v| switch (other) {
                .float_val => |ov| v == ov,
                .complex_val => false,
            },
            .complex_val => |c| switch (other) {
                .float_val => false,
                .complex_val => |oc| c.real == oc.real and c.imag == oc.imag,
            },
        };
    }
};

/// Compute pow with complex number support
/// Returns float for most cases, complex when base < 0 and exp is non-integer
pub fn pyPow(base: f64, exp: f64) PythonError!PyPowResult {
    // Python: 0.0 ** negative raises ZeroDivisionError
    if (base == 0.0 and exp < 0.0) {
        return PythonError.ZeroDivisionError;
    }

    // Check if exponent is an integer
    const exp_is_int = exp == @trunc(exp);

    // If base is negative and exponent is non-integer, we need complex math
    if (base < 0.0 and !exp_is_int and !std.math.isNan(exp) and !std.math.isInf(exp)) {
        // Use complex exponentiation: (-a)^b = e^(b * ln(-a)) = e^(b * (ln(|a|) + i*pi))
        // = e^(b*ln(|a|)) * e^(i*b*pi) = |a|^b * (cos(b*pi) + i*sin(b*pi))
        const abs_base = @abs(base);
        const magnitude = std.math.pow(f64, abs_base, exp);
        const angle = exp * std.math.pi;
        const real = magnitude * @cos(angle);
        const imag = magnitude * @sin(angle);
        return PyPowResult{ .complex_val = .{ .real = real, .imag = imag } };
    }

    // Normal float pow
    return PyPowResult{ .float_val = std.math.pow(f64, base, exp) };
}
