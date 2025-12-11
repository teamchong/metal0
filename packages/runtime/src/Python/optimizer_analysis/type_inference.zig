/// type_inference - Type Inference for Optimizer
/// Provides type lattice and type state tracking for abstract interpretation

const std = @import("std");

// ============================================================================
// Type Inference
// ============================================================================

/// Type lattice for abstract interpretation
pub const TypeLattice = enum(u8) {
    /// Unknown type (bottom)
    bottom,
    /// No possible value (top/unreachable)
    top,
    /// None singleton
    none_type,
    /// Boolean
    bool_type,
    /// Small integer
    small_int,
    /// Large integer (arbitrary precision)
    big_int,
    /// Float
    float_type,
    /// Complex number
    complex_type,
    /// String
    str_type,
    /// Bytes
    bytes_type,
    /// List
    list_type,
    /// Tuple
    tuple_type,
    /// Dict
    dict_type,
    /// Set
    set_type,
    /// Frozenset
    frozenset_type,
    /// Function
    function_type,
    /// Method
    method_type,
    /// Module
    module_type,
    /// Class/type
    type_type,
    /// Object (any object)
    object_type,

    /// Join two types in the lattice
    pub fn join(self: TypeLattice, other: TypeLattice) TypeLattice {
        if (self == .bottom) return other;
        if (other == .bottom) return self;
        if (self == other) return self;
        if (self == .top or other == .top) return .top;

        // Numeric types join to object
        if (isNumeric(self) and isNumeric(other)) return .object_type;

        // Sequence types join to object
        if (isSequence(self) and isSequence(other)) return .object_type;

        return .object_type;
    }

    /// Meet two types in the lattice
    pub fn meet(self: TypeLattice, other: TypeLattice) TypeLattice {
        if (self == .top) return other;
        if (other == .top) return self;
        if (self == other) return self;
        return .bottom;
    }

    /// Check if type is numeric
    pub fn isNumeric(t: TypeLattice) bool {
        return t == .small_int or t == .big_int or t == .float_type or t == .complex_type;
    }

    /// Check if type is sequence
    pub fn isSequence(t: TypeLattice) bool {
        return t == .str_type or t == .bytes_type or t == .list_type or t == .tuple_type;
    }

    /// Check if type is container
    pub fn isContainer(t: TypeLattice) bool {
        return isSequence(t) or t == .dict_type or t == .set_type or t == .frozenset_type;
    }
};

/// Type state for a stack slot
pub const TypeState = struct {
    /// Primary type
    type_lattice: TypeLattice = .bottom,
    /// Confidence (0.0 - 1.0)
    confidence: f32 = 0.0,
    /// Known constant value (if any)
    const_value: ?ConstValue = null,
    /// Version (for SSA)
    version: u32 = 0,

    /// Create unknown type state
    pub fn unknown() TypeState {
        return .{ .type_lattice = .bottom };
    }

    /// Create type state from lattice type
    pub fn fromType(t: TypeLattice) TypeState {
        return .{ .type_lattice = t, .confidence = 1.0 };
    }

    /// Join with another state
    pub fn join(self: TypeState, other: TypeState) TypeState {
        return TypeState{
            .type_lattice = self.type_lattice.join(other.type_lattice),
            .confidence = @min(self.confidence, other.confidence),
            .const_value = if (self.const_value != null and other.const_value != null and
                self.const_value.?.eql(other.const_value.?))
                self.const_value
            else
                null,
            .version = @max(self.version, other.version) + 1,
        };
    }
};

/// Constant value for constant propagation
pub const ConstValue = union(enum) {
    none: void,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    str_val: []const u8,

    pub fn eql(self: ConstValue, other: ConstValue) bool {
        return switch (self) {
            .none => other == .none,
            .bool_val => |b| other == .bool_val and other.bool_val == b,
            .int_val => |i| other == .int_val and other.int_val == i,
            .float_val => |f| other == .float_val and other.float_val == f,
            .str_val => |s| other == .str_val and std.mem.eql(u8, other.str_val, s),
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "type lattice join" {
    try std.testing.expectEqual(TypeLattice.small_int, TypeLattice.bottom.join(.small_int));
    try std.testing.expectEqual(TypeLattice.float_type, TypeLattice.float_type.join(.float_type));
    try std.testing.expectEqual(TypeLattice.object_type, TypeLattice.small_int.join(.float_type));
}

test "type state join" {
    const s1 = TypeState.fromType(.small_int);
    const s2 = TypeState.fromType(.small_int);
    const s3 = TypeState.fromType(.float_type);

    const joined_same = s1.join(s2);
    try std.testing.expectEqual(TypeLattice.small_int, joined_same.type_lattice);

    const joined_diff = s1.join(s3);
    try std.testing.expectEqual(TypeLattice.object_type, joined_diff.type_lattice);
}
