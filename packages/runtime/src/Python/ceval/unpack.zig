/// Unpack iterable for assignment
/// Mirrors part of cpython/Python/ceval.c
const std = @import("std");
const runtime = @import("../../runtime.zig");

/// Unpack iterable for assignment
pub fn unpackIterable(
    allocator: std.mem.Allocator,
    iterable: ?*anyopaque,
    argcnt: usize,
    argcntafter: usize,
) ![]?*anyopaque {
    const iter_ptr = iterable orelse return error.NotImplemented;
    const iter_obj: *runtime.PyObject = @ptrCast(@alignCast(iter_ptr));
    const type_id = runtime.getTypeId(iter_obj);

    return switch (type_id) {
        .list => unpackList(allocator, iter_obj, argcnt, argcntafter),
        .tuple => unpackTuple(allocator, iter_obj, argcnt, argcntafter),
        .string => unpackString(allocator, iter_obj, argcnt, argcntafter),
        .bytes => unpackBytes(allocator, iter_obj, argcnt, argcntafter),
        else => error.TypeError,
    };
}

fn unpackList(allocator: std.mem.Allocator, iter_obj: *runtime.PyObject, argcnt: usize, argcntafter: usize) ![]?*anyopaque {
    const list_obj: *runtime.PyListObject = @ptrCast(@alignCast(iter_obj));
    const items_ptr = list_obj.ob_item orelse return error.ValueError;
    const list_size: usize = @intCast(list_obj.ob_size);
    return unpackSlice(allocator, items_ptr[0..list_size], argcnt, argcntafter);
}

fn unpackTuple(allocator: std.mem.Allocator, iter_obj: *runtime.PyObject, argcnt: usize, argcntafter: usize) ![]?*anyopaque {
    const tuple_obj: *runtime.PyTupleObject = @ptrCast(@alignCast(iter_obj));
    const items_ptr = tuple_obj.ob_item orelse return error.ValueError;
    const tuple_size: usize = @intCast(tuple_obj.ob_size);
    return unpackSlice(allocator, items_ptr[0..tuple_size], argcnt, argcntafter);
}

fn unpackSlice(allocator: std.mem.Allocator, items: []*runtime.PyObject, argcnt: usize, argcntafter: usize) ![]?*anyopaque {
    const total_needed = argcnt + argcntafter;

    if (argcntafter > 0) {
        if (items.len < total_needed) {
            return error.ValueError;
        }

        var result = try allocator.alloc(?*anyopaque, argcnt + 1 + argcntafter);

        for (0..argcnt) |i| {
            runtime.incref(items[i]);
            result[i] = @ptrCast(items[i]);
        }

        const star_len = items.len - argcnt - argcntafter;
        const star_list = try runtime.PyList.create(allocator);
        for (0..star_len) |i| {
            runtime.incref(items[argcnt + i]);
            try runtime.PyList.append(star_list, items[argcnt + i]);
        }
        result[argcnt] = @ptrCast(star_list);

        for (0..argcntafter) |i| {
            const idx = items.len - argcntafter + i;
            runtime.incref(items[idx]);
            result[argcnt + 1 + i] = @ptrCast(items[idx]);
        }

        return result;
    } else {
        if (items.len != argcnt) {
            return error.ValueError;
        }

        var result = try allocator.alloc(?*anyopaque, argcnt);
        for (items, 0..) |item, i| {
            runtime.incref(item);
            result[i] = @ptrCast(item);
        }
        return result;
    }
}

fn unpackString(allocator: std.mem.Allocator, iter_obj: *runtime.PyObject, argcnt: usize, argcntafter: usize) ![]?*anyopaque {
    const str_val = runtime.PyString.getValue(iter_obj);
    const total_needed = argcnt + argcntafter;

    if (argcntafter > 0) {
        if (str_val.len < total_needed) {
            return error.ValueError;
        }

        var result = try allocator.alloc(?*anyopaque, argcnt + 1 + argcntafter);

        for (0..argcnt) |i| {
            const char_str = try allocator.alloc(u8, 1);
            char_str[0] = str_val[i];
            const char_obj = try runtime.PyString.create(allocator, char_str);
            result[i] = @ptrCast(char_obj);
        }

        const star_len = str_val.len - argcnt - argcntafter;
        const star_list = try runtime.PyList.create(allocator);
        for (0..star_len) |i| {
            const char_str = try allocator.alloc(u8, 1);
            char_str[0] = str_val[argcnt + i];
            const char_obj = try runtime.PyString.create(allocator, char_str);
            try runtime.PyList.append(star_list, char_obj);
        }
        result[argcnt] = @ptrCast(star_list);

        for (0..argcntafter) |i| {
            const idx = str_val.len - argcntafter + i;
            const char_str = try allocator.alloc(u8, 1);
            char_str[0] = str_val[idx];
            const char_obj = try runtime.PyString.create(allocator, char_str);
            result[argcnt + 1 + i] = @ptrCast(char_obj);
        }

        return result;
    } else {
        if (str_val.len != argcnt) {
            return error.ValueError;
        }

        var result = try allocator.alloc(?*anyopaque, argcnt);
        for (0..argcnt) |i| {
            const char_str = try allocator.alloc(u8, 1);
            char_str[0] = str_val[i];
            const char_obj = try runtime.PyString.create(allocator, char_str);
            result[i] = @ptrCast(char_obj);
        }
        return result;
    }
}

fn unpackBytes(allocator: std.mem.Allocator, iter_obj: *runtime.PyObject, argcnt: usize, argcntafter: usize) ![]?*anyopaque {
    const bytes_obj: *runtime.PyBytesObject = @ptrCast(@alignCast(iter_obj));
    const bytes_val = bytes_obj.ob_sval[0..@intCast(bytes_obj.ob_size)];
    const total_needed = argcnt + argcntafter;

    if (argcntafter > 0) {
        if (bytes_val.len < total_needed) {
            return error.ValueError;
        }

        var result = try allocator.alloc(?*anyopaque, argcnt + 1 + argcntafter);

        for (0..argcnt) |i| {
            const byte_slice = try allocator.alloc(u8, 1);
            byte_slice[0] = bytes_val[i];
            const byte_obj = try runtime.PyBytes.create(allocator, byte_slice);
            result[i] = @ptrCast(byte_obj);
        }

        const star_len = bytes_val.len - argcnt - argcntafter;
        const star_list = try runtime.PyList.create(allocator);
        for (0..star_len) |i| {
            const byte_slice = try allocator.alloc(u8, 1);
            byte_slice[0] = bytes_val[argcnt + i];
            const byte_obj = try runtime.PyBytes.create(allocator, byte_slice);
            try runtime.PyList.append(star_list, byte_obj);
        }
        result[argcnt] = @ptrCast(star_list);

        for (0..argcntafter) |i| {
            const idx = bytes_val.len - argcntafter + i;
            const byte_slice = try allocator.alloc(u8, 1);
            byte_slice[0] = bytes_val[idx];
            const byte_obj = try runtime.PyBytes.create(allocator, byte_slice);
            result[argcnt + 1 + i] = @ptrCast(byte_obj);
        }

        return result;
    } else {
        if (bytes_val.len != argcnt) {
            return error.ValueError;
        }

        var result = try allocator.alloc(?*anyopaque, argcnt);
        for (0..argcnt) |i| {
            const byte_slice = try allocator.alloc(u8, 1);
            byte_slice[0] = bytes_val[i];
            const byte_obj = try runtime.PyBytes.create(allocator, byte_slice);
            result[i] = @ptrCast(byte_obj);
        }
        return result;
    }
}
