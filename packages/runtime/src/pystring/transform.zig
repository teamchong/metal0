/// String transformation methods - case changes, formatting
const std = @import("std");
const core = @import("core.zig");
const PyString = core.PyString;
const runtime = @import("../runtime.zig");
const PyObject = runtime.PyObject;

pub fn upper(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    @setRuntimeSafety(false); // Hot path - disable bounds checks
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));

    const result = try allocator.alloc(u8, data.data.len);

    // SIMD fast path: process 16 bytes at once
    const Vec16 = @Vector(16, u8);
    const lower_a: Vec16 = @splat('a');
    const lower_z: Vec16 = @splat('z');
    const case_bit: Vec16 = @splat(32); // 'a' - 'A' = 32

    var i: usize = 0;
    while (i + 16 <= data.data.len) : (i += 16) {
        const chunk: Vec16 = data.data[i..][0..16].*;
        const is_lower = (chunk >= lower_a) & (chunk <= lower_z);
        const converted = chunk - (case_bit & is_lower); // Subtract 32 if lowercase
        result[i..][0..16].* = converted;
    }

    // Handle remaining bytes (< 16)
    while (i < data.data.len) : (i += 1) {
        result[i] = std.ascii.toUpper(data.data[i]);
    }

    return try PyString.createOwned(allocator, result);
}

pub fn lower(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    @setRuntimeSafety(false); // Hot path - disable bounds checks
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));

    const result = try allocator.alloc(u8, data.data.len);

    // SIMD fast path: process 16 bytes at once
    const Vec16 = @Vector(16, u8);
    const upper_a: Vec16 = @splat('A');
    const upper_z: Vec16 = @splat('Z');
    const case_bit: Vec16 = @splat(32); // 'a' - 'A' = 32

    var i: usize = 0;
    while (i + 16 <= data.data.len) : (i += 16) {
        const chunk: Vec16 = data.data[i..][0..16].*;
        const is_upper = (chunk >= upper_a) & (chunk <= upper_z);
        const converted = chunk + (case_bit & is_upper); // Add 32 if uppercase
        result[i..][0..16].* = converted;
    }

    // Handle remaining bytes (< 16)
    while (i < data.data.len) : (i += 1) {
        result[i] = std.ascii.toLower(data.data[i]);
    }

    return try PyString.createOwned(allocator, result);
}

pub fn capitalize(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));

    if (data.data.len == 0) {
        return try PyString.create(allocator, "");
    }

    const result = try allocator.alloc(u8, data.data.len);
    defer allocator.free(result); // Free temporary buffer
    result[0] = std.ascii.toUpper(data.data[0]);

    for (data.data[1..], 0..) |c, i| {
        result[i + 1] = std.ascii.toLower(c);
    }

    return try PyString.create(allocator, result);
}

pub fn swapcase(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));

    const result = try allocator.alloc(u8, data.data.len);
    defer allocator.free(result); // Free temporary buffer
    for (data.data, 0..) |c, i| {
        if (std.ascii.isUpper(c)) {
            result[i] = std.ascii.toLower(c);
        } else if (std.ascii.isLower(c)) {
            result[i] = std.ascii.toUpper(c);
        } else {
            result[i] = c;
        }
    }

    return try PyString.create(allocator, result);
}

pub fn title(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));

    const result = try allocator.alloc(u8, data.data.len);
    defer allocator.free(result); // Free temporary buffer
    var prev_was_alpha = false;

    for (data.data, 0..) |c, i| {
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

    return try PyString.create(allocator, result);
}

pub fn center(allocator: std.mem.Allocator, obj: *PyObject, width: i64) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));

    const w: usize = @intCast(width);
    if (w <= data.data.len) {
        return try PyString.create(allocator, data.data);
    }

    const total_padding = w - data.data.len;
    const left_padding = total_padding / 2;
    const right_padding = total_padding - left_padding;
    _ = right_padding; // Calculated for clarity, actual padding is handled by slice

    const result = try allocator.alloc(u8, w);
    defer allocator.free(result); // Free temporary buffer
    @memset(result[0..left_padding], ' ');
    @memcpy(result[left_padding .. left_padding + data.data.len], data.data);
    @memset(result[left_padding + data.data.len ..], ' ');

    return try PyString.create(allocator, result);
}
