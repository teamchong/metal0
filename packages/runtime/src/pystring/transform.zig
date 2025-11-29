/// String transformation methods - case changes, formatting
/// Updated for CPython-compatible PyUnicodeObject
const std = @import("std");
const core = @import("core.zig");
const PyString = core.PyString;
const runtime = @import("../runtime.zig");
const PyObject = runtime.PyObject;
const PyUnicodeObject = runtime.PyUnicodeObject;

/// Helper to get string data from PyUnicodeObject
inline fn getStrData(obj: *PyObject) []const u8 {
    const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
    const len: usize = @intCast(str_obj.length);
    return str_obj.data[0..len];
}

pub fn upper(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    @setRuntimeSafety(false); // Hot path - disable bounds checks
    std.debug.assert(runtime.PyUnicode_Check(obj));
    const str = getStrData(obj);

    const result = try allocator.alloc(u8, str.len);

    // SIMD fast path: process 16 bytes at once
    const Vec16 = @Vector(16, u8);
    const lower_a: Vec16 = @splat('a');
    const lower_z: Vec16 = @splat('z');
    const case_bit: Vec16 = @splat(32); // 'a' - 'A' = 32

    var i: usize = 0;
    while (i + 16 <= str.len) : (i += 16) {
        const chunk: Vec16 = str[i..][0..16].*;
        const is_lower = (chunk >= lower_a) & (chunk <= lower_z);
        const converted = chunk - (case_bit & is_lower); // Subtract 32 if lowercase
        result[i..][0..16].* = converted;
    }

    // Handle remaining bytes (< 16)
    while (i < str.len) : (i += 1) {
        result[i] = std.ascii.toUpper(str[i]);
    }

    return try PyString.createOwned(allocator, result);
}

pub fn lower(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    @setRuntimeSafety(false); // Hot path - disable bounds checks
    std.debug.assert(runtime.PyUnicode_Check(obj));
    const str = getStrData(obj);

    const result = try allocator.alloc(u8, str.len);

    // SIMD fast path: process 16 bytes at once
    const Vec16 = @Vector(16, u8);
    const upper_a: Vec16 = @splat('A');
    const upper_z: Vec16 = @splat('Z');
    const case_bit: Vec16 = @splat(32); // 'a' - 'A' = 32

    var i: usize = 0;
    while (i + 16 <= str.len) : (i += 16) {
        const chunk: Vec16 = str[i..][0..16].*;
        const is_upper = (chunk >= upper_a) & (chunk <= upper_z);
        const converted = chunk + (case_bit & is_upper); // Add 32 if uppercase
        result[i..][0..16].* = converted;
    }

    // Handle remaining bytes (< 16)
    while (i < str.len) : (i += 1) {
        result[i] = std.ascii.toLower(str[i]);
    }

    return try PyString.createOwned(allocator, result);
}

pub fn capitalize(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    std.debug.assert(runtime.PyUnicode_Check(obj));
    const str = getStrData(obj);

    if (str.len == 0) {
        return try PyString.create(allocator, "");
    }

    const result = try allocator.alloc(u8, str.len);
    result[0] = std.ascii.toUpper(str[0]);

    for (str[1..], 0..) |c, i| {
        result[i + 1] = std.ascii.toLower(c);
    }

    return try PyString.createOwned(allocator, result);
}

pub fn swapcase(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    std.debug.assert(runtime.PyUnicode_Check(obj));
    const str = getStrData(obj);

    const result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| {
        if (std.ascii.isUpper(c)) {
            result[i] = std.ascii.toLower(c);
        } else if (std.ascii.isLower(c)) {
            result[i] = std.ascii.toUpper(c);
        } else {
            result[i] = c;
        }
    }

    return try PyString.createOwned(allocator, result);
}

pub fn title(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    std.debug.assert(runtime.PyUnicode_Check(obj));
    const str = getStrData(obj);

    const result = try allocator.alloc(u8, str.len);
    var prev_was_alpha = false;

    for (str, 0..) |c, i| {
        if (std.ascii.isAlphabetic(c)) {
            if (!prev_was_alpha) {
                result[i] = std.ascii.toUpper(c);
            } else {
                result[i] = std.ascii.toLower(c);
            }
            prev_was_alpha = true;
        } else {
            result[i] = c;
            prev_was_alpha = false;
        }
    }

    return try PyString.createOwned(allocator, result);
}

pub fn center(allocator: std.mem.Allocator, obj: *PyObject, width: i64) !*PyObject {
    std.debug.assert(runtime.PyUnicode_Check(obj));
    const str = getStrData(obj);

    const w: usize = @intCast(width);
    if (w <= str.len) {
        return try PyString.create(allocator, str);
    }

    const total_padding = w - str.len;
    const left_padding = total_padding / 2;

    const result = try allocator.alloc(u8, w);
    @memset(result[0..left_padding], ' ');
    @memcpy(result[left_padding .. left_padding + str.len], str);
    @memset(result[left_padding + str.len ..], ' ');

    return try PyString.createOwned(allocator, result);
}
