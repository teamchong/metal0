/// String manipulation methods - split, strip, replace, join, slice
const std = @import("std");
const core = @import("core.zig");
const PyString = core.PyString;
const runtime = @import("runtime.zig");
const pylist = @import("pylist.zig");
const PyObject = runtime.PyObject;
const PyList = pylist.PyList;
const PythonError = runtime.PythonError;

pub fn slice(allocator: std.mem.Allocator, obj: *PyObject, start_opt: ?i64, end_opt: ?i64) !*PyObject {
    return sliceWithStep(allocator, obj, start_opt, end_opt, null);
}

pub fn sliceWithStep(allocator: std.mem.Allocator, obj: *PyObject, start_opt: ?i64, end_opt: ?i64, step_opt: ?i64) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));

    const str_len: i64 = @intCast(data.data.len);
    const step: i64 = step_opt orelse 1;

    if (step == 0) {
        return PythonError.ValueError; // Step cannot be zero
    }

    // Handle defaults and bounds
    var start: i64 = start_opt orelse (if (step > 0) 0 else str_len - 1);
    var end: i64 = end_opt orelse (if (step > 0) str_len else -str_len - 1);

    // Handle negative indices
    if (start < 0) start = @max(0, str_len + start);
    if (end < 0) {
        const min_end: i64 = if (step < 0) -1 else 0;
        end = @max(min_end, str_len + end);
    }

    // Clamp to valid range
    start = @max(0, @min(start, str_len));
    if (step > 0) {
        end = @max(0, @min(end, str_len));
    } else {
        // For negative step, allow end to be -1 to mean "include index 0"
        end = @max(-1, @min(end, str_len));
    }

    // If step is 1, use COW (zero-copy slice!)
    if (step == 1) {
        const start_idx: usize = @intCast(start);
        const end_idx: usize = @intCast(end);
        const substring = data.data[start_idx..end_idx];
        // COW: borrow from source, no copy!
        return try PyString.createBorrowed(allocator, obj, substring);
    }

    // Calculate result size for step != 1
    var result_len: usize = 0;
    if (step > 0) {
        const start_idx: usize = @intCast(start);
        const end_idx: usize = @intCast(end);
        const step_usize: usize = @intCast(step);
        if (end_idx > start_idx) {
            result_len = (end_idx - start_idx + step_usize - 1) / step_usize;
        }
    } else {
        const step_neg: i64 = -step;
        // end can be -1, so use i64 arithmetic
        if (start > end) {
            const count: i64 = @divFloor(start - end + step_neg - 1, step_neg);
            result_len = @intCast(count);
        }
    }

    // Allocate result buffer
    const result = try allocator.alloc(u8, result_len);
    var result_idx: usize = 0;

    // Fill result with step
    if (step > 0) {
        const start_idx: usize = @intCast(start);
        const end_idx: usize = @intCast(end);
        const step_usize: usize = @intCast(step);
        var i: usize = start_idx;
        while (i < end_idx and result_idx < result_len) : (i += step_usize) {
            result[result_idx] = data.data[i];
            result_idx += 1;
        }
    } else {
        // Negative step - iterate backwards
        const step_neg: i64 = -step;
        var i: i64 = start;
        while (i > end and result_idx < result_len) {
            const idx: usize = @intCast(i);
            result[result_idx] = data.data[idx];
            result_idx += 1;
            i -= step_neg;
        }
    }

    // Create new string from result
    const new_str = try PyString.create(allocator, result);
    // Free the temporary buffer (create() duplicates it)
    allocator.free(result);
    return new_str;
}

pub fn split(allocator: std.mem.Allocator, obj: *PyObject, separator: *PyObject) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    std.debug.assert(separator.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));
    const sep_data: *PyString = @ptrCast(@alignCast(separator.data));

    const str = data.data;
    const sep = sep_data.data;

    // Create result list
    const result = try PyList.create(allocator);

    // Handle empty separator (split into chars)
    if (sep.len == 0) {
        for (str) |c| {
            const char_obj = try PyString.create(allocator, &[_]u8{c});
            try PyList.append(result, char_obj);
            // append transfers ownership (no incref), so don't decref
        }
        return result;
    }

    // Split by separator
    var start: usize = 0;
    var i: usize = 0;
    while (i <= str.len - sep.len) {
        if (std.mem.eql(u8, str[i .. i + sep.len], sep)) {
            // Found separator - add substring
            const part = str[start..i];
            const part_obj = try PyString.create(allocator, part);
            try PyList.append(result, part_obj);
            // append transfers ownership (no incref), so don't decref
            i += sep.len;
            start = i;
        } else {
            i += 1;
        }
    }

    // Add final part
    const final_part = str[start..];
    const final_obj = try PyString.create(allocator, final_part);
    try PyList.append(result, final_obj);
    // append transfers ownership (no incref), so don't decref

    return result;
}

pub fn strip(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));
    const str = data.data;

    // Find first non-whitespace
    var start: usize = 0;
    while (start < str.len and std.ascii.isWhitespace(str[start])) : (start += 1) {}

    // Find last non-whitespace
    var end: usize = str.len;
    while (end > start and std.ascii.isWhitespace(str[end - 1])) : (end -= 1) {}

    // Create stripped string
    const stripped = str[start..end];
    return try PyString.create(allocator, stripped);
}

pub fn lstrip(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));
    const str = data.data;

    // Find first non-whitespace
    var start: usize = 0;
    while (start < str.len and std.ascii.isWhitespace(str[start])) : (start += 1) {}

    // Create left-stripped string
    const stripped = str[start..];
    return try PyString.create(allocator, stripped);
}

pub fn rstrip(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));
    const str = data.data;

    // Find last non-whitespace
    var end: usize = str.len;
    while (end > 0 and std.ascii.isWhitespace(str[end - 1])) : (end -= 1) {}

    // Create right-stripped string
    const stripped = str[0..end];
    return try PyString.create(allocator, stripped);
}

pub fn replace(allocator: std.mem.Allocator, obj: *PyObject, old: *PyObject, new: *PyObject) !*PyObject {
    std.debug.assert(obj.type_id == .string);
    std.debug.assert(old.type_id == .string);
    std.debug.assert(new.type_id == .string);
    const data: *PyString = @ptrCast(@alignCast(obj.data));
    const old_data: *PyString = @ptrCast(@alignCast(old.data));
    const new_data: *PyString = @ptrCast(@alignCast(new.data));

    const str = data.data;
    const old_str = old_data.data;
    const new_str = new_data.data;

    // Count occurrences to allocate result
    var count: usize = 0;
    var i: usize = 0;
    while (i <= str.len - old_str.len) {
        if (std.mem.eql(u8, str[i .. i + old_str.len], old_str)) {
            count += 1;
            i += old_str.len;
        } else {
            i += 1;
        }
    }

    // If no replacements, return copy of original
    if (count == 0) {
        return try PyString.create(allocator, str);
    }

    // Calculate result size and allocate
    const result_len = str.len - (count * old_str.len) + (count * new_str.len);
    const result = try allocator.alloc(u8, result_len);

    // Build result string
    var src_idx: usize = 0;
    var dst_idx: usize = 0;
    while (src_idx < str.len) {
        if (src_idx <= str.len - old_str.len and std.mem.eql(u8, str[src_idx .. src_idx + old_str.len], old_str)) {
            // Copy replacement
            @memcpy(result[dst_idx .. dst_idx + new_str.len], new_str);
            src_idx += old_str.len;
            dst_idx += new_str.len;
        } else {
            // Copy original char
            result[dst_idx] = str[src_idx];
            src_idx += 1;
            dst_idx += 1;
        }
    }

    const result_obj = try PyString.create(allocator, result);
    allocator.free(result); // Free temporary buffer after PyString duplicates it
    return result_obj;
}

pub fn join(allocator: std.mem.Allocator, separator: *PyObject, list: *PyObject) !*PyObject {
    std.debug.assert(separator.type_id == .string);
    std.debug.assert(list.type_id == .list);
    const sep_data: *PyString = @ptrCast(@alignCast(separator.data));
    const list_data: *PyList = @ptrCast(@alignCast(list.data));

    const sep = sep_data.data;
    const items = list_data.items.items;

    if (items.len == 0) {
        return try PyString.create(allocator, "");
    }

    // Calculate total length
    var total_len: usize = 0;
    for (items) |item| {
        if (item.type_id == .string) {
            const item_data: *PyString = @ptrCast(@alignCast(item.data));
            total_len += item_data.data.len;
        }
    }
    total_len += sep.len * (items.len - 1);

    // Build result
    const result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (items, 0..) |item, i| {
        if (item.type_id == .string) {
            const item_data: *PyString = @ptrCast(@alignCast(item.data));
            @memcpy(result[pos .. pos + item_data.data.len], item_data.data);
            pos += item_data.data.len;

            if (i < items.len - 1) {
                @memcpy(result[pos .. pos + sep.len], sep);
                pos += sep.len;
            }
        }
    }

    const result_obj = try PyString.create(allocator, result);
    allocator.free(result); // Free temporary buffer after PyString duplicates it
    return result_obj;
}
