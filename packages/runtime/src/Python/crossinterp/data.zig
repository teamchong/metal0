/// Cross-Interpreter Data Types
/// Types that can be shared across interpreters

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Interpreter ID
// ============================================================================

/// Unique identifier for an interpreter
pub const InterpID = i64;

/// Invalid interpreter ID
pub const INVALID_INTERP_ID: InterpID = -1;

/// Main interpreter ID
pub const MAIN_INTERP_ID: InterpID = 0;

// ============================================================================
// Cross-Interpreter Data
// ============================================================================

/// Types that can be shared across interpreters
pub const CrossInterpDataType = enum {
    /// None value
    none,
    /// Boolean value
    bool_val,
    /// Integer value
    int_val,
    /// Float value
    float_val,
    /// Bytes (immutable)
    bytes,
    /// String (immutable)
    str,
    /// Tuple of shareable items
    tuple,
    /// Exception info
    exception,
    /// Code object
    code,
    /// Memoryview
    memoryview,
};

/// Exception information for cross-interpreter transfer
pub const ExceptionInfo = struct {
    /// Exception type name
    type_name: []const u8,
    /// Exception message
    message: []const u8,
    /// Traceback (serialized)
    traceback: ?[]const u8 = null,
};

/// Memory view data for sharing buffers
pub const MemoryViewData = struct {
    /// Buffer pointer (must be managed carefully)
    ptr: [*]const u8,
    /// Buffer length
    len: usize,
    /// Item size
    itemsize: usize = 1,
    /// Format string
    format: []const u8 = "B",
    /// Is readonly
    readonly: bool = true,
};

/// Data that can be passed between interpreters
pub const CrossInterpData = struct {
    const Self = @This();

    /// Data type
    data_type: CrossInterpDataType,
    /// Raw data storage
    data: DataUnion,
    /// Allocator used
    allocator: Allocator,
    /// Whether data is owned
    owned: bool = true,

    const DataUnion = union {
        none: void,
        bool_val: bool,
        int_val: i64,
        float_val: f64,
        bytes: []const u8,
        str: []const u8,
        tuple: []Self,
        exception: ExceptionInfo,
        code: []const u8, // Serialized code
        memoryview: MemoryViewData,
    };

    pub fn initNone(allocator: Allocator) Self {
        return Self{
            .data_type = .none,
            .data = .{ .none = {} },
            .allocator = allocator,
        };
    }

    pub fn initInt(allocator: Allocator, value: i64) Self {
        return Self{
            .data_type = .int_val,
            .data = .{ .int_val = value },
            .allocator = allocator,
        };
    }

    pub fn initFloat(allocator: Allocator, value: f64) Self {
        return Self{
            .data_type = .float_val,
            .data = .{ .float_val = value },
            .allocator = allocator,
        };
    }

    pub fn initBytes(allocator: Allocator, bytes: []const u8) !Self {
        const owned = try allocator.dupe(u8, bytes);
        return Self{
            .data_type = .bytes,
            .data = .{ .bytes = owned },
            .allocator = allocator,
        };
    }

    pub fn initStr(allocator: Allocator, str: []const u8) !Self {
        const owned = try allocator.dupe(u8, str);
        return Self{
            .data_type = .str,
            .data = .{ .str = owned },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (!self.owned) return;

        switch (self.data_type) {
            .bytes => self.allocator.free(self.data.bytes),
            .str => self.allocator.free(self.data.str),
            .tuple => {
                for (self.data.tuple) |*item| {
                    item.deinit();
                }
                self.allocator.free(self.data.tuple);
            },
            .code => self.allocator.free(self.data.code),
            else => {},
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "cross interp data int" {
    const allocator = std.testing.allocator;
    var data = CrossInterpData.initInt(allocator, 42);
    defer data.deinit();

    try std.testing.expectEqual(CrossInterpDataType.int_val, data.data_type);
    try std.testing.expectEqual(@as(i64, 42), data.data.int_val);
}

test "cross interp data str" {
    const allocator = std.testing.allocator;
    var data = try CrossInterpData.initStr(allocator, "hello");
    defer data.deinit();

    try std.testing.expectEqual(CrossInterpDataType.str, data.data_type);
    try std.testing.expectEqualStrings("hello", data.data.str);
}
