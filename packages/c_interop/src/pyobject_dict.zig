/// PyDictObject implementation - EXACT CPython 3.12 memory layout
///
/// Uses exact CPython PyDictObject struct layout for binary compatibility.
/// Internal storage uses simplified hash table implementation.
///
/// Reference: cpython/Include/cpython/dictobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// Re-export type from cpython_object.zig for exact CPython layout
pub const PyDictObject = cpython.PyDictObject;

// ============================================================================
// Internal Dict Keys/Values Implementation
// ============================================================================

/// Internal hash table entry
const DictEntry = struct {
    hash: isize,
    key: ?*cpython.PyObject,
    value: ?*cpython.PyObject,
};

/// Internal keys storage - implements PyDictKeysObject interface
/// Note: We cast this opaque pointer to our internal struct
const InternalDictKeys = struct {
    dk_refcnt: isize,
    dk_log2_size: u8, // log2 of size (e.g., 3 = 8 entries)
    dk_log2_index_bytes: u8,
    dk_kind: u8,
    dk_version: u32,
    dk_usable: isize,
    dk_nentries: isize,
    // Entries follow
    entries: [*]DictEntry,
};

/// Mapping protocol for dicts
var dict_as_mapping: cpython.PyMappingMethods = .{
    .mp_length = dict_length,
    .mp_subscript = dict_subscript,
    .mp_ass_subscript = dict_ass_subscript,
};

/// PyDict_Type - the 'dict' type
pub var PyDict_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "dict",
    .tp_basicsize = @sizeOf(PyDictObject),
    .tp_itemsize = 0,
    .tp_dealloc = dict_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_DICT_SUBCLASS,
    .tp_doc = "dict() -> new empty dictionary",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
    .tp_watched = 0,
    .tp_versions_used = 0,
};

// ============================================================================
// Core API Functions
// ============================================================================

/// Initial dict size (power of 2)
const DICT_MINSIZE: usize = 8;

/// Create internal keys structure
fn createKeys(log2_size: u8) ?*InternalDictKeys {
    const size: usize = @as(usize, 1) << @intCast(log2_size);

    // Allocate keys header + entries array
    const header_size = @sizeOf(InternalDictKeys);
    const entries_size = size * @sizeOf(DictEntry);
    const total_size = header_size + entries_size;

    const memory = allocator.alloc(u8, total_size) catch return null;
    const keys: *InternalDictKeys = @ptrCast(@alignCast(memory.ptr));

    keys.dk_refcnt = 1;
    keys.dk_log2_size = log2_size;
    keys.dk_log2_index_bytes = 0;
    keys.dk_kind = 0;
    keys.dk_version = 0;
    keys.dk_usable = @intCast(size * 2 / 3); // 2/3 load factor
    keys.dk_nentries = 0;

    // Point to entries array after header
    const entries_ptr = memory.ptr + header_size;
    keys.entries = @ptrCast(@alignCast(entries_ptr));

    // Initialize all entries to empty
    var i: usize = 0;
    while (i < size) : (i += 1) {
        keys.entries[i] = .{
            .hash = 0,
            .key = null,
            .value = null,
        };
    }

    return keys;
}

/// Free internal keys structure
fn freeKeys(keys: *InternalDictKeys) void {
    const log2_size = keys.dk_log2_size;
    const size: usize = @as(usize, 1) << @intCast(log2_size);

    // Decref all keys and values
    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (keys.entries[i].key) |key| {
            key.ob_refcnt -= 1;
        }
        if (keys.entries[i].value) |value| {
            value.ob_refcnt -= 1;
        }
    }

    const header_size = @sizeOf(InternalDictKeys);
    const entries_size = size * @sizeOf(DictEntry);
    const total_size = header_size + entries_size;

    const memory: [*]u8 = @ptrCast(@alignCast(keys));
    allocator.free(memory[0..total_size]);
}

/// Create new empty dictionary
export fn PyDict_New() callconv(.c) ?*cpython.PyObject {
    const dict = allocator.create(PyDictObject) catch return null;

    dict.ob_base.ob_refcnt = 1;
    dict.ob_base.ob_type = &PyDict_Type;
    dict.ma_used = 0;
    dict._ma_watcher_tag = 0;

    // Create initial keys structure
    const keys = createKeys(3); // 8 entries
    if (keys == null) {
        allocator.destroy(dict);
        return null;
    }

    // Cast our internal keys to opaque CPython type
    dict.ma_keys = @ptrCast(keys);
    dict.ma_values = null; // Combined table

    return @ptrCast(&dict.ob_base);
}

/// Get dictionary size
export fn PyDict_Size(obj: *cpython.PyObject) callconv(.c) isize {
    if (PyDict_Check(obj) == 0) return -1;

    const dict: *PyDictObject = @ptrCast(@alignCast(obj));
    return dict.ma_used;
}

/// Compute hash for key using its tp_hash
fn computeHash(key: *cpython.PyObject) isize {
    const type_obj = cpython.Py_TYPE(key);
    if (type_obj.tp_hash) |hash_func| {
        return hash_func(key);
    }
    // Fallback: identity hash (pointer address)
    return @intCast(@intFromPtr(key));
}

/// Find entry index for key
fn findEntry(keys: *InternalDictKeys, key: *cpython.PyObject, hash: isize) ?usize {
    const size: usize = @as(usize, 1) << @intCast(keys.dk_log2_size);
    const mask = size - 1;
    var idx = @as(usize, @intCast(@as(u64, @bitCast(@as(i64, hash))) & mask));

    var perturb: u64 = @bitCast(@as(i64, hash));

    while (true) {
        const entry = &keys.entries[idx];

        if (entry.key == null) {
            return null; // Empty slot - key not found
        }

        if (entry.hash == hash and entry.key == key) {
            return idx; // Found by identity
        }

        // TODO: Call PyObject_RichCompareBool for equality
        // For now just use identity comparison

        // Probe next slot
        perturb >>= 5;
        idx = (idx * 5 + 1 + perturb) & mask;
    }
}

/// Find empty slot for insertion
fn findEmptySlot(keys: *InternalDictKeys, hash: isize) usize {
    const size: usize = @as(usize, 1) << @intCast(keys.dk_log2_size);
    const mask = size - 1;
    var idx = @as(usize, @intCast(@as(u64, @bitCast(@as(i64, hash))) & mask));

    var perturb: u64 = @bitCast(@as(i64, hash));

    while (true) {
        if (keys.entries[idx].key == null) {
            return idx;
        }

        perturb >>= 5;
        idx = (idx * 5 + 1 + perturb) & mask;
    }
}

/// Get item by key (returns borrowed reference, no INCREF)
export fn PyDict_GetItem(obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyDict_Check(obj) == 0) return null;

    const dict: *PyDictObject = @ptrCast(@alignCast(obj));
    const keys: *InternalDictKeys = @ptrCast(@alignCast(dict.ma_keys));

    const hash = computeHash(key);

    if (findEntry(keys, key, hash)) |idx| {
        return keys.entries[idx].value;
    }

    return null;
}

/// Set item (incref key and value)
export fn PyDict_SetItem(obj: *cpython.PyObject, key: *cpython.PyObject, value: *cpython.PyObject) callconv(.c) c_int {
    if (PyDict_Check(obj) == 0) return -1;

    const dict: *PyDictObject = @ptrCast(@alignCast(obj));
    var keys: *InternalDictKeys = @ptrCast(@alignCast(dict.ma_keys));

    const hash = computeHash(key);

    // Check if key already exists
    if (findEntry(keys, key, hash)) |idx| {
        // Update existing entry
        if (keys.entries[idx].value) |old_value| {
            old_value.ob_refcnt -= 1;
        }
        value.ob_refcnt += 1;
        keys.entries[idx].value = value;
        return 0;
    }

    // Need to insert new entry
    // Check if we need to resize
    if (keys.dk_usable <= 0) {
        // TODO: Resize dict
        return -1;
    }

    const idx = findEmptySlot(keys, hash);

    key.ob_refcnt += 1;
    value.ob_refcnt += 1;

    keys.entries[idx] = .{
        .hash = hash,
        .key = key,
        .value = value,
    };

    keys.dk_usable -= 1;
    keys.dk_nentries += 1;
    dict.ma_used += 1;
    dict._ma_watcher_tag +%= 1;

    return 0;
}

/// Delete item by key
export fn PyDict_DelItem(obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    if (PyDict_Check(obj) == 0) return -1;

    const dict: *PyDictObject = @ptrCast(@alignCast(obj));
    const keys: *InternalDictKeys = @ptrCast(@alignCast(dict.ma_keys));

    const hash = computeHash(key);

    if (findEntry(keys, key, hash)) |idx| {
        // Found - delete entry
        if (keys.entries[idx].key) |k| {
            k.ob_refcnt -= 1;
        }
        if (keys.entries[idx].value) |v| {
            v.ob_refcnt -= 1;
        }

        // Mark as deleted (tombstone)
        // For simplicity, just null out - real CPython uses DKIX_DUMMY
        keys.entries[idx].key = null;
        keys.entries[idx].value = null;
        keys.entries[idx].hash = 0;

        dict.ma_used -= 1;
        dict._ma_watcher_tag +%= 1;

        return 0;
    }

    return -1; // Key not found
}

/// Clear all items
export fn PyDict_Clear(obj: *cpython.PyObject) callconv(.c) void {
    if (PyDict_Check(obj) == 0) return;

    const dict: *PyDictObject = @ptrCast(@alignCast(obj));
    const keys: *InternalDictKeys = @ptrCast(@alignCast(dict.ma_keys));

    const size: usize = @as(usize, 1) << @intCast(keys.dk_log2_size);

    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (keys.entries[i].key) |k| {
            k.ob_refcnt -= 1;
        }
        if (keys.entries[i].value) |v| {
            v.ob_refcnt -= 1;
        }
        keys.entries[i] = .{ .hash = 0, .key = null, .value = null };
    }

    keys.dk_usable = @intCast(size * 2 / 3);
    keys.dk_nentries = 0;
    dict.ma_used = 0;
    dict._ma_watcher_tag +%= 1;
}

/// Check if key exists
export fn PyDict_Contains(obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    if (PyDict_GetItem(obj, key) != null) return 1;
    return 0;
}

/// Get item with string key
export fn PyDict_GetItemString(obj: *cpython.PyObject, key_str: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    // TODO: Convert C string to PyUnicode, then lookup
    _ = obj;
    _ = key_str;
    return null;
}

/// Set item with string key
export fn PyDict_SetItemString(obj: *cpython.PyObject, key_str: [*:0]const u8, value: *cpython.PyObject) callconv(.c) c_int {
    // TODO: Convert C string to PyUnicode, then set
    _ = obj;
    _ = key_str;
    _ = value;
    return -1;
}

/// Delete item with string key
export fn PyDict_DelItemString(obj: *cpython.PyObject, key_str: [*:0]const u8) callconv(.c) c_int {
    // TODO: Convert C string to PyUnicode, then delete
    _ = obj;
    _ = key_str;
    return -1;
}

/// Get list of keys (returns new reference)
export fn PyDict_Keys(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyDict_Check(obj) == 0) return null;

    const dict: *PyDictObject = @ptrCast(@alignCast(obj));
    const keys: *InternalDictKeys = @ptrCast(@alignCast(dict.ma_keys));

    const list = @import("pyobject_list.zig").PyList_New(dict.ma_used);
    if (list == null) return null;

    const size: usize = @as(usize, 1) << @intCast(keys.dk_log2_size);
    var list_idx: isize = 0;

    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (keys.entries[i].key) |key| {
            key.ob_refcnt += 1;
            _ = @import("pyobject_list.zig").PyList_SetItem(list.?, list_idx, key);
            list_idx += 1;
        }
    }

    return list;
}

/// Get list of values (returns new reference)
export fn PyDict_Values(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyDict_Check(obj) == 0) return null;

    const dict: *PyDictObject = @ptrCast(@alignCast(obj));
    const keys: *InternalDictKeys = @ptrCast(@alignCast(dict.ma_keys));

    const list = @import("pyobject_list.zig").PyList_New(dict.ma_used);
    if (list == null) return null;

    const size: usize = @as(usize, 1) << @intCast(keys.dk_log2_size);
    var list_idx: isize = 0;

    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (keys.entries[i].value) |value| {
            value.ob_refcnt += 1;
            _ = @import("pyobject_list.zig").PyList_SetItem(list.?, list_idx, value);
            list_idx += 1;
        }
    }

    return list;
}

/// Get list of (key, value) tuples (returns new reference)
export fn PyDict_Items(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyDict_Check(obj) == 0) return null;

    const dict: *PyDictObject = @ptrCast(@alignCast(obj));
    const keys_struct: *InternalDictKeys = @ptrCast(@alignCast(dict.ma_keys));

    const list = @import("pyobject_list.zig").PyList_New(dict.ma_used);
    if (list == null) return null;

    const size: usize = @as(usize, 1) << @intCast(keys_struct.dk_log2_size);
    var list_idx: isize = 0;

    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (keys_struct.entries[i].key) |key| {
            const tuple = @import("pyobject_tuple.zig").PyTuple_New(2);
            if (tuple == null) return null;

            key.ob_refcnt += 1;
            _ = @import("pyobject_tuple.zig").PyTuple_SetItem(tuple.?, 0, key);

            if (keys_struct.entries[i].value) |value| {
                value.ob_refcnt += 1;
                _ = @import("pyobject_tuple.zig").PyTuple_SetItem(tuple.?, 1, value);
            }

            _ = @import("pyobject_list.zig").PyList_SetItem(list.?, list_idx, tuple.?);
            list_idx += 1;
        }
    }

    return list;
}

// ============================================================================
// Internal Functions
// ============================================================================

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
    const dict: *PyDictObject = @ptrCast(@alignCast(obj));

    if (dict.ma_keys) |keys_opaque| {
        const keys: *InternalDictKeys = @ptrCast(@alignCast(keys_opaque));
        freeKeys(keys);
    }

    allocator.destroy(dict);
}

// ============================================================================
// Type Checking
// ============================================================================

pub export fn PyDict_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const flags = cpython.Py_TYPE(obj).tp_flags;
    return if ((flags & cpython.Py_TPFLAGS_DICT_SUBCLASS) != 0) 1 else 0;
}

export fn PyDict_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyDict_Type) 1 else 0;
}

// ============================================================================
// Tests
// ============================================================================

test "PyDictObject layout matches CPython" {
    // PyDictObject: ob_base(16) + ma_used(8) + _ma_watcher_tag(8) + ma_keys(8) + ma_values(8) = 48 bytes
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(PyDictObject));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PyDictObject, "ob_base"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyDictObject, "ma_used"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyDictObject, "_ma_watcher_tag"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(PyDictObject, "ma_keys"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(PyDictObject, "ma_values"));
}

test "dict exports" {
    _ = PyDict_New;
    _ = PyDict_GetItem;
    _ = PyDict_SetItem;
    _ = PyDict_Check;
}
