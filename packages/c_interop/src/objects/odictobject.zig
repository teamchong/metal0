/// Ordered Dictionary Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/odictobject.c
/// OrderedDict maintains insertion order (inherited behavior since Python 3.7)
///
/// Reference: cpython/Objects/odictobject.c
///            cpython/Include/cpython/odictobject.h
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// _ODictNode - Node in the ordered dict linked list
/// Reference: cpython/Objects/odictobject.c
///
/// struct _odictnode {
///     PyObject *key;
///     Py_hash_t hash;
///     _ODictNode *next;
///     _ODictNode *prev;
/// };
pub const _ODictNode = extern struct {
    key: ?*cpython.PyObject, // 8 bytes - the key
    hash: isize, // 8 bytes - cached hash
    next: ?*_ODictNode, // 8 bytes - next node
    prev: ?*_ODictNode, // 8 bytes - previous node
};

// Verify _ODictNode size: 8 + 8 + 8 + 8 = 32 bytes
comptime {
    if (@sizeOf(_ODictNode) != 32) {
        @compileError("_ODictNode size mismatch with CPython");
    }
}

/// PyODictObject - OrderedDict object
/// Reference: cpython/Objects/odictobject.c
///
/// typedef struct {
///     PyDictObject od_dict;           // base dict
///     _ODictNode *od_fast_nodes;      // hash table for O(1) node lookup
///     Py_ssize_t od_fast_nodes_size;  // size of fast nodes table
///     _ODictNode *od_first;           // first node in order
///     _ODictNode *od_last;            // last node in order
///     Py_ssize_t od_state;            // iteration state counter
///     PyObject *od_inst_dict;         // instance dict for subclasses
///     PyObject *od_weakreflist;       // weak references
/// } PyODictObject;
pub const PyODictObject = extern struct {
    od_dict: cpython.PyDictObject, // 48 bytes (3.12) - base dict
    od_fast_nodes: ?*?*_ODictNode, // 8 bytes - hash table for nodes
    od_fast_nodes_size: isize, // 8 bytes - size of fast nodes
    od_first: ?*_ODictNode, // 8 bytes - first node
    od_last: ?*_ODictNode, // 8 bytes - last node
    od_state: isize, // 8 bytes - iteration state
    od_inst_dict: ?*cpython.PyObject, // 8 bytes - instance dict
    od_weakreflist: ?*cpython.PyObject, // 8 bytes - weak references
};

/// PyODictIterObject - OrderedDict iterator
/// Reference: cpython/Objects/odictobject.c
pub const PyODictIterObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    di_odict: ?*PyODictObject, // 8 bytes - the dict
    di_current: ?*_ODictNode, // 8 bytes - current node
    di_state: isize, // 8 bytes - state at creation
    kind: c_int, // 4 bytes - 0=keys, 1=values, 2=items
    _pad: [4]u8, // 4 bytes padding
};

// Verify PyODictIterObject size: 16 + 8 + 8 + 8 + 4 + 4 = 48 bytes
comptime {
    if (@sizeOf(PyODictIterObject) != 48) {
        @compileError("PyODictIterObject size mismatch with CPython");
    }
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create a new odict node
fn odict_node_new(key: ?*cpython.PyObject, hash: isize) ?*_ODictNode {
    const mem = allocator.alignedAlloc(u8, @alignOf(_ODictNode), @sizeOf(_ODictNode)) catch return null;
    const node: *_ODictNode = @ptrCast(@alignCast(mem.ptr));

    if (key) |k| {
        k.ob_refcnt += 1;
    }

    node.* = .{
        .key = key,
        .hash = hash,
        .next = null,
        .prev = null,
    };

    return node;
}

/// Free an odict node
fn odict_node_free(node: ?*_ODictNode) void {
    if (node == null) return;
    const n = node.?;

    if (n.key) |k| {
        k.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(n);
    allocator.free(ptr[0..@sizeOf(_ODictNode)]);
}

// ============================================================================
// ODICT TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for ordered dict
fn odict_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const od: *PyODictObject = @ptrCast(@alignCast(self_obj.?));

    // Free all nodes
    var node = od.od_first;
    while (node) |n| {
        const next = n.next;
        odict_node_free(n);
        node = next;
    }

    // Free fast nodes table
    if (od.od_fast_nodes) |fast_nodes| {
        const size: usize = @intCast(od.od_fast_nodes_size);
        const fast_ptr: [*]u8 = @ptrCast(fast_nodes);
        allocator.free(fast_ptr[0 .. size * @sizeOf(?*_ODictNode)]);
    }

    // Decref instance dict
    if (od.od_inst_dict) |inst_dict| {
        inst_dict.ob_refcnt -= 1;
    }

    // Clear base dict entries
    if (od.od_dict.ma_keys) |keys_ptr| {
        const keys: *dictobject.InternalDictKeys = @ptrCast(@alignCast(keys_ptr));
        // Free entries
        for (0..@as(usize, 1) << @intCast(keys.dk_log2_size)) |i| {
            if (keys.entries[i].key) |key| {
                key.ob_refcnt -= 1;
            }
            if (keys.entries[i].value) |val| {
                val.ob_refcnt -= 1;
            }
        }
    }

    // Free weakrefs
    if (od.od_weakreflist) |weakref| {
        const weakrefobj = @import("weakrefobject.zig");
        weakrefobj.PyObject_ClearWeakRefs(@ptrCast(od));
        _ = weakref;
    }

    const ptr: [*]u8 = @ptrCast(od);
    allocator.free(ptr[0..@sizeOf(PyODictObject)]);
}

/// Traverse for ordered dict (GC)
fn odict_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const od: *PyODictObject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        // Visit all keys in order
        var node = od.od_first;
        while (node) |n| {
            if (n.key) |key| {
                const result = v(key, arg);
                if (result != 0) return result;
            }
            node = n.next;
        }

        // Visit instance dict
        if (od.od_inst_dict) |inst_dict| {
            const result = v(inst_dict, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Clear for ordered dict (GC)
fn odict_clear(self_obj: ?*cpython.PyObject) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const od: *PyODictObject = @ptrCast(@alignCast(self_obj.?));

    // Clear all nodes
    var node = od.od_first;
    while (node) |n| {
        const next = n.next;
        odict_node_free(n);
        node = next;
    }
    od.od_first = null;
    od.od_last = null;

    // Clear instance dict
    if (od.od_inst_dict) |inst_dict| {
        inst_dict.ob_refcnt -= 1;
        od.od_inst_dict = null;
    }

    return 0;
}

/// Repr for ordered dict
fn odict_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const od: *PyODictObject = @ptrCast(@alignCast(self_obj.?));
    const pyunicode = @import("unicodeobject.zig");

    // Check for empty dict
    if (od.od_first == null) {
        return pyunicode.PyUnicode_FromString("OrderedDict()");
    }

    // Build full repr: OrderedDict([(key1, val1), (key2, val2), ...])
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;

    const prefix = "OrderedDict([";
    @memcpy(buf[pos..][0..prefix.len], prefix);
    pos += prefix.len;

    var node = od.od_first;
    var first = true;
    while (node) |n| {
        if (!first) {
            buf[pos] = ',';
            buf[pos + 1] = ' ';
            pos += 2;
        }
        first = false;

        // Add (key, value)
        buf[pos] = '(';
        pos += 1;

        // Get key repr
        if (n.key) |key| {
            if (key.ob_type.tp_repr) |repr_fn| {
                const key_repr = repr_fn(key);
                if (key_repr) |kr| {
                    defer kr.ob_refcnt -= 1;
                    const key_str = pyunicode.PyUnicode_AsUTF8(kr);
                    if (key_str != null) {
                        const s = std.mem.span(key_str.?);
                        const len = @min(s.len, buf.len - pos - 100);
                        @memcpy(buf[pos..][0..len], s[0..len]);
                        pos += len;
                    }
                }
            }
        }

        buf[pos] = ',';
        buf[pos + 1] = ' ';
        pos += 2;

        // Get value repr
        const val = odict_node_value(od, n);
        if (val) |v| {
            if (v.ob_type.tp_repr) |repr_fn| {
                const val_repr = repr_fn(v);
                if (val_repr) |vr| {
                    defer vr.ob_refcnt -= 1;
                    const val_str = pyunicode.PyUnicode_AsUTF8(vr);
                    if (val_str != null) {
                        const s = std.mem.span(val_str.?);
                        const len = @min(s.len, buf.len - pos - 50);
                        @memcpy(buf[pos..][0..len], s[0..len]);
                        pos += len;
                    }
                }
            }
        }

        buf[pos] = ')';
        pos += 1;

        node = n.next;
    }

    const suffix = "])";
    @memcpy(buf[pos..][0..suffix.len], suffix);
    pos += suffix.len;

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(pos));
}

/// Helper to get value for a node
fn odict_node_value(od: *PyODictObject, node: *_ODictNode) ?*cpython.PyObject {
    if (node.key) |key| {
        return dictobject.PyDict_GetItem(@ptrCast(od), key);
    }
    return null;
}

/// Init for ordered dict
fn odict_init(self_obj: *cpython.PyObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) c_int {
    const od: *PyODictObject = @ptrCast(@alignCast(self_obj));
    _ = args;
    _ = kwargs;

    od.od_first = null;
    od.od_last = null;
    od.od_state = 0;
    od.od_fast_nodes = null;
    od.od_fast_nodes_size = 0;
    od.od_inst_dict = null;
    od.od_weakreflist = null;

    return 0;
}

/// New for ordered dict
fn odict_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = args;
    _ = kwargs;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyODictObject), @sizeOf(PyODictObject)) catch return null;
    const od: *PyODictObject = @ptrCast(@alignCast(mem.ptr));

    // Initialize base dict
    od.od_dict = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyODict_Type,
        },
        .ma_used = 0,
        ._ma_watcher_tag = 0,
        .ma_keys = null,
        .ma_values = null,
    };

    od.od_fast_nodes = null;
    od.od_fast_nodes_size = 0;
    od.od_first = null;
    od.od_last = null;
    od.od_state = 0;
    od.od_inst_dict = null;
    od.od_weakreflist = null;

    return @ptrCast(od);
}

/// Rich comparison for ordered dict
fn odict_richcompare(self_obj: *cpython.PyObject, other: *cpython.PyObject, op: c_int) callconv(.C) ?*cpython.PyObject {
    const pybool = @import("boolobject.zig");
    const object_mod = @import("object.zig");

    // Only support == and !=
    if (op != object_mod.Py_EQ and op != object_mod.Py_NE) {
        return cpython.Py_NotImplemented;
    }

    const od_self: *PyODictObject = @ptrCast(@alignCast(self_obj));

    // Check if other is also an OrderedDict
    if (other.ob_type != &PyODict_Type) {
        // Compare as regular dict if other is dict
        if (dictobject.PyDict_Check(other) != 0) {
            // OrderedDict != regular dict unless comparing values only
            return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
        }
        return cpython.Py_NotImplemented;
    }

    const od_other: *PyODictObject = @ptrCast(@alignCast(other));

    // Check size first
    if (od_self.od_dict.ma_used != od_other.od_dict.ma_used) {
        return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
    }

    // Compare key-value pairs in order
    var node_self = od_self.od_first;
    var node_other = od_other.od_first;

    while (node_self != null and node_other != null) {
        const key_self = node_self.?.key;
        const key_other = node_other.?.key;

        // Compare keys
        if (key_self != null and key_other != null) {
            const key_eq = object_mod.PyObject_RichCompareBool(key_self.?, key_other.?, object_mod.Py_EQ);
            if (key_eq != 1) {
                return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
            }

            // Compare values
            const val_self = odict_node_value(od_self, node_self.?);
            const val_other = odict_node_value(od_other, node_other.?);

            if (val_self != null and val_other != null) {
                const val_eq = object_mod.PyObject_RichCompareBool(val_self.?, val_other.?, object_mod.Py_EQ);
                if (val_eq != 1) {
                    return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
                }
            } else if (val_self != val_other) {
                return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
            }
        } else if (key_self != key_other) {
            return if (op == object_mod.Py_EQ) pybool.Py_False else pybool.Py_True;
        }

        node_self = node_self.?.next;
        node_other = node_other.?.next;
    }

    // Both should be exhausted at same time
    const both_null = (node_self == null and node_other == null);
    return if (op == object_mod.Py_EQ)
        (if (both_null) pybool.Py_True else pybool.Py_False)
    else
        (if (both_null) pybool.Py_False else pybool.Py_True);
}

/// PyODict_Type - the OrderedDict type object
pub export var PyODict_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "collections.OrderedDict",
    .tp_basicsize = @sizeOf(PyODictObject),
    .tp_itemsize = 0,
    .tp_dealloc = odict_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = odict_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null, // Uses dict's mapping
    .tp_hash = null, // Unhashable
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "Dictionary that remembers insertion order",
    .tp_traverse = odict_traverse,
    .tp_clear = odict_clear,
    .tp_richcompare = odict_richcompare,
    .tp_weaklistoffset = @offsetOf(PyODictObject, "od_weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null, // Set to PyDict_Type at init
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(PyODictObject, "od_inst_dict"),
    .tp_init = odict_init,
    .tp_alloc = null,
    .tp_new = odict_new,
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
};

// ============================================================================
// ODICT ITERATOR IMPLEMENTATION
// ============================================================================

/// Dealloc for odict iterator
fn odictiter_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const it: *PyODictIterObject = @ptrCast(@alignCast(self_obj.?));

    if (it.di_odict) |od| {
        const od_obj: *cpython.PyObject = @ptrCast(od);
        od_obj.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(it);
    allocator.free(ptr[0..@sizeOf(PyODictIterObject)]);
}

/// Next for odict keys iterator
fn odictiter_iternextkey(self_obj: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    const it: *PyODictIterObject = @ptrCast(@alignCast(self_obj));

    if (it.di_odict == null) return null;
    const od = it.di_odict.?;

    // Check if dict was modified
    if (it.di_state != od.od_state) {
        return null;
    }

    const node = it.di_current orelse return null;
    it.di_current = node.next;

    if (node.key) |key| {
        key.ob_refcnt += 1;
        return key;
    }

    return null;
}

/// Next for odict values iterator
fn odictiter_iternextvalue(self_obj: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    const it: *PyODictIterObject = @ptrCast(@alignCast(self_obj));

    if (it.di_odict == null) return null;
    const od = it.di_odict.?;

    if (it.di_state != od.od_state) return null;

    const node = it.di_current orelse return null;
    it.di_current = node.next;

    // Get value from dict using node.key
    if (node.key) |key| {
        const val = dictobject.PyDict_GetItem(@ptrCast(od), key);
        if (val) |v| {
            v.ob_refcnt += 1;
            return v;
        }
    }
    return null;
}

/// Next for odict items iterator
fn odictiter_iternextitem(self_obj: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    const it: *PyODictIterObject = @ptrCast(@alignCast(self_obj));

    if (it.di_odict == null) return null;
    const od = it.di_odict.?;

    if (it.di_state != od.od_state) return null;

    const node = it.di_current orelse return null;
    it.di_current = node.next;

    // Create tuple (key, value)
    if (node.key) |key| {
        const val = dictobject.PyDict_GetItem(@ptrCast(od), key);
        const tuple = @import("tupleobject.zig");
        const result = tuple.PyTuple_New(2);
        if (result) |r| {
            key.ob_refcnt += 1;
            _ = tuple.PyTuple_SetItem(r, 0, key);
            if (val) |v| {
                v.ob_refcnt += 1;
                _ = tuple.PyTuple_SetItem(r, 1, v);
            }
            return r;
        }
    }
    return null;
}

/// PyODictKeys_Type
pub export var PyODictKeys_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "odict_keys",
    .tp_basicsize = @sizeOf(PyODictIterObject),
    .tp_itemsize = 0,
    .tp_dealloc = odictiter_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = null,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = odictiter_iternextkey,
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
};

/// PyODictValues_Type
pub export var PyODictValues_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "odict_values",
    .tp_basicsize = @sizeOf(PyODictIterObject),
    .tp_itemsize = 0,
    .tp_dealloc = odictiter_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = null,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = odictiter_iternextvalue,
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
};

/// PyODictItems_Type
pub export var PyODictItems_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "odict_items",
    .tp_basicsize = @sizeOf(PyODictIterObject),
    .tp_itemsize = 0,
    .tp_dealloc = odictiter_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = null,
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = odictiter_iternextitem,
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
};

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// Create a new empty OrderedDict
pub export fn PyODict_New() ?*cpython.PyObject {
    return odict_new(&PyODict_Type, null, null);
}

/// Check if object is an OrderedDict
pub export fn PyODict_Check(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    return if (op.?.ob_type == &PyODict_Type) 1 else 0;
}

/// Check if object is an OrderedDict or subclass
pub export fn PyODict_CheckExact(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    // Check for exact type match
    return if (op.?.ob_type == &PyODict_Type) 1 else 0;
}

/// Check if object is an OrderedDict or subclass
pub export fn PyODict_CheckAny(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    // Check for type or subclass via tp_mro
    const tp = op.?.ob_type;
    if (tp == &PyODict_Type) return 1;

    // Check MRO for subclass relationship
    if (tp.tp_mro) |mro| {
        const tuple = @import("tupleobject.zig");
        const size = tuple.PyTuple_Size(mro);
        for (0..@intCast(size)) |i| {
            const base = tuple.PyTuple_GetItem(mro, @intCast(i));
            if (base) |b| {
                if (@as(*cpython.PyTypeObject, @ptrCast(@alignCast(b))) == &PyODict_Type) {
                    return 1;
                }
            }
        }
    }
    return 0;
}

/// Set item in OrderedDict (maintains order)
pub export fn PyODict_SetItem(od: ?*cpython.PyObject, key: ?*cpython.PyObject, value: ?*cpython.PyObject) c_int {
    if (od == null or key == null) return -1;
    const odict: *PyODictObject = @ptrCast(@alignCast(od.?));

    // Get hash of key
    var hash: isize = -1;
    if (key.?.ob_type.tp_hash) |hash_fn| {
        hash = hash_fn(key.?);
    }

    // Check if key already exists
    var node = odict.od_first;
    while (node) |n| {
        if (n.hash == hash and n.key == key) {
            // Key exists, just update value in base dict
            return dictobject.PyDict_SetItem(@ptrCast(odict), key.?, value.?);
        }
        node = n.next;
    }

    // New key - add node at end
    const new_node = odict_node_new(key, hash);
    if (new_node == null) return -1;

    // Add to end of list
    new_node.?.prev = odict.od_last;
    if (odict.od_last) |last| {
        last.next = new_node;
    } else {
        odict.od_first = new_node;
    }
    odict.od_last = new_node;

    // Update state
    odict.od_state += 1;

    // Set value in base dict
    return dictobject.PyDict_SetItem(@ptrCast(odict), key.?, value.?);
}

/// Delete item from OrderedDict
pub export fn PyODict_DelItem(od: ?*cpython.PyObject, key: ?*cpython.PyObject) c_int {
    if (od == null or key == null) return -1;
    const odict: *PyODictObject = @ptrCast(@alignCast(od.?));

    // Get hash of key
    var hash: isize = -1;
    if (key.?.ob_type.tp_hash) |hash_fn| {
        hash = hash_fn(key.?);
    }

    // Find and remove node
    var node = odict.od_first;
    while (node) |n| {
        if (n.hash == hash and n.key == key) {
            // Remove from list
            if (n.prev) |prev| {
                prev.next = n.next;
            } else {
                odict.od_first = n.next;
            }
            if (n.next) |next| {
                next.prev = n.prev;
            } else {
                odict.od_last = n.prev;
            }

            odict_node_free(n);
            odict.od_state += 1;

            // Delete from base dict
            return dictobject.PyDict_DelItem(@ptrCast(odict), key.?);
        }
        node = n.next;
    }

    return -1; // Key not found
}

/// Get iterator for keys
pub export fn PyODict_Keys(od: ?*cpython.PyObject) ?*cpython.PyObject {
    if (od == null) return null;
    const odict: *PyODictObject = @ptrCast(@alignCast(od.?));

    const mem = allocator.alignedAlloc(u8, @alignOf(PyODictIterObject), @sizeOf(PyODictIterObject)) catch return null;
    const it: *PyODictIterObject = @ptrCast(@alignCast(mem.ptr));

    od.?.ob_refcnt += 1;

    it.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyODictKeys_Type,
        },
        .di_odict = odict,
        .di_current = odict.od_first,
        .di_state = odict.od_state,
        .kind = 0,
        ._pad = [_]u8{0} ** 4,
    };

    return @ptrCast(it);
}

/// Get iterator for values
pub export fn PyODict_Values(od: ?*cpython.PyObject) ?*cpython.PyObject {
    if (od == null) return null;
    const odict: *PyODictObject = @ptrCast(@alignCast(od.?));

    const mem = allocator.alignedAlloc(u8, @alignOf(PyODictIterObject), @sizeOf(PyODictIterObject)) catch return null;
    const it: *PyODictIterObject = @ptrCast(@alignCast(mem.ptr));

    od.?.ob_refcnt += 1;

    it.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyODictValues_Type,
        },
        .di_odict = odict,
        .di_current = odict.od_first,
        .di_state = odict.od_state,
        .kind = 1,
        ._pad = [_]u8{0} ** 4,
    };

    return @ptrCast(it);
}

/// Get iterator for items
pub export fn PyODict_Items(od: ?*cpython.PyObject) ?*cpython.PyObject {
    if (od == null) return null;
    const odict: *PyODictObject = @ptrCast(@alignCast(od.?));

    const mem = allocator.alignedAlloc(u8, @alignOf(PyODictIterObject), @sizeOf(PyODictIterObject)) catch return null;
    const it: *PyODictIterObject = @ptrCast(@alignCast(mem.ptr));

    od.?.ob_refcnt += 1;

    it.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyODictItems_Type,
        },
        .di_odict = odict,
        .di_current = odict.od_first,
        .di_state = odict.od_state,
        .kind = 2,
        ._pad = [_]u8{0} ** 4,
    };

    return @ptrCast(it);
}

/// Move key to end of order
pub export fn PyODict_MoveToEnd(od: ?*cpython.PyObject, key: ?*cpython.PyObject, last: c_int) c_int {
    if (od == null or key == null) return -1;
    const odict: *PyODictObject = @ptrCast(@alignCast(od.?));

    // Get hash of key
    var hash: isize = -1;
    if (key.?.ob_type.tp_hash) |hash_fn| {
        hash = hash_fn(key.?);
    }

    // Find the node
    var node = odict.od_first;
    while (node) |n| {
        if (n.hash == hash and n.key == key) {
            // Already at correct position?
            if (last != 0 and n.next == null) return 0;
            if (last == 0 and n.prev == null) return 0;

            // Remove from current position
            if (n.prev) |prev| {
                prev.next = n.next;
            } else {
                odict.od_first = n.next;
            }
            if (n.next) |next| {
                next.prev = n.prev;
            } else {
                odict.od_last = n.prev;
            }

            // Insert at new position
            if (last != 0) {
                // Move to end
                n.next = null;
                n.prev = odict.od_last;
                if (odict.od_last) |l| {
                    l.next = n;
                }
                odict.od_last = n;
                if (odict.od_first == null) {
                    odict.od_first = n;
                }
            } else {
                // Move to beginning
                n.prev = null;
                n.next = odict.od_first;
                if (odict.od_first) |f| {
                    f.prev = n;
                }
                odict.od_first = n;
                if (odict.od_last == null) {
                    odict.od_last = n;
                }
            }

            odict.od_state += 1;
            return 0;
        }
        node = n.next;
    }

    return -1; // Key not found
}
