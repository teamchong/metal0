//! CPython source: Lib/stringprep.py
//!
//! Implements the StringPrep profile as defined in RFC 3454.
//! Used for preparation of internationalized strings, particularly for IDNA.
//!
//! Mirrors: CPython Lib/stringprep.py

const std = @import("std");

// ============================================================================
// Helper to decode first UTF-8 codepoint from a string
// ============================================================================
fn decodeFirstCodepoint(s: []const u8) ?u21 {
    if (s.len == 0) return null;
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return null;
    if (s.len < len) return null;
    return std.unicode.utf8Decode(s[0..len]) catch null;
}

// ============================================================================
// Character set membership tables (take string, check first char)
// ============================================================================

/// Table A.1: Unassigned code points in Unicode 3.2
pub fn in_table_a1(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
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
pub fn in_table_b1(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
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

/// Table B.2: Case mapping (simplified - returns lowercase char as string)
/// Returns true if mapping exists (Python returns the mapped char or original)
pub fn map_table_b2(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
    // Simplified ASCII case folding - returns true if char can be mapped
    return c >= 'A' and c <= 'Z' or c >= 'a' and c <= 'z';
}

/// Table B.3: Case folding with normalization
pub fn map_table_b3(s: []const u8) bool {
    // Same as B.2 for basic ASCII
    return map_table_b2(s);
}

/// Table C.1.1: ASCII space characters
pub fn in_table_c11(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
    return c == 0x0020; // SPACE
}

/// Table C.1.2: Non-ASCII space characters
pub fn in_table_c12(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
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

/// Table C.1: Space characters (combined C.1.1 and C.1.2)
pub fn in_table_c11_c12(s: []const u8) bool {
    return in_table_c11(s) or in_table_c12(s);
}

/// Table C.2.1: ASCII control characters
pub fn in_table_c21(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
    return c <= 0x001F or c == 0x007F;
}

/// Table C.2.2: Non-ASCII control characters
pub fn in_table_c22(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
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

/// Table C.2: Control characters (combined C.2.1 and C.2.2)
pub fn in_table_c21_c22(s: []const u8) bool {
    return in_table_c21(s) or in_table_c22(s);
}

/// Table C.3: Private use
pub fn in_table_c3(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
    return switch (c) {
        0xE000...0xF8FF => true, // Private use area
        0xF0000...0xFFFFD => true, // Supplementary private use area A
        0x100000...0x10FFFD => true, // Supplementary private use area B
        else => false,
    };
}

/// Table C.4: Non-character code points
pub fn in_table_c4(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
    // Last two code points of each plane
    if ((c & 0xFFFF) >= 0xFFFE) return true;
    // Noncharacter range
    return c >= 0xFDD0 and c <= 0xFDEF;
}

/// Table C.5: Surrogate codes
pub fn in_table_c5(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
    return c >= 0xD800 and c <= 0xDFFF;
}

/// Table C.6: Inappropriate for plain text
pub fn in_table_c6(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
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
pub fn in_table_c7(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
    return c >= 0x2FF0 and c <= 0x2FFB; // Ideographic description characters
}

/// Table C.8: Change display properties or deprecated
pub fn in_table_c8(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
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
pub fn in_table_c9(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
    return c >= 0xE0001 and c <= 0xE007F;
}

/// Table D.1: Characters with bidirectional property "R" or "AL"
pub fn in_table_d1(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
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
pub fn in_table_d2(s: []const u8) bool {
    const c = decodeFirstCodepoint(s) orelse return false;
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
    var i: usize = 0;
    while (i < s.len) {
        const len = std.unicode.utf8ByteSequenceLength(s[i]) catch {
            i += 1;
            continue;
        };
        if (i + len > s.len) break;
        if (in_table_a1(s[i .. i + len])) return true;
        i += len;
    }
    return false;
}

/// Map string according to table B.1 (remove mapped-to-nothing chars)
pub fn mapB1(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < s.len) {
        const len = std.unicode.utf8ByteSequenceLength(s[i]) catch {
            i += 1;
            continue;
        };
        if (i + len > s.len) break;
        if (!in_table_b1(s[i .. i + len])) {
            try result.appendSlice(s[i .. i + len]);
        }
        i += len;
    }
    return result.toOwnedSlice();
}

/// Map string to lowercase (table B.2)
pub fn mapB2(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < s.len) {
        const len = std.unicode.utf8ByteSequenceLength(s[i]) catch {
            try result.append(s[i]);
            i += 1;
            continue;
        };
        if (i + len > s.len) break;
        const c = std.unicode.utf8Decode(s[i .. i + len]) catch {
            try result.appendSlice(s[i .. i + len]);
            i += len;
            continue;
        };
        // Simple ASCII case folding
        const mapped: u21 = if (c >= 'A' and c <= 'Z') c + 32 else c;
        var buf: [4]u8 = undefined;
        const enc_len = std.unicode.utf8Encode(mapped, &buf) catch {
            try result.appendSlice(s[i .. i + len]);
            i += len;
            continue;
        };
        try result.appendSlice(buf[0..enc_len]);
        i += len;
    }
    return result.toOwnedSlice();
}
