/// format - Format Built-in Function
/// format() implementation with Python format spec parsing.

const std = @import("std");
const conversions = @import("conversions.zig");

// ============================================================================
// Format Function
// ============================================================================

/// Format a value according to format spec
/// Mirrors: builtin format()
/// Format spec: [[fill]align][sign][#][0][width][grouping][.precision][type]
/// Types: s (string), d (decimal), b (binary), o (octal), x/X (hex), e/E (exp), f/F (fixed), g/G (general), % (percent)
pub fn format_builtin(allocator: std.mem.Allocator, value: anytype, spec: []const u8) ![]const u8 {
    if (spec.len == 0) {
        return conversions.str_builtin(allocator, value);
    }

    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    // Parse format spec
    var idx: usize = 0;
    var fill: u8 = ' ';
    var align_char: ?u8 = null;
    var alternate: bool = false;
    var zero_pad: bool = false;
    var width: ?usize = null;
    var precision: ?usize = null;
    var type_char: u8 = 's';

    // Parse fill and align
    if (spec.len >= 2 and (spec[1] == '<' or spec[1] == '>' or spec[1] == '^' or spec[1] == '=')) {
        fill = spec[0];
        align_char = spec[1];
        idx = 2;
    } else if (spec.len >= 1 and (spec[0] == '<' or spec[0] == '>' or spec[0] == '^' or spec[0] == '=')) {
        align_char = spec[0];
        idx = 1;
    }

    // Parse sign
    if (idx < spec.len and (spec[idx] == '+' or spec[idx] == '-' or spec[idx] == ' ')) {
        idx += 1;
    }

    // Parse alternate form
    if (idx < spec.len and spec[idx] == '#') {
        alternate = true;
        idx += 1;
    }

    // Parse zero padding
    if (idx < spec.len and spec[idx] == '0') {
        zero_pad = true;
        idx += 1;
    }

    // Parse width
    var width_start = idx;
    while (idx < spec.len and spec[idx] >= '0' and spec[idx] <= '9') : (idx += 1) {}
    if (idx > width_start) {
        width = std.fmt.parseInt(usize, spec[width_start..idx], 10) catch null;
    }

    // Skip grouping option (,)
    if (idx < spec.len and spec[idx] == ',') {
        idx += 1;
    }

    // Parse precision
    if (idx < spec.len and spec[idx] == '.') {
        idx += 1;
        var prec_start = idx;
        while (idx < spec.len and spec[idx] >= '0' and spec[idx] <= '9') : (idx += 1) {}
        if (idx > prec_start) {
            precision = std.fmt.parseInt(usize, spec[prec_start..idx], 10) catch null;
        }
    }

    // Parse type
    if (idx < spec.len) {
        type_char = spec[idx];
    }

    // Format based on type
    var result: []const u8 = undefined;

    switch (type_info) {
        .int, .comptime_int => {
            const int_val: i64 = @intCast(value);
            result = switch (type_char) {
                'b' => if (alternate)
                    try std.fmt.allocPrint(allocator, "0b{b}", .{@as(u64, @intCast(@abs(int_val)))})
                else
                    try std.fmt.allocPrint(allocator, "{b}", .{@as(u64, @intCast(@abs(int_val)))}),
                'o' => if (alternate)
                    try std.fmt.allocPrint(allocator, "0o{o}", .{@as(u64, @intCast(@abs(int_val)))})
                else
                    try std.fmt.allocPrint(allocator, "{o}", .{@as(u64, @intCast(@abs(int_val)))}),
                'x' => if (alternate)
                    try std.fmt.allocPrint(allocator, "0x{x}", .{@as(u64, @intCast(@abs(int_val)))})
                else
                    try std.fmt.allocPrint(allocator, "{x}", .{@as(u64, @intCast(@abs(int_val)))}),
                'X' => if (alternate)
                    try std.fmt.allocPrint(allocator, "0X{X}", .{@as(u64, @intCast(@abs(int_val)))})
                else
                    try std.fmt.allocPrint(allocator, "{X}", .{@as(u64, @intCast(@abs(int_val)))}),
                else => try std.fmt.allocPrint(allocator, "{d}", .{int_val}),
            };
        },
        .float, .comptime_float => {
            const float_val: f64 = @floatCast(value);
            const prec = precision orelse 6;
            result = switch (type_char) {
                'e', 'E' => try std.fmt.allocPrint(allocator, "{e}", .{float_val}),
                '%' => try std.fmt.allocPrint(allocator, "{d:.{d}}%", .{ float_val * 100, prec }),
                else => blk: {
                    // Fixed-point formatting with precision
                    var buf: [64]u8 = undefined;
                    const formatted = std.fmt.formatFloat(&buf, float_val, .{ .precision = prec }) catch
                        break :blk try allocator.dupe(u8, "0.0");
                    break :blk try allocator.dupe(u8, formatted);
                },
            };
        },
        else => {
            result = try conversions.str_builtin(allocator, value);
        },
    }

    // Apply width padding
    if (width) |w| {
        if (result.len < w) {
            const padding = w - result.len;
            const pad_char: u8 = if (zero_pad) '0' else fill;
            var padded = try allocator.alloc(u8, w);

            const actual_align = align_char orelse (if (type_info == .int or type_info == .float) '>' else '<');
            switch (actual_align) {
                '<' => {
                    @memcpy(padded[0..result.len], result);
                    @memset(padded[result.len..], pad_char);
                },
                '>' => {
                    @memset(padded[0..padding], pad_char);
                    @memcpy(padded[padding..], result);
                },
                '^' => {
                    const left = padding / 2;
                    @memset(padded[0..left], pad_char);
                    @memcpy(padded[left .. left + result.len], result);
                    @memset(padded[left + result.len ..], pad_char);
                },
                else => {
                    @memset(padded[0..padding], pad_char);
                    @memcpy(padded[padding..], result);
                },
            }
            allocator.free(result);
            result = padded;
        }
    }

    return result;
}
