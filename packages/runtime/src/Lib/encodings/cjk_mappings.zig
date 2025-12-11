//! CJK Codec Mapping Tables - Zig wrapper for CPython's cjkcodecs
//!
//! Provides decode/encode functions for CJK character sets using
//! the mapping tables from CPython's Modules/cjkcodecs/.
//!
//! Supported encodings:
//! - Japanese: JIS X 0208, JIS X 0212, JIS X 0201, CP932
//! - Korean: KS X 1001 (EUC-KR)
//! - Chinese Simplified: GB2312, GBK
//! - Chinese Traditional: Big5, CP950

const std = @import("std");

// Import CPython's CJK mapping tables via C interop
const c = @cImport({
    @cInclude("vendor/cjkcodecs/cjk_mappings.h");
});

/// Invalid Unicode code point (no mapping)
pub const UNIINV: u16 = 0xFFFE;
/// No character mapping available
pub const NOCHAR: u16 = 0xFFFF;

// ============================================================================
// JIS X 0208 (Japanese)
// ============================================================================

/// Decode JIS X 0208 byte pair to Unicode
/// c1, c2 are the two bytes in JIS encoding (0x21-0x7E range)
pub fn decodeJisx0208(c1: u8, c2: u8) ?u21 {
    if (c1 < 0x21 or c1 > 0x7E) return null;

    const idx = &c.jisx0208_decmap[c1];
    if (idx.map == null) return null;
    if (c2 < idx.bottom or c2 > idx.top) return null;

    const result = idx.map[c2 - idx.bottom];
    if (result == UNIINV) return null;
    return @intCast(result);
}

/// Encode Unicode to JIS X 0208 byte pair
/// Returns the two bytes packed as u16 (high byte = c1, low byte = c2)
pub fn encodeJisx0208(unicode: u21) ?u16 {
    if (unicode > 0xFFFF) return null;

    const high: u8 = @intCast(unicode >> 8);
    const low: u8 = @intCast(unicode & 0xFF);

    const idx = &c.jisxcommon_encmap[high];
    if (idx.map == null) return null;
    if (low < idx.bottom or low > idx.top) return null;

    const result = idx.map[low - idx.bottom];
    if (result == NOCHAR) return null;
    return result;
}

// ============================================================================
// JIS X 0212 (Japanese supplemental)
// ============================================================================

/// Decode JIS X 0212 byte pair to Unicode
pub fn decodeJisx0212(c1: u8, c2: u8) ?u21 {
    if (c1 < 0x21 or c1 > 0x7E) return null;

    const idx = &c.jisx0212_decmap[c1];
    if (idx.map == null) return null;
    if (c2 < idx.bottom or c2 > idx.top) return null;

    const result = idx.map[c2 - idx.bottom];
    if (result == UNIINV) return null;
    return @intCast(result);
}

// ============================================================================
// CP932 Extensions (Windows Japanese)
// ============================================================================

/// Decode CP932 extension characters
pub fn decodeCp932Ext(c1: u8, c2: u8) ?u21 {
    const idx = &c.cp932ext_decmap[c1];
    if (idx.map == null) return null;
    if (c2 < idx.bottom or c2 > idx.top) return null;

    const result = idx.map[c2 - idx.bottom];
    if (result == UNIINV) return null;
    return @intCast(result);
}

/// Encode Unicode to CP932 extension
pub fn encodeCp932Ext(unicode: u21) ?u16 {
    if (unicode > 0xFFFF) return null;

    const high: u8 = @intCast(unicode >> 8);
    const low: u8 = @intCast(unicode & 0xFF);

    const idx = &c.cp932ext_encmap[high];
    if (idx.map == null) return null;
    if (low < idx.bottom or low > idx.top) return null;

    const result = idx.map[low - idx.bottom];
    if (result == NOCHAR) return null;
    return result;
}

// ============================================================================
// KS X 1001 (Korean)
// ============================================================================

/// Decode KS X 1001 byte pair to Unicode (EUC-KR)
/// c1, c2 are the raw bytes (0xA1-0xFE range in EUC-KR)
pub fn decodeKsx1001(c1: u8, c2: u8) ?u21 {
    // EUC-KR uses 0xA1-0xFE, but table uses 0x21-0x7E
    const k1 = if (c1 >= 0xA1) c1 -| 0x80 else c1;
    const k2 = if (c2 >= 0xA1) c2 -| 0x80 else c2;

    if (k1 < 0x21 or k1 > 0x7E) return null;

    const idx = &c.ksx1001_decmap[k1];
    if (idx.map == null) return null;
    if (k2 < idx.bottom or k2 > idx.top) return null;

    const result = idx.map[k2 - idx.bottom];
    if (result == UNIINV) return null;
    return @intCast(result);
}

/// Encode Unicode to KS X 1001 byte pair
pub fn encodeKsx1001(unicode: u21) ?u16 {
    if (unicode > 0xFFFF) return null;

    const high: u8 = @intCast(unicode >> 8);
    const low: u8 = @intCast(unicode & 0xFF);

    const idx = &c.ksx1001_encmap[high];
    if (idx.map == null) return null;
    if (low < idx.bottom or low > idx.top) return null;

    const result = idx.map[low - idx.bottom];
    if (result == NOCHAR) return null;
    return result;
}

// ============================================================================
// GB2312 (Chinese Simplified)
// ============================================================================

/// Decode GB2312 byte pair to Unicode
/// c1, c2 are the raw bytes (0xA1-0xFE range in EUC-CN)
pub fn decodeGb2312(c1: u8, c2: u8) ?u21 {
    // GB2312 uses 0xA1-0xFE, but table uses 0x21-0x7E
    const g1 = if (c1 >= 0xA1) c1 -| 0x80 else c1;
    const g2 = if (c2 >= 0xA1) c2 -| 0x80 else c2;

    if (g1 < 0x21 or g1 > 0x7E) return null;

    const idx = &c.gb2312_decmap[g1];
    if (idx.map == null) return null;
    if (g2 < idx.bottom or g2 > idx.top) return null;

    const result = idx.map[g2 - idx.bottom];
    if (result == UNIINV) return null;
    return @intCast(result);
}

/// Encode Unicode to GB2312 byte pair
pub fn encodeGb2312(unicode: u21) ?u16 {
    if (unicode > 0xFFFF) return null;

    const high: u8 = @intCast(unicode >> 8);
    const low: u8 = @intCast(unicode & 0xFF);

    const idx = &c.gbcommon_encmap[high];
    if (idx.map == null) return null;
    if (low < idx.bottom or low > idx.top) return null;

    const result = idx.map[low - idx.bottom];
    if (result == NOCHAR) return null;
    // GB2312-only check: reject GBK extensions (bit 15 set)
    if (result & 0x8000 != 0) return null;
    return result;
}

// ============================================================================
// Big5 (Chinese Traditional)
// ============================================================================

/// Decode Big5 byte pair to Unicode
/// c1 is the lead byte (0x81-0xFE), c2 is the trail byte
pub fn decodeBig5(c1: u8, c2: u8) ?u21 {
    if (c1 < 0x81 or c1 > 0xFE) return null;

    const idx = &c.big5_decmap[c1];
    if (idx.map == null) return null;
    if (c2 < idx.bottom or c2 > idx.top) return null;

    const result = idx.map[c2 - idx.bottom];
    if (result == UNIINV) return null;
    return @intCast(result);
}

/// Encode Unicode to Big5 byte pair
pub fn encodeBig5(unicode: u21) ?u16 {
    if (unicode > 0xFFFF) return null;

    const high: u8 = @intCast(unicode >> 8);
    const low: u8 = @intCast(unicode & 0xFF);

    const idx = &c.big5_encmap[high];
    if (idx.map == null) return null;
    if (low < idx.bottom or low > idx.top) return null;

    const result = idx.map[low - idx.bottom];
    if (result == NOCHAR) return null;
    return result;
}

// ============================================================================
// Shift-JIS Transformation
// ============================================================================

/// Transform JIS X 0208 code to Shift-JIS byte pair
pub fn jisToShiftJis(jis_code: u16) struct { c1: u8, c2: u8 } {
    var c1: u8 = @intCast(jis_code >> 8);
    var c2: u8 = @intCast(jis_code & 0xFF);

    // JIS X 0208 to Shift-JIS transformation
    c2 = if (((c1 - 0x21) & 1) != 0) 0x5E else 0;
    c2 += (c2 - 0x21);
    c1 = (c1 - 0x21) >> 1;

    return .{
        .c1 = if (c1 < 0x1F) c1 + 0x81 else c1 + 0xC1,
        .c2 = if (c2 < 0x3F) c2 + 0x40 else c2 + 0x41,
    };
}

/// Transform Shift-JIS byte pair to JIS X 0208 code
pub fn shiftJisToJis(c1: u8, c2: u8) ?u16 {
    // Validate Shift-JIS lead byte ranges
    if (!((c1 >= 0x81 and c1 <= 0x9F) or (c1 >= 0xE0 and c1 <= 0xEA))) {
        return null;
    }

    // Validate trail byte
    if (!((c2 >= 0x40 and c2 <= 0x7E) or (c2 >= 0x80 and c2 <= 0xFC))) {
        return null;
    }

    var j1: u8 = undefined;
    var j2: u8 = undefined;

    // Shift-JIS to JIS X 0208 transformation
    if (c1 >= 0xE0) {
        j1 = (c1 - 0xC1) * 2;
    } else {
        j1 = (c1 - 0x81) * 2;
    }

    if (c2 >= 0x80) {
        j2 = c2 - 0x41;
    } else {
        j2 = c2 - 0x40;
    }

    if (j2 >= 0x5E) {
        j1 += 1;
        j2 -= 0x5E;
    }

    j1 += 0x21;
    j2 += 0x21;

    return (@as(u16, j1) << 8) | j2;
}

// ============================================================================
// Tests
// ============================================================================

test "JIS X 0208 decode - ideographic space" {
    // JIS 0x2121 should decode to U+3000 (ideographic space)
    const result = decodeJisx0208(0x21, 0x21);
    try std.testing.expectEqual(@as(?u21, 0x3000), result);
}

test "JIS X 0208 encode - ideographic space" {
    // U+3000 should encode to JIS
    const result = encodeJisx0208(0x3000);
    try std.testing.expect(result != null);
}

test "GB2312 decode - ideographic space" {
    // GB2312 0xA1A1 should decode to U+3000
    const result = decodeGb2312(0xA1, 0xA1);
    try std.testing.expectEqual(@as(?u21, 0x3000), result);
}

test "Big5 decode" {
    // Big5 0xA140 should decode to a full-width space
    const result = decodeBig5(0xA1, 0x40);
    try std.testing.expect(result != null);
}

test "KS X 1001 decode" {
    // KS X 1001 should decode Korean characters
    const result = decodeKsx1001(0xA1, 0xA1);
    try std.testing.expect(result != null);
}
