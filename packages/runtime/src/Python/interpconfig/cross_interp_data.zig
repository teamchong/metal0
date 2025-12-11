/// cross_interp_data - Cross-Interpreter Data Sharing
/// Mirrors cpython/Python/interpconfig.c (cross-interp section)
///
/// Defines types and values that can be safely shared between interpreters:
/// - Immutable primitive types (bool, int, float)
/// - Immutable string/bytes data
/// - Type tagging for runtime dispatch
/// - Ownership tracking for memory management

/// Types that can be shared between interpreters
pub const CrossInterpDataType = enum {
    none,
    bool_type,
    int_type,
    float_type,
    bytes_type,
    str_type,
    tuple_type,

    pub fn isShareable(self: CrossInterpDataType) bool {
        return self != .none;
    }
};

/// Cross-interpreter data container
pub const CrossInterpData = struct {
    /// Data type
    data_type: CrossInterpDataType,
    /// Data storage (type-dependent)
    data: union {
        bool_val: bool,
        int_val: i64,
        float_val: f64,
        bytes_val: []const u8,
        str_val: []const u8,
    },
    /// Whether data is owned
    owned: bool,

    const Self = @This();

    pub fn initNone() Self {
        return .{
            .data_type = .none,
            .data = undefined,
            .owned = false,
        };
    }

    pub fn initBool(val: bool) Self {
        return .{
            .data_type = .bool_type,
            .data = .{ .bool_val = val },
            .owned = false,
        };
    }

    pub fn initInt(val: i64) Self {
        return .{
            .data_type = .int_type,
            .data = .{ .int_val = val },
            .owned = false,
        };
    }

    pub fn initFloat(val: f64) Self {
        return .{
            .data_type = .float_type,
            .data = .{ .float_val = val },
            .owned = false,
        };
    }

    pub fn initStr(val: []const u8, owned: bool) Self {
        return .{
            .data_type = .str_type,
            .data = .{ .str_val = val },
            .owned = owned,
        };
    }
};
