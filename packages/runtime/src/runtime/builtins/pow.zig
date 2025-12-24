/// Power function with complex number support
const std = @import("std");
const PythonError = @import("../../runtime.zig").PythonError;

const PyValue = @import("../../Objects/object.zig").PyValue;

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

    /// Convert to PyValue for type-safe assignment to PyValue variables
    /// This is the O(1) fix for pow/complex type mismatches
    pub fn toPyValue(self: PyPowResult) PyValue {
        return switch (self) {
            .float_val => |f| .{ .float = f },
            .complex_val => |c| .{ .complex = .{ .real = c.real, .imag = c.imag } },
        };
    }
};

/// Compute pow with complex number support
/// Returns float for most cases, complex when base < 0 and exp is non-integer
pub fn pyPow(base: f64, exp: f64) PythonError!PyPowResult {
    // Python special cases (IEEE 754 compatible):
    // pow(1.0, anything) = 1.0 (including NaN, inf, -inf)
    if (base == 1.0) {
        return PyPowResult{ .float_val = 1.0 };
    }
    // pow(anything, 0.0) = 1.0 (including NaN, inf)
    // Note: -0.0 == 0.0 in IEEE 754 comparison
    if (exp == 0.0) {
        return PyPowResult{ .float_val = 1.0 };
    }
    // pow(-1.0, ±inf) = 1.0
    if (base == -1.0 and std.math.isInf(exp)) {
        return PyPowResult{ .float_val = 1.0 };
    }
    // pow(-1.0, integer) = 1.0 or -1.0 depending on parity
    // Special case needed because std.math.pow(-1.0, large_int) returns NaN
    if (base == -1.0 and !std.math.isNan(exp)) {
        const exp_is_int = exp == @trunc(exp);
        if (exp_is_int) {
            // For large floats, @mod may not work correctly due to precision
            // Use @rem which works like fmod, then check parity
            const rem = @rem(exp, 2.0);
            // rem is 0.0, 1.0, or -1.0 for integers
            if (rem == 0.0) {
                return PyPowResult{ .float_val = 1.0 };
            } else {
                return PyPowResult{ .float_val = -1.0 };
            }
        }
    }

    // Python: 0.0 ** negative raises ZeroDivisionError
    // EXCEPT when exp is -inf: pow(0.0, -inf) = inf (not an error)
    if (base == 0.0 and exp < 0.0 and !std.math.isInf(exp)) {
        return PythonError.ZeroDivisionError;
    }

    // Check if exponent is an integer
    const exp_is_int = exp == @trunc(exp);

    // If base is negative and exponent is non-integer, we need complex math
    // EXCEPT: infinite base always returns float (Python: pow(-inf, 0.5) = inf)
    if (base < 0.0 and !exp_is_int and !std.math.isNan(exp) and !std.math.isInf(exp) and !std.math.isInf(base)) {
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

/// Compute pow and return PyValue directly
/// This is the PUBLIC API for pow when result type is unknown/polymorphic
/// Used by operator.pow() and other contexts where result is assigned to PyValue
pub fn pyPowAsPyValue(base: f64, exp: f64) PythonError!PyValue {
    const result = try pyPow(base, exp);
    return result.toPyValue();
}
