/// PyDictObject implementation using comptime dict_impl
///
/// Pattern: Reuse generic hash table with PyObject-specific config
/// Benefits:
/// - Same optimizations as native dicts
/// - Less code (wrapper around dict_impl)
/// - Easier to maintain (fix once, works everywhere)

const std = @import("std");
const cpython = @import("cpython_object.zig");
const dict_impl = @import("collections");

const allocator = std.heap.c_allocator;

// ============================================================================
//                         PYOBJECT DICT CONFIG
// ============================================================================

/// Config for PyObject dictionaries (with refcounting)
const PyDictConfig = struct {
    pub const KeyType = *cpython.PyObject;
    pub const ValueType = *cpython.PyObject;

    pub fn hashKey(key: *cpython.PyObject) u64 {
        // Call PyObject's tp_hash if available
        const type_obj = cpython.Py_TYPE(key);
        if (type_obj.tp_hash) |hash_func| {
            const hash = hash_func(key);
            // Convert isize hash to u64
            return @as(u64, @bitCast(@as(i64, hash)));
        }

        // Fallback: identity hash (pointer address)
        return @intFromPtr(key);
    }

    pub fn keysEqual(a: *cpython.PyObject, b: *cpython.PyObject) bool {
        // For now: pointer equality
        // TODO: Use PyObject_RichCompareBool for proper equality
        return a == b;
    }

    pub fn retainKey(key: *cpython.PyObject) *cpython.PyObject {
        key.ob_refcnt += 1; // Py_INCREF
        return key;
    }

    pub fn releaseKey(key: *cpython.PyObject) void {
        key.ob_refcnt -= 1; // Py_DECREF
        // TODO: Call dealloc if refcnt == 0
    }

    pub fn retainValue(val: *cpython.PyObject) *cpython.PyObject {
        val.ob_refcnt += 1; // Py_INCREF
        return val;
    }

    pub fn releaseValue(val: *cpython.PyObject) void {
        val.ob_refcnt -= 1; // Py_DECREF
        // TODO: Call dealloc if refcnt == 0
    }
};

/// Comptime-specialized dict for PyObjects
const DictCore = dict_impl.DictImpl(PyDictConfig);

// ============================================================================
//                         PYDICT OBJECT
// ============================================================================

/// PyDictObject - wraps generic dict implementation
pub const PyDictObject = extern struct {
    ob_base: cpython.PyVarObject,

    // Internal implementation (heap-allocated)
    impl: *DictCore,

    // CPython compatibility fields
    ma_version_tag: u64,
};

// ============================================================================
//                         C API FUNCTIONS
// ============================================================================

/// Create new empty dictionary
export fn PyDict_New() callconv(.c) ?*cpython.PyObject {
    const dict = allocator.create(PyDictObject) catch return null;

    dict.ob_base = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyDict_Type,
        },
        .ob_size = 0,
    };
    dict.ma_version_tag = 0;

    // Create dict implementation
    const impl = allocator.create(DictCore) catch {
        allocator.destroy(dict);
        return null;
    };

    impl.* = DictCore.init(allocator) catch {
        allocator.destroy(impl);
        allocator.destroy(dict);
        return null;
    };

    dict.impl = impl;

    return @ptrCast(&dict.ob_base.ob_base);
}

/// Get item by key (returns borrowed reference, no INCREF)
export fn PyDict_GetItem(dict_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const dict = @as(*PyDictObject, @ptrCast(dict_obj));

    // Use generic dict implementation!
    return dict.impl.get(key);
}

/// Set item (steals references to key and value)
export fn PyDict_SetItem(dict_obj: *cpython.PyObject, key: *cpython.PyObject, value: *cpython.PyObject) callconv(.c) c_int {
    const dict = @as(*PyDictObject, @ptrCast(dict_obj));

    // Use generic dict implementation!
    dict.impl.set(key, value) catch return -1;

    // Update ob_size
    dict.ob_base.ob_size = @intCast(dict.impl.size);

    // Update version tag (for dict watchers)
    dict.ma_version_tag +%= 1;

    return 0;
}

/// Delete item by key
export fn PyDict_DelItem(dict_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    const dict = @as(*PyDictObject, @ptrCast(dict_obj));

    // Use generic dict implementation!
    const deleted = dict.impl.delete(key);

    if (deleted) {
        // Update ob_size
        dict.ob_base.ob_size = @intCast(dict.impl.size);

        // Update version tag
        dict.ma_version_tag +%= 1;

        return 0;
    }

    return -1; // Key not found
}

/// Get dictionary size
export fn PyDict_Size(dict_obj: *cpython.PyObject) callconv(.c) isize {
    const dict = @as(*PyDictObject, @ptrCast(dict_obj));
    return @intCast(dict.impl.size);
}

/// Clear all items
export fn PyDict_Clear(dict_obj: *cpython.PyObject) callconv(.c) void {
    const dict = @as(*PyDictObject, @ptrCast(dict_obj));

    // Use generic dict implementation!
    dict.impl.clear();

    // Update ob_size
    dict.ob_base.ob_size = 0;

    // Update version tag
    dict.ma_version_tag +%= 1;
}

/// Check if key exists
export fn PyDict_Contains(dict_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    const dict = @as(*PyDictObject, @ptrCast(dict_obj));

    // Use generic dict implementation!
    return if (dict.impl.contains(key)) 1 else 0;
}

/// Get item with default (returns new reference)
export fn PyDict_GetItemString(dict_obj: *cpython.PyObject, key_str: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    // TODO: Convert C string to PyUnicode, then lookup
    // For now: not implemented
    _ = dict_obj;
    _ = key_str;
    return null;
}

/// Set item with string key
export fn PyDict_SetItemString(dict_obj: *cpython.PyObject, key_str: [*:0]const u8, value: *cpython.PyObject) callconv(.c) c_int {
    // TODO: Convert C string to PyUnicode, then set
    // For now: not implemented
    _ = dict_obj;
    _ = key_str;
    _ = value;
    return -1;
}

/// Delete item with string key
export fn PyDict_DelItemString(dict_obj: *cpython.PyObject, key_str: [*:0]const u8) callconv(.c) c_int {
    // TODO: Convert C string to PyUnicode, then delete
    // For now: not implemented
    _ = dict_obj;
    _ = key_str;
    return -1;
}

/// Get list of keys (returns new reference)
export fn PyDict_Keys(dict_obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const dict = @as(*PyDictObject, @ptrCast(dict_obj));

    // Create new list
    const list = @import("pyobject_list.zig").PyList_New(@intCast(dict.impl.size));
    if (list == null) return null;

    // Add all keys using iterator
    var iter = dict.impl.iterator();
    var idx: isize = 0;
    while (iter.next()) |entry| {
        _ = @import("pyobject_list.zig").PyList_SetItem(list.?, idx, entry.key);
        idx += 1;
    }

    return list;
}

/// Get list of values (returns new reference)
export fn PyDict_Values(dict_obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const dict = @as(*PyDictObject, @ptrCast(dict_obj));

    // Create new list
    const list = @import("pyobject_list.zig").PyList_New(@intCast(dict.impl.size));
    if (list == null) return null;

    // Add all values using iterator
    var iter = dict.impl.iterator();
    var idx: isize = 0;
    while (iter.next()) |entry| {
        _ = @import("pyobject_list.zig").PyList_SetItem(list.?, idx, entry.value);
        idx += 1;
    }

    return list;
}

/// Get list of (key, value) tuples (returns new reference)
export fn PyDict_Items(dict_obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const dict = @as(*PyDictObject, @ptrCast(dict_obj));

    // Create new list
    const list = @import("pyobject_list.zig").PyList_New(@intCast(dict.impl.size));
    if (list == null) return null;

    // Add all (key, value) tuples using iterator
    var iter = dict.impl.iterator();
    var idx: isize = 0;
    while (iter.next()) |entry| {
        const tuple = @import("pyobject_tuple.zig").PyTuple_New(2);
        if (tuple == null) return null;

        _ = @import("pyobject_tuple.zig").PyTuple_SetItem(tuple.?, 0, entry.key);
        _ = @import("pyobject_tuple.zig").PyTuple_SetItem(tuple.?, 1, entry.value);

        _ = @import("pyobject_list.zig").PyList_SetItem(list.?, idx, tuple.?);
        idx += 1;
    }

    return list;
}

// ============================================================================
//                         TYPE OBJECT
// ============================================================================

/// PyDict type object
pub var PyDict_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = null },
        .ob_size = 0,
    },
    .tp_name = "dict",
    .tp_basicsize = @sizeOf(PyDictObject),
    .tp_itemsize = 0,
    .tp_dealloc = dict_dealloc,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = &dict_as_mapping,
    .tp_hash = null, // Dicts are not hashable
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = 0,
    .tp_doc = null,
};

/// Mapping protocol for dicts
var dict_as_mapping: cpython.PyMappingMethods = .{
    .mp_length = dict_length,
    .mp_subscript = dict_subscript,
    .mp_ass_subscript = dict_ass_subscript,
};

fn dict_length(obj: *cpython.PyObject) callconv(.c) isize {
    return PyDict_Size(obj);
}

fn dict_subscript(obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const result = PyDict_GetItem(obj, key);
    if (result) |r| {
        r.ob_refcnt += 1; // Return new reference
        return r;
    }
    return null;
}

fn dict_ass_subscript(obj: *cpython.PyObject, key: *cpython.PyObject, value: ?*cpython.PyObject) callconv(.c) c_int {
    if (value) |v| {
        return PyDict_SetItem(obj, key, v);
    } else {
        return PyDict_DelItem(obj, key);
    }
}

fn dict_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const dict = @as(*PyDictObject, @ptrCast(obj));

    // Free dict implementation
    dict.impl.deinit();
    allocator.destroy(dict.impl);

    // Free dict object
    allocator.destroy(dict);
}

// ============================================================================
//                         TYPE CHECKING
// ============================================================================

export fn PyDict_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyDict_Type) 1 else 0;
}

export fn PyDict_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyDict_Type) 1 else 0;
}
