/// Unicode Character Type Implementation - Character Classification
///
/// Implements CPython's Objects/unicodectype.c
/// Provides Unicode character classification functions
///
/// Reference: cpython/Objects/unicodectype.c
/// This provides character type lookup using Unicode database tables

const std = @import("std");
const cpython = @import("../include/object.zig");

// ============================================================================
// CHARACTER TYPE FLAGS
// ============================================================================

pub const ALPHA_MASK: u16 = 0x01;
pub const DECIMAL_MASK: u16 = 0x02;
pub const DIGIT_MASK: u16 = 0x04;
pub const LOWER_MASK: u16 = 0x08;
pub const TITLE_MASK: u16 = 0x40;
pub const UPPER_MASK: u16 = 0x80;
pub const XID_START_MASK: u16 = 0x100;
pub const XID_CONTINUE_MASK: u16 = 0x200;
pub const PRINTABLE_MASK: u16 = 0x400;
pub const NUMERIC_MASK: u16 = 0x800;
pub const CASE_IGNORABLE_MASK: u16 = 0x1000;
pub const CASED_MASK: u16 = 0x2000;
pub const EXTENDED_CASE_MASK: u16 = 0x4000;

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

/// _PyUnicode_TypeRecord - Unicode character type information
/// Reference: cpython/Objects/unicodectype.c
pub const _PyUnicode_TypeRecord = extern struct {
    upper: c_int, // 4 bytes - delta to uppercase or index to ExtendedCase
    lower: c_int, // 4 bytes - delta to lowercase or index to ExtendedCase
    title: c_int, // 4 bytes - delta to titlecase or index to ExtendedCase
    decimal: u8, // 1 byte - decimal digit value (0-9) or 0xFF
    digit: u8, // 1 byte - digit value (0-9) or 0xFF
    flags: u16, // 2 bytes - character type flags
};

// Verify _PyUnicode_TypeRecord size: 4+4+4+1+1+2 = 16 bytes
comptime {
    if (@sizeOf(_PyUnicode_TypeRecord) != 16) {
        @compileError("_PyUnicode_TypeRecord size mismatch with CPython");
    }
}

// ============================================================================
// EXTENDED CASE TABLE
// Used for characters that have case mappings that don't fit in simple delta
// Based on CPython's _PyUnicode_ExtendedCase from unicodectype.c
// ============================================================================

/// Extended case mappings for special Unicode characters
/// Each entry contains: [upper_length, upper_chars..., lower_length, lower_chars..., title_length, title_chars...]
const _PyUnicode_ExtendedCase = [_]u32{
    // Index 0: German sharp s (ß, U+00DF) -> SS (uppercase)
    2, 0x0053, 0x0053, // uppercase: SS
    1, 0x00DF, // lowercase: ß
    2, 0x0053, 0x0073, // titlecase: Ss

    // Index 6: Latin small letter dotless i (ı, U+0131) -> I
    1, 0x0049, // uppercase: I
    1, 0x0131, // lowercase: ı
    1, 0x0049, // titlecase: I

    // Index 10: Latin capital letter I with dot above (İ, U+0130) -> i
    1, 0x0130, // uppercase: İ
    1, 0x0069, // lowercase: i
    1, 0x0130, // titlecase: İ

    // Index 14: Greek capital letter sigma (Σ) final form considerations
    1, 0x03A3, // uppercase: Σ
    1, 0x03C3, // lowercase: σ (or ς at end of word)
    1, 0x03A3, // titlecase: Σ

    // Index 18: ff ligature (U+FB00)
    2, 0x0046, 0x0046, // uppercase: FF
    1, 0xFB00, // lowercase: ff
    2, 0x0046, 0x0066, // titlecase: Ff

    // Index 24: fi ligature (U+FB01)
    2, 0x0046, 0x0049, // uppercase: FI
    1, 0xFB01, // lowercase: fi
    2, 0x0046, 0x0069, // titlecase: Fi

    // Index 30: fl ligature (U+FB02)
    2, 0x0046, 0x004C, // uppercase: FL
    1, 0xFB02, // lowercase: fl
    2, 0x0046, 0x006C, // titlecase: Fl

    // Index 36: ffi ligature (U+FB03)
    3, 0x0046, 0x0046, 0x0049, // uppercase: FFI
    1, 0xFB03, // lowercase: ffi
    3, 0x0046, 0x0066, 0x0069, // titlecase: Ffi

    // Index 44: ffl ligature (U+FB04)
    3, 0x0046, 0x0046, 0x004C, // uppercase: FFL
    1, 0xFB04, // lowercase: ffl
    3, 0x0046, 0x0066, 0x006C, // titlecase: Ffl

    // Index 52: st ligature (U+FB05, U+FB06)
    2, 0x0053, 0x0054, // uppercase: ST
    1, 0xFB05, // lowercase: st
    2, 0x0053, 0x0074, // titlecase: St
};

/// Get extended case mapping for a character
/// Returns the codepoint sequence for the requested case transformation
fn getExtendedCase(index: u32, case_type: enum { upper, lower, title }) struct { len: u32, chars: [4]u32 } {
    if (index >= _PyUnicode_ExtendedCase.len) {
        return .{ .len = 0, .chars = [_]u32{0} ** 4 };
    }

    var pos: usize = @intCast(index);
    var result: struct { len: u32, chars: [4]u32 } = .{ .len = 0, .chars = [_]u32{0} ** 4 };

    // Skip to requested case type
    const skips: usize = switch (case_type) {
        .upper => 0,
        .lower => 1,
        .title => 2,
    };

    // Skip previous case entries
    for (0..skips) |_| {
        if (pos >= _PyUnicode_ExtendedCase.len) return result;
        const len = _PyUnicode_ExtendedCase[pos];
        pos += 1 + len;
    }

    if (pos >= _PyUnicode_ExtendedCase.len) return result;

    const len = _PyUnicode_ExtendedCase[pos];
    result.len = len;
    pos += 1;

    for (0..@min(len, 4)) |i| {
        if (pos + i < _PyUnicode_ExtendedCase.len) {
            result.chars[i] = _PyUnicode_ExtendedCase[pos + i];
        }
    }

    return result;
}

// ============================================================================
// UNICODE TYPE TABLES (ASCII + Latin-1 Extended support)
// Full Unicode tables would be generated from UnicodeData.txt
// ============================================================================

/// ASCII type records for characters 0-127
const ascii_type_records: [128]_PyUnicode_TypeRecord = init: {
    var records: [128]_PyUnicode_TypeRecord = undefined;

    for (0..128) |i| {
        const c: u8 = @intCast(i);
        var flags: u16 = PRINTABLE_MASK; // Most printable by default
        var upper: c_int = 0;
        var lower: c_int = 0;
        var decimal: u8 = 0xFF;
        var digit: u8 = 0xFF;

        // Control characters are not printable
        if (c < 0x20 or c == 0x7F) {
            flags = 0;
        }

        // Digits 0-9
        if (c >= '0' and c <= '9') {
            const d: u8 = c - '0';
            decimal = d;
            digit = d;
            flags |= DECIMAL_MASK | DIGIT_MASK | NUMERIC_MASK;
        }

        // Uppercase A-Z
        if (c >= 'A' and c <= 'Z') {
            flags |= ALPHA_MASK | UPPER_MASK | CASED_MASK | XID_START_MASK | XID_CONTINUE_MASK;
            lower = 32; // Delta to lowercase
        }

        // Lowercase a-z
        if (c >= 'a' and c <= 'z') {
            flags |= ALPHA_MASK | LOWER_MASK | CASED_MASK | XID_START_MASK | XID_CONTINUE_MASK;
            upper = -32; // Delta to uppercase
        }

        // Underscore is valid in identifiers
        if (c == '_') {
            flags |= XID_START_MASK | XID_CONTINUE_MASK;
        }

        records[i] = .{
            .upper = upper,
            .lower = lower,
            .title = upper, // Title case same as upper for ASCII
            .decimal = decimal,
            .digit = digit,
            .flags = flags,
        };
    }

    break :init records;
};

/// Default type record for unknown/unhandled characters
const default_type_record: _PyUnicode_TypeRecord = .{
    .upper = 0,
    .lower = 0,
    .title = 0,
    .decimal = 0xFF,
    .digit = 0xFF,
    .flags = PRINTABLE_MASK, // Assume printable by default
};

/// Get the type record for a Unicode code point
fn gettyperecord(code: u32) *const _PyUnicode_TypeRecord {
    if (code >= 0x110000) {
        return &default_type_record;
    }

    // ASCII fast path
    if (code < 128) {
        return &ascii_type_records[code];
    }

    // For non-ASCII, return default for now
    // Full implementation would use generated Unicode tables
    return &default_type_record;
}

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// Returns the titlecase Unicode character corresponding to ch
/// or just ch if no titlecase mapping is known
pub export fn _PyUnicode_ToTitlecase(ch: u32) u32 {
    const ctype = gettyperecord(ch);

    if ((ctype.flags & EXTENDED_CASE_MASK) != 0) {
        // Extended case - use _PyUnicode_ExtendedCase table
        const index: u32 = @intCast(ctype.title);
        const mapping = getExtendedCase(index, .title);
        if (mapping.len > 0) {
            // Return first character of the mapping
            // (Full implementation would handle multi-char mappings)
            return mapping.chars[0];
        }
        return ch;
    }

    const delta: i32 = @intCast(ctype.title);
    const result: i64 = @as(i64, ch) + delta;
    if (result < 0 or result > 0x10FFFF) return ch;
    return @intCast(result);
}

/// Returns 1 for Unicode characters having the category 'Lt', 0 otherwise
pub export fn _PyUnicode_IsTitlecase(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    return if ((ctype.flags & TITLE_MASK) != 0) 1 else 0;
}

/// Returns 1 for Unicode characters having the XID_Start property
pub export fn _PyUnicode_IsXidStart(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    return if ((ctype.flags & XID_START_MASK) != 0) 1 else 0;
}

/// Returns 1 for Unicode characters having the XID_Continue property
pub export fn _PyUnicode_IsXidContinue(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    return if ((ctype.flags & XID_CONTINUE_MASK) != 0) 1 else 0;
}

/// Returns the integer decimal (0-9) for Unicode characters having
/// this property, -1 otherwise
pub export fn _PyUnicode_ToDecimalDigit(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    if ((ctype.flags & DECIMAL_MASK) != 0) {
        return @as(c_int, ctype.decimal);
    }
    return -1;
}

/// Returns 1 if character is a decimal digit
pub export fn _PyUnicode_IsDecimalDigit(ch: u32) c_int {
    return if (_PyUnicode_ToDecimalDigit(ch) >= 0) 1 else 0;
}

/// Returns the integer digit (0-9) for Unicode characters having
/// this property, -1 otherwise
pub export fn _PyUnicode_ToDigit(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    if ((ctype.flags & DIGIT_MASK) != 0) {
        return @as(c_int, ctype.digit);
    }
    return -1;
}

/// Returns 1 if character is a digit
pub export fn _PyUnicode_IsDigit(ch: u32) c_int {
    return if (_PyUnicode_ToDigit(ch) >= 0) 1 else 0;
}

/// Returns 1 for Unicode characters having the Numeric property
pub export fn _PyUnicode_IsNumeric(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    return if ((ctype.flags & NUMERIC_MASK) != 0) 1 else 0;
}

/// Returns 1 for Unicode characters that repr() may use in its output
pub export fn _PyUnicode_IsPrintable(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    return if ((ctype.flags & PRINTABLE_MASK) != 0) 1 else 0;
}

/// Returns 1 for Unicode characters having the category 'Ll'
pub export fn _PyUnicode_IsLowercase(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    return if ((ctype.flags & LOWER_MASK) != 0) 1 else 0;
}

/// Returns 1 for Unicode characters having the category 'Lu'
pub export fn _PyUnicode_IsUppercase(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    return if ((ctype.flags & UPPER_MASK) != 0) 1 else 0;
}

/// Returns the uppercase Unicode character corresponding to ch
pub export fn _PyUnicode_ToUppercase(ch: u32) u32 {
    const ctype = gettyperecord(ch);

    if ((ctype.flags & EXTENDED_CASE_MASK) != 0) {
        return ch; // Would need ExtendedCase table
    }

    const delta: i32 = @intCast(ctype.upper);
    const result: i64 = @as(i64, ch) + delta;
    if (result < 0 or result > 0x10FFFF) return ch;
    return @intCast(result);
}

/// Returns the lowercase Unicode character corresponding to ch
pub export fn _PyUnicode_ToLowercase(ch: u32) u32 {
    const ctype = gettyperecord(ch);

    if ((ctype.flags & EXTENDED_CASE_MASK) != 0) {
        return ch; // Would need ExtendedCase table
    }

    const delta: i32 = @intCast(ctype.lower);
    const result: i64 = @as(i64, ch) + delta;
    if (result < 0 or result > 0x10FFFF) return ch;
    return @intCast(result);
}

/// Returns full lowercase mapping (may be multiple characters)
/// Returns number of characters written to res
pub export fn _PyUnicode_ToLowerFull(ch: u32, res: [*]u32) c_int {
    const ctype = gettyperecord(ch);

    if ((ctype.flags & EXTENDED_CASE_MASK) != 0) {
        // Would need ExtendedCase table for multi-char mappings
        res[0] = ch;
        return 1;
    }

    const delta: i32 = @intCast(ctype.lower);
    const result: i64 = @as(i64, ch) + delta;
    if (result < 0 or result > 0x10FFFF) {
        res[0] = ch;
    } else {
        res[0] = @intCast(result);
    }
    return 1;
}

/// Returns full titlecase mapping
pub export fn _PyUnicode_ToTitleFull(ch: u32, res: [*]u32) c_int {
    const ctype = gettyperecord(ch);

    if ((ctype.flags & EXTENDED_CASE_MASK) != 0) {
        res[0] = ch;
        return 1;
    }

    const delta: i32 = @intCast(ctype.title);
    const result: i64 = @as(i64, ch) + delta;
    if (result < 0 or result > 0x10FFFF) {
        res[0] = ch;
    } else {
        res[0] = @intCast(result);
    }
    return 1;
}

/// Returns full uppercase mapping
pub export fn _PyUnicode_ToUpperFull(ch: u32, res: [*]u32) c_int {
    const ctype = gettyperecord(ch);

    if ((ctype.flags & EXTENDED_CASE_MASK) != 0) {
        res[0] = ch;
        return 1;
    }

    const delta: i32 = @intCast(ctype.upper);
    const result: i64 = @as(i64, ch) + delta;
    if (result < 0 or result > 0x10FFFF) {
        res[0] = ch;
    } else {
        res[0] = @intCast(result);
    }
    return 1;
}

/// Returns full case folding
pub export fn _PyUnicode_ToFoldedFull(ch: u32, res: [*]u32) c_int {
    // Case folding is similar to lowercase for most characters
    return _PyUnicode_ToLowerFull(ch, res);
}

/// Returns 1 for cased Unicode characters
pub export fn _PyUnicode_IsCased(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    return if ((ctype.flags & CASED_MASK) != 0) 1 else 0;
}

/// Returns 1 for case-ignorable Unicode characters
pub export fn _PyUnicode_IsCaseIgnorable(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    return if ((ctype.flags & CASE_IGNORABLE_MASK) != 0) 1 else 0;
}

/// Returns 1 for Unicode characters having the category 'Ll', 'Lu', 'Lt', 'Lo' or 'Lm'
pub export fn _PyUnicode_IsAlpha(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    return if ((ctype.flags & ALPHA_MASK) != 0) 1 else 0;
}

/// Returns 1 if character is alphanumeric
pub export fn _PyUnicode_IsAlnum(ch: u32) c_int {
    const ctype = gettyperecord(ch);
    return if ((ctype.flags & (ALPHA_MASK | DECIMAL_MASK | DIGIT_MASK | NUMERIC_MASK)) != 0) 1 else 0;
}

/// Returns 1 if character is whitespace
pub export fn _PyUnicode_IsWhitespace(ch: u32) c_int {
    // ASCII whitespace characters
    return switch (ch) {
        0x0009, // CHARACTER TABULATION
        0x000A, // LINE FEED
        0x000B, // LINE TABULATION
        0x000C, // FORM FEED
        0x000D, // CARRIAGE RETURN
        0x001C, // FILE SEPARATOR
        0x001D, // GROUP SEPARATOR
        0x001E, // RECORD SEPARATOR
        0x001F, // UNIT SEPARATOR
        0x0020, // SPACE
        0x0085, // NEXT LINE
        0x00A0, // NO-BREAK SPACE
        0x1680, // OGHAM SPACE MARK
        0x2000...0x200A, // Various spaces
        0x2028, // LINE SEPARATOR
        0x2029, // PARAGRAPH SEPARATOR
        0x202F, // NARROW NO-BREAK SPACE
        0x205F, // MEDIUM MATHEMATICAL SPACE
        0x3000, // IDEOGRAPHIC SPACE
        => 1,
        else => 0,
    };
}

/// Returns 1 if character is a line break
pub export fn _PyUnicode_IsLinebreak(ch: u32) c_int {
    return switch (ch) {
        0x000A, // LINE FEED
        0x000B, // LINE TABULATION
        0x000C, // FORM FEED
        0x000D, // CARRIAGE RETURN
        0x001C, // FILE SEPARATOR
        0x001D, // GROUP SEPARATOR
        0x001E, // RECORD SEPARATOR
        0x0085, // NEXT LINE
        0x2028, // LINE SEPARATOR
        0x2029, // PARAGRAPH SEPARATOR
        => 1,
        else => 0,
    };
}
