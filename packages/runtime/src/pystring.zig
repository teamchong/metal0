/// Python string type implementation
const std = @import("std");
const runtime = @import("runtime.zig");
const pylist = @import("pylist.zig");

const PyObject = runtime.PyObject;
const PyList = pylist.PyList;
const incref = runtime.incref;
const decref = runtime.decref;
const PythonError = runtime.PythonError;

/// Python string type
pub const PyString = struct {
    data: []const u8,

    pub fn create(allocator: std.mem.Allocator, str: []const u8) !*PyObject {
        const obj = try allocator.create(PyObject);
        const str_data = try allocator.create(PyString);
        const owned = try allocator.dupe(u8, str);
        str_data.data = owned;

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .string,
            .data = str_data,
        };
        return obj;
    }

    pub fn getValue(obj: *PyObject) []const u8 {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        return data.data;
    }

    pub fn len(obj: *PyObject) usize {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        return data.data.len;
    }

    pub fn concat(allocator: std.mem.Allocator, a: *PyObject, b: *PyObject) !*PyObject {
        std.debug.assert(a.type_id == .string);
        std.debug.assert(b.type_id == .string);
        const a_data: *PyString = @ptrCast(@alignCast(a.data));
        const b_data: *PyString = @ptrCast(@alignCast(b.data));

        const result = try allocator.alloc(u8, a_data.data.len + b_data.data.len);
        @memcpy(result[0..a_data.data.len], a_data.data);
        @memcpy(result[a_data.data.len..], b_data.data);

        const obj = try allocator.create(PyObject);
        const str_data = try allocator.create(PyString);
        str_data.data = result;

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .string,
            .data = str_data,
        };
        return obj;
    }

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
            if (std.mem.eql(u8, haystack[i..i + needle.len], needle)) {
                return true;
            }
        }
        return false;
    }

    pub fn slice(obj: *PyObject, allocator: std.mem.Allocator, start_opt: ?i64, end_opt: ?i64, step_opt: ?i64) !*PyObject {
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
        if (end < 0) end = @max(0, str_len + end);

        // Clamp to valid range
        start = @max(0, @min(start, str_len));
        end = @max(0, @min(end, str_len));

        // If step is 1, we can use simple substring extraction (optimization)
        if (step == 1) {
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const substring = data.data[start_idx..end_idx];
            return try create(allocator, substring);
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
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const step_neg: usize = @intCast(-step);
            if (start_idx > end_idx) {
                result_len = (start_idx - end_idx + step_neg - 1) / step_neg;
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
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const step_neg: usize = @intCast(-step);
            var i: usize = start_idx;
            while (i > end_idx and result_idx < result_len) {
                result[result_idx] = data.data[i];
                result_idx += 1;
                if (i < step_neg) break;
                i -= step_neg;
            }
        }

        // Create new string from result
        const new_str = try create(allocator, result);
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
                const char_obj = try create(allocator, &[_]u8{c});
                try PyList.append(result, char_obj);
            }
            return result;
        }

        // Split by separator
        var start: usize = 0;
        var i: usize = 0;
        while (i <= str.len - sep.len) {
            if (std.mem.eql(u8, str[i..i + sep.len], sep)) {
                // Found separator - add substring
                const part = str[start..i];
                const part_obj = try create(allocator, part);
                try PyList.append(result, part_obj);
                i += sep.len;
                start = i;
            } else {
                i += 1;
            }
        }

        // Add final part
        const final_part = str[start..];
        const final_obj = try create(allocator, final_part);
        try PyList.append(result, final_obj);

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
        return try create(allocator, stripped);
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
            if (std.mem.eql(u8, str[i..i + old_str.len], old_str)) {
                count += 1;
                i += old_str.len;
            } else {
                i += 1;
            }
        }

        // If no replacements, return copy of original
        if (count == 0) {
            return try create(allocator, str);
        }

        // Calculate result size and allocate
        const result_len = str.len - (count * old_str.len) + (count * new_str.len);
        const result = try allocator.alloc(u8, result_len);

        // Build result string
        var src_idx: usize = 0;
        var dst_idx: usize = 0;
        while (src_idx < str.len) {
            if (src_idx <= str.len - old_str.len and std.mem.eql(u8, str[src_idx..src_idx + old_str.len], old_str)) {
                // Copy replacement
                @memcpy(result[dst_idx..dst_idx + new_str.len], new_str);
                src_idx += old_str.len;
                dst_idx += new_str.len;
            } else {
                // Copy original char
                result[dst_idx] = str[src_idx];
                src_idx += 1;
                dst_idx += 1;
            }
        }

        return try create(allocator, result);
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
        return std.mem.eql(u8, str[str.len - suf.len..], suf);
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
            if (std.mem.eql(u8, haystack[i..i + needle.len], needle)) {
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
            if (std.mem.eql(u8, str[i..i + sub.len], sub)) {
                count_val += 1;
                i += sub.len; // Move past this occurrence
            } else {
                i += 1;
            }
        }
        return count_val;
    }

    pub fn join(allocator: std.mem.Allocator, separator: *PyObject, list: *PyObject) !*PyObject {
        std.debug.assert(separator.type_id == .string);
        std.debug.assert(list.type_id == .list);
        const sep_data: *PyString = @ptrCast(@alignCast(separator.data));
        const list_data: *PyList = @ptrCast(@alignCast(list.data));

        const sep = sep_data.data;
        const items = list_data.items.items;

        if (items.len == 0) {
            return try create(allocator, "");
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
                @memcpy(result[pos..pos + item_data.data.len], item_data.data);
                pos += item_data.data.len;

                if (i < items.len - 1) {
                    @memcpy(result[pos..pos + sep.len], sep);
                    pos += sep.len;
                }
            }
        }

        return try create(allocator, result);
    }

    pub fn isdigit(obj: *PyObject) bool {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const str = data.data;

        if (str.len == 0) return false;

        for (str) |c| {
            if (!std.ascii.isDigit(c)) {
                return false;
            }
        }
        return true;
    }

    pub fn isalpha(obj: *PyObject) bool {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const str = data.data;

        if (str.len == 0) return false;

        for (str) |c| {
            if (!std.ascii.isAlphabetic(c)) {
                return false;
            }
        }
        return true;
    }

    pub fn capitalize(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        if (data.data.len == 0) {
            return try create(allocator, "");
        }

        const result = try allocator.alloc(u8, data.data.len);
        result[0] = std.ascii.toUpper(data.data[0]);

        for (data.data[1..], 0..) |c, i| {
            result[i + 1] = std.ascii.toLower(c);
        }

        return try create(allocator, result);
    }

    pub fn swapcase(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        const result = try allocator.alloc(u8, data.data.len);
        for (data.data, 0..) |c, i| {
            if (std.ascii.isUpper(c)) {
                result[i] = std.ascii.toLower(c);
            } else if (std.ascii.isLower(c)) {
                result[i] = std.ascii.toUpper(c);
            } else {
                result[i] = c;
            }
        }

        return try create(allocator, result);
    }

    pub fn title(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        const result = try allocator.alloc(u8, data.data.len);
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

        return try create(allocator, result);
    }

    pub fn center(allocator: std.mem.Allocator, obj: *PyObject, width: i64) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        const w: usize = @intCast(width);
        if (w <= data.data.len) {
            return try create(allocator, data.data);
        }

        const total_padding = w - data.data.len;
        const left_padding = total_padding / 2;
        const right_padding = total_padding - left_padding;
        _ = right_padding; // Calculated for clarity, actual padding is handled by slice

        const result = try allocator.alloc(u8, w);
        @memset(result[0..left_padding], ' ');
        @memcpy(result[left_padding..left_padding + data.data.len], data.data);
        @memset(result[left_padding + data.data.len..], ' ');

        return try create(allocator, result);
    }
};
