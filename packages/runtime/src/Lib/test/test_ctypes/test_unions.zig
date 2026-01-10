//! test.test_ctypes.test_unions - Tests for ctypes Union types
//! Reference: cpython/Lib/test/test_ctypes/test_unions.py
//!
//! Tests for ctypes union functionality including overlapping storage,
//! field access, and memory layout.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Union Base Type
// ============================================================================

/// Create a union type for ctypes - all fields share the same memory
pub fn Union(comptime fields: []const UnionField) type {
    const max_size = calculateMaxSize(fields);
    const max_align = calculateMaxAlignment(fields);

    return struct {
        const Self = @This();
        pub const _fields_ = fields;

        /// Storage - sized to hold the largest field
        data: [max_size]u8 align(max_align) = undefined,

        /// Currently active field name (for debugging)
        active_field: ?[]const u8 = null,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.data, 0);
            return self;
        }

        /// Get raw pointer to data
        pub fn ptr(self: *Self) *anyopaque {
            return @ptrCast(&self.data);
        }

        /// Get const raw pointer to data
        pub fn constPtr(self: *const Self) *const anyopaque {
            return @ptrCast(&self.data);
        }

        pub fn sizeof() usize {
            return max_size;
        }

        pub fn alignment() usize {
            return max_align;
        }

        /// Set data from bytes
        pub fn setBytes(self: *Self, bytes: []const u8) void {
            const len = @min(bytes.len, max_size);
            @memcpy(self.data[0..len], bytes[0..len]);
        }

        /// Get data as bytes
        pub fn getBytes(self: *const Self) []const u8 {
            return &self.data;
        }
    };
}

/// Union field descriptor
pub const UnionField = struct {
    name: []const u8,
    type_name: []const u8,
    size: usize,
    alignment: usize = 1,
};

/// Calculate maximum size needed
fn calculateMaxSize(fields: []const UnionField) usize {
    var max: usize = 1;
    for (fields) |field| {
        max = @max(max, field.size);
    }
    return max;
}

/// Calculate maximum alignment needed
fn calculateMaxAlignment(fields: []const UnionField) usize {
    var max: usize = 1;
    for (fields) |field| {
        max = @max(max, field.alignment);
    }
    return max;
}

// ============================================================================
// Example Unions
// ============================================================================

/// Simple int/float union
pub const IntFloat = Union(&.{
    .{ .name = "i", .type_name = "c_int", .size = 4, .alignment = 4 },
    .{ .name = "f", .type_name = "c_float", .size = 4, .alignment = 4 },
});

/// Mixed size union
pub const MixedUnion = Union(&.{
    .{ .name = "b", .type_name = "c_byte", .size = 1, .alignment = 1 },
    .{ .name = "s", .type_name = "c_short", .size = 2, .alignment = 2 },
    .{ .name = "i", .type_name = "c_int", .size = 4, .alignment = 4 },
    .{ .name = "l", .type_name = "c_longlong", .size = 8, .alignment = 8 },
});

/// Pointer union
pub const PointerUnion = Union(&.{
    .{ .name = "void_p", .type_name = "c_void_p", .size = 8, .alignment = 8 },
    .{ .name = "char_p", .type_name = "c_char_p", .size = 8, .alignment = 8 },
    .{ .name = "int_p", .type_name = "POINTER(c_int)", .size = 8, .alignment = 8 },
});

/// Union with array field
pub const ArrayUnion = Union(&.{
    .{ .name = "value", .type_name = "c_int", .size = 4, .alignment = 4 },
    .{ .name = "bytes", .type_name = "c_byte * 4", .size = 4, .alignment = 1 },
});

// ============================================================================
// Union Operations
// ============================================================================

/// Copy union data
pub fn copyUnion(comptime T: type, dest: *T, src: *const T) void {
    @memcpy(&dest.data, &src.data);
    dest.active_field = src.active_field;
}

/// Compare unions by memory
pub fn unionsEqual(comptime T: type, a: *const T, b: *const T) bool {
    return std.mem.eql(u8, &a.data, &b.data);
}

/// Set integer value in union
pub fn setInt(u: *IntFloat, value: i32) void {
    const bytes = std.mem.asBytes(&value);
    @memcpy(u.data[0..4], bytes);
    u.active_field = "i";
}

/// Get integer value from union
pub fn getInt(u: *const IntFloat) i32 {
    return std.mem.bytesToValue(i32, u.data[0..4]);
}

/// Set float value in union
pub fn setFloat(u: *IntFloat, value: f32) void {
    const bytes = std.mem.asBytes(&value);
    @memcpy(u.data[0..4], bytes);
    u.active_field = "f";
}

/// Get float value from union
pub fn getFloat(u: *const IntFloat) f32 {
    return std.mem.bytesToValue(f32, u.data[0..4]);
}

// ============================================================================
// Test Cases
// ============================================================================

fn testIntFloatUnion() !void {
    var u = IntFloat.init();
    try std.testing.expectEqual(@as(usize, 4), IntFloat.sizeof());

    // Set as int
    setInt(&u, 0x41200000); // This is 10.0 as float bits
    try std.testing.expectEqual(@as(i32, 0x41200000), getInt(&u));

    // Read as float (reinterpret bytes)
    const f = getFloat(&u);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), f, 0.001);
}

fn testMixedUnion() !void {
    var u = MixedUnion.init();
    try std.testing.expectEqual(@as(usize, 8), MixedUnion.sizeof());
    try std.testing.expectEqual(@as(usize, 8), MixedUnion.alignment());

    // Write longlong
    const val: i64 = 0x0102030405060708;
    const bytes = std.mem.asBytes(&val);
    @memcpy(&u.data, bytes);

    // Read back
    const read_val = std.mem.bytesToValue(i64, &u.data);
    try std.testing.expectEqual(val, read_val);

    // Read as byte (lowest byte)
    try std.testing.expectEqual(@as(u8, 0x08), u.data[0]);
}

fn testUnionOverlap() !void {
    var u = ArrayUnion.init();

    // Set individual bytes
    u.data[0] = 0x12;
    u.data[1] = 0x34;
    u.data[2] = 0x56;
    u.data[3] = 0x78;

    // Read as integer (little-endian)
    const int_val = std.mem.bytesToValue(i32, u.data[0..4]);
    try std.testing.expectEqual(@as(i32, 0x78563412), int_val);
}

fn testUnionCopy() !void {
    var src = IntFloat.init();
    setInt(&src, 42);

    var dest = IntFloat.init();
    copyUnion(IntFloat, &dest, &src);

    try std.testing.expectEqual(getInt(&src), getInt(&dest));
    try std.testing.expect(unionsEqual(IntFloat, &src, &dest));
}

fn testUnionPointers() !void {
    var u = PointerUnion.init();
    try std.testing.expectEqual(@as(usize, 8), PointerUnion.sizeof());

    // All pointer types should share the same storage
    try std.testing.expectEqual(@as(usize, 8), u.data.len);
}

fn testUnionInit() !void {
    const u = IntFloat.init();

    // Should be zero-initialized
    try std.testing.expectEqual(@as(i32, 0), getInt(&u));
    try std.testing.expectEqual(@as(f32, 0.0), getFloat(&u));
}

fn testUnionFieldsMetadata() !void {
    try std.testing.expectEqual(@as(usize, 2), IntFloat._fields_.len);
    try std.testing.expectEqualStrings("i", IntFloat._fields_[0].name);
    try std.testing.expectEqualStrings("f", IntFloat._fields_[1].name);
}

fn testUnionSetBytes() !void {
    var u = IntFloat.init();
    const bytes = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    u.setBytes(&bytes);

    try std.testing.expectEqual(@as(u8, 0xAA), u.data[0]);
    try std.testing.expectEqual(@as(u8, 0xDD), u.data[3]);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "int_float_union" {
    try testIntFloatUnion();
}

test "mixed_union" {
    try testMixedUnion();
}

test "union_overlap" {
    try testUnionOverlap();
}

test "union_copy" {
    try testUnionCopy();
}

test "union_pointers" {
    try testUnionPointers();
}

test "union_init" {
    try testUnionInit();
}

test "union_fields_metadata" {
    try testUnionFieldsMetadata();
}

test "union_set_bytes" {
    try testUnionSetBytes();
}
