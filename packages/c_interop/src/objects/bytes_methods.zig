/// Shared bytes/bytearray methods
///
/// Implements CPython's Objects/bytes_methods.c
/// Common methods shared between bytes and bytearray types
///
/// Reference: cpython/Objects/bytes_methods.c

const std = @import("std");
const cpython = @import("../include/object.zig");

pub const PyObject = cpython.PyObject;

// ============================================================================
// STRING PREDICATES
// ============================================================================

/// Check if all characters are lowercase
pub fn _Py_bytes_islower(data: [*]const u8, len: isize) c_int {
    if (len <= 0) return 0;
    var cased = false;
    var i: usize = 0;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        const c = data[i];
        if (std.ascii.isUpper(c)) return 0;
        if (!cased and std.ascii.isLower(c)) cased = true;
    }
    return if (cased) 1 else 0;
}

/// Check if all characters are uppercase
pub fn _Py_bytes_isupper(data: [*]const u8, len: isize) c_int {
    if (len <= 0) return 0;
    var cased = false;
    var i: usize = 0;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        const c = data[i];
        if (std.ascii.isLower(c)) return 0;
        if (!cased and std.ascii.isUpper(c)) cased = true;
    }
    return if (cased) 1 else 0;
}

/// Check if all characters are alphanumeric
pub fn _Py_bytes_isalnum(data: [*]const u8, len: isize) c_int {
    if (len <= 0) return 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        if (!std.ascii.isAlphanumeric(data[i])) return 0;
    }
    return 1;
}

/// Check if all characters are alphabetic
pub fn _Py_bytes_isalpha(data: [*]const u8, len: isize) c_int {
    if (len <= 0) return 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        if (!std.ascii.isAlphabetic(data[i])) return 0;
    }
    return 1;
}

/// Check if all characters are digits
pub fn _Py_bytes_isdigit(data: [*]const u8, len: isize) c_int {
    if (len <= 0) return 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        if (!std.ascii.isDigit(data[i])) return 0;
    }
    return 1;
}

/// Check if all characters are whitespace
pub fn _Py_bytes_isspace(data: [*]const u8, len: isize) c_int {
    if (len <= 0) return 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        if (!std.ascii.isWhitespace(data[i])) return 0;
    }
    return 1;
}

/// Check if titlecase
pub fn _Py_bytes_istitle(data: [*]const u8, len: isize) c_int {
    if (len <= 0) return 0;
    var cased = false;
    var previous_is_cased = false;
    var i: usize = 0;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        const c = data[i];
        if (std.ascii.isUpper(c)) {
            if (previous_is_cased) return 0;
            previous_is_cased = true;
            cased = true;
        } else if (std.ascii.isLower(c)) {
            if (!previous_is_cased) return 0;
            previous_is_cased = true;
            cased = true;
        } else {
            previous_is_cased = false;
        }
    }
    return if (cased) 1 else 0;
}

// ============================================================================
// CASE CONVERSION
// ============================================================================

/// Convert to lowercase
pub fn _Py_bytes_lower(data: [*]u8, len: isize) void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        data[i] = std.ascii.toLower(data[i]);
    }
}

/// Convert to uppercase
pub fn _Py_bytes_upper(data: [*]u8, len: isize) void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        data[i] = std.ascii.toUpper(data[i]);
    }
}

/// Swap case
pub fn _Py_bytes_swapcase(data: [*]u8, len: isize) void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        const c = data[i];
        if (std.ascii.isUpper(c)) {
            data[i] = std.ascii.toLower(c);
        } else if (std.ascii.isLower(c)) {
            data[i] = std.ascii.toUpper(c);
        }
    }
}

/// Capitalize (first char upper, rest lower)
pub fn _Py_bytes_capitalize(data: [*]u8, len: isize) void {
    if (len <= 0) return;
    data[0] = std.ascii.toUpper(data[0]);
    var i: usize = 1;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        data[i] = std.ascii.toLower(data[i]);
    }
}

/// Title case
pub fn _Py_bytes_title(data: [*]u8, len: isize) void {
    var previous_is_cased = false;
    var i: usize = 0;
    while (i < @as(usize, @intCast(len))) : (i += 1) {
        const c = data[i];
        if (std.ascii.isLower(c)) {
            if (!previous_is_cased) {
                data[i] = std.ascii.toUpper(c);
            }
            previous_is_cased = true;
        } else if (std.ascii.isUpper(c)) {
            if (previous_is_cased) {
                data[i] = std.ascii.toLower(c);
            }
            previous_is_cased = true;
        } else {
            previous_is_cased = false;
        }
    }
}

// ============================================================================
// SEARCH OPERATIONS
// ============================================================================

/// Find substring (returns -1 if not found)
pub fn _Py_bytes_find(haystack: [*]const u8, haystack_len: isize, needle: [*]const u8, needle_len: isize, start: isize, end: isize) isize {
    if (needle_len <= 0) return start;
    if (haystack_len <= 0) return -1;

    const h_len = @as(usize, @intCast(haystack_len));
    const n_len = @as(usize, @intCast(needle_len));
    const s = @as(usize, @intCast(@max(0, start)));
    const e = @as(usize, @intCast(@min(haystack_len, end)));

    if (s >= e or n_len > e - s) return -1;

    const haystack_slice = haystack[s..e];
    const needle_slice = needle[0..n_len];

    if (std.mem.indexOf(u8, haystack_slice, needle_slice)) |pos| {
        return @as(isize, @intCast(s + pos));
    }
    return -1;
}

/// Reverse find substring
pub fn _Py_bytes_rfind(haystack: [*]const u8, haystack_len: isize, needle: [*]const u8, needle_len: isize, start: isize, end: isize) isize {
    if (needle_len <= 0) return end;
    if (haystack_len <= 0) return -1;

    const h_len = @as(usize, @intCast(haystack_len));
    const n_len = @as(usize, @intCast(needle_len));
    const s = @as(usize, @intCast(@max(0, start)));
    const e = @as(usize, @intCast(@min(haystack_len, end)));

    _ = h_len;

    if (s >= e or n_len > e - s) return -1;

    const haystack_slice = haystack[s..e];
    const needle_slice = needle[0..n_len];

    if (std.mem.lastIndexOf(u8, haystack_slice, needle_slice)) |pos| {
        return @as(isize, @intCast(s + pos));
    }
    return -1;
}

/// Count occurrences
pub fn _Py_bytes_count(haystack: [*]const u8, haystack_len: isize, needle: [*]const u8, needle_len: isize, start: isize, end: isize) isize {
    if (needle_len <= 0) return haystack_len + 1;
    if (haystack_len <= 0) return 0;

    const n_len = @as(usize, @intCast(needle_len));
    const s = @as(usize, @intCast(@max(0, start)));
    const e = @as(usize, @intCast(@min(haystack_len, end)));

    if (s >= e or n_len > e - s) return 0;

    const haystack_slice = haystack[s..e];
    const needle_slice = needle[0..n_len];

    var count: isize = 0;
    var pos: usize = 0;
    while (pos + n_len <= haystack_slice.len) {
        if (std.mem.eql(u8, haystack_slice[pos .. pos + n_len], needle_slice)) {
            count += 1;
            pos += n_len;
        } else {
            pos += 1;
        }
    }
    return count;
}

/// Check if starts with prefix
pub fn _Py_bytes_startswith(data: [*]const u8, len: isize, prefix: [*]const u8, prefix_len: isize, start: isize, end: isize) c_int {
    const s = @as(usize, @intCast(@max(0, start)));
    const e = @as(usize, @intCast(@min(len, end)));
    const p_len = @as(usize, @intCast(prefix_len));

    if (s >= e or p_len > e - s) return 0;

    const data_slice = data[s .. s + p_len];
    const prefix_slice = prefix[0..p_len];

    return if (std.mem.eql(u8, data_slice, prefix_slice)) 1 else 0;
}

/// Check if ends with suffix
pub fn _Py_bytes_endswith(data: [*]const u8, len: isize, suffix: [*]const u8, suffix_len: isize, start: isize, end: isize) c_int {
    const s = @as(usize, @intCast(@max(0, start)));
    const e = @as(usize, @intCast(@min(len, end)));
    const suf_len = @as(usize, @intCast(suffix_len));

    if (s >= e or suf_len > e - s) return 0;

    const data_slice = data[e - suf_len .. e];
    const suffix_slice = suffix[0..suf_len];

    return if (std.mem.eql(u8, data_slice, suffix_slice)) 1 else 0;
}
