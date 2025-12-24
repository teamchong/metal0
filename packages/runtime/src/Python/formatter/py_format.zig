/// Python format() builtin and string formatting
const std = @import("std");
const format_spec = @import("format_spec.zig");
const float_format = @import("float_format.zig");
const FormatSpec = format_spec.FormatSpec;
const parseFormatSpec = format_spec.parseFormatSpec;
const applyPadding = format_spec.applyPadding;
const applyZeroPaddingWithGrouping = format_spec.applyZeroPaddingWithGrouping;
const addThousandsGrouping = format_spec.addThousandsGrouping;
const formatSignificantFigures = format_spec.formatSignificantFigures;
const formatSignificantFiguresG = format_spec.formatSignificantFiguresG;
const FloatSignOption = float_format.FloatSignOption;
const FloatFormatType = float_format.FloatFormatType;
const formatPythonFloat = float_format.formatPythonFloat;
const formatFloat = float_format.formatFloat;

/// Python format(value, format_spec) builtin
pub fn pyFormat(allocator: std.mem.Allocator, value: anytype, format_spec_str: anytype) ![]const u8 {
    const spec_str: []const u8 = if (@TypeOf(format_spec_str) == []const u8) format_spec_str else @as([]const u8, format_spec_str);
    var spec = parseFormatSpec(spec_str);

    const T = @TypeOf(value);
    var buf = std.ArrayListUnmanaged(u8){};

    if (T == []const u8 or T == [:0]const u8) {
        if (spec_str.len == 0 or (spec_str[0] != '<' and spec_str[0] != '>' and spec_str[0] != '^' and spec_str[0] != '=' and
            (spec_str.len < 2 or (spec_str[1] != '<' and spec_str[1] != '>' and spec_str[1] != '^' and spec_str[1] != '='))))
        {
            spec.alignment = .left;
        }
        var str = value;
        if (spec.precision) |p| {
            if (p < str.len) str = str[0..p];
        }
        try buf.appendSlice(allocator, str);
    } else if (T == bool) {
        try buf.appendSlice(allocator, if (value) "True" else "False");
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        const int_val: i64 = @intCast(value);

        // Float format types on integers - convert to float and use float formatting
        switch (spec.fmt_type) {
            'e', 'E', 'f', 'F', 'g', 'G', '%' => {
                return pyFormat(allocator, @as(f64, @floatFromInt(int_val)), spec_str);
            },
            else => {},
        }

        const abs_val: u64 = if (int_val < 0) @intCast(-int_val) else @intCast(int_val);
        const is_neg = int_val < 0;

        var base: u8 = 10;
        var prefix: []const u8 = "";
        var uppercase = false;

        switch (spec.fmt_type) {
            'b' => base = 2,
            'o' => {
                base = 8;
                if (spec.alternate and abs_val != 0) prefix = "0o";
            },
            'x' => {
                base = 16;
                if (spec.alternate and abs_val != 0) prefix = "0x";
            },
            'X' => {
                base = 16;
                uppercase = true;
                if (spec.alternate and abs_val != 0) prefix = "0X";
            },
            'c' => {
                if (abs_val < 128) {
                    try buf.append(allocator, @as(u8, @intCast(abs_val)));
                }
                return applyPadding(allocator, buf.items, spec);
            },
            else => {},
        }

        var temp: [66]u8 = undefined;
        var temp_len: usize = 0;
        var n = abs_val;
        if (n == 0) {
            temp[0] = '0';
            temp_len = 1;
        } else {
            while (n > 0) {
                const digit = @as(u8, @intCast(n % base));
                const c = if (digit < 10) '0' + digit else if (uppercase) 'A' + digit - 10 else 'a' + digit - 10;
                temp[temp_len] = c;
                temp_len += 1;
                n /= base;
            }
        }

        if (spec.zero_pad and spec.width != null) {
            var num_buf: [68]u8 = undefined;
            var num_len: usize = 0;

            if (is_neg) {
                num_buf[num_len] = '-';
                num_len += 1;
            } else if (spec.sign == .always) {
                num_buf[num_len] = '+';
                num_len += 1;
            } else if (spec.sign == .space) {
                num_buf[num_len] = ' ';
                num_len += 1;
            }

            for (prefix) |c| {
                num_buf[num_len] = c;
                num_len += 1;
            }

            const width = spec.width.?;
            const digits_and_prefix_len = num_len + temp_len;
            const zeros_needed = if (width > digits_and_prefix_len) width - digits_and_prefix_len else 0;

            var z: usize = 0;
            while (z < zeros_needed) : (z += 1) {
                num_buf[num_len] = '0';
                num_len += 1;
            }

            var j: usize = 0;
            while (j < temp_len) : (j += 1) {
                num_buf[num_len + j] = temp[temp_len - 1 - j];
            }
            num_len += temp_len;

            try buf.appendSlice(allocator, num_buf[0..num_len]);
            return allocator.dupe(u8, buf.items);
        }

        var num_buf: [68]u8 = undefined;
        var num_len: usize = 0;

        if (is_neg) {
            num_buf[num_len] = '-';
            num_len += 1;
        } else if (spec.sign == .always) {
            num_buf[num_len] = '+';
            num_len += 1;
        } else if (spec.sign == .space) {
            num_buf[num_len] = ' ';
            num_len += 1;
        }

        for (prefix) |c| {
            num_buf[num_len] = c;
            num_len += 1;
        }

        var j: usize = 0;
        while (j < temp_len) : (j += 1) {
            num_buf[num_len + j] = temp[temp_len - 1 - j];
        }
        num_len += temp_len;

        try buf.appendSlice(allocator, num_buf[0..num_len]);
    } else if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
        const float_val: f64 = @floatCast(value);
        const prec = spec.precision orelse 6;

        switch (spec.fmt_type) {
            's', 'b', 'c', 'd', 'o', 'x', 'X', 'n' => {
                return error.ValueError;
            },
            else => {},
        }

        if (std.math.isNan(float_val)) {
            const uppercase = spec.fmt_type == 'F' or spec.fmt_type == 'E';
            if (spec.sign == .always) {
                try buf.append(allocator, '+');
            } else if (spec.sign == .space) {
                try buf.append(allocator, ' ');
            }
            try buf.appendSlice(allocator, if (uppercase) "NAN" else "nan");
        } else if (std.math.isInf(float_val)) {
            const uppercase = spec.fmt_type == 'F' or spec.fmt_type == 'E';
            if (float_val < 0) {
                try buf.append(allocator, '-');
            } else if (spec.sign == .always) {
                try buf.append(allocator, '+');
            } else if (spec.sign == .space) {
                try buf.append(allocator, ' ');
            }
            try buf.appendSlice(allocator, if (uppercase) "INF" else "inf");
        } else {
            if (float_val < 0) {
                try buf.append(allocator, '-');
            } else if (spec.sign == .always) {
                try buf.append(allocator, '+');
            } else if (spec.sign == .space) {
                try buf.append(allocator, ' ');
            }

            const abs_val = @abs(float_val);
            switch (spec.fmt_type) {
                'e', 'E' => {
                    var exp: i32 = 0;
                    var mantissa = abs_val;
                    if (abs_val >= 1.0) {
                        while (mantissa >= 10.0) {
                            mantissa /= 10.0;
                            exp += 1;
                        }
                    } else if (abs_val > 0) {
                        while (mantissa < 1.0) {
                            mantissa *= 10.0;
                            exp -= 1;
                        }
                    }
                    try buf.writer(allocator).print("{d:.[1]}", .{ mantissa, prec });
                    try buf.append(allocator, if (spec.fmt_type == 'E') 'E' else 'e');
                    try buf.append(allocator, if (exp >= 0) '+' else '-');
                    const abs_exp: u32 = @intCast(@abs(exp));
                    if (abs_exp < 10) try buf.append(allocator, '0');
                    try buf.writer(allocator).print("{d}", .{abs_exp});
                },
                '%' => {
                    try buf.writer(allocator).print("{d:.[1]}", .{ abs_val * 100.0, prec });
                    try buf.append(allocator, '%');
                },
                'f', 'F' => {
                    try buf.writer(allocator).print("{d:.[1]}", .{ abs_val, prec });
                },
                'g', 'G' => {
                    // 'g' format: significant figures with trailing zeros stripped
                    // Unless alternate form (#) is used - then always include decimal point
                    // Uses exp >= precision threshold (different from empty format which uses exp >= precision - 1)
                    const sig_figs = spec.precision orelse 6;
                    const formatted_str = try formatSignificantFiguresG(allocator, abs_val, sig_figs);
                    defer allocator.free(formatted_str);

                    if (spec.alternate) {
                        // Alternate form (#): don't strip trailing zeros, always include decimal point
                        // Find if there's a decimal point
                        var has_dot = false;
                        var e_pos: ?usize = null;
                        for (formatted_str, 0..) |c, idx| {
                            if (c == '.') has_dot = true;
                            if (c == 'e' or c == 'E') {
                                e_pos = idx;
                                break;
                            }
                        }

                        if (e_pos) |pos| {
                            // Scientific notation - insert '.' before 'e' if not present
                            if (!has_dot) {
                                try buf.appendSlice(allocator, formatted_str[0..pos]);
                                try buf.append(allocator, '.');
                                try buf.appendSlice(allocator, formatted_str[pos..]);
                            } else {
                                try buf.appendSlice(allocator, formatted_str);
                            }
                        } else {
                            // Fixed notation - append '.' if not present
                            if (!has_dot) {
                                try buf.appendSlice(allocator, formatted_str);
                                try buf.append(allocator, '.');
                            } else {
                                try buf.appendSlice(allocator, formatted_str);
                            }
                        }
                    } else {
                        // Normal form: strip trailing zeros and decimal point
                        var e_pos: ?usize = null;
                        for (formatted_str, 0..) |c, idx| {
                            if (c == 'e' or c == 'E') {
                                e_pos = idx;
                                break;
                            }
                        }

                        if (e_pos) |pos| {
                            // Has exponent - strip zeros from mantissa part only
                            var mantissa_end = pos;
                            while (mantissa_end > 1 and formatted_str[mantissa_end - 1] == '0') {
                                mantissa_end -= 1;
                            }
                            if (mantissa_end > 0 and formatted_str[mantissa_end - 1] == '.') {
                                mantissa_end -= 1;
                            }
                            // Append mantissa + exponent
                            try buf.appendSlice(allocator, formatted_str[0..mantissa_end]);
                            try buf.appendSlice(allocator, formatted_str[pos..]);
                        } else {
                            // No exponent - strip trailing zeros only after decimal point
                            // Find decimal point first
                            var dot_pos: ?usize = null;
                            for (formatted_str, 0..) |c, i| {
                                if (c == '.') {
                                    dot_pos = i;
                                    break;
                                }
                            }

                            if (dot_pos != null) {
                                // Has decimal point - strip trailing zeros after it
                                var end: usize = formatted_str.len;
                                while (end > dot_pos.? + 1 and formatted_str[end - 1] == '0') {
                                    end -= 1;
                                }
                                if (end > 0 and formatted_str[end - 1] == '.') {
                                    end -= 1;
                                }
                                try buf.appendSlice(allocator, formatted_str[0..end]);
                            } else {
                                // No decimal point - don't strip anything (these are significant digits)
                                try buf.appendSlice(allocator, formatted_str);
                            }
                        }
                    }
                },
                else => {
                    if (spec.precision != null) {
                        const sig_figs = spec.precision.?;
                        const formatted_str = try formatSignificantFigures(allocator, abs_val, sig_figs);
                        try buf.appendSlice(allocator, formatted_str);
                    } else if (@mod(abs_val, 1.0) == 0.0 and abs_val < 1e15) {
                        try buf.writer(allocator).print("{d:.1}", .{abs_val});
                    } else {
                        try buf.writer(allocator).print("{d}", .{abs_val});
                    }
                },
            }
        }
    } else {
        try buf.writer(allocator).print("{any}", .{value});
    }

    var formatted: []const u8 = buf.items;
    if (spec.grouping_char != null or spec.decimal_grouping_char != null) {
        formatted = try addThousandsGrouping(allocator, buf.items, spec.grouping_char, spec.decimal_grouping_char);
    }

    if (spec.zero_pad and spec.alignment == .sign_aware and spec.grouping_char != null and spec.width != null) {
        const width = spec.width.?;
        if (formatted.len < width) {
            return applyZeroPaddingWithGrouping(allocator, formatted, width, spec.grouping_char.?);
        }
    }

    return applyPadding(allocator, formatted, spec);
}

/// Python % operator for string formatting vs numeric modulo
pub fn pyMod(allocator: std.mem.Allocator, left: anytype, right: anytype) ![]const u8 {
    const L = @TypeOf(left);

    if (L == []const u8 or L == [:0]const u8) {
        return pyStringFormat(allocator, left, right);
    } else if (@typeInfo(L) == .pointer and @typeInfo(std.meta.Child(L)) == .array) {
        return pyStringFormat(allocator, left, right);
    } else if (@typeInfo(L) == .int or @typeInfo(L) == .comptime_int) {
        const result = @rem(left, right);
        var buf = std.ArrayListUnmanaged(u8){};
        try buf.writer(allocator).print("{d}", .{result});
        return buf.toOwnedSlice(allocator);
    } else if (@typeInfo(L) == .float or @typeInfo(L) == .comptime_float) {
        const a: f64 = @floatCast(left);
        const b: f64 = @floatCast(right);
        const result = a - @floor(a / b) * b;
        return formatFloat(result, allocator);
    } else {
        return pyStringFormat(allocator, left, right);
    }
}

/// Python string formatting helper
pub fn pyStringFormat(allocator: std.mem.Allocator, format: anytype, value: anytype) ![]const u8 {
    const F = @TypeOf(format);
    const V = @TypeOf(value);

    const format_str: []const u8 = if (F == []const u8 or F == [:0]const u8) format else @as([]const u8, format);

    var result = std.ArrayListUnmanaged(u8){};
    var i: usize = 0;
    while (i < format_str.len) {
        if (format_str[i] == '%' and i + 1 < format_str.len) {
            var j = i + 1;
            var sign_flag: u8 = 0;
            var alt_form: bool = false;

            while (j < format_str.len) {
                const c = format_str[j];
                if (c == '+' or c == ' ') {
                    sign_flag = c;
                    j += 1;
                } else if (c == '#') {
                    alt_form = true;
                    j += 1;
                } else if (c == '-' or c == '0') {
                    j += 1;
                } else {
                    break;
                }
            }

            while (j < format_str.len and std.ascii.isDigit(format_str[j])) {
                j += 1;
            }

            var precision: ?u32 = null;
            if (j < format_str.len and format_str[j] == '.') {
                j += 1;
                var p: u32 = 0;
                while (j < format_str.len and std.ascii.isDigit(format_str[j])) {
                    p = p * 10 + @as(u32, format_str[j] - '0');
                    j += 1;
                }
                precision = p;
            }

            if (j >= format_str.len) {
                try result.append(allocator, format_str[i]);
                i += 1;
                continue;
            }

            const spec = format_str[j];
            if (spec == 's') {
                if (V == []const u8 or V == [:0]const u8) {
                    try result.appendSlice(allocator, value);
                } else {
                    try result.writer(allocator).print("{any}", .{value});
                }
                i = j + 1;
            } else if (spec == 'd' or spec == 'i') {
                if (@typeInfo(V) == .int or @typeInfo(V) == .comptime_int) {
                    if (sign_flag == '+' and value >= 0) try result.append(allocator, '+');
                    if (sign_flag == ' ' and value >= 0) try result.append(allocator, ' ');
                    try result.writer(allocator).print("{d}", .{value});
                } else if (@typeInfo(V) == .float or @typeInfo(V) == .comptime_float) {
                    const int_val = @as(i64, @intFromFloat(value));
                    if (sign_flag == '+' and int_val >= 0) try result.append(allocator, '+');
                    if (sign_flag == ' ' and int_val >= 0) try result.append(allocator, ' ');
                    try result.writer(allocator).print("{d}", .{int_val});
                } else {
                    try result.writer(allocator).print("{any}", .{value});
                }
                i = j + 1;
            } else if (spec == 'f' or spec == 'e' or spec == 'g' or spec == 'G') {
                if (@typeInfo(V) == .float or @typeInfo(V) == .comptime_float) {
                    const sign_opt: FloatSignOption = if (sign_flag == '+') .plus else if (sign_flag == ' ') .space else .none;
                    const format_opt: FloatFormatType = if (spec == 'e') .scientific else if (spec == 'f') .fixed else .general;
                    const val_str = try formatPythonFloat(allocator, value, .{ .sign = sign_opt, .format_type = format_opt, .precision = precision, .alt_form = alt_form });
                    defer allocator.free(val_str);
                    try result.appendSlice(allocator, val_str);
                } else if (@typeInfo(V) == .int or @typeInfo(V) == .comptime_int) {
                    // For %f/%e/%g formats, convert int to float and use float formatting
                    const float_val: f64 = @floatFromInt(value);
                    const sign_opt: FloatSignOption = if (sign_flag == '+') .plus else if (sign_flag == ' ') .space else .none;
                    const format_opt: FloatFormatType = if (spec == 'e') .scientific else if (spec == 'f') .fixed else .general;
                    const val_str = try formatPythonFloat(allocator, float_val, .{ .sign = sign_opt, .format_type = format_opt, .precision = precision, .alt_form = alt_form });
                    defer allocator.free(val_str);
                    try result.appendSlice(allocator, val_str);
                } else {
                    try result.writer(allocator).print("{any}", .{value});
                }
                i = j + 1;
            } else if (spec == 'r') {
                // %r format - repr() of value
                if (@typeInfo(V) == .float or @typeInfo(V) == .comptime_float) {
                    const val_str = try formatPythonFloat(allocator, value, .{ .format_type = .repr });
                    defer allocator.free(val_str);
                    try result.appendSlice(allocator, val_str);
                } else if (@typeInfo(V) == .int or @typeInfo(V) == .comptime_int) {
                    try result.writer(allocator).print("{d}", .{value});
                } else if (V == []const u8 or V == [:0]const u8) {
                    try result.append(allocator, '\'');
                    try result.appendSlice(allocator, value);
                    try result.append(allocator, '\'');
                } else {
                    try result.writer(allocator).print("{any}", .{value});
                }
                i = j + 1;
            } else if (spec == '%') {
                try result.append(allocator, '%');
                i = j + 1;
            } else {
                try result.append(allocator, format_str[i]);
                i += 1;
            }
        } else {
            try result.append(allocator, format_str[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}
