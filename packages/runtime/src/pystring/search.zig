/// String search and test methods - contains, find, count, predicates
const std = @import("std");
const core = @import("core.zig");
const PyString = core.PyString;
const runtime = @import("../runtime.zig");
const PyObject = runtime.PyObject;

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

pub fn contains(obj: *PyObject, substring: *PyObject) bool {
    std.debug.assert(obj.type_id == .string);
    std.debug.assert(substring.type_id == .string);
    const haystack_data: *PyString = @ptrCast(@alignCast(obj.data));
    const needle_data: *PyString = @ptrCast(@alignCast(substring.data));

    const haystack = haystack_data.data;
    const needle = needle_data.data;

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
    std.debug.assert(obj.type_id == .string);
    std.debug.assert(prefix.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));
    const prefix_data: *PyString = @ptrCast(@alignCast(prefix.data));

    const str = data.data;
    const pre = prefix_data.data;

    if (pre.len > str.len) return false;
    return std.mem.eql(u8, str[0..pre.len], pre);
}

pub fn endswith(obj: *PyObject, suffix: *PyObject) bool {
    std.debug.assert(obj.type_id == .string);
    std.debug.assert(suffix.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));
    const suffix_data: *PyString = @ptrCast(@alignCast(suffix.data));

    const str = data.data;
    const suf = suffix_data.data;

    if (suf.len > str.len) return false;
    return std.mem.eql(u8, str[str.len - suf.len ..], suf);
}

pub fn find(obj: *PyObject, substring: *PyObject) i64 {
    std.debug.assert(obj.type_id == .string);
    std.debug.assert(substring.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));
    const needle_data: *PyString = @ptrCast(@alignCast(substring.data));

    const haystack = data.data;
    const needle = needle_data.data;

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
    std.debug.assert(obj.type_id == .string);
    std.debug.assert(substring.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));
    const needle_data: *PyString = @ptrCast(@alignCast(substring.data));

    const str = data.data;
    const sub = needle_data.data;

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
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));
    const str = data.data;

    if (str.len == 0) return false;

    // Use comptime lookup table (faster than function call!)
    for (str) |c| {
        if (!IS_DIGIT[c]) return false;
    }
    return true;
}

pub fn isalpha(obj: *PyObject) bool {
    @setRuntimeSafety(false); // Hot path - disable bounds checks
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));
    const str = data.data;

    if (str.len == 0) return false;

    // Use comptime lookup table (faster than function call!)
    for (str) |c| {
        if (!IS_ALPHA[c]) return false;
    }
    return true;
}
