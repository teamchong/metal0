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

    // Precision and/or decimal grouping (Python 3.13+: ._f, .10_f, .,f)
    if (i < spec.len and spec[i] == '.') {
        i += 1;
        // Check if decimal grouping char immediately follows '.' (no precision)
        if (i < spec.len and (spec[i] == ',' or spec[i] == '_')) {
            result.decimal_grouping_char = spec[i];
            i += 1;
        } else {
            // Parse precision digits
            const prec_start = i;
            while (i < spec.len and spec[i] >= '0' and spec[i] <= '9') : (i += 1) {}
            if (i > prec_start) {
                result.precision = std.fmt.parseInt(usize, spec[prec_start..i], 10) catch null;
            }
            // Decimal grouping after precision (e.g., .10_f)
            if (i < spec.len and (spec[i] == ',' or spec[i] == '_')) {
                result.decimal_grouping_char = spec[i];
                i += 1;
            }
        }
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

    // Find decimal point and exponent
    var decimal_pos: ?usize = null;
    var exp_pos: ?usize = null;
    for (number_part, 0..) |c, idx| {
        if (c == '.') decimal_pos = idx;
        if (c == 'e' or c == 'E') {
            exp_pos = idx;
            break;
        }
    }

    const integer_end = decimal_pos orelse (exp_pos orelse number_part.len);
    const integer_part_with_groups = number_part[0..integer_end];
    const rest = number_part[integer_end..];

    // Strip existing grouping characters to get raw digits
    var raw_digits: [64]u8 = undefined;
    var raw_len: usize = 0;
    for (integer_part_with_groups) |c| {
        if (c != '_' and c != ',') {
            raw_digits[raw_len] = c;
            raw_len += 1;
        }
    }

    // Calculate how many digits we need for target width
    // Target: sign + grouped_integer + rest = width
    // grouped_integer = digits + separators
    // For N digits: separators = (N-1)/3
    // So: sign_len + digits + (digits-1)/3 + rest_len = width
    // Solve for digits: digits + (digits-1)/3 = width - sign_len - rest_len
    const target_content_len = width - sign_prefix.len - rest.len;

    // We need to find how many total digits we need
    // If we have D digits, we'll have (D-1)/3 separators
    // Total = D + (D-1)/3
    // We want D + (D-1)/3 >= target_content_len
    var digits_needed: usize = raw_len;
    while (digits_needed + (if (digits_needed > 3) (digits_needed - 1) / 3 else 0) < target_content_len) {
        digits_needed += 1;
    }

    const zeros_to_add = if (digits_needed > raw_len) digits_needed - raw_len else 0;

    // Build result: sign + zeros + raw_digits with grouping + rest
    try result.appendSlice(allocator, sign_prefix);

    // Create combined digits: zeros + raw_digits
    var combined: [128]u8 = undefined;
    var combined_len: usize = 0;
    var i: usize = 0;
    while (i < zeros_to_add) : (i += 1) {
        combined[combined_len] = '0';
        combined_len += 1;
    }
    i = 0;
    while (i < raw_len) : (i += 1) {
        combined[combined_len] = raw_digits[i];
        combined_len += 1;
    }

    // Apply grouping to combined
    try addThousandsGroupingToList(allocator, &result, combined[0..combined_len], sep);
    try result.appendSlice(allocator, rest);

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
    // If neither separator is set, return as-is
    if (int_sep == null and dec_sep == null) {
        return allocator.dupe(u8, num_str);
    }

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
    const fractional_digits = if (decimal_pos) |dp| num_str[dp + 1 ..] else ""; // Skip the '.'

    // Add integer part with grouping if int_sep is set
    if (int_sep) |sep| {
        try addThousandsGroupingToList(allocator, &result, integer_part, sep);
    } else {
        try result.appendSlice(allocator, integer_part);
    }

    // Add decimal point and fractional part
    if (decimal_pos != null) {
        try result.append(allocator, '.');
        if (dec_sep) |sep| {
            // Find exponent part (e or E) - don't group exponent
            var exp_pos: ?usize = null;
            for (fractional_digits, 0..) |c, idx| {
                if (c == 'e' or c == 'E') {
                    exp_pos = idx;
                    break;
                }
            }

            const mantissa_frac = if (exp_pos) |ep| fractional_digits[0..ep] else fractional_digits;
            const exponent_part = if (exp_pos) |ep| fractional_digits[ep..] else "";

            // Add mantissa fractional digits with grouping (groups of 3 from left)
            var count: usize = 0;
            for (mantissa_frac) |c| {
                if (count > 0 and count % 3 == 0) {
                    try result.append(allocator, sep);
                }
                try result.append(allocator, c);
                count += 1;
            }

            // Append exponent unchanged
            try result.appendSlice(allocator, exponent_part);
        } else {
            try result.appendSlice(allocator, fractional_digits);
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Format with significant figures - for empty format spec ('.4')
/// Uses threshold exp >= precision - 1 for switching to scientific
pub fn formatSignificantFigures(allocator: std.mem.Allocator, value: f64, sig_figs: usize) ![]const u8 {
    return formatSignificantFiguresImpl(allocator, value, sig_figs, -1);
}

/// Format with significant figures - for explicit 'g' format ('.4g')
/// Uses threshold exp >= precision for switching to scientific
pub fn formatSignificantFiguresG(allocator: std.mem.Allocator, value: f64, sig_figs: usize) ![]const u8 {
    return formatSignificantFiguresImpl(allocator, value, sig_figs, 0);
}

fn formatSignificantFiguresImpl(allocator: std.mem.Allocator, value: f64, sig_figs_in: usize, exp_threshold_offset: i32) ![]const u8 {
    // Python treats precision 0 as precision 1 for g format
    const sig_figs = if (sig_figs_in == 0) 1 else sig_figs_in;

    if (value == 0.0) {
        var result = std.ArrayListUnmanaged(u8){};
        try result.appendSlice(allocator, "0.");
        try result.appendNTimes(allocator, '0', sig_figs - 1);
        return result.toOwnedSlice(allocator);
    }

    const abs_val = @abs(value);
    const log_val = @log10(abs_val);
    const exp: i32 = @intFromFloat(@floor(log_val));

    var result = std.ArrayListUnmanaged(u8){};

    // Python's format behavior:
    // - Empty format with precision ('.4'): use exponential when exp >= precision - 1 (offset = -1)
    // - Explicit 'g' format ('.4g'): use exponential when exp >= precision (offset = 0)
    const threshold = @as(i32, @intCast(sig_figs)) + exp_threshold_offset;
    const use_exponential = exp < -4 or exp >= threshold;

    if (use_exponential) {
        // Exponential notation: X.XXXe+YY with (sig_figs - 1) decimal places in mantissa
        var mantissa = abs_val;
        const exp_val = exp;

        // Normalize mantissa to 1.xxx
        if (abs_val >= 10.0) {
            const divisor = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(exp)));
            mantissa = abs_val / divisor;
        } else if (abs_val > 0 and abs_val < 1.0) {
            const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(-exp)));
            mantissa = abs_val * multiplier;
        }

        // Round mantissa to sig_figs significant figures
        const mantissa_prec = if (sig_figs > 1) sig_figs - 1 else 0;
        if (value < 0) {
            try result.writer(allocator).print("{d:.[1]}e", .{ -mantissa, mantissa_prec });
        } else {
            try result.writer(allocator).print("{d:.[1]}e", .{ mantissa, mantissa_prec });
        }
        // Format exponent: +XX or -XX with at least 2 digits
        if (exp_val >= 0) {
            try result.append(allocator, '+');
            if (exp_val < 10) try result.append(allocator, '0');
            try result.writer(allocator).print("{d}", .{@as(u32, @intCast(exp_val))});
        } else {
            try result.append(allocator, '-');
            const abs_exp: u32 = @intCast(-exp_val);
            if (abs_exp < 10) try result.append(allocator, '0');
            try result.writer(allocator).print("{d}", .{abs_exp});
        }
    } else {
        // Fixed-point notation
        const decimal_places: i32 = @as(i32, @intCast(sig_figs)) - exp - 1;

        if (decimal_places >= 0) {
            const prec: usize = @intCast(decimal_places);
            try result.writer(allocator).print("{d:.[1]}", .{ value, prec });
        } else {
            try result.writer(allocator).print("{d:.0}", .{value});
        }
    }

    return result.toOwnedSlice(allocator);
}
