//! ctypes._layout - Structure layout calculation
//! Reference: Internal ctypes module (not directly in CPython Lib)
//!
//! Provides utilities for calculating structure field offsets,
//! sizes, and alignments for C-compatible structures.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Layout Mode
// ============================================================================

/// CPython: _pack_ attribute on structures
/// Specifies the maximum alignment for structure fields.
pub const PackMode = enum(u8) {
    /// Natural alignment (default)
    natural = 0,
    /// Byte-packed (no padding)
    pack1 = 1,
    /// 2-byte alignment
    pack2 = 2,
    /// 4-byte alignment
    pack4 = 4,
    /// 8-byte alignment
    pack8 = 8,
    /// 16-byte alignment
    pack16 = 16,
};

// ============================================================================
// Field Information
// ============================================================================

/// Information about a structure field
pub const FieldInfo = struct {
    /// Field name
    name: []const u8,
    /// Field type (as string for Python compatibility)
    type_name: []const u8,
    /// Offset from structure start
    offset: usize,
    /// Size of the field
    size: usize,
    /// Alignment requirement
    alignment: usize,
    /// Bit field width (0 for non-bit fields)
    bit_width: u8 = 0,
    /// Bit offset within the storage unit
    bit_offset: u8 = 0,
};

/// Information about a structure layout
pub const LayoutInfo = struct {
    /// Total size of the structure
    size: usize,
    /// Alignment requirement of the structure
    alignment: usize,
    /// Fields in the structure
    fields: []const FieldInfo,
};

// ============================================================================
// Alignment Calculation
// ============================================================================

/// Get the natural alignment for a C type
pub fn getNaturalAlignment(comptime T: type) usize {
    return @alignOf(T);
}

/// Get the effective alignment considering pack mode
pub fn getEffectiveAlignment(natural_align: usize, pack_mode: PackMode) usize {
    const pack_value = @intFromEnum(pack_mode);
    if (pack_value == 0) return natural_align;
    return @min(natural_align, pack_value);
}

/// Align an offset to the given alignment
pub fn alignOffset(offset: usize, alignment: usize) usize {
    if (alignment == 0) return offset;
    return (offset + alignment - 1) & ~(alignment - 1);
}

// ============================================================================
// Size Calculation
// ============================================================================

/// Get the size of a C type by name
pub fn getCTypeSize(type_name: []const u8) ?usize {
    const type_sizes = .{
        .{ "c_char", 1 },
        .{ "c_byte", 1 },
        .{ "c_ubyte", 1 },
        .{ "c_short", 2 },
        .{ "c_ushort", 2 },
        .{ "c_int", 4 },
        .{ "c_uint", 4 },
        .{ "c_long", @sizeOf(c_long) },
        .{ "c_ulong", @sizeOf(c_ulong) },
        .{ "c_longlong", 8 },
        .{ "c_ulonglong", 8 },
        .{ "c_float", 4 },
        .{ "c_double", 8 },
        .{ "c_longdouble", @sizeOf(c_longdouble) },
        .{ "c_void_p", @sizeOf(*anyopaque) },
        .{ "c_char_p", @sizeOf(*anyopaque) },
        .{ "c_wchar_p", @sizeOf(*anyopaque) },
    };

    inline for (type_sizes) |entry| {
        if (std.mem.eql(u8, type_name, entry[0])) {
            return entry[1];
        }
    }
    return null;
}

/// Get the alignment of a C type by name
pub fn getCTypeAlignment(type_name: []const u8) ?usize {
    const type_alignments = .{
        .{ "c_char", 1 },
        .{ "c_byte", 1 },
        .{ "c_ubyte", 1 },
        .{ "c_short", 2 },
        .{ "c_ushort", 2 },
        .{ "c_int", 4 },
        .{ "c_uint", 4 },
        .{ "c_long", @alignOf(c_long) },
        .{ "c_ulong", @alignOf(c_ulong) },
        .{ "c_longlong", 8 },
        .{ "c_ulonglong", 8 },
        .{ "c_float", 4 },
        .{ "c_double", 8 },
        .{ "c_longdouble", @alignOf(c_longdouble) },
        .{ "c_void_p", @alignOf(*anyopaque) },
        .{ "c_char_p", @alignOf(*anyopaque) },
        .{ "c_wchar_p", @alignOf(*anyopaque) },
    };

    inline for (type_alignments) |entry| {
        if (std.mem.eql(u8, type_name, entry[0])) {
            return entry[1];
        }
    }
    return null;
}

// Platform-specific types
const c_long = switch (builtin.os.tag) {
    .windows => i32,
    else => isize,
};
const c_ulong = switch (builtin.os.tag) {
    .windows => u32,
    else => usize,
};
const c_longdouble = f128;

// ============================================================================
// Structure Layout Calculation
// ============================================================================

/// Calculate the layout of a structure given its fields
pub fn calculateLayout(
    allocator: std.mem.Allocator,
    fields: []const FieldInfo,
    pack_mode: PackMode,
) !LayoutInfo {
    var current_offset: usize = 0;
    var max_alignment: usize = 1;

    var result_fields = try allocator.alloc(FieldInfo, fields.len);

    for (fields, 0..) |field, i| {
        const effective_align = getEffectiveAlignment(field.alignment, pack_mode);

        // Align current offset
        current_offset = alignOffset(current_offset, effective_align);

        // Update field info
        result_fields[i] = .{
            .name = field.name,
            .type_name = field.type_name,
            .offset = current_offset,
            .size = field.size,
            .alignment = effective_align,
            .bit_width = field.bit_width,
            .bit_offset = field.bit_offset,
        };

        // Advance offset
        current_offset += field.size;

        // Track maximum alignment
        max_alignment = @max(max_alignment, effective_align);
    }

    // Final size is aligned to structure alignment
    const final_size = alignOffset(current_offset, max_alignment);

    return .{
        .size = final_size,
        .alignment = max_alignment,
        .fields = result_fields,
    };
}

// ============================================================================
// Bit Field Support
// ============================================================================

/// Calculate bit field layout within a storage unit
pub fn calculateBitField(
    current_bit_offset: u32,
    bit_width: u8,
    storage_size: usize,
) struct { offset: u32, new_bit_offset: u32 } {
    const storage_bits: u32 = @intCast(storage_size * 8);

    // Check if we need to start a new storage unit
    if (current_bit_offset + bit_width > storage_bits) {
        return .{
            .offset = 0,
            .new_bit_offset = bit_width,
        };
    }

    return .{
        .offset = current_bit_offset,
        .new_bit_offset = current_bit_offset + bit_width,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "alignOffset" {
    try std.testing.expectEqual(@as(usize, 0), alignOffset(0, 4));
    try std.testing.expectEqual(@as(usize, 4), alignOffset(1, 4));
    try std.testing.expectEqual(@as(usize, 4), alignOffset(2, 4));
    try std.testing.expectEqual(@as(usize, 4), alignOffset(3, 4));
    try std.testing.expectEqual(@as(usize, 4), alignOffset(4, 4));
    try std.testing.expectEqual(@as(usize, 8), alignOffset(5, 4));
}

test "getEffectiveAlignment" {
    try std.testing.expectEqual(@as(usize, 8), getEffectiveAlignment(8, .natural));
    try std.testing.expectEqual(@as(usize, 1), getEffectiveAlignment(8, .pack1));
    try std.testing.expectEqual(@as(usize, 2), getEffectiveAlignment(8, .pack2));
    try std.testing.expectEqual(@as(usize, 4), getEffectiveAlignment(8, .pack4));
    try std.testing.expectEqual(@as(usize, 4), getEffectiveAlignment(4, .pack8));
}

test "getCTypeSize" {
    try std.testing.expectEqual(@as(?usize, 1), getCTypeSize("c_char"));
    try std.testing.expectEqual(@as(?usize, 4), getCTypeSize("c_int"));
    try std.testing.expectEqual(@as(?usize, 8), getCTypeSize("c_double"));
    try std.testing.expectEqual(@as(?usize, null), getCTypeSize("unknown"));
}

test "getCTypeAlignment" {
    try std.testing.expectEqual(@as(?usize, 1), getCTypeAlignment("c_char"));
    try std.testing.expectEqual(@as(?usize, 4), getCTypeAlignment("c_int"));
    try std.testing.expectEqual(@as(?usize, 8), getCTypeAlignment("c_double"));
}

test "calculateBitField" {
    // First bit field in a byte
    const result1 = calculateBitField(0, 3, 1);
    try std.testing.expectEqual(@as(u32, 0), result1.offset);
    try std.testing.expectEqual(@as(u32, 3), result1.new_bit_offset);

    // Second bit field in the same byte
    const result2 = calculateBitField(3, 4, 1);
    try std.testing.expectEqual(@as(u32, 3), result2.offset);
    try std.testing.expectEqual(@as(u32, 7), result2.new_bit_offset);

    // Overflow to new storage unit
    const result3 = calculateBitField(7, 3, 1);
    try std.testing.expectEqual(@as(u32, 0), result3.offset);
    try std.testing.expectEqual(@as(u32, 3), result3.new_bit_offset);
}
