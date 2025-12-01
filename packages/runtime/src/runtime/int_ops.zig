/// Integer operations for runtime
const std = @import("std");
const runtime_core = @import("../runtime.zig");
const bigint = @import("bigint");
const BigInt = bigint.BigInt;
const PythonError = runtime_core.PythonError;
const PyObject = runtime_core.PyObject;
const PyString = runtime_core.pystring.PyString;

/// Convert any value to i64 (supports __int__ protocol)
pub fn toInt(value: anytype) !i64 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Handle integers - pass through
    if (info == .int or info == .comptime_int) {
        return @as(i64, @intCast(value));
    }

    // Handle floats - truncate
    if (info == .float or info == .comptime_float) {
        return @as(i64, @intFromFloat(value));
    }

    // Handle bool
    if (T == bool) {
        return @as(i64, @intFromBool(value));
    }

    // Handle slices (strings)
    if (info == .pointer and info.pointer.size == .slice) {
        return std.fmt.parseInt(i64, value, 10);
    }

    // Handle single-item pointers to arrays (string literals)
    if (info == .pointer and info.pointer.size == .one) {
        const child = info.pointer.child;
        if (@typeInfo(child) == .array) {
            const array_info = @typeInfo(child).array;
            if (array_info.child == u8) {
                return std.fmt.parseInt(i64, value, 10);
            }
        }
    }

    // Handle structs with __int__ method (Python protocol)
    if (info == .@"struct") {
        // Check for __int__ method
        if (@hasDecl(T, "__int__")) {
            const result = value.__int__();
            const ResultT = @TypeOf(result);
            // Handle both direct return and error union
            if (@typeInfo(ResultT) == .error_union) {
                const actual_result = result catch return error.IntConversionFailed;
                // Convert the unwrapped result to i64
                if (@TypeOf(actual_result) == bool) {
                    return @as(i64, @intFromBool(actual_result));
                }
                return @as(i64, @intCast(actual_result));
            }
            // Direct return (not an error union)
            if (ResultT == bool) {
                return @as(i64, @intFromBool(result));
            }
            return @as(i64, @intCast(result));
        }
    }

    // Handle pointers to structs with __int__ method
    if (info == .pointer and info.pointer.size == .one) {
        const child = info.pointer.child;
        if (@typeInfo(child) == .@"struct") {
            if (@hasDecl(child, "__int__")) {
                const result = value.__int__();
                const ResultT = @TypeOf(result);
                if (@typeInfo(ResultT) == .error_union) {
                    const actual_result = result catch return error.IntConversionFailed;
                    if (@TypeOf(actual_result) == bool) {
                        return @as(i64, @intFromBool(actual_result));
                    }
                    return @as(i64, @intCast(actual_result));
                }
                if (ResultT == bool) {
                    return @as(i64, @intFromBool(result));
                }
                return @as(i64, @intCast(result));
            }
        }
    }

    return error.IntConversionFailed;
}

/// Integer division with zero check
pub fn divideInt(a: i64, b: i64) PythonError!i64 {
    if (b == 0) {
        return PythonError.ZeroDivisionError;
    }
    return @divTrunc(a, b);
}

/// Modulo with zero check
pub fn moduloInt(a: i64, b: i64) PythonError!i64 {
    if (b == 0) {
        return PythonError.ZeroDivisionError;
    }
    return @mod(a, b);
}

/// Convert any value to i64 (Python int() constructor)
/// Handles strings, floats, ints, and types with __int__ method
pub fn pyIntFromAny(value: anytype) i64 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Integer types - direct conversion
    if (info == .int or info == .comptime_int) {
        return @as(i64, @intCast(value));
    }

    // Float types - truncate
    if (info == .float or info == .comptime_float) {
        return @as(i64, @intFromFloat(value));
    }

    // Bool
    if (T == bool) {
        return if (value) 1 else 0;
    }

    // String types - parse
    if (info == .pointer) {
        const child = @typeInfo(info.pointer.child);
        if (child == .int and child.int.bits == 8) {
            // []const u8 or []u8 - parse as integer
            return std.fmt.parseInt(i64, value, 10) catch 0;
        }
    }

    // Struct with __int__ method
    if (info == .@"struct") {
        if (@hasDecl(T, "__int__")) {
            const result = value.__int__();
            const ResultT = @TypeOf(result);
            if (@typeInfo(ResultT) == .error_union) {
                return result catch 0;
            }
            return result;
        }
    }

    // Pointer to struct with __int__ method
    if (info == .pointer and @typeInfo(info.pointer.child) == .@"struct") {
        const ChildT = info.pointer.child;
        if (@hasDecl(ChildT, "__int__")) {
            const result = value.__int__();
            const ResultT = @TypeOf(result);
            if (@typeInfo(ResultT) == .error_union) {
                return result catch 0;
            }
            return result;
        }
    }

    return 0;
}

/// Convert primitive i64 to PyString
pub fn intToString(allocator: std.mem.Allocator, value: i64) !*PyObject {
    const str = try std.fmt.allocPrint(allocator, "{}", .{value});
    return try PyString.create(allocator, str);
}

/// Parse int from string with Unicode whitespace stripping
/// Returns i128 to support large integers without BigInt allocation
pub fn parseIntUnicode(str: []const u8, base: u8) !i128 {
    // Debug: print input
    // std.debug.print("parseIntUnicode: input='{s}' base={}\n", .{ str, base });

    // Strip leading Unicode whitespace
    var start: usize = 0;
    while (start < str.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(str[start]) catch 1;
        if (start + cp_len > str.len) break;
        const cp = std.unicode.utf8Decode(str[start..][0..cp_len]) catch break;
        if (!isUnicodeWhitespace(cp)) break;
        start += cp_len;
    }

    // Strip trailing Unicode whitespace
    var end: usize = str.len;
    while (end > start) {
        // Find start of last codepoint by scanning backwards
        var cp_start = end - 1;
        while (cp_start > start and (str[cp_start] & 0xC0) == 0x80) {
            cp_start -= 1;
        }
        const cp_len = std.unicode.utf8ByteSequenceLength(str[cp_start]) catch 1;
        if (cp_start + cp_len > end) break;
        const cp = std.unicode.utf8Decode(str[cp_start..][0..cp_len]) catch break;
        if (!isUnicodeWhitespace(cp)) break;
        end = cp_start;
    }

    // Empty string after stripping whitespace -> ValueError
    if (start >= end) return error.ValueError;

    const trimmed = str[start..end];

    // Handle base 0 - auto-detect from prefix
    var actual_base = base;
    var is_negative = false;
    var parse_str = trimmed;
    var had_base_prefix = false; // Track if we stripped 0x/0o/0b

    if (base == 0) {
        // Check for sign
        var prefix_start: usize = 0;
        if (trimmed.len > 0 and (trimmed[0] == '+' or trimmed[0] == '-')) {
            is_negative = trimmed[0] == '-';
            prefix_start = 1;
        }
        // Check for base prefix
        if (trimmed.len > prefix_start + 1 and trimmed[prefix_start] == '0') {
            const prefix_char = trimmed[prefix_start + 1];
            if (prefix_char == 'x' or prefix_char == 'X') {
                actual_base = 16;
                parse_str = trimmed[prefix_start + 2 ..];
                had_base_prefix = true;
            } else if (prefix_char == 'o' or prefix_char == 'O') {
                actual_base = 8;
                parse_str = trimmed[prefix_start + 2 ..];
                had_base_prefix = true;
            } else if (prefix_char == 'b' or prefix_char == 'B') {
                actual_base = 2;
                parse_str = trimmed[prefix_start + 2 ..];
                had_base_prefix = true;
            } else {
                actual_base = 10;
                parse_str = trimmed[prefix_start..];
            }
        } else {
            actual_base = 10;
            parse_str = trimmed[prefix_start..];
        }
    } else {
        // Non-zero base - check for sign
        var after_sign = trimmed;
        if (trimmed.len > 0 and (trimmed[0] == '+' or trimmed[0] == '-')) {
            is_negative = trimmed[0] == '-';
            after_sign = trimmed[1..];
        }
        // Python allows base prefixes even with explicit base: int('0x10', 16) == 16
        // Check for prefix matching the explicit base
        if (after_sign.len > 1 and after_sign[0] == '0') {
            const prefix_char = after_sign[1];
            if ((base == 16 and (prefix_char == 'x' or prefix_char == 'X')) or
                (base == 8 and (prefix_char == 'o' or prefix_char == 'O')) or
                (base == 2 and (prefix_char == 'b' or prefix_char == 'B')))
            {
                parse_str = after_sign[2..];
                had_base_prefix = true;
            } else {
                parse_str = after_sign;
            }
        } else {
            parse_str = after_sign;
        }
    }

    // Empty string after removing prefix -> ValueError
    if (parse_str.len == 0) return error.ValueError;

    // Validate and strip underscores for Python 3.6+ numeric literal support
    // Rules: no trailing underscore, no consecutive underscores
    // Leading underscore only allowed right after base prefix (0x_f is valid, _100 is not)
    var clean_buf: [128]u8 = undefined;
    var clean_len: usize = 0;
    var prev_was_underscore = false;

    // Check for leading underscore (only allowed after base prefix like 0x_)
    if (parse_str[0] == '_' and !had_base_prefix) return error.ValueError;
    // Check for trailing underscore
    if (parse_str[parse_str.len - 1] == '_') return error.ValueError;

    for (parse_str) |c| {
        if (c == '_') {
            if (prev_was_underscore) return error.ValueError; // consecutive underscores
            prev_was_underscore = true;
        } else {
            if (clean_len >= clean_buf.len) return error.ValueError;
            clean_buf[clean_len] = c;
            clean_len += 1;
            prev_was_underscore = false;
        }
    }
    if (clean_len == 0) return error.ValueError;
    const clean_str = clean_buf[0..clean_len];

    // Parse the number (without sign, we handle it separately)
    // First try standard ASCII parsing
    const result = std.fmt.parseInt(i128, clean_str, actual_base) catch {
        // If standard parsing fails, try Unicode digit parsing
        // This handles strings like "१२३४" (Devanagari digits)
        // We need an allocator for this, use thread-local GPA
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const unicode_result = parseIntWithUnicodeDigits(gpa.allocator(), clean_str, actual_base) catch return error.ValueError;
        return if (is_negative) -unicode_result else unicode_result;
    };
    return if (is_negative) -result else result;
}

/// Parse int from string directly to BigInt with Unicode whitespace stripping
/// Use this when you know the result will be stored in a BigInt
pub fn parseIntToBigInt(allocator: std.mem.Allocator, str: []const u8, base: u8) !BigInt {
    // Strip leading Unicode whitespace
    var start: usize = 0;
    while (start < str.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(str[start]) catch 1;
        if (start + cp_len > str.len) break;
        const cp = std.unicode.utf8Decode(str[start..][0..cp_len]) catch break;
        if (!isUnicodeWhitespace(cp)) break;
        start += cp_len;
    }

    // Strip trailing Unicode whitespace
    var end: usize = str.len;
    while (end > start) {
        var cp_start = end - 1;
        while (cp_start > start and (str[cp_start] & 0xC0) == 0x80) {
            cp_start -= 1;
        }
        const cp_len = std.unicode.utf8ByteSequenceLength(str[cp_start]) catch 1;
        if (cp_start + cp_len > end) break;
        const cp = std.unicode.utf8Decode(str[cp_start..][0..cp_len]) catch break;
        if (!isUnicodeWhitespace(cp)) break;
        end = cp_start;
    }

    if (start >= end) return error.ValueError;
    const trimmed = str[start..end];

    // Handle base 0 - auto-detect from prefix
    var actual_base = base;
    var is_negative = false;
    var parse_str = trimmed;
    var had_base_prefix = false; // Track if we stripped 0x/0o/0b

    if (base == 0) {
        // Check for sign
        var prefix_start: usize = 0;
        if (trimmed.len > 0 and (trimmed[0] == '+' or trimmed[0] == '-')) {
            is_negative = trimmed[0] == '-';
            prefix_start = 1;
        }
        // Check for base prefix
        if (trimmed.len > prefix_start + 1 and trimmed[prefix_start] == '0') {
            const prefix_char = trimmed[prefix_start + 1];
            if (prefix_char == 'x' or prefix_char == 'X') {
                actual_base = 16;
                parse_str = trimmed[prefix_start + 2 ..];
                had_base_prefix = true;
            } else if (prefix_char == 'o' or prefix_char == 'O') {
                actual_base = 8;
                parse_str = trimmed[prefix_start + 2 ..];
                had_base_prefix = true;
            } else if (prefix_char == 'b' or prefix_char == 'B') {
                actual_base = 2;
                parse_str = trimmed[prefix_start + 2 ..];
                had_base_prefix = true;
            } else {
                actual_base = 10;
                parse_str = trimmed[prefix_start..];
            }
        } else {
            actual_base = 10;
            parse_str = trimmed[prefix_start..];
        }
    } else {
        // Non-zero base - check for sign
        var after_sign = trimmed;
        if (trimmed.len > 0 and (trimmed[0] == '+' or trimmed[0] == '-')) {
            is_negative = trimmed[0] == '-';
            after_sign = trimmed[1..];
        }
        // Python allows base prefixes even with explicit base: int('0x10', 16) == 16
        // Check for prefix matching the explicit base
        if (after_sign.len > 1 and after_sign[0] == '0') {
            const prefix_char = after_sign[1];
            if ((base == 16 and (prefix_char == 'x' or prefix_char == 'X')) or
                (base == 8 and (prefix_char == 'o' or prefix_char == 'O')) or
                (base == 2 and (prefix_char == 'b' or prefix_char == 'B')))
            {
                parse_str = after_sign[2..];
                had_base_prefix = true;
            } else {
                parse_str = after_sign;
            }
        } else {
            parse_str = after_sign;
        }
    }

    // Empty string after removing prefix -> ValueError
    if (parse_str.len == 0) return error.ValueError;

    // Validate and strip underscores for Python 3.6+ numeric literal support
    // Rules: no trailing underscore, no consecutive underscores
    // Leading underscore only allowed right after base prefix (0x_f is valid, _100 is not)

    // Check for leading underscore (only allowed after base prefix like 0x_)
    if (parse_str[0] == '_' and !had_base_prefix) return error.ValueError;
    // Check for trailing underscore
    if (parse_str[parse_str.len - 1] == '_') return error.ValueError;

    // Count underscores to determine if we need to clean
    var underscore_count: usize = 0;
    var prev_was_underscore = false;
    for (parse_str) |c| {
        if (c == '_') {
            if (prev_was_underscore) return error.ValueError; // consecutive underscores
            underscore_count += 1;
            prev_was_underscore = true;
        } else {
            prev_was_underscore = false;
        }
    }

    // If no underscores, use parse_str directly
    const clean_str = if (underscore_count == 0) parse_str else blk: {
        // Allocate buffer for cleaned string (without underscores)
        const clean_buf = allocator.alloc(u8, parse_str.len - underscore_count) catch return error.ValueError;
        var clean_len: usize = 0;
        for (parse_str) |c| {
            if (c != '_') {
                clean_buf[clean_len] = c;
                clean_len += 1;
            }
        }
        break :blk clean_buf[0..clean_len];
    };
    defer if (underscore_count > 0) allocator.free(clean_str);

    if (clean_str.len == 0) return error.ValueError;

    var result = BigInt.fromString(allocator, clean_str, actual_base) catch return error.ValueError;
    if (is_negative) result.negate();
    return result;
}

/// int() builtin call wrapper for assertRaises testing
/// Handles int(x) and int(x, base) with proper error checking
pub fn intBuiltinCall(allocator: std.mem.Allocator, first: anytype, rest: anytype) PythonError!i128 {
    _ = allocator;
    const FirstType = @TypeOf(first);
    const first_info = @typeInfo(FirstType);
    const RestType = @TypeOf(rest);
    const rest_info = @typeInfo(RestType);

    // Count additional arguments
    const has_extra_args = rest_info == .@"struct" and rest_info.@"struct".fields.len > 0;

    // If first arg is numeric (int/float), any additional args are invalid
    if (first_info == .int or first_info == .comptime_int or first_info == .float or first_info == .comptime_float) {
        if (has_extra_args) {
            // int(number, base) is TypeError
            return PythonError.TypeError;
        }
        // int(number) is valid - convert to int
        if (first_info == .float or first_info == .comptime_float) {
            return @intFromFloat(first);
        }
        return @as(i128, @intCast(first));
    }

    // String case
    if (first_info == .pointer) {
        // Get base from rest args if present
        const base: u8 = if (has_extra_args) blk: {
            const fields = rest_info.@"struct".fields;
            const base_val = @field(rest, fields[0].name);
            // Check for invalid third+ arguments
            if (fields.len > 1) {
                return PythonError.TypeError;
            }
            break :blk @as(u8, @intCast(base_val));
        } else 10;

        return parseIntUnicode(first, base) catch return PythonError.ValueError;
    }

    return PythonError.TypeError;
}

// ============================================================================
// Helper functions (private)
// ============================================================================

/// Check if codepoint is Unicode whitespace (Python's definition)
fn isUnicodeWhitespace(cp: u21) bool {
    return switch (cp) {
        // ASCII whitespace
        ' ', '\t', '\n', '\r', 0x0B, 0x0C => true,
        // Unicode whitespace
        0x00A0 => true, // NO-BREAK SPACE
        0x1680 => true, // OGHAM SPACE MARK
        0x2000...0x200A => true, // EN QUAD through HAIR SPACE
        0x2028 => true, // LINE SEPARATOR
        0x2029 => true, // PARAGRAPH SEPARATOR
        0x202F => true, // NARROW NO-BREAK SPACE
        0x205F => true, // MEDIUM MATHEMATICAL SPACE
        0x3000 => true, // IDEOGRAPHIC SPACE
        else => false,
    };
}

/// Get numeric value of a Unicode digit character (0-9)
/// Returns null if not a digit
fn getUnicodeDigitValue(cp: u21) ?u8 {
    // ASCII digits
    if (cp >= '0' and cp <= '9') return @intCast(cp - '0');

    // Devanagari digits (०-९) U+0966-U+096F
    if (cp >= 0x0966 and cp <= 0x096F) return @intCast(cp - 0x0966);

    // Arabic-Indic digits (٠-٩) U+0660-U+0669
    if (cp >= 0x0660 and cp <= 0x0669) return @intCast(cp - 0x0660);

    // Extended Arabic-Indic digits (۰-۹) U+06F0-U+06F9
    if (cp >= 0x06F0 and cp <= 0x06F9) return @intCast(cp - 0x06F0);

    // Bengali digits (০-৯) U+09E6-U+09EF
    if (cp >= 0x09E6 and cp <= 0x09EF) return @intCast(cp - 0x09E6);

    // Fullwidth digits (０-９) U+FF10-U+FF19
    if (cp >= 0xFF10 and cp <= 0xFF19) return @intCast(cp - 0xFF10);

    // Thai digits (๐-๙) U+0E50-U+0E59
    if (cp >= 0x0E50 and cp <= 0x0E59) return @intCast(cp - 0x0E50);

    return null;
}

/// Parse integer from string with Unicode digit support
fn parseIntWithUnicodeDigits(allocator: std.mem.Allocator, str: []const u8, base: u8) !i128 {
    // Build ASCII digit string from Unicode digits
    var ascii_digits = std.ArrayList(u8){};
    defer ascii_digits.deinit(allocator);

    var i: usize = 0;
    while (i < str.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(str[i]) catch return error.ValueError;
        if (i + cp_len > str.len) return error.ValueError;
        const cp = std.unicode.utf8Decode(str[i..][0..cp_len]) catch return error.ValueError;

        if (getUnicodeDigitValue(cp)) |digit| {
            try ascii_digits.append(allocator, '0' + digit);
        } else if (cp == '+' or cp == '-') {
            try ascii_digits.append(allocator, @intCast(cp));
        } else if (cp >= 'a' and cp <= 'z') {
            try ascii_digits.append(allocator, @intCast(cp));
        } else if (cp >= 'A' and cp <= 'Z') {
            try ascii_digits.append(allocator, @intCast(cp));
        } else if (cp == '_') {
            // Skip underscores (Python 3.6+ numeric literal feature)
            // but don't add them - parseInt handles them
            try ascii_digits.append(allocator, '_');
        } else {
            return error.ValueError;
        }
        i += cp_len;
    }

    if (ascii_digits.items.len == 0) return error.ValueError;

    return std.fmt.parseInt(i128, ascii_digits.items, base) catch return error.ValueError;
}
