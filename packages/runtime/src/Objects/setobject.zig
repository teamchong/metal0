/// PySet implementation - Python set and frozenset types (CPython ABI compatible)
const std = @import("std");
const runtime = @import("../runtime.zig");

// Re-export CPython-compatible types
pub const PyObject = runtime.PyObject;
pub const PySetObject = runtime.PySetObject;
pub const setentry = runtime.setentry;
pub const PySet_Type = &runtime.PySet_Type;
pub const PyFrozenSet_Type = &runtime.PyFrozenSet_Type;
pub const PySet_MINSIZE = runtime.PySet_MINSIZE;

const incref = runtime.incref;
const decref = runtime.decref;
const PythonError = runtime.PythonError;
const Py_ssize_t = runtime.Py_ssize_t;

/// Python set type - wrapper around CPython-compatible PySetObject
pub const PySet = struct {
    /// Create a new empty PySetObject
    pub fn create(allocator: std.mem.Allocator) !*PyObject {
        return createWithType(allocator, PySet_Type);
    }

    /// Create a new empty frozenset
    pub fn createFrozenset(allocator: std.mem.Allocator) !*PyObject {
        return createWithType(allocator, PyFrozenSet_Type);
    }

    fn createWithType(allocator: std.mem.Allocator, type_obj: *runtime.PyTypeObject) !*PyObject {
        const set_obj = try allocator.create(PySetObject);

        // Initialize empty set
        set_obj.* = PySetObject{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = type_obj,
            },
            .fill = 0,
            .used = 0,
            .mask = PySet_MINSIZE - 1,
            .table = &set_obj.smalltable,
            .hash = -1, // Not computed yet (for frozenset)
            .finger = 0,
            .smalltable = [_]setentry{.{ .key = null, .hash = 0 }} ** PySet_MINSIZE,
            .weakreflist = null,
        };

        return @ptrCast(set_obj);
    }

    /// Compute hash for a key using object identity or hash function
    fn computeHash(key: *PyObject) Py_ssize_t {
        // Use object identity as hash for simplicity
        // In a full implementation, this would call tp_hash
        return @intCast(@intFromPtr(key));
    }

    /// Find entry in set
    fn lookupEntry(set: *PySetObject, key: *PyObject, hash: Py_ssize_t) ?*setentry {
        const mask: usize = @intCast(set.mask);
        var idx = @as(usize, @intCast(@as(u64, @bitCast(@as(i64, hash))) & mask));
        var perturb: u64 = @bitCast(@as(i64, hash));
        const table: [*]setentry = set.table orelse return null;

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
            idx = (idx * 5 + 1 + @as(usize, @intCast(perturb))) & mask;
        }
    }

    /// Find empty slot for insertion
    fn findEmptySlot(set: *PySetObject, hash: Py_ssize_t) *setentry {
        const mask: usize = @intCast(set.mask);
        var idx = @as(usize, @intCast(@as(u64, @bitCast(@as(i64, hash))) & mask));
        var perturb: u64 = @bitCast(@as(i64, hash));
        const table: [*]setentry = set.table.?;

        while (true) {
            const entry = &table[idx];

            if (entry.key == null) {
                return entry;
            }

            perturb >>= 5;
            idx = (idx * 5 + 1 + @as(usize, @intCast(perturb))) & mask;
        }
    }

    /// Resize the hash table
    fn resize(set: *PySetObject, allocator: std.mem.Allocator, minused: Py_ssize_t) !void {
        // Calculate new size (power of 2)
        var newsize: Py_ssize_t = PySet_MINSIZE;
        while (newsize <= minused) {
            newsize *= 2;
            if (newsize <= 0) return error.OutOfMemory; // overflow
        }

        const old_mask: usize = @intCast(set.mask);
        const old_table: [*]setentry = set.table.?;
        const is_small = (set.table == &set.smalltable);

        // Allocate new table
        const new_table = try allocator.alloc(setentry, @intCast(newsize));
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
    }

    /// Add an item to the set
    pub fn add(obj: *PyObject, item: *PyObject) !void {
        std.debug.assert(runtime.PySet_Check(obj));
        const set_obj: *PySetObject = @ptrCast(@alignCast(obj));

        const hash = computeHash(item);

        // Check if already exists
        if (lookupEntry(set_obj, item, hash) != null) {
            return; // Already in set
        }

        // Check if we need to resize (when fill > 2/3 of capacity)
        const capacity: Py_ssize_t = set_obj.mask + 1;
        if (set_obj.fill * 3 >= capacity * 2) {
            try resize(set_obj, std.heap.c_allocator, capacity * 2);
        }

        // Find empty slot and insert
        const entry = findEmptySlot(set_obj, hash);
        incref(item);
        entry.key = item;
        entry.hash = hash;
        set_obj.fill += 1;
        set_obj.used += 1;
    }

    /// Check if set contains an item
    pub fn contains(obj: *PyObject, item: *PyObject) bool {
        std.debug.assert(runtime.PyAnySet_Check(obj));
        const set_obj: *PySetObject = @ptrCast(@alignCast(obj));

        const hash = computeHash(item);
        return lookupEntry(set_obj, item, hash) != null;
    }

    /// Remove an item from the set (no error if not found)
    pub fn discard(obj: *PyObject, item: *PyObject) void {
        std.debug.assert(runtime.PySet_Check(obj));
        const set_obj: *PySetObject = @ptrCast(@alignCast(obj));

        const hash = computeHash(item);
        if (lookupEntry(set_obj, item, hash)) |entry| {
            if (entry.key) |k| {
                decref(k, std.heap.c_allocator);
            }
            entry.key = null;
            entry.hash = 0;
            set_obj.used -= 1;
        }
    }

    /// Pop an arbitrary item from the set
    pub fn pop(obj: *PyObject) PythonError!*PyObject {
        std.debug.assert(runtime.PySet_Check(obj));
        const set_obj: *PySetObject = @ptrCast(@alignCast(obj));

        if (set_obj.used == 0) return PythonError.KeyError;

        const mask: usize = @intCast(set_obj.mask);
        var idx: usize = @intCast(set_obj.finger);
        const table: [*]setentry = set_obj.table.?;

        // Find first non-empty entry starting from finger
        while (idx <= mask) : (idx += 1) {
            const entry = &table[idx];
            if (entry.key != null) {
                const key = entry.key.?;
                entry.key = null;
                entry.hash = 0;
                set_obj.used -= 1;
                set_obj.finger = @intCast(idx);
                // Don't decref - transferring ownership to caller
                return key;
            }
        }

        // Wrap around
        idx = 0;
        while (idx < @as(usize, @intCast(set_obj.finger))) : (idx += 1) {
            const entry = &table[idx];
            if (entry.key != null) {
                const key = entry.key.?;
                entry.key = null;
                entry.hash = 0;
                set_obj.used -= 1;
                set_obj.finger = @intCast(idx);
                return key;
            }
        }

        return PythonError.KeyError;
    }

    /// Clear all items from the set
    pub fn clear(obj: *PyObject, allocator: std.mem.Allocator) void {
        std.debug.assert(runtime.PySet_Check(obj));
        const set_obj: *PySetObject = @ptrCast(@alignCast(obj));

        // Decref all keys
        const mask: usize = @intCast(set_obj.mask);
        const table: [*]setentry = set_obj.table orelse return;
        var i: usize = 0;
        while (i <= mask) : (i += 1) {
            const entry = &table[i];
            if (entry.key) |key| {
                decref(key, allocator);
                entry.key = null;
                entry.hash = 0;
            }
        }

        // Reset to smalltable if using external table
        if (set_obj.table != &set_obj.smalltable) {
            allocator.free(table[0 .. mask + 1]);
            set_obj.table = &set_obj.smalltable;
            set_obj.mask = PySet_MINSIZE - 1;
        }

        set_obj.fill = 0;
        set_obj.used = 0;
        set_obj.finger = 0;
    }

    /// Get number of items in set
    pub fn len(obj: *PyObject) usize {
        std.debug.assert(runtime.PyAnySet_Check(obj));
        const set_obj: *PySetObject = @ptrCast(@alignCast(obj));
        return @intCast(set_obj.used);
    }

    /// Create set from iterable (list)
    pub fn fromList(allocator: std.mem.Allocator, list_obj: *PyObject) !*PyObject {
        std.debug.assert(runtime.PyList_Check(list_obj));
        const list: *runtime.PyListObject = @ptrCast(@alignCast(list_obj));

        const result = try create(allocator);
        const size: usize = @intCast(list.ob_base.ob_size);

        var i: usize = 0;
        while (i < size) : (i += 1) {
            const item = list.ob_item[i];
            try add(result, item);
        }

        return result;
    }

    /// Create frozenset from iterable (list)
    pub fn frozensetFromList(allocator: std.mem.Allocator, list_obj: *PyObject) !*PyObject {
        std.debug.assert(runtime.PyList_Check(list_obj));
        const list: *runtime.PyListObject = @ptrCast(@alignCast(list_obj));

        const result = try createFrozenset(allocator);
        const result_set: *PySetObject = @ptrCast(@alignCast(result));
        const size: usize = @intCast(list.ob_base.ob_size);

        var i: usize = 0;
        while (i < size) : (i += 1) {
            const item = list.ob_item[i];
            const hash = computeHash(item);

            // Check if already exists
            if (lookupEntry(result_set, item, hash) != null) {
                continue; // Already in set
            }

            // Check if we need to resize
            const capacity: Py_ssize_t = result_set.mask + 1;
            if (result_set.fill * 3 >= capacity * 2) {
                try resize(result_set, allocator, capacity * 2);
            }

            // Find empty slot and insert
            const entry = findEmptySlot(result_set, hash);
            incref(item);
            entry.key = item;
            entry.hash = hash;
            result_set.fill += 1;
            result_set.used += 1;
        }

        return result;
    }
};
