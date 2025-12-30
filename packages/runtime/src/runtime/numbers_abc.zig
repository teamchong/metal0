/// Python numbers module ABC (Abstract Base Classes)
/// Implements the numeric tower: Number > Complex > Real > Rational > Integral
/// Used by issubclass() to check numeric type relationships
const std = @import("std");

/// Numbers ABC hierarchy
/// Number -> Complex -> Real -> Rational -> Integral
pub const NumbersABC = enum {
    Number,
    Complex,
    Real,
    Rational,
    Integral,

    /// Check if this ABC is the same or a superclass of other
    /// Integral < Rational < Real < Complex < Number
    pub fn isSupertypeOf(self: NumbersABC, other: NumbersABC) bool {
        const self_level = self.hierarchyLevel();
        const other_level = other.hierarchyLevel();
        // Higher level = more general (Number=0, Integral=4)
        // Supertype means self_level <= other_level
        return self_level <= other_level;
    }

    /// Get hierarchy level (0=Number, 4=Integral)
    fn hierarchyLevel(self: NumbersABC) u8 {
        return switch (self) {
            .Number => 0,
            .Complex => 1,
            .Real => 2,
            .Rational => 3,
            .Integral => 4,
        };
    }
};

/// Built-in type registration with numbers ABCs
const BuiltinRegistration = struct {
    type_name: []const u8,
    abc: NumbersABC,
};

/// Pre-registered built-in types with their most specific ABC
/// int is Integral, float is Real, Decimal is Number (not in strict hierarchy)
const builtin_registrations = [_]BuiltinRegistration{
    .{ .type_name = "int", .abc = .Integral },
    .{ .type_name = "bool", .abc = .Integral }, // bool is subclass of int
    .{ .type_name = "float", .abc = .Real },
    .{ .type_name = "complex", .abc = .Complex },
    .{ .type_name = "Decimal", .abc = .Number }, // Decimal registers as Number
    .{ .type_name = "Fraction", .abc = .Rational },
};

/// Check if a built-in type is a subclass of a numbers ABC
/// Returns true if type_name is registered at or below abc in the hierarchy
///
/// Examples:
///   isBuiltinSubclassOfABC("int", .Number) -> true (int is Integral, subclass of Number)
///   isBuiltinSubclassOfABC("int", .Real) -> true (Integral < Real)
///   isBuiltinSubclassOfABC("float", .Integral) -> false (Real is not subclass of Integral)
///   isBuiltinSubclassOfABC("Decimal", .Number) -> true (registered as Number)
pub fn isBuiltinSubclassOfABC(type_name: []const u8, abc: NumbersABC) bool {
    for (builtin_registrations) |reg| {
        if (std.mem.eql(u8, reg.type_name, type_name)) {
            // Found the type - check if abc is supertype of the type's registered ABC
            return abc.isSupertypeOf(reg.abc);
        }
    }
    return false;
}

/// Get the ABC level for a built-in type name, or null if not registered
pub fn getBuiltinABC(type_name: []const u8) ?NumbersABC {
    for (builtin_registrations) |reg| {
        if (std.mem.eql(u8, reg.type_name, type_name)) {
            return reg.abc;
        }
    }
    return null;
}

/// Parse a numbers.ABC name (like "Number", "Integral") to enum
pub fn parseABCName(name: []const u8) ?NumbersABC {
    if (std.mem.eql(u8, name, "Number")) return .Number;
    if (std.mem.eql(u8, name, "Complex")) return .Complex;
    if (std.mem.eql(u8, name, "Real")) return .Real;
    if (std.mem.eql(u8, name, "Rational")) return .Rational;
    if (std.mem.eql(u8, name, "Integral")) return .Integral;
    return null;
}

// Tests
test "isBuiltinSubclassOfABC" {
    const testing = std.testing;

    // int is subclass of all numeric ABCs
    try testing.expect(isBuiltinSubclassOfABC("int", .Number));
    try testing.expect(isBuiltinSubclassOfABC("int", .Complex));
    try testing.expect(isBuiltinSubclassOfABC("int", .Real));
    try testing.expect(isBuiltinSubclassOfABC("int", .Rational));
    try testing.expect(isBuiltinSubclassOfABC("int", .Integral));

    // float is Real, so subclass of Number, Complex, Real, but not Rational/Integral
    try testing.expect(isBuiltinSubclassOfABC("float", .Number));
    try testing.expect(isBuiltinSubclassOfABC("float", .Complex));
    try testing.expect(isBuiltinSubclassOfABC("float", .Real));
    try testing.expect(!isBuiltinSubclassOfABC("float", .Rational));
    try testing.expect(!isBuiltinSubclassOfABC("float", .Integral));

    // Decimal is only Number
    try testing.expect(isBuiltinSubclassOfABC("Decimal", .Number));
    try testing.expect(!isBuiltinSubclassOfABC("Decimal", .Complex));

    // Fraction is Rational
    try testing.expect(isBuiltinSubclassOfABC("Fraction", .Number));
    try testing.expect(isBuiltinSubclassOfABC("Fraction", .Rational));
    try testing.expect(!isBuiltinSubclassOfABC("Fraction", .Integral));

    // Unknown type
    try testing.expect(!isBuiltinSubclassOfABC("str", .Number));
}
