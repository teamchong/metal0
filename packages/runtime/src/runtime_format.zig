/// metal0 Runtime Format Utilities
/// Formatting functions for Python-style printing
const std = @import("std");
const pystring = @import("pystring.zig");
const pyint = @import("pyint.zig");
const pyfloat = @import("pyfloat.zig");
const pybool = @import("pybool.zig");
const dict_module = @import("dict.zig");

pub const PyString = pystring.PyString;
pub const PyInt = pyint.PyInt;
pub const PyFloat = pyfloat.PyFloat;
pub const PyBool = pybool.PyBool;
pub const PyDict = dict_module.PyDict;

// Forward declare PyObject from runtime
const runtime = @import("runtime.zig");
pub const PyObject = runtime.PyObject;

// ============================================================================
// CANONICAL PYTHON FLOAT FORMATTER
// This is THE source of truth for all Python float formatting.
// All other float formatting functions should delegate to this.
// ============================================================================

/// Sign handling for float formatting
pub const FloatSignOption = enum { none, plus, space };

/// Format type for float formatting
pub const FloatFormatType = enum { general, fixed, scientific, repr };

/// Options for Python float formatting
pub const PyFloatFormatOptions = struct {
    /// Sign handling: none (default), plus (+), or space ( )
    sign: FloatSignOption = .none,
    /// Precision (digits after decimal). null = auto
    precision: ?u32 = null,
    /// Format type
    format_type: FloatFormatType = .general,
};

/// Canonical Python float formatter - handles NaN, inf, sign flags, precision
/// ALL other float formatters should call this function.
pub fn formatPythonFloat(allocator: std.mem.Allocator, value: f64, options: PyFloatFormatOptions) ![]const u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    // Handle NaN - Python convention: NaN is always "nan" (never "-nan")
    // Sign flags apply: %+f → "+nan", % f → " nan", %f → "nan"
    if (std.math.isNan(value)) {
        switch (options.sign) {
            .plus => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            .none => {},
        }
        try result.appendSlice(allocator, "nan");
        return result.toOwnedSlice(allocator);
    }

    // Handle infinity
    if (std.math.isInf(value)) {
        if (value < 0) {
            try result.appendSlice(allocator, "-inf");
        } else {
            switch (options.sign) {
                .plus => try result.append(allocator, '+'),
                .space => try result.append(allocator, ' '),
                .none => {},
            }
            try result.appendSlice(allocator, "inf");
        }
        return result.toOwnedSlice(allocator);
    }

    // Normal float - apply sign flag for non-negative values
    if (value >= 0) {
        switch (options.sign) {
            .plus => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            .none => {},
        }
    }

    // Format the number based on format type
    switch (options.format_type) {
        .repr, .general => {
            // Python repr/general: minimal representation
            if (@mod(value, 1.0) == 0.0 and @abs(value) < 1e15) {
                // Whole number: force .0 to match Python behavior
                try result.writer(allocator).print("{d:.1}", .{value});
            } else {
                try result.writer(allocator).print("{d}", .{value});
            }
        },
        .fixed => {
            // Fixed-point notation
            const prec = options.precision orelse 6;
            try result.writer(allocator).print("{d:.[1]}", .{ value, prec });
        },
        .scientific => {
            // Scientific notation
            const prec = options.precision orelse 6;
            try result.writer(allocator).print("{e:.[1]}", .{ value, prec });
        },
    }

    return result.toOwnedSlice(allocator);
}

/// Format any value for Python-style printing (booleans as True/False)
/// This function is a no-op at runtime - it's just for compile-time type checking
/// For bool: returns "True" or "False"
/// For other types: identity function (returns the value unchanged)
pub inline fn formatAny(value: anytype) (if (@TypeOf(value) == bool) []const u8 else @TypeOf(value)) {
    if (@TypeOf(value) == bool) {
        return if (value) "True" else "False";
    } else {
        return value;
    }
}

/// Format any value to string for printing (used for module constants with unknown types)
/// Handles: strings (as-is), bools ("True"/"False"), ints (converted to string), other types (unchanged)
/// Note: This is a COMPILE-TIME function that generates different code based on the input type
pub inline fn formatUnknown(value: anytype) @TypeOf(value) {
    // For unknown module constants, just return as-is
    // Zig's compiler will figure out the actual type
    // String literals will be coerced to []const u8 when printed with {s}
    // Ints/bools will use their natural formatting with {any}
    return value;
}

/// Format float value for printing (Python-style: always show .0 for whole numbers)
/// Examples: 25.0 -> "25.0", 3.14159 -> "3.14159"
/// Delegates to formatPythonFloat with default options.
pub fn formatFloat(value: f64, allocator: std.mem.Allocator) ![]const u8 {
    return formatPythonFloat(allocator, value, .{});
}

/// Format PyObject as string for printing
/// Used when printing dict values with unknown/mixed types
/// Returns a formatted string that can be printed with {s}
pub fn formatPyObject(obj: *PyObject, allocator: std.mem.Allocator) ![]const u8 {
    return switch (obj.type_id) {
        .string => blk: {
            const str_data: *PyString = @ptrCast(@alignCast(obj.data));
            break :blk try allocator.dupe(u8, str_data.data);
        },
        .int => blk: {
            const int_data: *PyInt = @ptrCast(@alignCast(obj.data));
            var buf = std.ArrayList(u8){};
            try buf.writer(allocator).print("{d}", .{int_data.value});
            break :blk try buf.toOwnedSlice(allocator);
        },
        .float => blk: {
            const float_data: *PyFloat = @ptrCast(@alignCast(obj.data));
            break :blk try formatFloat(float_data.value, allocator);
        },
        .bool => blk: {
            const bool_data: *PyBool = @ptrCast(@alignCast(obj.data));
            const str = if (bool_data.value) "True" else "False";
            break :blk try allocator.dupe(u8, str);
        },
        .dict => blk: {
            const dict_data: *PyDict = @ptrCast(@alignCast(obj.data));
            var buf = std.ArrayList(u8){};
            try buf.appendSlice(allocator, "{");

            var it = dict_data.map.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) {
                    try buf.appendSlice(allocator, ", ");
                }
                // Format as Python dict: {'key': value}
                try buf.writer(allocator).print("'{s}': ", .{entry.key_ptr.*});

                // Format value based on type
                const val_obj = entry.value_ptr.*;
                switch (val_obj.type_id) {
                    .string => {
                        const val_str: *PyString = @ptrCast(@alignCast(val_obj.data));
                        try buf.writer(allocator).print("'{s}'", .{val_str.data});
                    },
                    .int => {
                        const val_int: *PyInt = @ptrCast(@alignCast(val_obj.data));
                        try buf.writer(allocator).print("{d}", .{val_int.value});
                    },
                    else => {
                        try buf.appendSlice(allocator, "<object>");
                    },
                }
                first = false;
            }

            try buf.appendSlice(allocator, "}");
            break :blk try buf.toOwnedSlice(allocator);
        },
        else => try allocator.dupe(u8, "<object>"),
    };
}

/// Format dict as Python dict string: {key: value, ...}
/// Supports both StringHashMap and ArrayList(KV) for dict comprehensions
/// ArrayList preserves insertion order (Python 3.7+ behavior)
pub fn PyDict_AsString(dict: anytype, allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayList(u8){};
    try buf.appendSlice(allocator, "{");

    const T = @TypeOf(dict);
    const type_info = @typeInfo(T);

    // Check if it's an ArrayList by checking for 'items' field
    const is_arraylist = comptime blk: {
        if (type_info == .@"struct") {
            if (@hasDecl(T, "Slice")) {
                // It's likely an ArrayList
                break :blk true;
            }
        }
        break :blk false;
    };

    if (is_arraylist) {
        // ArrayList(KV) - iterate in order
        for (dict.items, 0..) |item, i| {
            if (i > 0) {
                try buf.appendSlice(allocator, ", ");
            }
            try buf.writer(allocator).print("{s}: {d}", .{ item.key, item.value });
        }
    } else {
        // StringHashMap - iterate in hash order
        var it = dict.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) {
                try buf.appendSlice(allocator, ", ");
            }

            // Format key and value
            try buf.writer(allocator).print("{s}: {d}", .{
                entry.key_ptr.*,
                entry.value_ptr.*,
            });

            first = false;
        }
    }

    try buf.appendSlice(allocator, "}");
    return try buf.toOwnedSlice(allocator);
}

/// Generic value printer using comptime type detection
/// Prints any value with Python-style formatting
pub fn printValue(value: anytype) void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    switch (type_info) {
        .int, .comptime_int => std.debug.print("{d}", .{value}),
        .float, .comptime_float => std.debug.print("{d}", .{value}),
        .bool => std.debug.print("{s}", .{if (value) "True" else "False"}),
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice) {
                // Check if it's a string ([]const u8 or []u8)
                if (ptr_info.child == u8) {
                    std.debug.print("'{s}'", .{value});
                } else {
                    // Generic slice/array
                    std.debug.print("[", .{});
                    for (value, 0..) |item, i| {
                        if (i > 0) std.debug.print(", ", .{});
                        printValue(item);
                    }
                    std.debug.print("]", .{});
                }
            } else {
                std.debug.print("{any}", .{value});
            }
        },
        .array => {
            std.debug.print("[", .{});
            for (value, 0..) |item, i| {
                if (i > 0) std.debug.print(", ", .{});
                printValue(item);
            }
            std.debug.print("]", .{});
        },
        .void => std.debug.print("None", .{}),
        else => std.debug.print("{any}", .{value}),
    }
}

/// Python format spec: [[fill]align][sign][#][0][width][grouping][.precision][type]
/// Grouping can be ',' or '_' for thousands separator
const FormatSpec = struct {
    fill: u8 = ' ',
    alignment: enum { left, right, center, sign_aware } = .right,
    sign: enum { minus_only, always, space } = .minus_only,
    alternate: bool = false,
    zero_pad: bool = false,
    width: ?usize = null,
    grouping_char: ?u8 = null, // ',' or '_' for integer part thousands separator
    precision: ?usize = null,
    decimal_grouping_char: ?u8 = null, // ',' or '_' for decimal part grouping
    fmt_type: u8 = 0, // 0 = default, 's', 'd', 'b', 'o', 'x', 'X', 'e', 'E', 'f', 'F', 'g', 'G', '%', 'c', 'n'
};

fn parseFormatSpec(spec: []const u8) FormatSpec {
    var result = FormatSpec{};
    if (spec.len == 0) return result;

    var i: usize = 0;

    // Check for fill and align: if second char is align, first is fill
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
    // Check for align only
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

    // Sign: +, -, or space
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

    // Alternate form: #
    if (i < spec.len and spec[i] == '#') {
        result.alternate = true;
        i += 1;
    }

    // Zero padding: 0
    if (i < spec.len and spec[i] == '0') {
        result.zero_pad = true;
        result.fill = '0';
        result.alignment = .sign_aware;
        i += 1;
    }

    // Width: digits
    const width_start = i;
    while (i < spec.len and spec[i] >= '0' and spec[i] <= '9') : (i += 1) {}
    if (i > width_start) {
        result.width = std.fmt.parseInt(usize, spec[width_start..i], 10) catch null;
    }

    // Grouping: comma or underscore for thousands separator
    if (i < spec.len and (spec[i] == ',' or spec[i] == '_')) {
        result.grouping_char = spec[i];
        i += 1;
    }

    // Precision: .digits
    if (i < spec.len and spec[i] == '.') {
        i += 1;
        const prec_start = i;
        while (i < spec.len and spec[i] >= '0' and spec[i] <= '9') : (i += 1) {}
        if (i > prec_start) {
            result.precision = std.fmt.parseInt(usize, spec[prec_start..i], 10) catch null;
        }
    }

    // Decimal grouping: comma or underscore after precision, before type
    if (i < spec.len and (spec[i] == ',' or spec[i] == '_')) {
        result.decimal_grouping_char = spec[i];
        i += 1;
    }

    // Type: single character at end
    if (i < spec.len) {
        result.fmt_type = spec[i];
    }

    return result;
}

fn applyPadding(allocator: std.mem.Allocator, content: []const u8, spec: FormatSpec) ![]const u8 {
    const width = spec.width orelse return allocator.dupe(u8, content);
    if (content.len >= width) return allocator.dupe(u8, content);

    const padding = width - content.len;
    var result = std.ArrayList(u8){};

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

/// Add thousands grouping separator to a number string
/// e.g., "123456.789" with int_sep='_', dec_sep=null -> "123_456.789"
/// e.g., "123456.789" with int_sep=null, dec_sep='_' -> "123456.789_" (every 3 digits in decimal part)
/// e.g., "123456.789123" with int_sep='_', dec_sep='_' -> "123_456.789_123"
/// NOTE: Exponent part (e.g., "e+05") is NOT grouped - grouping stops at 'e' or 'E'
fn addThousandsGrouping(allocator: std.mem.Allocator, num_str: []const u8, int_sep: ?u8, dec_sep: ?u8) ![]const u8 {
    if (int_sep == null and dec_sep == null) {
        return try allocator.dupe(u8, num_str);
    }

    // Find positions of decimal point and exponent
    var decimal_pos: usize = num_str.len;
    var exponent_pos: usize = num_str.len;
    var start_pos: usize = 0;
    for (num_str, 0..) |c, i| {
        if (c == '.') {
            decimal_pos = i;
        } else if (c == 'e' or c == 'E') {
            exponent_pos = i;
            break; // Stop at exponent
        }
        // Skip sign at the start
        if (i == 0 and (c == '-' or c == '+' or c == ' ')) {
            start_pos = 1;
        }
    }

    // The actual end of the numeric part we group
    const numeric_end = exponent_pos;

    var result = std.ArrayList(u8){};

    // Copy sign if present
    if (start_pos > 0) {
        try result.append(allocator, num_str[0]);
    }

    const int_part = num_str[start_pos..@min(decimal_pos, numeric_end)];

    // Add integer part with grouping
    if (int_sep) |sep| {
        if (int_part.len > 3) {
            const num_groups = (int_part.len + 2) / 3;
            const first_group_len = int_part.len - (num_groups - 1) * 3;

            // First group (may be less than 3 digits)
            try result.appendSlice(allocator, int_part[0..first_group_len]);

            // Remaining groups (exactly 3 digits each)
            var pos: usize = first_group_len;
            while (pos < int_part.len) {
                try result.append(allocator, sep);
                try result.appendSlice(allocator, int_part[pos .. pos + 3]);
                pos += 3;
            }
        } else {
            try result.appendSlice(allocator, int_part);
        }
    } else {
        try result.appendSlice(allocator, int_part);
    }

    // Copy decimal part with grouping if present (only up to exponent)
    if (decimal_pos < numeric_end) {
        try result.append(allocator, '.'); // Add the decimal point
        const dec_part = num_str[decimal_pos + 1 .. numeric_end]; // Skip the '.', stop at exponent

        if (dec_sep) |sep| {
            if (dec_part.len > 3) {
                // Add groups of 3 from the LEFT (after decimal point)
                var pos: usize = 0;
                while (pos < dec_part.len) {
                    if (pos > 0) {
                        try result.append(allocator, sep);
                    }
                    const end = @min(pos + 3, dec_part.len);
                    try result.appendSlice(allocator, dec_part[pos..end]);
                    pos = end;
                }
            } else {
                try result.appendSlice(allocator, dec_part);
            }
        } else {
            try result.appendSlice(allocator, dec_part);
        }
    }

    // Append exponent part without grouping
    if (exponent_pos < num_str.len) {
        try result.appendSlice(allocator, num_str[exponent_pos..]);
    }

    return result.toOwnedSlice(allocator);
}

/// Python format(value, format_spec) builtin
/// Applies format_spec to value and returns formatted string
pub fn pyFormat(allocator: std.mem.Allocator, value: anytype, format_spec: anytype) ![]const u8 {
    const spec_str: []const u8 = if (@TypeOf(format_spec) == []const u8) format_spec else @as([]const u8, format_spec);
    const spec = parseFormatSpec(spec_str);

    const T = @TypeOf(value);
    var buf = std.ArrayList(u8){};

    // Format the value based on type
    if (T == []const u8 or T == [:0]const u8) {
        // String formatting
        var str = value;
        if (spec.precision) |p| {
            if (p < str.len) str = str[0..p];
        }
        try buf.appendSlice(allocator, str);
    } else if (T == bool) {
        try buf.appendSlice(allocator, if (value) "True" else "False");
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        // Integer formatting
        const int_val: i64 = @intCast(value);
        const abs_val: u64 = if (int_val < 0) @intCast(-int_val) else @intCast(int_val);
        const is_neg = int_val < 0;

        // Determine base and prefix
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
                // Character
                if (abs_val < 128) {
                    try buf.append(allocator, @as(u8, @intCast(abs_val)));
                }
                return applyPadding(allocator, buf.items, spec);
            },
            else => {},
        }

        // Convert number to string (in reverse order)
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

        // For zero-padding with sign-aware alignment, we need special handling
        // The sign and prefix come first, then zero padding, then digits
        if (spec.zero_pad and spec.width != null) {
            var num_buf: [68]u8 = undefined;
            var num_len: usize = 0;

            // Add sign first
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

            // Add prefix
            for (prefix) |c| {
                num_buf[num_len] = c;
                num_len += 1;
            }

            // Calculate how many zeros we need
            const width = spec.width.?;
            const digits_and_prefix_len = num_len + temp_len;
            const zeros_needed = if (width > digits_and_prefix_len) width - digits_and_prefix_len else 0;

            // Add zeros
            var z: usize = 0;
            while (z < zeros_needed) : (z += 1) {
                num_buf[num_len] = '0';
                num_len += 1;
            }

            // Reverse and add digits
            var j: usize = 0;
            while (j < temp_len) : (j += 1) {
                num_buf[num_len + j] = temp[temp_len - 1 - j];
            }
            num_len += temp_len;

            try buf.appendSlice(allocator, num_buf[0..num_len]);
            // Return directly - no additional padding needed
            return allocator.dupe(u8, buf.items);
        }

        // Normal case: build number string then pad
        var num_buf: [68]u8 = undefined;
        var num_len: usize = 0;

        // Add sign
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

        // Add prefix
        for (prefix) |c| {
            num_buf[num_len] = c;
            num_len += 1;
        }

        // Reverse and add digits
        var j: usize = 0;
        while (j < temp_len) : (j += 1) {
            num_buf[num_len + j] = temp[temp_len - 1 - j];
        }
        num_len += temp_len;

        try buf.appendSlice(allocator, num_buf[0..num_len]);
    } else if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
        // Float formatting
        const float_val: f64 = @floatCast(value);
        const prec = spec.precision orelse 6;

        // Validate format type - integer presentation types are invalid for floats
        switch (spec.fmt_type) {
            's', 'b', 'c', 'd', 'o', 'x', 'X', 'n' => {
                return error.ValueError;
            },
            else => {},
        }

        // Handle special values: nan, inf, -inf
        // Sign flags apply to inf/nan: + forces +, space forces space for positive
        if (std.math.isNan(float_val)) {
            const uppercase = spec.fmt_type == 'F' or spec.fmt_type == 'E';
            // nan is always "positive" - sign flags apply
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
            // Apply sign flag for normal floats
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
                    // Python 'e'/'E' format: scientific notation
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
                    // Fixed point: always use precision
                    try buf.writer(allocator).print("{d:.[1]}", .{ abs_val, prec });
                },
                else => {
                    // Default / 'g' / 'G' / empty spec: use shortest representation
                    // like repr() - minimal digits, no trailing zeros
                    if (@mod(abs_val, 1.0) == 0.0 and abs_val < 1e15) {
                        // Whole number: show .0
                        try buf.writer(allocator).print("{d:.1}", .{abs_val});
                    } else {
                        // Zig's {d} gives shortest representation
                        try buf.writer(allocator).print("{d}", .{abs_val});
                    }
                },
            }
        }
    } else {
        // Default: use {any} format
        try buf.writer(allocator).print("{any}", .{value});
    }

    // Apply thousands grouping if specified
    var formatted: []const u8 = buf.items;
    if (spec.grouping_char != null or spec.decimal_grouping_char != null) {
        formatted = try addThousandsGrouping(allocator, buf.items, spec.grouping_char, spec.decimal_grouping_char);
    }

    return applyPadding(allocator, formatted, spec);
}

/// Python % operator - runtime dispatch for string formatting vs numeric modulo
/// When left operand type is unknown at compile time, this function decides at runtime
pub fn pyMod(allocator: std.mem.Allocator, left: anytype, right: anytype) ![]const u8 {
    const L = @TypeOf(left);

    // Check if left is a string type
    if (L == []const u8 or L == [:0]const u8) {
        // String formatting: "format" % value
        return pyStringFormat(allocator, left, right);
    } else if (@typeInfo(L) == .pointer and @typeInfo(std.meta.Child(L)) == .array) {
        // String literal type [N:0]u8
        return pyStringFormat(allocator, left, right);
    } else if (@typeInfo(L) == .int or @typeInfo(L) == .comptime_int) {
        // Numeric modulo - return result as string for consistency
        const result = @rem(left, right);
        var buf = std.ArrayList(u8){};
        try buf.writer(allocator).print("{d}", .{result});
        return buf.toOwnedSlice(allocator);
    } else if (@typeInfo(L) == .float or @typeInfo(L) == .comptime_float) {
        // Float modulo
        const result = @rem(left, right);
        return formatFloat(result, allocator);
    } else {
        // Unknown type - try string formatting as fallback
        return pyStringFormat(allocator, left, right);
    }
}

/// Python string formatting helper - "format" % value
pub fn pyStringFormat(allocator: std.mem.Allocator, format: anytype, value: anytype) ![]const u8 {
    const F = @TypeOf(format);
    const V = @TypeOf(value);

    // Get format string as slice
    const format_str: []const u8 = if (F == []const u8 or F == [:0]const u8) format else @as([]const u8, format);

    // Parse Python format specs: %[flags][width][.precision]conversion
    // flags: +, -, space, #, 0
    // width: digits
    // precision: .digits
    // conversion: s, d, i, f, e, g, x, X, o, r, %
    var result = std.ArrayList(u8){};
    var i: usize = 0;
    while (i < format_str.len) {
        if (format_str[i] == '%' and i + 1 < format_str.len) {
            // Parse format spec starting after %
            var j = i + 1;
            var sign_flag: u8 = 0; // '+', ' ', or 0 for none

            // Skip flags: +, -, space, #, 0
            while (j < format_str.len) {
                const c = format_str[j];
                if (c == '+' or c == ' ') {
                    sign_flag = c;
                    j += 1;
                } else if (c == '-' or c == '#' or c == '0') {
                    j += 1;
                } else {
                    break;
                }
            }

            // Skip width (digits)
            while (j < format_str.len and std.ascii.isDigit(format_str[j])) {
                j += 1;
            }

            // Skip precision (.digits)
            if (j < format_str.len and format_str[j] == '.') {
                j += 1;
                while (j < format_str.len and std.ascii.isDigit(format_str[j])) {
                    j += 1;
                }
            }

            // Now j points to the conversion character
            if (j >= format_str.len) {
                // Malformed - just copy
                try result.append(allocator, format_str[i]);
                i += 1;
                continue;
            }

            const spec = format_str[j];
            if (spec == 's') {
                // String format
                if (V == []const u8 or V == [:0]const u8) {
                    try result.appendSlice(allocator, value);
                } else {
                    try result.writer(allocator).print("{any}", .{value});
                }
                i = j + 1;
            } else if (spec == 'd' or spec == 'i') {
                // Integer format
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
            } else if (spec == 'f' or spec == 'e' or spec == 'g') {
                // Float format - use canonical formatter
                if (@typeInfo(V) == .float or @typeInfo(V) == .comptime_float) {
                    const sign_opt: FloatSignOption = if (sign_flag == '+') .plus else if (sign_flag == ' ') .space else .none;
                    const format_opt: FloatFormatType = if (spec == 'e') .scientific else if (spec == 'f') .fixed else .general;
                    const val_str = try formatPythonFloat(allocator, value, .{ .sign = sign_opt, .format_type = format_opt });
                    defer allocator.free(val_str);
                    try result.appendSlice(allocator, val_str);
                } else if (@typeInfo(V) == .int or @typeInfo(V) == .comptime_int) {
                    if (sign_flag == '+' and value >= 0) try result.append(allocator, '+');
                    if (sign_flag == ' ' and value >= 0) try result.append(allocator, ' ');
                    try result.writer(allocator).print("{d}.0", .{value});
                } else {
                    try result.writer(allocator).print("{any}", .{value});
                }
                i = j + 1;
            } else if (spec == '%') {
                // Escaped %
                try result.append(allocator, '%');
                i = j + 1;
            } else {
                // Unknown spec - just copy the % and continue
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
