//! CPython source: Lib/stringprep.py
//!
//! Implements the StringPrep profile as defined in RFC 3454.
//! Used for preparation of internationalized strings, particularly for IDNA.
//!
//! Mirrors: CPython Lib/stringprep.py

const std = @import("std");

// ============================================================================
// Character set membership tables
// ============================================================================

/// Table A.1: Unassigned code points in Unicode 3.2
pub fn in_table_a1(c: u21) bool {
    // Simplified version - check common unassigned ranges
    // Full implementation would include all Unicode 3.2 unassigned ranges
    return switch (c) {
        0x0221 => true,
        0x0234...0x024F => true,
        0x02AE...0x02AF => true,
        0x02EF...0x02FF => true,
        0x0350...0x035F => true,
        0x0370...0x0373 => true,
        0x0376...0x0379 => true,
        0x037B...0x037D => true,
        0x037F...0x0383 => true,
        else => false,
    };
}

/// Table B.1: Commonly mapped to nothing
pub fn in_table_b1(c: u21) bool {
    return switch (c) {
        0x00AD => true, // SOFT HYPHEN
        0x034F => true, // COMBINING GRAPHEME JOINER
        0x1806 => true, // MONGOLIAN TODO SOFT HYPHEN
        0x180B => true, // MONGOLIAN FREE VARIATION SELECTOR ONE
        0x180C => true, // MONGOLIAN FREE VARIATION SELECTOR TWO
        0x180D => true, // MONGOLIAN FREE VARIATION SELECTOR THREE
        0x200B => true, // ZERO WIDTH SPACE
        0x200C => true, // ZERO WIDTH NON-JOINER
        0x200D => true, // ZERO WIDTH JOINER
        0x2060 => true, // WORD JOINER
        0xFE00...0xFE0F => true, // VARIATION SELECTOR 1-16
        0xFEFF => true, // ZERO WIDTH NO-BREAK SPACE
        else => false,
    };
}

/// Table B.2: Case mapping (simplified - returns lowercase)
pub fn map_table_b2(c: u21) u21 {
    // Simplified ASCII case folding
    if (c >= 'A' and c <= 'Z') {
        return c + 32;
    }
    return c;
}

/// Table B.3: Case folding with normalization
pub fn map_table_b3(c: u21) u21 {
    // Same as B.2 for basic ASCII
    return map_table_b2(c);
}

/// Table C.1.1: ASCII space characters
pub fn in_table_c11(c: u21) bool {
    return c == 0x0020; // SPACE
}

/// Table C.1.2: Non-ASCII space characters
pub fn in_table_c12(c: u21) bool {
    return switch (c) {
        0x00A0 => true, // NO-BREAK SPACE
        0x1680 => true, // OGHAM SPACE MARK
        0x2000...0x200B => true, // Various width spaces
        0x202F => true, // NARROW NO-BREAK SPACE
        0x205F => true, // MEDIUM MATHEMATICAL SPACE
        0x3000 => true, // IDEOGRAPHIC SPACE
        else => false,
    };
}

/// Table C.2.1: ASCII control characters
pub fn in_table_c21(c: u21) bool {
    return c <= 0x001F or c == 0x007F;
}

/// Table C.2.2: Non-ASCII control characters
pub fn in_table_c22(c: u21) bool {
    return switch (c) {
        0x0080...0x009F => true,
        0x06DD => true, // ARABIC END OF AYAH
        0x070F => true, // SYRIAC ABBREVIATION MARK
        0x180E => true, // MONGOLIAN VOWEL SEPARATOR
        0x200C => true, // ZERO WIDTH NON-JOINER
        0x200D => true, // ZERO WIDTH JOINER
        0x2028 => true, // LINE SEPARATOR
        0x2029 => true, // PARAGRAPH SEPARATOR
        0x2060 => true, // WORD JOINER
        0x2061...0x2063 => true, // Invisible operators
        0x206A...0x206F => true, // Inhibit/activate
        0xFEFF => true, // BYTE ORDER MARK
        0xFFF9...0xFFFC => true, // Interlinear annotation
        0x1D173...0x1D17A => true, // Musical formatting
        else => false,
    };
}

/// Table C.3: Private use
pub fn in_table_c3(c: u21) bool {
    return switch (c) {
        0xE000...0xF8FF => true, // Private use area
        0xF0000...0xFFFFD => true, // Supplementary private use area A
        0x100000...0x10FFFD => true, // Supplementary private use area B
        else => false,
    };
}

/// Table C.4: Non-character code points
pub fn in_table_c4(c: u21) bool {
    // Last two code points of each plane
    if ((c & 0xFFFF) >= 0xFFFE) return true;
    // Noncharacter range
    return c >= 0xFDD0 and c <= 0xFDEF;
}

/// Table C.5: Surrogate codes
pub fn in_table_c5(c: u21) bool {
    return c >= 0xD800 and c <= 0xDFFF;
}

/// Table C.6: Inappropriate for plain text
pub fn in_table_c6(c: u21) bool {
    return switch (c) {
        0xFFF9 => true, // INTERLINEAR ANNOTATION ANCHOR
        0xFFFA => true, // INTERLINEAR ANNOTATION SEPARATOR
        0xFFFB => true, // INTERLINEAR ANNOTATION TERMINATOR
        0xFFFC => true, // OBJECT REPLACEMENT CHARACTER
        0xFFFD => true, // REPLACEMENT CHARACTER
        else => false,
    };
}

/// Table C.7: Inappropriate for canonical representation
pub fn in_table_c7(c: u21) bool {
    return c >= 0x2FF0 and c <= 0x2FFB; // Ideographic description characters
}

/// Table C.8: Change display properties or deprecated
pub fn in_table_c8(c: u21) bool {
    return switch (c) {
        0x0340 => true, // COMBINING GRAVE TONE MARK
        0x0341 => true, // COMBINING ACUTE TONE MARK
        0x200E => true, // LEFT-TO-RIGHT MARK
        0x200F => true, // RIGHT-TO-LEFT MARK
        0x202A => true, // LEFT-TO-RIGHT EMBEDDING
        0x202B => true, // RIGHT-TO-LEFT EMBEDDING
        0x202C => true, // POP DIRECTIONAL FORMATTING
        0x202D => true, // LEFT-TO-RIGHT OVERRIDE
        0x202E => true, // RIGHT-TO-LEFT OVERRIDE
        0x206A => true, // INHIBIT SYMMETRIC SWAPPING
        0x206B => true, // ACTIVATE SYMMETRIC SWAPPING
        0x206C => true, // INHIBIT ARABIC FORM SHAPING
        0x206D => true, // ACTIVATE ARABIC FORM SHAPING
        0x206E => true, // NATIONAL DIGIT SHAPES
        0x206F => true, // NOMINAL DIGIT SHAPES
        else => false,
    };
}

/// Table C.9: Tagging characters
pub fn in_table_c9(c: u21) bool {
    return c >= 0xE0001 and c <= 0xE007F;
}

/// Table D.1: Characters with bidirectional property "R" or "AL"
pub fn in_table_d1(c: u21) bool {
    return switch (c) {
        0x05BE => true,
        0x05C0 => true,
        0x05C3 => true,
        0x05D0...0x05EA => true,
        0x05F0...0x05F4 => true,
        0x061B => true,
        0x061F => true,
        0x0621...0x063A => true,
        0x0640...0x064A => true,
        0x066D...0x066F => true,
        0x0671...0x06D5 => true,
        0x06DD => true,
        0x06E5...0x06E6 => true,
        0x06FA...0x06FE => true,
        0x0700...0x070D => true,
        0x0710 => true,
        0x0712...0x072C => true,
        0x0780...0x07A5 => true,
        0x07B1 => true,
        0xFB1D => true,
        0xFB1F...0xFB28 => true,
        0xFB2A...0xFB36 => true,
        0xFB38...0xFB3C => true,
        0xFB3E => true,
        0xFB40...0xFB41 => true,
        0xFB43...0xFB44 => true,
        0xFB46...0xFBB1 => true,
        0xFBD3...0xFD3D => true,
        0xFD50...0xFD8F => true,
        0xFD92...0xFDC7 => true,
        0xFDF0...0xFDFC => true,
        0xFE70...0xFE74 => true,
        0xFE76...0xFEFC => true,
        else => false,
    };
}

/// Table D.2: Characters with bidirectional property "L"
pub fn in_table_d2(c: u21) bool {
    return switch (c) {
        0x0041...0x005A => true, // A-Z
        0x0061...0x007A => true, // a-z
        0x00AA => true,
        0x00B5 => true,
        0x00BA => true,
        0x00C0...0x00D6 => true,
        0x00D8...0x00F6 => true,
        0x00F8...0x0220 => true,
        0x0222...0x0233 => true,
        0x0250...0x02AD => true,
        0x02B0...0x02B8 => true,
        0x02BB...0x02C1 => true,
        0x02D0...0x02D1 => true,
        0x02E0...0x02E4 => true,
        0x02EE => true,
        0x037A => true,
        0x0386 => true,
        0x0388...0x038A => true,
        0x038C => true,
        0x038E...0x03A1 => true,
        0x03A3...0x03CE => true,
        0x03D0...0x03F5 => true,
        0x0400...0x0482 => true,
        0x048A...0x04CE => true,
        0x04D0...0x04F5 => true,
        0x04F8...0x04F9 => true,
        0x0500...0x050F => true,
        0x0531...0x0556 => true,
        0x0559...0x055F => true,
        0x0561...0x0587 => true,
        else => false,
    };
}

// ============================================================================
// Utility functions
// ============================================================================

/// Check if string contains any unassigned code points
pub fn containsUnassigned(s: []const u8) bool {
    var iter = std.unicode.Utf8Iterator{ .bytes = s, .i = 0 };
    while (iter.nextCodepoint()) |c| {
        if (in_table_a1(c)) return true;
    }
    return false;
}

/// Map string according to table B.1 (remove mapped-to-nothing chars)
pub fn mapB1(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var iter = std.unicode.Utf8Iterator{ .bytes = s, .i = 0 };
    while (iter.nextCodepoint()) |c| {
        if (!in_table_b1(c)) {
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(c, &buf) catch continue;
            try result.appendSlice(buf[0..len]);
        }
    }
    return result.toOwnedSlice();
}

/// Map string to lowercase (table B.2)
pub fn mapB2(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var iter = std.unicode.Utf8Iterator{ .bytes = s, .i = 0 };
    while (iter.nextCodepoint()) |c| {
        const mapped = map_table_b2(c);
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(mapped, &buf) catch continue;
        try result.appendSlice(buf[0..len]);
    }
    return result.toOwnedSlice();
}

// ============================================================================
// Tests
// ============================================================================

test "in_table_b1" {
    try std.testing.expect(in_table_b1(0x00AD)); // SOFT HYPHEN
    try std.testing.expect(in_table_b1(0x200B)); // ZERO WIDTH SPACE
    try std.testing.expect(!in_table_b1('A'));
}

test "map_table_b2" {
    try std.testing.expectEqual(@as(u21, 'a'), map_table_b2('A'));
    try std.testing.expectEqual(@as(u21, 'z'), map_table_b2('Z'));
    try std.testing.expectEqual(@as(u21, 'a'), map_table_b2('a'));
}

test "in_table_c21" {
    try std.testing.expect(in_table_c21(0x00)); // NUL
    try std.testing.expect(in_table_c21(0x1F)); // US
    try std.testing.expect(in_table_c21(0x7F)); // DEL
    try std.testing.expect(!in_table_c21('A'));
}

test "in_table_c3" {
    try std.testing.expect(in_table_c3(0xE000)); // Private use start
    try std.testing.expect(in_table_c3(0xF8FF)); // Private use end
    try std.testing.expect(!in_table_c3('A'));
}

test "in_table_d1" {
    try std.testing.expect(in_table_d1(0x05D0)); // Hebrew Alef
    try std.testing.expect(in_table_d1(0x0621)); // Arabic Hamza
    try std.testing.expect(!in_table_d1('A'));
}

test "in_table_d2" {
    try std.testing.expect(in_table_d2('A'));
    try std.testing.expect(in_table_d2('z'));
    try std.testing.expect(!in_table_d2(0x05D0)); // Hebrew
}

test "mapB1" {
    const allocator = std.testing.allocator;
    const result = try mapB1(allocator, "hello");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "mapB2 case folding" {
    const allocator = std.testing.allocator;
    const result = try mapB2(allocator, "HELLO");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}
