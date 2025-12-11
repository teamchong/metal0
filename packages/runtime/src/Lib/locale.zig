//! CPython source: Lib/locale.py
//!
//! Provides access to POSIX locale functionality.
//!
//! Mirrors: CPython Lib/locale.py

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");

// ============================================================================
// Locale Categories
// ============================================================================

/// Locale categories
pub const Category = enum(i32) {
    LC_CTYPE = 0,
    LC_NUMERIC = 1,
    LC_TIME = 2,
    LC_COLLATE = 3,
    LC_MONETARY = 4,
    LC_MESSAGES = 5,
    LC_ALL = 6,
    LC_PAPER = 7,
    LC_NAME = 8,
    LC_ADDRESS = 9,
    LC_TELEPHONE = 10,
    LC_MEASUREMENT = 11,
    LC_IDENTIFICATION = 12,
};

// ============================================================================
// Locale Convention Structure
// ============================================================================

/// Locale conventions
pub const LocaleConv = struct {
    decimal_point: []const u8 = ".",
    thousands_sep: []const u8 = "",
    grouping: []const u8 = "",
    int_curr_symbol: []const u8 = "",
    currency_symbol: []const u8 = "",
    mon_decimal_point: []const u8 = "",
    mon_thousands_sep: []const u8 = "",
    mon_grouping: []const u8 = "",
    positive_sign: []const u8 = "",
    negative_sign: []const u8 = "",
    int_frac_digits: u8 = 127,
    frac_digits: u8 = 127,
    p_cs_precedes: u8 = 127,
    p_sep_by_space: u8 = 127,
    n_cs_precedes: u8 = 127,
    n_sep_by_space: u8 = 127,
    p_sign_posn: u8 = 127,
    n_sign_posn: u8 = 127,
};

// ============================================================================
// Current Locale State
// ============================================================================

var current_locale: []const u8 = "C";
var current_conv = LocaleConv{};

// ============================================================================
// Locale Functions
// ============================================================================

/// Set the locale
pub fn setlocale(category: Category, locale: ?[]const u8) ?[]const u8 {
    if (locale) |loc| {
        if (loc.len == 0) {
            // Query environment
            return current_locale;
        }

        // Set locale
        current_locale = loc;

        // Update conventions based on locale
        if (std.mem.eql(u8, loc, "C") or std.mem.eql(u8, loc, "POSIX")) {
            current_conv = LocaleConv{};
        } else if (std.mem.startsWith(u8, loc, "en_US")) {
            current_conv = LocaleConv{
                .decimal_point = ".",
                .thousands_sep = ",",
                .grouping = "\x03\x03",
                .currency_symbol = "$",
                .int_curr_symbol = "USD ",
                .mon_decimal_point = ".",
                .mon_thousands_sep = ",",
                .positive_sign = "",
                .negative_sign = "-",
                .frac_digits = 2,
                .int_frac_digits = 2,
                .p_cs_precedes = 1,
                .n_cs_precedes = 1,
                .p_sep_by_space = 0,
                .n_sep_by_space = 0,
                .p_sign_posn = 1,
                .n_sign_posn = 1,
            };
        } else if (std.mem.startsWith(u8, loc, "de_DE")) {
            current_conv = LocaleConv{
                .decimal_point = ",",
                .thousands_sep = ".",
                .grouping = "\x03\x03",
                .currency_symbol = "€",
                .int_curr_symbol = "EUR ",
                .mon_decimal_point = ",",
                .mon_thousands_sep = ".",
                .positive_sign = "",
                .negative_sign = "-",
                .frac_digits = 2,
                .int_frac_digits = 2,
                .p_cs_precedes = 0,
                .n_cs_precedes = 0,
                .p_sep_by_space = 1,
                .n_sep_by_space = 1,
                .p_sign_posn = 1,
                .n_sign_posn = 1,
            };
        }

        return current_locale;
    }
    _ = category;
    return current_locale;
}

/// Get current locale conventions
pub fn localeconv() LocaleConv {
    return current_conv;
}

/// Reset locale to default
pub fn resetlocale(category: Category) void {
    _ = setlocale(category, "C");
}

// ============================================================================
// String Comparison
// ============================================================================

/// Compare strings according to locale
pub fn strcoll(s1: []const u8, s2: []const u8) i32 {
    // Simple ASCII comparison for C locale
    const min_len = @min(s1.len, s2.len);
    for (s1[0..min_len], s2[0..min_len]) |c1, c2| {
        if (c1 < c2) return -1;
        if (c1 > c2) return 1;
    }
    if (s1.len < s2.len) return -1;
    if (s1.len > s2.len) return 1;
    return 0;
}

/// Transform string for comparison
pub fn strxfrm(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    // For C locale, just return a copy
    return allocator.dupe(u8, s);
}

// ============================================================================
// Number Formatting
// ============================================================================

/// Format a number with locale-specific formatting
pub fn format(allocator: std.mem.Allocator, fmt_str: []const u8, value: anytype, grouping: bool, monetary: bool) ![]u8 {
    _ = fmt_str;
    _ = monetary;

    const conv = localeconv();

    // Format the number
    var buf: [64]u8 = undefined;
    const str = switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.FormatError,
        .float, .comptime_float => std.fmt.bufPrint(&buf, "{d:.2}", .{value}) catch return error.FormatError,
        else => return error.UnsupportedType,
    };

    if (!grouping) {
        return allocator.dupe(u8, str);
    }

    // Apply grouping
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Find decimal point
    const decimal_pos = std.mem.indexOf(u8, str, ".") orelse str.len;
    const integer_part = str[0..decimal_pos];
    const decimal_part = if (decimal_pos < str.len) str[decimal_pos..] else "";

    // Apply thousands separator to integer part
    var i: usize = integer_part.len;
    var group_count: usize = 0;
    while (i > 0) {
        i -= 1;
        if (group_count > 0 and group_count % 3 == 0) {
            try result.insert(0, conv.thousands_sep[0]);
        }
        try result.insert(0, integer_part[i]);
        group_count += 1;
    }

    // Add decimal part
    if (decimal_part.len > 0) {
        try result.append(conv.decimal_point[0]);
        try result.appendSlice(decimal_part[1..]);
    }

    return result.toOwnedSlice();
}

/// Format a string as a number
pub fn formatString(allocator: std.mem.Allocator, str: []const u8, grouping: bool) ![]u8 {
    const conv = localeconv();

    if (!grouping) {
        return allocator.dupe(u8, str);
    }

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const decimal_pos = std.mem.indexOf(u8, str, ".") orelse str.len;
    const integer_part = str[0..decimal_pos];

    var i: usize = integer_part.len;
    var group_count: usize = 0;
    while (i > 0) {
        i -= 1;
        if (group_count > 0 and group_count % 3 == 0) {
            try result.insert(0, conv.thousands_sep[0]);
        }
        try result.insert(0, integer_part[i]);
        group_count += 1;
    }

    if (decimal_pos < str.len) {
        try result.append(conv.decimal_point[0]);
        try result.appendSlice(str[decimal_pos + 1 ..]);
    }

    return result.toOwnedSlice();
}

/// Format currency
pub fn currency(allocator: std.mem.Allocator, value: f64, grouping: bool, international: bool) ![]u8 {
    const conv = localeconv();

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Format the number
    var buf: [64]u8 = undefined;
    const frac = if (international) conv.int_frac_digits else conv.frac_digits;
    const str = switch (frac) {
        0 => std.fmt.bufPrint(&buf, "{d:.0}", .{@abs(value)}) catch return error.FormatError,
        1 => std.fmt.bufPrint(&buf, "{d:.1}", .{@abs(value)}) catch return error.FormatError,
        else => std.fmt.bufPrint(&buf, "{d:.2}", .{@abs(value)}) catch return error.FormatError,
    };

    const is_negative = value < 0;
    const curr_sym = if (international) conv.int_curr_symbol else conv.currency_symbol;
    const cs_precedes = if (is_negative) conv.n_cs_precedes else conv.p_cs_precedes;
    const sep_by_space = if (is_negative) conv.n_sep_by_space else conv.p_sep_by_space;

    // Build result
    if (is_negative) {
        try result.appendSlice(conv.negative_sign);
    } else {
        try result.appendSlice(conv.positive_sign);
    }

    if (cs_precedes == 1) {
        try result.appendSlice(curr_sym);
        if (sep_by_space == 1) {
            try result.append(' ');
        }
    }

    // Add formatted number
    if (grouping) {
        const formatted = try formatString(allocator, str, true);
        defer allocator.free(formatted);
        try result.appendSlice(formatted);
    } else {
        try result.appendSlice(str);
    }

    if (cs_precedes == 0) {
        if (sep_by_space == 1) {
            try result.append(' ');
        }
        try result.appendSlice(curr_sym);
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Number Parsing
// ============================================================================

/// Convert a locale-formatted string to float
pub fn atof(str: []const u8) !f64 {
    const conv = localeconv();

    // Replace locale decimal point with '.'
    var normalized = std.ArrayList(u8).init(allocator_helper.fast_allocator);
    defer normalized.deinit();

    for (str) |c| {
        if (conv.decimal_point.len > 0 and c == conv.decimal_point[0]) {
            try normalized.append('.');
        } else if (conv.thousands_sep.len > 0 and c == conv.thousands_sep[0]) {
            // Skip thousands separator
        } else {
            try normalized.append(c);
        }
    }

    return std.fmt.parseFloat(f64, normalized.items);
}

/// Convert a locale-formatted string to integer
pub fn atoi(str: []const u8) !i64 {
    const conv = localeconv();

    // Remove thousands separators
    var normalized = std.ArrayList(u8).init(allocator_helper.fast_allocator);
    defer normalized.deinit();

    for (str) |c| {
        if (conv.thousands_sep.len > 0 and c == conv.thousands_sep[0]) {
            // Skip
        } else {
            try normalized.append(c);
        }
    }

    return std.fmt.parseInt(i64, normalized.items, 10);
}

// ============================================================================
// Encoding Functions
// ============================================================================

/// Get the preferred encoding for the locale
pub fn getpreferredencoding(do_setlocale: bool) []const u8 {
    _ = do_setlocale;
    // Most modern systems use UTF-8
    return "UTF-8";
}

/// Get the default locale
pub fn getdefaultlocale() struct { language: ?[]const u8, encoding: ?[]const u8 } {
    return .{
        .language = "en_US",
        .encoding = "UTF-8",
    };
}

/// Get the current locale
pub fn getlocale(category: Category) struct { language: ?[]const u8, encoding: ?[]const u8 } {
    _ = category;
    if (std.mem.indexOf(u8, current_locale, ".")) |dot| {
        return .{
            .language = current_locale[0..dot],
            .encoding = current_locale[dot + 1 ..],
        };
    }
    return .{
        .language = current_locale,
        .encoding = null,
    };
}

/// Normalize locale name
pub fn normalize(allocator: std.mem.Allocator, localename: []const u8) ![]u8 {
    // Simple normalization: lowercase language, uppercase country
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var in_country = false;
    for (localename) |c| {
        if (c == '_') {
            in_country = true;
            try result.append('_');
        } else if (in_country) {
            try result.append(std.ascii.toUpper(c));
        } else {
            try result.append(std.ascii.toLower(c));
        }
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Day and Month Names
// ============================================================================

/// Day names (Sunday = 0)
pub const day_name = [_][]const u8{
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
};

/// Abbreviated day names
pub const day_abbr = [_][]const u8{
    "Sun",
    "Mon",
    "Tue",
    "Wed",
    "Thu",
    "Fri",
    "Sat",
};

/// Month names (January = 1)
pub const month_name = [_][]const u8{
    "",
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
};

/// Abbreviated month names
pub const month_abbr = [_][]const u8{
    "",
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
};

// ============================================================================
// Tests
// ============================================================================

test "setlocale" {
    const loc = setlocale(.LC_ALL, "C");
    try std.testing.expectEqualStrings("C", loc.?);
}

test "localeconv C locale" {
    _ = setlocale(.LC_ALL, "C");
    const conv = localeconv();
    try std.testing.expectEqualStrings(".", conv.decimal_point);
}

test "strcoll" {
    try std.testing.expectEqual(@as(i32, 0), strcoll("abc", "abc"));
    try std.testing.expect(strcoll("abc", "abd") < 0);
    try std.testing.expect(strcoll("abd", "abc") > 0);
}

test "atof" {
    _ = setlocale(.LC_ALL, "C");
    const value = try atof("123.45");
    try std.testing.expectApproxEqAbs(@as(f64, 123.45), value, 0.001);
}

test "atoi" {
    _ = setlocale(.LC_ALL, "C");
    const value = try atoi("12345");
    try std.testing.expectEqual(@as(i64, 12345), value);
}

test "getpreferredencoding" {
    const enc = getpreferredencoding(false);
    try std.testing.expectEqualStrings("UTF-8", enc);
}
