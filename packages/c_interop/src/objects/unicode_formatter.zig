/// Unicode Formatter Implementation - Built-in type formatters
///
/// Implements CPython's Objects/unicode_formatter.c
/// Provides format() implementations for int, float, and complex types
/// This handles the newer PEP 3101 format specification mini-language
///
/// Reference: cpython/Objects/unicode_formatter.c

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// FORMAT SPEC PARSING
// ============================================================================

/// InternalFormatSpec - parsed format specification
/// Reference: cpython/Include/internal/pycore_format.h
pub const InternalFormatSpec = extern struct {
    fill_char: u32, // 4 bytes - fill character (default ' ')
    align: u8, // 1 byte - alignment: '<', '>', '=', '^'
    alt: u8, // 1 byte - alternate form (#)
    sign: u8, // 1 byte - sign: '+', '-', ' '
    coerce_negative_zero: u8, // 1 byte - whether to coerce -0.0 to 0.0
    thousands_separator: u32, // 4 bytes - thousands separator character
    width: isize, // 8 bytes - minimum field width
    precision: isize, // 8 bytes - precision for floats, max length for strings
    type: u8, // 1 byte - format type: 'd', 'f', 's', etc.
    _padding: [7]u8, // 7 bytes - alignment padding
};

/// GroupGenerator - generates grouping widths for thousands separators
/// Reference: cpython/Objects/unicode_formatter.c
pub const GroupGenerator = extern struct {
    grouping: [*:0]const u8, // grouping specification
    previous: u8, // previous grouping value
    i: usize, // current index into grouping
};

/// Initialize a GroupGenerator
pub fn GroupGenerator_init(self: *GroupGenerator, grouping: [*:0]const u8) void {
    self.grouping = grouping;
    self.i = 0;
    self.previous = 0;
}

/// Get the next grouping value, 0 to signify end
pub fn GroupGenerator_next(self: *GroupGenerator) isize {
    switch (self.grouping[self.i]) {
        0 => return self.previous,
        255 => return 0, // CHAR_MAX - stop the generator
        else => {
            const ch = self.grouping[self.i];
            self.previous = ch;
            self.i += 1;
            return @as(isize, ch);
        },
    }
}

// ============================================================================
// FORMAT SPEC PARSING FUNCTIONS
// ============================================================================

/// Parse a format specification string
/// Reference: cpython/Objects/unicode_formatter.c parse_internal_render_format_spec()
pub export fn _PyUnicode_ParseFormatSpec(format: [*:0]const u8, end: usize, default_type: u8, default_align: u8, spec: *InternalFormatSpec) c_int {
    var pos: usize = 0;

    // Initialize with defaults
    spec.fill_char = ' ';
    spec.align = default_align;
    spec.alt = 0;
    spec.sign = 0;
    spec.coerce_negative_zero = 0;
    spec.thousands_separator = 0;
    spec.width = -1;
    spec.precision = -1;
    spec.type = default_type;
    spec._padding = [_]u8{0} ** 7;

    if (pos >= end) return 0;

    // Check for fill character and alignment
    // Fill character comes before alignment, but we need to look ahead
    if (pos + 1 < end) {
        const next_char = format[pos + 1];
        if (next_char == '<' or next_char == '>' or next_char == '=' or next_char == '^') {
            spec.fill_char = format[pos];
            spec.align = next_char;
            pos += 2;
        }
    }

    // Check for alignment only (no fill)
    if (pos < end) {
        const c = format[pos];
        if (c == '<' or c == '>' or c == '=' or c == '^') {
            spec.align = c;
            pos += 1;
        }
    }

    // Check for sign
    if (pos < end) {
        const c = format[pos];
        if (c == '+' or c == '-' or c == ' ') {
            spec.sign = c;
            pos += 1;
        }
    }

    // Check for z (coerce negative zero)
    if (pos < end and format[pos] == 'z') {
        spec.coerce_negative_zero = 1;
        pos += 1;
    }

    // Check for alternate form (#)
    if (pos < end and format[pos] == '#') {
        spec.alt = 1;
        pos += 1;
    }

    // Check for zero padding (0)
    if (pos < end and format[pos] == '0') {
        spec.fill_char = '0';
        if (spec.align == 0) {
            spec.align = '=';
        }
        pos += 1;
    }

    // Parse width
    if (pos < end and format[pos] >= '0' and format[pos] <= '9') {
        spec.width = 0;
        while (pos < end and format[pos] >= '0' and format[pos] <= '9') {
            spec.width = spec.width * 10 + @as(isize, format[pos] - '0');
            pos += 1;
        }
    }

    // Check for thousands separator (comma or underscore)
    if (pos < end) {
        const c = format[pos];
        if (c == ',' or c == '_') {
            spec.thousands_separator = c;
            pos += 1;
        }
    }

    // Parse precision
    if (pos < end and format[pos] == '.') {
        pos += 1;
        if (pos >= end or format[pos] < '0' or format[pos] > '9') {
            // Invalid precision
            return -1;
        }
        spec.precision = 0;
        while (pos < end and format[pos] >= '0' and format[pos] <= '9') {
            spec.precision = spec.precision * 10 + @as(isize, format[pos] - '0');
            pos += 1;
        }
    }

    // Parse type
    if (pos < end) {
        spec.type = format[pos];
        pos += 1;
    }

    // Check for trailing characters (error)
    if (pos < end) {
        return -1;
    }

    return 0;
}

// ============================================================================
// THOUSANDS GROUPING
// ============================================================================

/// Insert thousands grouping into a number string
/// Reference: cpython/Objects/unicode_formatter.c _PyUnicode_InsertThousandsGrouping()
pub export fn _PyUnicode_InsertThousandsGrouping(
    buffer: ?[*]u8,
    buffer_size: isize,
    digits: [*]const u8,
    n_digits: isize,
    min_width: isize,
    grouping: [*:0]const u8,
    thousands_sep: [*:0]const u8,
) isize {
    if (grouping[0] == 0 or grouping[0] == 255) {
        // No grouping
        if (buffer != null and n_digits > 0) {
            @memcpy(buffer.?[0..@intCast(n_digits)], digits[0..@intCast(n_digits)]);
        }
        return n_digits;
    }

    const sep_len: isize = @intCast(std.mem.len(thousands_sep));
    var gen: GroupGenerator = undefined;
    GroupGenerator_init(&gen, grouping);

    // Count how many separators we need
    var remaining = n_digits;
    var n_seps: isize = 0;
    var total_len = n_digits;

    while (remaining > 0) {
        const group_len = GroupGenerator_next(&gen);
        if (group_len == 0) break;

        if (remaining > group_len) {
            n_seps += 1;
            remaining -= group_len;
        } else {
            break;
        }
    }

    total_len += n_seps * sep_len;

    // Apply minimum width padding
    const min_w = if (min_width > 0) min_width else 0;
    if (total_len < min_w) {
        total_len = min_w;
    }

    if (buffer == null) {
        // Just return the required size
        return total_len;
    }

    if (total_len > buffer_size) {
        return -1; // Buffer too small
    }

    // Fill buffer from right to left
    GroupGenerator_init(&gen, grouping);
    var buf_pos: isize = total_len;
    var digit_pos: isize = n_digits;
    var first_group = true;

    while (digit_pos > 0) {
        var group_len = GroupGenerator_next(&gen);
        if (group_len == 0) {
            group_len = digit_pos; // Take all remaining
        }
        if (group_len > digit_pos) {
            group_len = digit_pos;
        }

        // Copy digits
        buf_pos -= group_len;
        digit_pos -= group_len;
        @memcpy(buffer.?[@intCast(buf_pos)..@intCast(buf_pos + group_len)], digits[@intCast(digit_pos)..@intCast(digit_pos + group_len)]);

        // Add separator if not the first group and there are more digits
        if (!first_group and digit_pos > 0) {
            buf_pos -= sep_len;
            @memcpy(buffer.?[@intCast(buf_pos)..@intCast(buf_pos + sep_len)], thousands_sep[0..@intCast(sep_len)]);
        }
        first_group = false;
    }

    // Zero-pad on the left if needed
    while (buf_pos > 0) {
        buf_pos -= 1;
        buffer.?[@intCast(buf_pos)] = '0';
    }

    return total_len;
}

// ============================================================================
// NUMBER FORMATTING
// ============================================================================

/// Format an integer using the format specification
pub export fn _PyLong_FormatAdvancedWriter(
    value: ?*cpython.PyObject,
    format_spec: [*:0]const u8,
    format_spec_len: isize,
) ?*cpython.PyObject {
    if (value == null) return null;

    var spec: InternalFormatSpec = undefined;

    // Parse format specification
    if (_PyUnicode_ParseFormatSpec(format_spec, @intCast(format_spec_len), 'd', '>', &spec) < 0) {
        return null;
    }

    const pyunicode = @import("unicodeobject.zig");
    const pylong = @import("longobject.zig");

    // Get the integer value
    const int_val = pylong.PyLong_AsLongLong(value);

    // Format buffer
    var buf: [128]u8 = undefined;
    var pos: usize = 0;

    // Handle sign
    const is_negative = int_val < 0;
    const abs_val: u64 = if (is_negative) @intCast(-int_val) else @intCast(int_val);

    // Format based on type
    switch (spec.type) {
        'b' => {
            // Binary
            if (spec.alternate) {
                buf[pos] = '0';
                buf[pos + 1] = 'b';
                pos += 2;
            }
            pos += formatBinary(abs_val, buf[pos..]);
        },
        'o' => {
            // Octal
            if (spec.alternate) {
                buf[pos] = '0';
                buf[pos + 1] = 'o';
                pos += 2;
            }
            pos += formatOctal(abs_val, buf[pos..]);
        },
        'x' => {
            // Hex lowercase
            if (spec.alternate) {
                buf[pos] = '0';
                buf[pos + 1] = 'x';
                pos += 2;
            }
            pos += formatHex(abs_val, buf[pos..], false);
        },
        'X' => {
            // Hex uppercase
            if (spec.alternate) {
                buf[pos] = '0';
                buf[pos + 1] = 'X';
                pos += 2;
            }
            pos += formatHex(abs_val, buf[pos..], true);
        },
        'c' => {
            // Character
            if (abs_val < 128) {
                buf[pos] = @truncate(abs_val);
                pos += 1;
            }
        },
        else => {
            // Decimal (default)
            if (is_negative) {
                buf[pos] = '-';
                pos += 1;
            } else if (spec.sign == '+') {
                buf[pos] = '+';
                pos += 1;
            } else if (spec.sign == ' ') {
                buf[pos] = ' ';
                pos += 1;
            }
            pos += formatDecimal(abs_val, buf[pos..]);
        },
    }

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(pos));
}

fn formatDecimal(val: u64, buf: []u8) usize {
    if (val == 0) {
        buf[0] = '0';
        return 1;
    }
    var n = val;
    var digits: [20]u8 = undefined;
    var len: usize = 0;
    while (n > 0) : (n /= 10) {
        digits[len] = '0' + @as(u8, @truncate(n % 10));
        len += 1;
    }
    // Reverse
    for (0..len) |i| {
        buf[i] = digits[len - 1 - i];
    }
    return len;
}

fn formatBinary(val: u64, buf: []u8) usize {
    if (val == 0) {
        buf[0] = '0';
        return 1;
    }
    var n = val;
    var digits: [64]u8 = undefined;
    var len: usize = 0;
    while (n > 0) : (n >>= 1) {
        digits[len] = '0' + @as(u8, @truncate(n & 1));
        len += 1;
    }
    for (0..len) |i| {
        buf[i] = digits[len - 1 - i];
    }
    return len;
}

fn formatOctal(val: u64, buf: []u8) usize {
    if (val == 0) {
        buf[0] = '0';
        return 1;
    }
    var n = val;
    var digits: [22]u8 = undefined;
    var len: usize = 0;
    while (n > 0) : (n >>= 3) {
        digits[len] = '0' + @as(u8, @truncate(n & 7));
        len += 1;
    }
    for (0..len) |i| {
        buf[i] = digits[len - 1 - i];
    }
    return len;
}

fn formatHex(val: u64, buf: []u8, uppercase: bool) usize {
    const chars = if (uppercase) "0123456789ABCDEF" else "0123456789abcdef";
    if (val == 0) {
        buf[0] = '0';
        return 1;
    }
    var n = val;
    var digits: [16]u8 = undefined;
    var len: usize = 0;
    while (n > 0) : (n >>= 4) {
        digits[len] = chars[n & 15];
        len += 1;
    }
    for (0..len) |i| {
        buf[i] = digits[len - 1 - i];
    }
    return len;
}

/// Format a float using the format specification
pub export fn _PyFloat_FormatAdvancedWriter(
    value: ?*cpython.PyObject,
    format_spec: [*:0]const u8,
    format_spec_len: isize,
) ?*cpython.PyObject {
    if (value == null) return null;

    var spec: InternalFormatSpec = undefined;

    // Parse format specification (default type is empty for float)
    if (_PyUnicode_ParseFormatSpec(format_spec, @intCast(format_spec_len), 0, '>', &spec) < 0) {
        return null;
    }

    const pyunicode = @import("unicodeobject.zig");
    const pyfloat = @import("floatobject.zig");

    // Get the float value
    const float_val = pyfloat.PyFloat_AsDouble(value);

    // Format buffer
    var buf: [64]u8 = undefined;
    var len: usize = 0;

    // Handle special values
    if (std.math.isNan(float_val)) {
        const nan_str = "nan";
        @memcpy(buf[0..nan_str.len], nan_str);
        return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(nan_str.len));
    }
    if (std.math.isInf(float_val)) {
        if (float_val < 0) {
            const ninf = "-inf";
            @memcpy(buf[0..ninf.len], ninf);
            return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(ninf.len));
        } else {
            const inf = "inf";
            @memcpy(buf[0..inf.len], inf);
            return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(inf.len));
        }
    }

    // Determine precision (default 6)
    const precision: usize = if (spec.precision >= 0) @intCast(spec.precision) else 6;

    // Format based on type
    switch (spec.type) {
        'e', 'E' => {
            // Scientific notation
            len = formatFloatScientific(float_val, &buf, precision, spec.type == 'E');
        },
        'f', 'F' => {
            // Fixed-point
            len = formatFloatFixed(float_val, &buf, precision);
        },
        '%' => {
            // Percentage
            len = formatFloatFixed(float_val * 100.0, &buf, precision);
            buf[len] = '%';
            len += 1;
        },
        else => {
            // General format (g) - use fixed or scientific based on magnitude
            const abs_val = @abs(float_val);
            if (abs_val >= 1e-4 and abs_val < 1e6) {
                len = formatFloatFixed(float_val, &buf, precision);
            } else {
                len = formatFloatScientific(float_val, &buf, precision, false);
            }
        },
    }

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(len));
}

fn formatFloatFixed(val: f64, buf: []u8, precision: usize) usize {
    const is_negative = val < 0;
    const abs_val = @abs(val);

    var pos: usize = 0;

    // Sign
    if (is_negative) {
        buf[pos] = '-';
        pos += 1;
    }

    // Integer part
    const int_part: u64 = @intFromFloat(abs_val);
    pos += formatDecimal(int_part, buf[pos..]);

    // Decimal point and fractional part
    if (precision > 0) {
        buf[pos] = '.';
        pos += 1;

        var frac = abs_val - @as(f64, @floatFromInt(int_part));
        for (0..precision) |_| {
            frac *= 10.0;
            const digit: u8 = @intFromFloat(@mod(frac, 10.0));
            buf[pos] = '0' + digit;
            pos += 1;
        }
    }

    return pos;
}

fn formatFloatScientific(val: f64, buf: []u8, precision: usize, uppercase: bool) usize {
    const is_negative = val < 0;
    const abs_val = @abs(val);

    var pos: usize = 0;

    // Sign
    if (is_negative) {
        buf[pos] = '-';
        pos += 1;
    }

    // Handle zero
    if (abs_val == 0.0) {
        buf[pos] = '0';
        pos += 1;
        if (precision > 0) {
            buf[pos] = '.';
            pos += 1;
            for (0..precision) |_| {
                buf[pos] = '0';
                pos += 1;
            }
        }
        buf[pos] = if (uppercase) 'E' else 'e';
        pos += 1;
        buf[pos] = '+';
        buf[pos + 1] = '0';
        buf[pos + 2] = '0';
        return pos + 3;
    }

    // Calculate exponent
    const log_val = @log10(abs_val);
    var exponent: i32 = @intFromFloat(@floor(log_val));
    var mantissa = abs_val / std.math.pow(f64, 10.0, @floatFromInt(exponent));

    // Normalize mantissa to [1, 10)
    if (mantissa >= 10.0) {
        mantissa /= 10.0;
        exponent += 1;
    } else if (mantissa < 1.0 and mantissa > 0.0) {
        mantissa *= 10.0;
        exponent -= 1;
    }

    // Format mantissa
    const mant_len = formatFloatFixed(mantissa, buf[pos..], precision);
    pos += mant_len;

    // Exponent
    buf[pos] = if (uppercase) 'E' else 'e';
    pos += 1;
    buf[pos] = if (exponent >= 0) '+' else '-';
    pos += 1;

    const abs_exp: u32 = @intCast(@abs(exponent));
    if (abs_exp < 10) {
        buf[pos] = '0';
        pos += 1;
    }
    pos += formatDecimal(abs_exp, buf[pos..]);

    return pos;
}

/// Format a complex number using the format specification
pub export fn _PyComplex_FormatAdvancedWriter(
    value: ?*cpython.PyObject,
    format_spec: [*:0]const u8,
    format_spec_len: isize,
) ?*cpython.PyObject {
    if (value == null) return null;

    var spec: InternalFormatSpec = undefined;

    // Parse format specification
    if (_PyUnicode_ParseFormatSpec(format_spec, @intCast(format_spec_len), 0, '>', &spec) < 0) {
        return null;
    }

    const pyunicode = @import("unicodeobject.zig");
    const pycomplex = @import("complexobject.zig");

    // Get real and imaginary parts
    const real = pycomplex.PyComplex_RealAsDouble(value);
    const imag = pycomplex.PyComplex_ImagAsDouble(value);

    // Determine precision (default 6)
    const precision: usize = if (spec.precision >= 0) @intCast(spec.precision) else 6;

    // Format buffer - complex needs more space for both parts
    var buf: [150]u8 = undefined;
    var pos: usize = 0;

    // Opening paren
    buf[pos] = '(';
    pos += 1;

    // Format real part
    pos += formatFloatFixed(real, buf[pos..], precision);

    // Sign for imaginary part
    if (imag >= 0) {
        buf[pos] = '+';
        pos += 1;
    }

    // Format imaginary part
    pos += formatFloatFixed(imag, buf[pos..], precision);

    // Add 'j' suffix
    buf[pos] = 'j';
    pos += 1;

    // Closing paren
    buf[pos] = ')';
    pos += 1;

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(pos));
}

// ============================================================================
// LOCALE SUPPORT
// ============================================================================

/// Get the locale's thousands separator and grouping
pub export fn _Py_GetLocaleconvNumeric(
    decimal_point: *[*:0]const u8,
    thousands_sep: *[*:0]const u8,
    grouping: *[*:0]const u8,
) c_int {
    // Return C locale defaults
    decimal_point.* = ".";
    thousands_sep.* = "";
    grouping.* = "";
    return 0;
}

/// Fill in a numeric locale info struct from current locale
pub export fn _Py_GetNumericLocale() void {
    // No-op for now - uses C locale defaults
}
