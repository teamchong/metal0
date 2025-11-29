/// Python dict type implementation (CPython ABI compatible)
const std = @import("std");
const runtime = @import("runtime.zig");
const hashmap_helper = @import("hashmap_helper");

// Re-export CPython-compatible types
pub const PyObject = runtime.PyObject;
pub const PyDictObject = runtime.PyDictObject;
pub const PyDict_Type = &runtime.PyDict_Type;

/// Python dict type - wrapper around CPython-compatible PyDictObject
pub const PyDict = struct {
    // Legacy field for backwards compatibility
    map: hashmap_helper.StringHashMap(*PyObject) = undefined,

    pub fn create(allocator: std.mem.Allocator) !*PyObject {
        const dict_obj = try allocator.create(PyDictObject);

        // Create internal hashmap
        const map = try allocator.create(hashmap_helper.StringHashMap(*PyObject));
        map.* = hashmap_helper.StringHashMap(*PyObject).init(allocator);

        dict_obj.* = PyDictObject{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = PyDict_Type,
            },
            .ma_used = 0,
            .ma_keys = map,
            .ma_values = null,
        };
        return @ptrCast(dict_obj);
    }

    pub fn set(obj: *PyObject, key: []const u8, value: *PyObject) !void {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

        // Duplicate the key since dict needs to own it
        const owned_key = try map.allocator.dupe(u8, key);

        // Check if key already exists (to maintain correct count)
        const existed = map.contains(key);

        try map.put(owned_key, value);

        if (!existed) {
            dict_obj.ma_used += 1;
        }

        runtime.incref(value);
    }

    /// Set key-value pair with owned key (takes ownership, no duplication)
    pub fn setOwned(obj: *PyObject, owned_key: []const u8, value: *PyObject) !void {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

        const existed = map.contains(owned_key);
        try map.put(owned_key, value);

        if (!existed) {
            dict_obj.ma_used += 1;
        }

        runtime.incref(value);
    }

    pub fn get(obj: *PyObject, key: []const u8) ?*PyObject {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

        if (map.get(key)) |value| {
            runtime.incref(value);
            return value;
        }
        return null;
    }

    pub fn contains(obj: *PyObject, key: []const u8) bool {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));
        return map.contains(key);
    }

    pub fn len(obj: *PyObject) usize {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));
        return @intCast(dict_obj.ma_used);
    }

    pub fn keys(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

        // Create list to hold keys
        const result = try runtime.PyList.create(allocator);

        var iterator = map.keyIterator();
        while (iterator.next()) |key| {
            const key_obj = try runtime.PyString.create(allocator, key.*);
            try runtime.PyList.append(result, key_obj);
        }

        return result;
    }

    pub fn values(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

        // Create list to hold values
        const result = try runtime.PyList.create(allocator);

        var iterator = map.valueIterator();
        while (iterator.next()) |value| {
            runtime.incref(value.*);
            try runtime.PyList.append(result, value.*);
        }

        return result;
    }

    pub fn getWithDefault(allocator: std.mem.Allocator, obj: *PyObject, key: []const u8, default: *PyObject) *PyObject {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));
        _ = allocator;

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

        if (map.get(key)) |found| {
            runtime.incref(found);
            return found;
        } else {
            runtime.incref(default);
            return default;
        }
    }

    pub fn get_method(allocator: std.mem.Allocator, obj: *PyObject, key: *PyObject, default: *PyObject) *PyObject {
        std.debug.assert(runtime.PyDict_Check(obj));
        std.debug.assert(runtime.PyUnicode_Check(key));

        const str_obj: *runtime.PyUnicodeObject = @ptrCast(@alignCast(key));
        const key_len: usize = @intCast(str_obj.length);
        const key_str = str_obj.data[0..key_len];

        return getWithDefault(allocator, obj, key_str, default);
    }

    pub fn pop(allocator: std.mem.Allocator, obj: *PyObject, key: []const u8) ?*PyObject {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

        if (map.fetchRemove(key)) |entry| {
            allocator.free(entry.key);
            dict_obj.ma_used -= 1;
            return entry.value;
        }
        return null;
    }

    pub fn pop_method(allocator: std.mem.Allocator, obj: *PyObject, key: *PyObject) ?*PyObject {
        std.debug.assert(runtime.PyDict_Check(obj));
        std.debug.assert(runtime.PyUnicode_Check(key));

        const str_obj: *runtime.PyUnicodeObject = @ptrCast(@alignCast(key));
        const key_len: usize = @intCast(str_obj.length);
        const key_str = str_obj.data[0..key_len];

        return pop(allocator, obj, key_str);
    }

    pub fn clear(allocator: std.mem.Allocator, obj: *PyObject) void {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

        var iterator = map.iterator();
        while (iterator.next()) |entry| {
            map.allocator.free(entry.key_ptr.*);
            runtime.decref(entry.value_ptr.*, allocator);
        }

        map.clearRetainingCapacity();
        dict_obj.ma_used = 0;
    }

    pub fn items(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

        // Create list to hold items
        const result = try runtime.PyList.create(allocator);

        var iterator = map.iterator();
        while (iterator.next()) |entry| {
            const pair = try runtime.PyTuple.create(allocator, 2);
            const key_obj = try runtime.PyString.create(allocator, entry.key_ptr.*);
            runtime.PyTuple.setItem(pair, 0, key_obj);
            runtime.incref(entry.value_ptr.*);
            runtime.PyTuple.setItem(pair, 1, entry.value_ptr.*);
            try runtime.PyList.append(result, pair);
        }

        return result;
    }

    pub fn update(obj: *PyObject, other: *PyObject) !void {
        std.debug.assert(runtime.PyDict_Check(obj));
        std.debug.assert(runtime.PyDict_Check(other));

        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));
        const other_dict: *PyDictObject = @ptrCast(@alignCast(other));

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));
        const other_map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(other_dict.ma_keys.?));

        var iterator = other_map.iterator();
        while (iterator.next()) |entry| {
            const owned_key = try map.allocator.dupe(u8, entry.key_ptr.*);
            const existed = map.contains(entry.key_ptr.*);
            try map.put(owned_key, entry.value_ptr.*);
            runtime.incref(entry.value_ptr.*);
            if (!existed) {
                dict_obj.ma_used += 1;
            }
        }
    }

    pub fn copy(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(runtime.PyDict_Check(obj));
        const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

        const new_dict = try create(allocator);
        const new_dict_obj: *PyDictObject = @ptrCast(@alignCast(new_dict));
        const new_map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(new_dict_obj.ma_keys.?));

        var iterator = map.iterator();
        while (iterator.next()) |entry| {
            const owned_key = try new_map.allocator.dupe(u8, entry.key_ptr.*);
            try new_map.put(owned_key, entry.value_ptr.*);
            runtime.incref(entry.value_ptr.*);
            new_dict_obj.ma_used += 1;
        }

        return new_dict;
    }
};

// CPython-compatible C API functions
pub fn PyDict_New() callconv(.C) *PyObject {
    const allocator = std.heap.page_allocator;
    return PyDict.create(allocator) catch @panic("PyDict_New allocation failed");
}

pub fn PyDict_Size(obj: *PyObject) callconv(.C) runtime.Py_ssize_t {
    const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));
    return dict_obj.ma_used;
}

pub fn PyDict_GetItem(obj: *PyObject, key: *PyObject) callconv(.C) ?*PyObject {
    if (!runtime.PyUnicode_Check(key)) return null;

    const str_obj: *runtime.PyUnicodeObject = @ptrCast(@alignCast(key));
    const key_len: usize = @intCast(str_obj.length);
    const key_str = str_obj.data[0..key_len];

    const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));
    const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(dict_obj.ma_keys.?));

    return map.get(key_str);
}

pub fn PyDict_SetItem(obj: *PyObject, key: *PyObject, value: *PyObject) callconv(.C) c_int {
    if (!runtime.PyUnicode_Check(key)) return -1;

    const str_obj: *runtime.PyUnicodeObject = @ptrCast(@alignCast(key));
    const key_len: usize = @intCast(str_obj.length);
    const key_str = str_obj.data[0..key_len];

    PyDict.set(obj, key_str, value) catch return -1;
    return 0;
}
