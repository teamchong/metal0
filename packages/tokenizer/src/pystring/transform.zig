/// String transformation methods - case changes, formatting
const std = @import("std");
const core = @import("core.zig");
const PyString = core.PyString;
const runtime = @import("../runtime.zig");
const PyObject = runtime.PyObject;

pub fn upper(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));

    const result = try allocator.alloc(u8, data.data.len);
    for (data.data, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }

    const new_obj = try allocator.create(PyObject);
    const str_data = try allocator.create(PyString);
    str_data.data = result;

    new_obj.* = PyObject{
        .ref_count = 1,
        .type_id = .string,
        .data = str_data,
    };
    return new_obj;
}

pub fn lower(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));

    const result = try allocator.alloc(u8, data.data.len);
    for (data.data, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }

    const new_obj = try allocator.create(PyObject);
    const str_data = try allocator.create(PyString);
    str_data.data = result;

    new_obj.* = PyObject{
        .ref_count = 1,
        .type_id = .string,
        .data = str_data,
    };
    return new_obj;
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
