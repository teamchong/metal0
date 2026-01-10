//! CPython source: Lib/colorsys.py
//!
//! Provides conversions between RGB and other color systems:
//! - YIQ (used in NTSC video)
//! - HLS (Hue Lightness Saturation)
//! - HSV (Hue Saturation Value)
//!
//! Mirrors: CPython Lib/colorsys.py

const std = @import("std");

// ============================================================================
// RGB to YIQ conversions
// ============================================================================

/// Convert RGB to YIQ color space.
/// Input: r, g, b in range [0, 1]
/// Output: y in [0, 1], i in [-0.5959, 0.5959], q in [-0.5227, 0.5227]
pub fn rgb_to_yiq(r: f64, g: f64, b: f64) struct { y: f64, i: f64, q: f64 } {
    const y = 0.30 * r + 0.59 * g + 0.11 * b;
    const i = 0.74 * (r - y) - 0.27 * (b - y);
    const q = 0.48 * (r - y) + 0.41 * (b - y);
    return .{ .y = y, .i = i, .q = q };
}

/// Convert YIQ to RGB color space.
/// Input: y in [0, 1], i in [-0.5959, 0.5959], q in [-0.5227, 0.5227]
/// Output: r, g, b in range [0, 1]
pub fn yiq_to_rgb(y: f64, i: f64, q: f64) struct { r: f64, g: f64, b: f64 } {
    const r = y + 0.9468822170900693 * i + 0.6235565819861433 * q;
    const g = y - 0.27478764629897834 * i - 0.6356910791873801 * q;
    const b = y - 1.1085450346420322 * i + 1.7090069284064666 * q;
    return .{
        .r = std.math.clamp(r, 0.0, 1.0),
        .g = std.math.clamp(g, 0.0, 1.0),
        .b = std.math.clamp(b, 0.0, 1.0),
    };
}

// ============================================================================
// RGB to HLS conversions
// ============================================================================

/// Convert RGB to HLS (Hue, Lightness, Saturation).
/// Input: r, g, b in range [0, 1]
/// Output: h in [0, 1], l in [0, 1], s in [0, 1]
pub fn rgb_to_hls(r: f64, g: f64, b: f64) struct { h: f64, l: f64, s: f64 } {
    const maxc = @max(@max(r, g), b);
    const minc = @min(@min(r, g), b);
    const sumc = maxc + minc;
    const rangec = maxc - minc;

    const l = sumc / 2.0;

    if (minc == maxc) {
        return .{ .h = 0.0, .l = l, .s = 0.0 };
    }

    const s = if (l <= 0.5)
        rangec / sumc
    else blk: {
        const denom = 2.0 - sumc;
        // Guard against division by near-zero for near-white colors (gh-106498)
        break :blk if (denom < 1e-14) 1.0 else rangec / denom;
    };

    const rc = (maxc - r) / rangec;
    const gc = (maxc - g) / rangec;
    const bc = (maxc - b) / rangec;

    var h: f64 = undefined;
    if (r == maxc) {
        h = bc - gc;
    } else if (g == maxc) {
        h = 2.0 + rc - bc;
    } else {
        h = 4.0 + gc - rc;
    }

    h = @mod(h / 6.0, 1.0);
    return .{ .h = h, .l = l, .s = s };
}

/// Convert HLS to RGB.
/// Input: h in [0, 1], l in [0, 1], s in [0, 1]
/// Output: r, g, b in range [0, 1]
pub fn hls_to_rgb(h: f64, l: f64, s: f64) struct { r: f64, g: f64, b: f64 } {
    if (s == 0.0) {
        return .{ .r = l, .g = l, .b = l };
    }

    const m2 = if (l <= 0.5)
        l * (1.0 + s)
    else
        l + s - (l * s);

    const m1 = 2.0 * l - m2;

    return .{
        .r = _v(m1, m2, h + 1.0 / 3.0),
        .g = _v(m1, m2, h),
        .b = _v(m1, m2, h - 1.0 / 3.0),
    };
}

fn _v(m1: f64, m2: f64, hue: f64) f64 {
    const h = @mod(hue, 1.0);
    if (h < 1.0 / 6.0) {
        return m1 + (m2 - m1) * h * 6.0;
    }
    if (h < 0.5) {
        return m2;
    }
    if (h < 2.0 / 3.0) {
        return m1 + (m2 - m1) * (2.0 / 3.0 - h) * 6.0;
    }
    return m1;
}

// ============================================================================
// RGB to HSV conversions
// ============================================================================

/// Convert RGB to HSV (Hue, Saturation, Value).
/// Input: r, g, b in range [0, 1]
/// Output: h in [0, 1], s in [0, 1], v in [0, 1]
pub fn rgb_to_hsv(r: f64, g: f64, b: f64) struct { h: f64, s: f64, v: f64 } {
    const maxc = @max(@max(r, g), b);
    const minc = @min(@min(r, g), b);
    const rangec = maxc - minc;

    const v = maxc;

    if (minc == maxc) {
        return .{ .h = 0.0, .s = 0.0, .v = v };
    }

    const s = rangec / maxc;

    const rc = (maxc - r) / rangec;
    const gc = (maxc - g) / rangec;
    const bc = (maxc - b) / rangec;

    var h: f64 = undefined;
    if (r == maxc) {
        h = bc - gc;
    } else if (g == maxc) {
        h = 2.0 + rc - bc;
    } else {
        h = 4.0 + gc - rc;
    }

    h = @mod(h / 6.0, 1.0);
    return .{ .h = h, .s = s, .v = v };
}

/// Convert HSV to RGB.
/// Input: h in [0, 1], s in [0, 1], v in [0, 1]
/// Output: r, g, b in range [0, 1]
pub fn hsv_to_rgb(h: f64, s: f64, v: f64) struct { r: f64, g: f64, b: f64 } {
    if (s == 0.0) {
        return .{ .r = v, .g = v, .b = v };
    }

    const i_float = h * 6.0;
    const i: usize = @intFromFloat(@floor(i_float));
    const f = i_float - @as(f64, @floatFromInt(i));

    const p = v * (1.0 - s);
    const q = v * (1.0 - s * f);
    const t = v * (1.0 - s * (1.0 - f));

    return switch (i % 6) {
        0 => .{ .r = v, .g = t, .b = p },
        1 => .{ .r = q, .g = v, .b = p },
        2 => .{ .r = p, .g = v, .b = t },
        3 => .{ .r = p, .g = q, .b = v },
        4 => .{ .r = t, .g = p, .b = v },
        else => .{ .r = v, .g = p, .b = q },
    };
}

// ============================================================================
// Utility functions
// ============================================================================

/// Convert 8-bit RGB (0-255) to normalized RGB (0-1)
pub fn rgb_int_to_float(r: u8, g: u8, b: u8) struct { r: f64, g: f64, b: f64 } {
    return .{
        .r = @as(f64, @floatFromInt(r)) / 255.0,
        .g = @as(f64, @floatFromInt(g)) / 255.0,
        .b = @as(f64, @floatFromInt(b)) / 255.0,
    };
}

/// Convert normalized RGB (0-1) to 8-bit RGB (0-255)
pub fn rgb_float_to_int(r: f64, g: f64, b: f64) struct { r: u8, g: u8, b: u8 } {
    return .{
        .r = @intFromFloat(std.math.clamp(r * 255.0, 0.0, 255.0)),
        .g = @intFromFloat(std.math.clamp(g * 255.0, 0.0, 255.0)),
        .b = @intFromFloat(std.math.clamp(b * 255.0, 0.0, 255.0)),
    };
}

/// Parse hex color string (#RRGGBB or RRGGBB) to RGB
pub fn hex_to_rgb(hex: []const u8) !struct { r: f64, g: f64, b: f64 } {
    var start: usize = 0;
    if (hex.len > 0 and hex[0] == '#') {
        start = 1;
    }

    if (hex.len - start != 6) {
        return error.InvalidFormat;
    }

    const r = std.fmt.parseInt(u8, hex[start .. start + 2], 16) catch return error.InvalidFormat;
    const g = std.fmt.parseInt(u8, hex[start + 2 .. start + 4], 16) catch return error.InvalidFormat;
    const b = std.fmt.parseInt(u8, hex[start + 4 .. start + 6], 16) catch return error.InvalidFormat;

    return rgb_int_to_float(r, g, b);
}

/// Convert RGB to hex color string (#RRGGBB)
pub fn rgb_to_hex(allocator: std.mem.Allocator, r: f64, g: f64, b: f64) ![]u8 {
    const rgb = rgb_float_to_int(r, g, b);
    const result = try allocator.alloc(u8, 7);
    _ = std.fmt.bufPrint(result, "#{X:0>2}{X:0>2}{X:0>2}", .{ rgb.r, rgb.g, rgb.b }) catch unreachable;
    return result;
}

// ============================================================================
// Color interpolation
// ============================================================================

/// Linearly interpolate between two colors in RGB space
pub fn lerp_rgb(
    r1: f64,
    g1: f64,
    b1: f64,
    r2: f64,
    g2: f64,
    b2: f64,
    t: f64,
) struct { r: f64, g: f64, b: f64 } {
    const tt = std.math.clamp(t, 0.0, 1.0);
    return .{
        .r = r1 + (r2 - r1) * tt,
        .g = g1 + (g2 - g1) * tt,
        .b = b1 + (b2 - b1) * tt,
    };
}

/// Interpolate between two colors in HSV space (better for color gradients)
pub fn lerp_hsv(
    h1: f64,
    s1: f64,
    v1: f64,
    h2: f64,
    s2: f64,
    v2: f64,
    t: f64,
) struct { h: f64, s: f64, v: f64 } {
    const tt = std.math.clamp(t, 0.0, 1.0);

    // Handle hue wrap-around (shortest path)
    var dh = h2 - h1;
    if (dh > 0.5) dh -= 1.0;
    if (dh < -0.5) dh += 1.0;

    return .{
        .h = @mod(h1 + dh * tt, 1.0),
        .s = s1 + (s2 - s1) * tt,
        .v = v1 + (v2 - v1) * tt,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "rgb_to_yiq and back" {
    const rgb = .{ .r = 0.5, .g = 0.3, .b = 0.8 };
    const yiq = rgb_to_yiq(rgb.r, rgb.g, rgb.b);
    const back = yiq_to_rgb(yiq.y, yiq.i, yiq.q);

    try std.testing.expectApproxEqAbs(rgb.r, back.r, 0.01);
    try std.testing.expectApproxEqAbs(rgb.g, back.g, 0.01);
    try std.testing.expectApproxEqAbs(rgb.b, back.b, 0.01);
}

test "rgb_to_hls and back" {
    const rgb = .{ .r = 0.5, .g = 0.3, .b = 0.8 };
    const hls = rgb_to_hls(rgb.r, rgb.g, rgb.b);
    const back = hls_to_rgb(hls.h, hls.l, hls.s);

    try std.testing.expectApproxEqAbs(rgb.r, back.r, 0.01);
    try std.testing.expectApproxEqAbs(rgb.g, back.g, 0.01);
    try std.testing.expectApproxEqAbs(rgb.b, back.b, 0.01);
}

test "rgb_to_hsv and back" {
    const rgb = .{ .r = 0.5, .g = 0.3, .b = 0.8 };
    const hsv = rgb_to_hsv(rgb.r, rgb.g, rgb.b);
    const back = hsv_to_rgb(hsv.h, hsv.s, hsv.v);

    try std.testing.expectApproxEqAbs(rgb.r, back.r, 0.01);
    try std.testing.expectApproxEqAbs(rgb.g, back.g, 0.01);
    try std.testing.expectApproxEqAbs(rgb.b, back.b, 0.01);
}

test "hsv pure red" {
    // Pure red is hue=0, sat=1, val=1
    const rgb = hsv_to_rgb(0.0, 1.0, 1.0);
    try std.testing.expectApproxEqAbs(1.0, rgb.r, 0.01);
    try std.testing.expectApproxEqAbs(0.0, rgb.g, 0.01);
    try std.testing.expectApproxEqAbs(0.0, rgb.b, 0.01);
}

test "hsv pure green" {
    // Pure green is hue=1/3, sat=1, val=1
    const rgb = hsv_to_rgb(1.0 / 3.0, 1.0, 1.0);
    try std.testing.expectApproxEqAbs(0.0, rgb.r, 0.01);
    try std.testing.expectApproxEqAbs(1.0, rgb.g, 0.01);
    try std.testing.expectApproxEqAbs(0.0, rgb.b, 0.01);
}

test "hsv pure blue" {
    // Pure blue is hue=2/3, sat=1, val=1
    const rgb = hsv_to_rgb(2.0 / 3.0, 1.0, 1.0);
    try std.testing.expectApproxEqAbs(0.0, rgb.r, 0.01);
    try std.testing.expectApproxEqAbs(0.0, rgb.g, 0.01);
    try std.testing.expectApproxEqAbs(1.0, rgb.b, 0.01);
}

test "rgb gray" {
    // Gray has no saturation
    const hsv = rgb_to_hsv(0.5, 0.5, 0.5);
    try std.testing.expectApproxEqAbs(0.0, hsv.s, 0.01);
    try std.testing.expectApproxEqAbs(0.5, hsv.v, 0.01);
}

test "hex_to_rgb" {
    const rgb = try hex_to_rgb("#FF8040");
    try std.testing.expectApproxEqAbs(1.0, rgb.r, 0.01);
    try std.testing.expectApproxEqAbs(0.502, rgb.g, 0.01);
    try std.testing.expectApproxEqAbs(0.251, rgb.b, 0.01);
}

test "rgb_to_hex" {
    const allocator = std.testing.allocator;
    const hex = try rgb_to_hex(allocator, 1.0, 0.5, 0.25);
    defer allocator.free(hex);
    try std.testing.expectEqualStrings("#FF803F", hex);
}

test "lerp_rgb" {
    const result = lerp_rgb(0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.5);
    try std.testing.expectApproxEqAbs(0.5, result.r, 0.01);
    try std.testing.expectApproxEqAbs(0.5, result.g, 0.01);
    try std.testing.expectApproxEqAbs(0.5, result.b, 0.01);
}
