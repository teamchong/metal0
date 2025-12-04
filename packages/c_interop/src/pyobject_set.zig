/// PySet and PyFrozenSet - EXACT CPython 3.12 memory layout
///
/// Uses exact CPython PySetObject struct for binary compatibility.
///
/// Reference: cpython/Include/cpython/setobject.h

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// Re-export types from cpython_object.zig for exact CPython layout
pub const PySetObject = cpython.PySetObject;
pub const setentry = cpython.setentry;
pub const PySet_MINSIZE = cpython.PySet_MINSIZE;

// ============================================================================
// Type Objects
// ============================================================================

pub var PySet_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "set",
    .tp_basicsize = @sizeOf(PySetObject),
    .tp_itemsize = 0,
    .tp_dealloc = set_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null, // Sets are not hashable
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "set() -> new empty set object",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PySetObject, "weakreflist"),
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

pub var PyFrozenSet_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "frozenset",
    .tp_basicsize = @sizeOf(PySetObject),
    .tp_itemsize = 0,
    .tp_dealloc = set_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = frozenset_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "frozenset() -> empty frozenset object",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PySetObject, "weakreflist"),
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

/// Compute hash for a key
fn computeHash(key: *cpython.PyObject) isize {
    const type_obj = cpython.Py_TYPE(key);
    if (type_obj.tp_hash) |hash_fn| {
        return hash_fn(key);
    }
    return @intCast(@intFromPtr(key));
}

/// Find entry in set
fn lookupEntry(set: *PySetObject, key: *cpython.PyObject, hash: isize) ?*setentry {
    const mask: usize = @intCast(set.mask);
    var idx = @as(usize, @intCast(@as(u64, @bitCast(@as(i64, hash))) & mask));
    var perturb: u64 = @bitCast(@as(i64, hash));
    const table: [*]setentry = @ptrCast(set.table.?);

    while (true) {
        const entry = &table[idx];

        if (entry.key == null) {
            return null; // Empty slot - not found
        }

        if (entry.hash == hash and entry.key == key) {
            return entry; // Found
        }

        // Probe next slot
        perturb >>= 5;
        idx = (idx * 5 + 1 + perturb) & mask;
    }
}

/// Find empty slot for insertion
fn findEmptySlot(set: *PySetObject, hash: isize) *setentry {
    const mask: usize = @intCast(set.mask);
    var idx = @as(usize, @intCast(@as(u64, @bitCast(@as(i64, hash))) & mask));
    var perturb: u64 = @bitCast(@as(i64, hash));
    const table: [*]setentry = @ptrCast(set.table.?);

    while (true) {
        const entry = &table[idx];

        if (entry.key == null) {
            return entry;
        }

        perturb >>= 5;
        idx = (idx * 5 + 1 + perturb) & mask;
    }
}

/// Create new set with given type
fn createSet(type_obj: *cpython.PyTypeObject) ?*cpython.PyObject {
    const set = allocator.create(PySetObject) catch return null;

    set.ob_base.ob_refcnt = 1;
    set.ob_base.ob_type = type_obj;
    set.fill = 0;
    set.used = 0;
    set.mask = PySet_MINSIZE - 1;
    set.table = @ptrCast(&set.smalltable);
    set.hash = -1; // Not computed yet (for frozenset)
    set.finger = 0;
    set.weakreflist = null;

    // Initialize smalltable
    for (&set.smalltable) |*entry| {
        entry.key = null;
        entry.hash = 0;
    }

    return @ptrCast(&set.ob_base);
}

/// Create new PySet
pub export fn PySet_New(iterable: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const set = createSet(&PySet_Type);
    if (set == null) return null;

    // Add items from iterable if provided
    if (iterable) |it| {
        if (addFromIterable(set.?, it) < 0) {
            set_dealloc(set.?);
            return null;
        }
    }

    return set;
}

/// Create new PyFrozenSet
pub export fn PyFrozenSet_New(iterable: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const set = createSet(&PyFrozenSet_Type);
    if (set == null) return null;

    // Add items from iterable if provided
    if (iterable) |it| {
        // Temporarily allow mutations during construction
        const set_obj: *PySetObject = @ptrCast(@alignCast(set.?));
        _ = set_obj;
        if (addFromIterableInternal(set.?, it) < 0) {
            set_dealloc(set.?);
            return null;
        }
    }

    return set;
}

/// Get set size
pub export fn PySet_Size(obj: *cpython.PyObject) callconv(.c) isize {
    const set: *PySetObject = @ptrCast(@alignCast(obj));
    return set.used;
}

/// Get set size (macro version)
export fn PySet_GET_SIZE(obj: *cpython.PyObject) callconv(.c) isize {
    return PySet_Size(obj);
}

/// Check if set contains element
pub export fn PySet_Contains(obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    const set: *PySetObject = @ptrCast(@alignCast(obj));
    const hash = computeHash(key);

    if (lookupEntry(set, key, hash) != null) {
        return 1;
    }
    return 0;
}

/// Add element to set
pub export fn PySet_Add(obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    if (cpython.Py_TYPE(obj) == &PyFrozenSet_Type) {
        return -1; // frozenset is immutable
    }

    const set: *PySetObject = @ptrCast(@alignCast(obj));
    const hash = computeHash(key);

    // Check if already exists
    if (lookupEntry(set, key, hash) != null) {
        return 0; // Already in set
    }

    // Check if we need to resize (when fill > 2/3 of capacity)
    const capacity: isize = set.mask + 1;
    if (set.fill * 3 >= capacity * 2) {
        // Resize to double the size (minus one for mask)
        if (set_resize(set, capacity * 2) < 0) {
            return -1;
        }
    }

    // Find empty slot and insert
    const entry = findEmptySlot(set, hash);
    key.ob_refcnt += 1;
    entry.key = key;
    entry.hash = hash;
    set.fill += 1;
    set.used += 1;

    return 0;
}

/// Discard element from set (no error if not found)
pub export fn PySet_Discard(obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    if (cpython.Py_TYPE(obj) == &PyFrozenSet_Type) {
        return -1; // frozenset is immutable
    }

    const set: *PySetObject = @ptrCast(@alignCast(obj));
    const hash = computeHash(key);

    if (lookupEntry(set, key, hash)) |entry| {
        if (entry.key) |k| {
            k.ob_refcnt -= 1;
        }
        entry.key = null; // Mark as deleted (dummy)
        entry.hash = 0;
        set.used -= 1;
        return 1; // Found and removed
    }

    return 0; // Not found
}

/// Pop arbitrary element from set
pub export fn PySet_Pop(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (cpython.Py_TYPE(obj) == &PyFrozenSet_Type) {
        return null; // frozenset is immutable
    }

    const set: *PySetObject = @ptrCast(@alignCast(obj));

    if (set.used == 0) return null;

    // Find first non-empty entry using finger
    const mask: usize = @intCast(set.mask);
    var idx: usize = @intCast(set.finger);
    const table: [*]setentry = @ptrCast(set.table.?);

    while (idx <= mask) : (idx += 1) {
        const entry = &table[idx];
        if (entry.key != null) {
            const key = entry.key;
            entry.key = null;
            entry.hash = 0;
            set.used -= 1;
            set.finger = @intCast(idx);
            return key;
        }
    }

    // Wrap around
    idx = 0;
    while (idx < @as(usize, @intCast(set.finger))) : (idx += 1) {
        const entry = &table[idx];
        if (entry.key != null) {
            const key = entry.key;
            entry.key = null;
            entry.hash = 0;
            set.used -= 1;
            set.finger = @intCast(idx);
            return key;
        }
    }

    return null;
}

/// Clear all elements
pub export fn PySet_Clear(obj: *cpython.PyObject) callconv(.c) c_int {
    if (cpython.Py_TYPE(obj) == &PyFrozenSet_Type) {
        return -1; // frozenset is immutable
    }

    const set: *PySetObject = @ptrCast(@alignCast(obj));

    // Decref all keys
    const mask: usize = @intCast(set.mask);
    const table: [*]setentry = @ptrCast(set.table.?);
    var i: usize = 0;
    while (i <= mask) : (i += 1) {
        const entry = &table[i];
        if (entry.key) |key| {
            key.ob_refcnt -= 1;
            entry.key = null;
            entry.hash = 0;
        }
    }

    // Reset to smalltable if using external table
    const smalltable_ptr: *setentry = @ptrCast(&set.smalltable);
    if (set.table != smalltable_ptr) {
        // TODO: Free external table
        set.table = @ptrCast(&set.smalltable);
        set.mask = PySet_MINSIZE - 1;
    }

    set.fill = 0;
    set.used = 0;
    set.finger = 0;

    return 0;
}

// ============================================================================
// Type Checking
// ============================================================================

pub export fn PySet_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PySet_Type) 1 else 0;
}

export fn PySet_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PySet_Type) 1 else 0;
}

pub export fn PyFrozenSet_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyFrozenSet_Type) 1 else 0;
}

export fn PyFrozenSet_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyFrozenSet_Type) 1 else 0;
}

pub export fn PyAnySet_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj == &PySet_Type or type_obj == &PyFrozenSet_Type) 1 else 0;
}

// ============================================================================
// Internal Functions
// ============================================================================

/// Resize the hash table
fn set_resize(set: *PySetObject, minused: isize) c_int {
    // Calculate new size (power of 2)
    var newsize: isize = PySet_MINSIZE;
    while (newsize <= minused) {
        newsize *= 2;
        if (newsize <= 0) return -1; // overflow
    }

    const old_mask: usize = @intCast(set.mask);
    const old_table: [*]setentry = @ptrCast(set.table.?);
    const smalltable_ptr: *setentry = @ptrCast(&set.smalltable);
    const is_small = (set.table == smalltable_ptr);

    // Allocate new table
    const new_table = allocator.alloc(setentry, @intCast(newsize)) catch return -1;
    @memset(new_table, setentry{ .key = null, .hash = 0 });

    // Set new table
    set.table = new_table.ptr;
    set.mask = newsize - 1;
    set.fill = set.used;

    // Rehash all entries from old table
    var i: usize = 0;
    while (i <= old_mask) : (i += 1) {
        if (old_table[i].key) |key| {
            const entry = findEmptySlot(set, old_table[i].hash);
            entry.key = key;
            entry.hash = old_table[i].hash;
        }
    }

    // Free old table if it wasn't smalltable
    if (!is_small) {
        allocator.free(old_table[0 .. old_mask + 1]);
    }

    return 0;
}

/// Add items from an iterable to a set (for PySet_New)
fn addFromIterable(obj: *cpython.PyObject, iterable: *cpython.PyObject) c_int {
    return addFromIterableInternal(obj, iterable);
}

/// Internal add from iterable (works even on frozensets during construction)
fn addFromIterableInternal(obj: *cpython.PyObject, iterable: *cpython.PyObject) c_int {
    const set: *PySetObject = @ptrCast(@alignCast(obj));

    // Handle list iterable
    const list = @import("pyobject_list.zig");
    if (list.PyList_Check(iterable) != 0) {
        const size = list.PyList_Size(iterable);
        var i: isize = 0;
        while (i < size) : (i += 1) {
            if (list.PyList_GetItem(iterable, i)) |item| {
                const hash = computeHash(item);
                if (lookupEntry(set, item, hash) == null) {
                    const entry = findEmptySlot(set, hash);
                    item.ob_refcnt += 1;
                    entry.key = item;
                    entry.hash = hash;
                    set.fill += 1;
                    set.used += 1;
                }
            }
        }
        return 0;
    }

    // Handle tuple iterable
    const tuple = @import("pyobject_tuple.zig");
    if (tuple.PyTuple_Check(iterable) != 0) {
        const size = tuple.PyTuple_Size(iterable);
        var i: isize = 0;
        while (i < size) : (i += 1) {
            if (tuple.PyTuple_GetItem(iterable, i)) |item| {
                const hash = computeHash(item);
                if (lookupEntry(set, item, hash) == null) {
                    const entry = findEmptySlot(set, hash);
                    item.ob_refcnt += 1;
                    entry.key = item;
                    entry.hash = hash;
                    set.fill += 1;
                    set.used += 1;
                }
            }
        }
        return 0;
    }

    // Handle another set
    if (PyAnySet_Check(iterable) != 0) {
        const other: *PySetObject = @ptrCast(@alignCast(iterable));
        const mask: usize = @intCast(other.mask);
        const other_table: [*]setentry = @ptrCast(other.table.?);
        var i: usize = 0;
        while (i <= mask) : (i += 1) {
            if (other_table[i].key) |item| {
                const hash = other_table[i].hash;
                if (lookupEntry(set, item, hash) == null) {
                    const entry = findEmptySlot(set, hash);
                    item.ob_refcnt += 1;
                    entry.key = item;
                    entry.hash = hash;
                    set.fill += 1;
                    set.used += 1;
                }
            }
        }
        return 0;
    }

    return 0; // Unknown iterable type - ignore
}

fn set_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const set: *PySetObject = @ptrCast(@alignCast(obj));

    // Decref all keys
    const mask: usize = @intCast(set.mask);
    const table: [*]setentry = @ptrCast(set.table.?);
    var i: usize = 0;
    while (i <= mask) : (i += 1) {
        if (table[i].key) |key| {
            key.ob_refcnt -= 1;
            // Deallocate if refcnt reaches 0
            if (key.ob_refcnt == 0) {
                if (key.ob_type) |tp| {
                    if (tp.tp_dealloc) |dealloc| {
                        dealloc(key);
                    }
                }
            }
        }
    }

    // Free external table if not using smalltable
    const smalltable_ptr: *setentry = @ptrCast(&set.smalltable);
    if (set.table != smalltable_ptr) {
        if (set.table) |tbl| {
            const tbl_slice: [*]setentry = @ptrCast(tbl);
            allocator.free(tbl_slice[0 .. mask + 1]);
        }
    }

    allocator.destroy(set);
}

fn frozenset_hash(obj: *cpython.PyObject) callconv(.c) isize {
    const set: *PySetObject = @ptrCast(@alignCast(obj));

    // Return cached hash if available
    if (set.hash != -1) {
        return set.hash;
    }

    // Compute hash (XOR of element hashes)
    var hash: u64 = 0;
    const mask: usize = @intCast(set.mask);
    const table: [*]setentry = @ptrCast(set.table.?);
    var i: usize = 0;

    while (i <= mask) : (i += 1) {
        if (table[i].key != null) {
            hash ^= @bitCast(@as(i64, table[i].hash));
        }
    }

    const result: isize = @intCast(hash);
    set.hash = result;
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "PySetObject layout matches CPython" {
    // PySetObject has specific layout with smalltable inline
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PySetObject, "ob_base"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PySetObject, "fill"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PySetObject, "used"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(PySetObject, "mask"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(PySetObject, "table"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(PySetObject, "hash"));
    try std.testing.expectEqual(@as(usize, 56), @offsetOf(PySetObject, "finger"));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(PySetObject, "smalltable"));
}

test "set exports" {
    _ = PySet_New;
    _ = PySet_Add;
    _ = PySet_Contains;
    _ = PySet_Check;
}
