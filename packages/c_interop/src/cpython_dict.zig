/// CPython Dictionary Operations
///
/// Implements PyDict_* functions with binary-compatible layout
/// Uses simplified hash table for now (can optimize later)

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

/// Simple hash table entry
const DictEntry = struct {
    key: ?*cpython.PyObject,
    value: ?*cpython.PyObject,
    hash: isize,
};

/// Internal dict implementation (simplified)
const DictImpl = struct {
    entries: []DictEntry,
    size: usize,
    capacity: usize,
    allocator: std.mem.Allocator,
};

/// Create new empty dictionary
export fn PyDict_New() callconv(.c) ?*cpython.PyObject {
    const dict = allocator.create(cpython.PyDictObject) catch return null;

    dict.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = undefined,
    };
    dict.ma_used = 0;
    dict.ma_version_tag = 0;

    const impl = allocator.create(DictImpl) catch {
        allocator.destroy(dict);
        return null;
    };

    const initial_capacity = 8;
    impl.entries = allocator.alloc(DictEntry, initial_capacity) catch {
        allocator.destroy(impl);
        allocator.destroy(dict);
        return null;
    };

    for (impl.entries) |*entry| {
        entry.* = .{ .key = null, .value = null, .hash = 0 };
    }

    impl.size = 0;
    impl.capacity = initial_capacity;
    impl.allocator = allocator;

    dict.ma_keys = impl;
    dict.ma_values = null;

    return @ptrCast(&dict.ob_base);
}

export fn PyDict_Size(dict_obj: *cpython.PyObject) callconv(.c) isize {
    const dict = @as(*cpython.PyDictObject, @ptrCast(dict_obj));
    return dict.ma_used;
}

fn hashObject(obj: *cpython.PyObject) isize {
    return @intCast(@intFromPtr(obj));
}

export fn PyDict_GetItem(dict_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const dict = @as(*cpython.PyDictObject, @ptrCast(dict_obj));
    const impl = @as(*DictImpl, @ptrCast(@alignCast(dict.ma_keys)));

    const hash = hashObject(key);
    const idx = @as(usize, @intCast(@mod(hash, @as(isize, @intCast(impl.capacity)))));

    var i = idx;
    while (i < impl.capacity) : (i += 1) {
        const entry = &impl.entries[i];
        if (entry.key == null) break;
        if (entry.hash == hash and entry.key == key) {
            return entry.value;
        }
    }

    return null;
}

export fn PyDict_SetItem(dict_obj: *cpython.PyObject, key: *cpython.PyObject, value: *cpython.PyObject) callconv(.c) c_int {
    const dict = @as(*cpython.PyDictObject, @ptrCast(dict_obj));
    const impl = @as(*DictImpl, @ptrCast(@alignCast(dict.ma_keys)));

    if (impl.size >= impl.capacity * 3 / 4) return -1;

    const hash = hashObject(key);
    const idx = @as(usize, @intCast(@mod(hash, @as(isize, @intCast(impl.capacity)))));

    var i = idx;
    while (i < impl.capacity) : (i += 1) {
        const entry = &impl.entries[i];

        if (entry.key == null) {
            entry.key = key;
            entry.value = value;
            entry.hash = hash;
            impl.size += 1;
            dict.ma_used += 1;
            Py_INCREF(key);
            Py_INCREF(value);
            return 0;
        }

        if (entry.hash == hash and entry.key == key) {
            const old_value = entry.value;
            entry.value = value;
            Py_INCREF(value);
            if (old_value) |old| Py_DECREF(old);
            return 0;
        }
    }

    return -1;
}

export fn PyDict_DelItem(dict_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    const dict = @as(*cpython.PyDictObject, @ptrCast(dict_obj));
    const impl = @as(*DictImpl, @ptrCast(@alignCast(dict.ma_keys)));

    const hash = hashObject(key);
    const idx = @as(usize, @intCast(@mod(hash, @as(isize, @intCast(impl.capacity)))));

    var i = idx;
    while (i < impl.capacity) : (i += 1) {
        const entry = &impl.entries[i];
        if (entry.key == null) break;

        if (entry.hash == hash and entry.key == key) {
            if (entry.key) |k| Py_DECREF(k);
            if (entry.value) |v| Py_DECREF(v);
            entry.* = .{ .key = null, .value = null, .hash = 0 };
            impl.size -= 1;
            dict.ma_used -= 1;
            return 0;
        }
    }

    return -1;
}

export fn PyDict_Clear(dict_obj: *cpython.PyObject) callconv(.c) void {
    const dict = @as(*cpython.PyDictObject, @ptrCast(dict_obj));
    const impl = @as(*DictImpl, @ptrCast(@alignCast(dict.ma_keys)));

    for (impl.entries) |*entry| {
        if (entry.key) |k| Py_DECREF(k);
        if (entry.value) |v| Py_DECREF(v);
        entry.* = .{ .key = null, .value = null, .hash = 0 };
    }

    impl.size = 0;
    dict.ma_used = 0;
}

export fn PyDict_Contains(dict_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    return if (PyDict_GetItem(dict_obj, key) != null) 1 else 0;
}

export fn PyDict_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    return 1;
}

/// Get item by string key (convenience function)
export fn PyDict_GetItemString(dict_obj: *cpython.PyObject, key: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const key_obj = PyUnicode_FromString(key);
    if (key_obj == null) return null;

    const result = PyDict_GetItem(dict_obj, key_obj.?);
    Py_DECREF(key_obj.?);

    return result;
}

/// Set item by string key (convenience function)
export fn PyDict_SetItemString(dict_obj: *cpython.PyObject, key: [*:0]const u8, value: *cpython.PyObject) callconv(.c) c_int {
    const key_obj = PyUnicode_FromString(key);
    if (key_obj == null) return -1;

    const result = PyDict_SetItem(dict_obj, key_obj.?, value);
    Py_DECREF(key_obj.?);

    return result;
}

extern fn PyUnicode_FromString([*:0]const u8) callconv(.c) ?*cpython.PyObject;
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;

test "PyDict basics" {
    const dict = PyDict_New();
    try std.testing.expect(dict != null);
    try std.testing.expectEqual(@as(isize, 0), PyDict_Size(dict.?));
}
