/// String search and test methods - contains, find, count, predicates
/// Updated for CPython-compatible PyUnicodeObject
const std = @import("std");
const runtime = @import("../runtime.zig");
const PyObject = runtime.PyObject;
const PyUnicodeObject = runtime.PyUnicodeObject;

/// Comptime lookup tables for ASCII character classes (much faster than function calls!)
const IS_DIGIT: [256]bool = blk: {
    var table: [256]bool = [_]bool{false} ** 256;
    var i: u8 = '0';
    while (i <= '9') : (i += 1) table[i] = true;
    break :blk table;
};

const IS_ALPHA: [256]bool = blk: {
    var table: [256]bool = [_]bool{false} ** 256;
    var i: u8 = 'A';
    while (i <= 'Z') : (i += 1) table[i] = true;
    i = 'a';
    while (i <= 'z') : (i += 1) table[i] = true;
    break :blk table;
};

const IS_ALNUM: [256]bool = blk: {
    var table: [256]bool = [_]bool{false} ** 256;
    var i: u8 = '0';
    while (i <= '9') : (i += 1) table[i] = true;
    i = 'A';
    while (i <= 'Z') : (i += 1) table[i] = true;
    i = 'a';
    while (i <= 'z') : (i += 1) table[i] = true;
    break :blk table;
};

const IS_SPACE: [256]bool = blk: {
    var table: [256]bool = [_]bool{false} ** 256;
    table[' '] = true;
    table['\t'] = true;
    table['\n'] = true;
    table['\r'] = true;
    table['\x0B'] = true; // vertical tab
    table['\x0C'] = true; // form feed
    break :blk table;
};

/// Helper to get string data from PyUnicodeObject
inline fn getStrData(obj: *PyObject) []const u8 {
    const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
    const len: usize = @intCast(str_obj.length);
    return str_obj.data[0..len];
}

pub fn contains(obj: *PyObject, substring: *PyObject) bool {
    std.debug.assert(runtime.PyUnicode_Check(obj));
    std.debug.assert(runtime.PyUnicode_Check(substring));

    const haystack = getStrData(obj);
    const needle = getStrData(substring);

    // Empty string is always contained
    if (needle.len == 0) return true;

    // Needle longer than haystack
    if (needle.len > haystack.len) return false;

    // Search for substring
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) {
            return true;
        }
    }
    return false;
}

pub fn startswith(obj: *PyObject, prefix: *PyObject) bool {
    std.debug.assert(runtime.PyUnicode_Check(obj));
    std.debug.assert(runtime.PyUnicode_Check(prefix));

    const str = getStrData(obj);
    const pre = getStrData(prefix);

    if (pre.len > str.len) return false;
    return std.mem.eql(u8, str[0..pre.len], pre);
}

pub fn endswith(obj: *PyObject, suffix: *PyObject) bool {
    std.debug.assert(runtime.PyUnicode_Check(obj));
    std.debug.assert(runtime.PyUnicode_Check(suffix));

    const str = getStrData(obj);
    const suf = getStrData(suffix);

    if (suf.len > str.len) return false;
    return std.mem.eql(u8, str[str.len - suf.len ..], suf);
}

pub fn find(obj: *PyObject, substring: *PyObject) i64 {
    std.debug.assert(runtime.PyUnicode_Check(obj));
    std.debug.assert(runtime.PyUnicode_Check(substring));

    const haystack = getStrData(obj);
    const needle = getStrData(substring);

    // Empty string is found at position 0
    if (needle.len == 0) return 0;

    // Needle longer than haystack
    if (needle.len > haystack.len) return -1;

    // Search for substring
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) {
            return @intCast(i);
        }
    }
    return -1;
}

pub fn count_substr(obj: *PyObject, substring: *PyObject) i64 {
    std.debug.assert(runtime.PyUnicode_Check(obj));
    std.debug.assert(runtime.PyUnicode_Check(substring));

    const str = getStrData(obj);
    const sub = getStrData(substring);

    if (sub.len == 0) return 0;
    if (sub.len > str.len) return 0;

    var count_val: i64 = 0;
    var i: usize = 0;
    while (i <= str.len - sub.len) {
        if (std.mem.eql(u8, str[i .. i + sub.len], sub)) {
            count_val += 1;
            i += sub.len; // Move past this occurrence
        } else {
            i += 1;
        }
    }
    return count_val;
}

pub fn isdigit(obj: *PyObject) bool {
    @setRuntimeSafety(false); // Hot path - disable bounds checks
    std.debug.assert(runtime.PyUnicode_Check(obj));

    const str = getStrData(obj);
    if (str.len == 0) return false;

    // Use comptime lookup table (faster than function call!)
    for (str) |c| {
        if (!IS_DIGIT[c]) return false;
    }
    return true;
}

pub fn isalpha(obj: *PyObject) bool {
    @setRuntimeSafety(false); // Hot path - disable bounds checks
    std.debug.assert(runtime.PyUnicode_Check(obj));

    const str = getStrData(obj);
    if (str.len == 0) return false;

    // Use comptime lookup table (faster than function call!)
    for (str) |c| {
        if (!IS_ALPHA[c]) return false;
    }
    return true;
}
