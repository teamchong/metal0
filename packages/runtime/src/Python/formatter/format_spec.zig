/// Format specification parsing and application
const std = @import("std");

/// Python format spec: [[fill]align][sign][#][0][width][grouping][.precision][type]
pub const FormatSpec = struct {
    fill: u8 = ' ',
    alignment: enum { left, right, center, sign_aware } = .right,
    sign: enum { minus_only, always, space } = .minus_only,
    alternate: bool = false,
    zero_pad: bool = false,
    width: ?usize = null,
    grouping_char: ?u8 = null,
    precision: ?usize = null,
    decimal_grouping_char: ?u8 = null,
    fmt_type: u8 = 0,
};

pub fn parseFormatSpec(spec: []const u8) FormatSpec {
    var result = FormatSpec{};
    if (spec.len == 0) return result;

    var i: usize = 0;

    // Check for fill and align
    if (spec.len >= 2) {
        const maybe_align = spec[1];
        if (maybe_align == '<' or maybe_align == '>' or maybe_align == '^' or maybe_align == '=') {
            result.fill = spec[0];
            result.alignment = switch (maybe_align) {
                '<' => .left,
                '>' => .right,
                '^' => .center,
                '=' => .sign_aware,
                else => .right,
            };
            i = 2;
        }
    }
    if (i == 0 and spec.len >= 1) {
        const maybe_align = spec[0];
        if (maybe_align == '<' or maybe_align == '>' or maybe_align == '^' or maybe_align == '=') {
            result.alignment = switch (maybe_align) {
                '<' => .left,
                '>' => .right,
                '^' => .center,
                '=' => .sign_aware,
                else => .right,
            };
            i = 1;
        }
    }

    // Sign
    if (i < spec.len) {
        if (spec[i] == '+') {
            result.sign = .always;
            i += 1;
        } else if (spec[i] == '-') {
            result.sign = .minus_only;
            i += 1;
        } else if (spec[i] == ' ') {
            result.sign = .space;
            i += 1;
        }
    }

    // Alternate form
    if (i < spec.len and spec[i] == '#') {
        result.alternate = true;
        i += 1;
    }

    // Zero padding
    if (i < spec.len and spec[i] == '0') {
        result.zero_pad = true;
        result.fill = '0';
        if (result.alignment == .right and i > 0 and (spec[0] == '<' or spec[0] == '>' or spec[0] == '^' or spec[0] == '=')) {
            // Keep explicit alignment
        } else if (result.alignment == .right) {
            result.alignment = .sign_aware;
        }
        i += 1;
    }

    // Width
    const width_start = i;
    while (i < spec.len and spec[i] >= '0' and spec[i] <= '9') : (i += 1) {}
    if (i > width_start) {
        result.width = std.fmt.parseInt(usize, spec[width_start..i], 10) catch null;
    }

    // Grouping
    if (i < spec.len and (spec[i] == ',' or spec[i] == '_')) {
        result.grouping_char = spec[i];
        i += 1;
    }

    // Precision
    if (i < spec.len and spec[i] == '.') {
        i += 1;
        const prec_start = i;
        while (i < spec.len and spec[i] >= '0' and spec[i] <= '9') : (i += 1) {}
        if (i > prec_start) {
            result.precision = std.fmt.parseInt(usize, spec[prec_start..i], 10) catch null;
        }
    }

    // Decimal grouping
    if (i < spec.len and (spec[i] == ',' or spec[i] == '_')) {
        result.decimal_grouping_char = spec[i];
        i += 1;
    }

    // Type
    if (i < spec.len) {
        result.fmt_type = spec[i];
    }

    return result;
}

pub fn applyPadding(allocator: std.mem.Allocator, content: []const u8, spec: FormatSpec) ![]const u8 {
    const width = spec.width orelse return allocator.dupe(u8, content);
    if (content.len >= width) return allocator.dupe(u8, content);

    const padding = width - content.len;
    var result = std.ArrayListUnmanaged(u8){};

    switch (spec.alignment) {
        .left => {
            try result.appendSlice(allocator, content);
            try result.appendNTimes(allocator, spec.fill, padding);
        },
        .right, .sign_aware => {
            try result.appendNTimes(allocator, spec.fill, padding);
            try result.appendSlice(allocator, content);
        },
        .center => {
            const left_pad = padding / 2;
            const right_pad = padding - left_pad;
            try result.appendNTimes(allocator, spec.fill, left_pad);
            try result.appendSlice(allocator, content);
            try result.appendNTimes(allocator, spec.fill, right_pad);
        },
    }

    return result.toOwnedSlice(allocator);
}

pub fn applyZeroPaddingWithGrouping(allocator: std.mem.Allocator, content: []const u8, width: usize, sep: u8) ![]const u8 {
    if (content.len >= width) return allocator.dupe(u8, content);

    var result = std.ArrayListUnmanaged(u8){};
    var sign_prefix: []const u8 = "";
    var number_start: usize = 0;

    // Handle sign prefix
    if (content.len > 0 and (content[0] == '-' or content[0] == '+' or content[0] == ' ')) {
        sign_prefix = content[0..1];
        number_start = 1;
    }

    // Handle base prefix
    if (content.len > number_start + 1 and content[number_start] == '0') {
        const next = content[number_start + 1];
        if (next == 'x' or next == 'X' or next == 'b' or next == 'B' or next == 'o' or next == 'O') {
            sign_prefix = content[0 .. number_start + 2];
            number_start += 2;
        }
    }

    const number_part = content[number_start..];

    // Find decimal point
    var decimal_pos: ?usize = null;
    for (number_part, 0..) |c, idx| {
        if (c == '.') {
            decimal_pos = idx;
            break;
        }
    }

    const integer_part = if (decimal_pos) |dp| number_part[0..dp] else number_part;
    const fractional_part = if (decimal_pos) |dp| number_part[dp..] else "";

    // Calculate zeros needed
    const content_width = sign_prefix.len + integer_part.len + fractional_part.len;
    const group_count = if (integer_part.len > 3) (integer_part.len - 1) / 3 else 0;
    const final_width = content_width + group_count;

    if (final_width >= width) {
        // Just add grouping
        try result.appendSlice(allocator, sign_prefix);
        try addThousandsGroupingToList(allocator, &result, integer_part, sep);
        try result.appendSlice(allocator, fractional_part);
    } else {
        // Add zeros and grouping
        const zeros_needed = width - final_width;
        try result.appendSlice(allocator, sign_prefix);
        try result.appendNTimes(allocator, '0', zeros_needed);
        try addThousandsGroupingToList(allocator, &result, integer_part, sep);
        try result.appendSlice(allocator, fractional_part);
    }

    return result.toOwnedSlice(allocator);
}

fn addThousandsGroupingToList(allocator: std.mem.Allocator, result: *std.ArrayListUnmanaged(u8), num_str: []const u8, sep: u8) !void {
    if (num_str.len <= 3) {
        try result.appendSlice(allocator, num_str);
        return;
    }

    const first_group_size = num_str.len % 3;
    var pos: usize = 0;

    if (first_group_size > 0) {
        try result.appendSlice(allocator, num_str[0..first_group_size]);
        pos = first_group_size;
    }

    while (pos < num_str.len) {
        if (pos > 0) {
            try result.append(allocator, sep);
        }
        try result.appendSlice(allocator, num_str[pos..@min(pos + 3, num_str.len)]);
        pos += 3;
    }
}

pub fn addThousandsGrouping(allocator: std.mem.Allocator, num_str: []const u8, int_sep: ?u8, dec_sep: ?u8) ![]const u8 {
    _ = dec_sep;
    const sep = int_sep orelse return allocator.dupe(u8, num_str);

    var result = std.ArrayListUnmanaged(u8){};

    // Find decimal point
    var decimal_pos: ?usize = null;
    for (num_str, 0..) |c, idx| {
        if (c == '.') {
            decimal_pos = idx;
            break;
        }
    }

    const integer_part = if (decimal_pos) |dp| num_str[0..dp] else num_str;
    const fractional_part = if (decimal_pos) |dp| num_str[dp..] else "";

    try addThousandsGroupingToList(allocator, &result, integer_part, sep);
    try result.appendSlice(allocator, fractional_part);

    return result.toOwnedSlice(allocator);
}

pub fn formatSignificantFigures(allocator: std.mem.Allocator, value: f64, sig_figs: usize) ![]const u8 {
    if (sig_figs == 0) {
        return allocator.dupe(u8, "0");
    }

    if (value == 0.0) {
        var result = std.ArrayListUnmanaged(u8){};
        try result.appendSlice(allocator, "0.");
        try result.appendNTimes(allocator, '0', sig_figs - 1);
        return result.toOwnedSlice(allocator);
    }

    const abs_val = @abs(value);
    const log_val = @log10(abs_val);
    const exp: i32 = @intFromFloat(@floor(log_val));

    // Calculate decimal places needed
    const decimal_places: i32 = @as(i32, @intCast(sig_figs)) - exp - 1;

    var result = std.ArrayListUnmanaged(u8){};

    if (decimal_places >= 0) {
        const prec: usize = @intCast(decimal_places);
        try result.writer(allocator).print("{d:.[1]}", .{ value, prec });
    } else {
        try result.writer(allocator).print("{d:.0}", .{value});
    }

    return result.toOwnedSlice(allocator);
}
