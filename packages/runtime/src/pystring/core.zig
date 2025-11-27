/// Core PyString operations - creation, access, concatenation
/// Supports Copy-on-Write (COW) for zero-copy slicing and sharing
const std = @import("std");
const runtime = @import("../runtime.zig");
const PyObject = runtime.PyObject;
const PythonError = runtime.PythonError;

/// Python string type with COW support
/// - owned: we allocated data, must free it
/// - borrowed: slice into another PyString, source keeps ref
pub const PyString = struct {
    data: []const u8,
    source: ?*PyObject = null, // If non-null, we borrowed from this (COW)

    pub fn create(allocator: std.mem.Allocator, str: []const u8) !*PyObject {
        const obj = try allocator.create(PyObject);
        const str_data = try allocator.create(PyString);
        const owned = try allocator.dupe(u8, str);
        str_data.* = .{ .data = owned, .source = null };

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .string,
            .data = str_data,
        };
        return obj;
    }

    /// Check if this string is borrowed (COW) or owned
    pub fn isBorrowed(obj: *PyObject) bool {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        return data.source != null;
    }

    /// Free PyString resources (handles COW)
    pub fn deinit(obj: *PyObject, allocator: std.mem.Allocator) void {
        std.debug.assert(obj.type_id == .string);
        const str_data: *PyString = @ptrCast(@alignCast(obj.data));

        if (str_data.source) |source| {
            // Borrowed - just decref source, don't free data
            runtime.decref(source, allocator);
        } else {
            // Owned - free data
            allocator.free(@constCast(str_data.data));
        }
        allocator.destroy(str_data);
        allocator.destroy(obj);
    }

    /// Create PyString with owned data (takes ownership, no duplication)
    /// IMPORTANT: Caller must ensure owned_str is allocated with this allocator
    pub fn createOwned(allocator: std.mem.Allocator, owned_str: []const u8) !*PyObject {
        const obj = try allocator.create(PyObject);
        const str_data = try allocator.create(PyString);
        str_data.* = .{ .data = owned_str, .source = null };

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .string,
            .data = str_data,
        };
        return obj;
    }

    /// Create PyString borrowing from another PyString (COW - zero copy!)
    /// The source PyString is kept alive via reference counting
    pub fn createBorrowed(allocator: std.mem.Allocator, source_obj: *PyObject, slice: []const u8) !*PyObject {
        std.debug.assert(source_obj.type_id == .string);

        const obj = try allocator.create(PyObject);
        const str_data = try allocator.create(PyString);

        // Keep source alive
        runtime.incref(source_obj);
        str_data.* = .{ .data = slice, .source = source_obj };

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

    pub fn getItem(allocator: std.mem.Allocator, obj: *PyObject, index: i64) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        const idx: usize = @intCast(index);
        if (idx >= data.data.len) {
            return PythonError.IndexError;
        }

        // Return single character as a new string
        const result = try allocator.alloc(u8, 1);
        defer allocator.free(result); // Free temporary buffer
        result[0] = data.data[idx];

        return create(allocator, result);
    }

    pub fn charAt(allocator: std.mem.Allocator, obj: *PyObject, index_val: i64) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const str_len: i64 = @intCast(data.data.len);

        // Handle negative indices
        const idx = if (index_val < 0) str_len + index_val else index_val;

        if (idx < 0 or idx >= str_len) {
            return PythonError.IndexError;
        }

        // Return single character as a new string
        const result = try allocator.alloc(u8, 1);
        defer allocator.free(result); // Free temporary buffer
        result[0] = data.data[@intCast(idx)];

        return create(allocator, result);
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

    /// Optimized concatenation for multiple strings - single allocation
    pub fn concatMulti(allocator: std.mem.Allocator, strings: []const *PyObject) !*PyObject {
        if (strings.len == 0) {
            return try create(allocator, "");
        }
        if (strings.len == 1) {
            runtime.incref(strings[0]);
            return strings[0];
        }

        // Calculate total length
        var total_len: usize = 0;
        for (strings) |str| {
            std.debug.assert(str.type_id == .string);
            const str_data: *PyString = @ptrCast(@alignCast(str.data));
            total_len += str_data.data.len;
        }

        // Allocate result buffer once
        const result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;

        // Copy all strings
        for (strings) |str| {
            const str_data: *PyString = @ptrCast(@alignCast(str.data));
            @memcpy(result[pos .. pos + str_data.data.len], str_data.data);
            pos += str_data.data.len;
        }

        // Create PyObject
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

    pub fn toInt(obj: *PyObject) !i64 {
        const str_val = getValue(obj);
        return std.fmt.parseInt(i64, str_val, 10);
    }
};
