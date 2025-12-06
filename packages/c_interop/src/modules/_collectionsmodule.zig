/// _collections Module - Collections C Accelerator
///
/// Implements CPython's Modules/_collectionsmodule.c
/// Provides C implementations of deque, defaultdict, and other collections
///
/// Reference: cpython/Modules/_collectionsmodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// DEQUE IMPLEMENTATION
// ============================================================================

/// Block size for deque (matches CPython)
const BLOCKLEN = 64;

/// Deque block - linked list node containing BLOCKLEN items
const DequeBlock = struct {
    data: [BLOCKLEN]?*cpython.PyObject,
    prev: ?*DequeBlock,
    next: ?*DequeBlock,
};

/// DequeObject - Double-ended queue
pub const DequeObject = extern struct {
    ob_base: cpython.PyObject,
    leftblock: ?*DequeBlock,
    rightblock: ?*DequeBlock,
    leftindex: usize, // Index in leftblock
    rightindex: usize, // Index in rightblock
    len: isize, // Number of items
    maxlen: isize, // Maximum length (-1 for unbounded)
    weakreflist: ?*cpython.PyObject,
};

/// Create a new deque
pub export fn _collections_deque_new(maxlen: isize) ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(DequeObject), @sizeOf(DequeObject)) catch return null;
    const deque: *DequeObject = @ptrCast(@alignCast(mem.ptr));

    // Allocate initial block
    const block = allocator.create(DequeBlock) catch {
        allocator.free(mem);
        return null;
    };
    block.* = .{
        .data = [_]?*cpython.PyObject{null} ** BLOCKLEN,
        .prev = null,
        .next = null,
    };

    deque.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &DequeType },
        .leftblock = block,
        .rightblock = block,
        .leftindex = BLOCKLEN / 2,
        .rightindex = BLOCKLEN / 2 - 1,
        .len = 0,
        .maxlen = maxlen,
        .weakreflist = null,
    };

    return @ptrCast(deque);
}

/// Append to the right side of the deque
fn deque_append(self_obj: ?*cpython.PyObject, item: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null or item == null) return null;
    const deque: *DequeObject = @ptrCast(@alignCast(self_obj.?));

    // Check maxlen
    if (deque.maxlen >= 0 and deque.len >= deque.maxlen) {
        // Pop from left to make room
        _ = deque_popleft(self_obj);
    }

    deque.rightindex += 1;

    // Check if we need a new block
    if (deque.rightindex >= BLOCKLEN) {
        const new_block = allocator.create(DequeBlock) catch return null;
        new_block.* = .{
            .data = [_]?*cpython.PyObject{null} ** BLOCKLEN,
            .prev = deque.rightblock,
            .next = null,
        };
        if (deque.rightblock) |rb| {
            rb.next = new_block;
        }
        deque.rightblock = new_block;
        deque.rightindex = 0;
    }

    item.?.ob_refcnt += 1;
    if (deque.rightblock) |rb| {
        rb.data[deque.rightindex] = item;
    }
    deque.len += 1;

    const object_mod = @import("../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// Append to the left side of the deque
fn deque_appendleft(self_obj: ?*cpython.PyObject, item: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null or item == null) return null;
    const deque: *DequeObject = @ptrCast(@alignCast(self_obj.?));

    if (deque.maxlen >= 0 and deque.len >= deque.maxlen) {
        _ = deque_pop(self_obj);
    }

    if (deque.leftindex == 0) {
        const new_block = allocator.create(DequeBlock) catch return null;
        new_block.* = .{
            .data = [_]?*cpython.PyObject{null} ** BLOCKLEN,
            .prev = null,
            .next = deque.leftblock,
        };
        if (deque.leftblock) |lb| {
            lb.prev = new_block;
        }
        deque.leftblock = new_block;
        deque.leftindex = BLOCKLEN;
    }

    deque.leftindex -= 1;
    item.?.ob_refcnt += 1;
    if (deque.leftblock) |lb| {
        lb.data[deque.leftindex] = item;
    }
    deque.len += 1;

    const object_mod = @import("../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// Pop from the right side of the deque
fn deque_pop(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const deque: *DequeObject = @ptrCast(@alignCast(self_obj.?));

    if (deque.len == 0) return null; // Would raise IndexError

    var item: ?*cpython.PyObject = null;
    if (deque.rightblock) |rb| {
        item = rb.data[deque.rightindex];
        rb.data[deque.rightindex] = null;
    }

    deque.len -= 1;

    if (deque.rightindex == 0) {
        // Move to previous block
        if (deque.rightblock) |rb| {
            const prev = rb.prev;
            if (prev != null and rb != deque.leftblock) {
                allocator.destroy(rb);
                deque.rightblock = prev;
                if (prev) |p| p.next = null;
                deque.rightindex = BLOCKLEN - 1;
            }
        }
    } else {
        deque.rightindex -= 1;
    }

    return item;
}

/// Pop from the left side of the deque
fn deque_popleft(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const deque: *DequeObject = @ptrCast(@alignCast(self_obj.?));

    if (deque.len == 0) return null;

    var item: ?*cpython.PyObject = null;
    if (deque.leftblock) |lb| {
        item = lb.data[deque.leftindex];
        lb.data[deque.leftindex] = null;
    }

    deque.len -= 1;
    deque.leftindex += 1;

    if (deque.leftindex >= BLOCKLEN) {
        if (deque.leftblock) |lb| {
            const next = lb.next;
            if (next != null and lb != deque.rightblock) {
                allocator.destroy(lb);
                deque.leftblock = next;
                if (next) |n| n.prev = null;
                deque.leftindex = 0;
            }
        }
    }

    return item;
}

/// Get length of deque
fn deque_len(self_obj: ?*cpython.PyObject) callconv(.C) isize {
    if (self_obj == null) return 0;
    const deque: *DequeObject = @ptrCast(@alignCast(self_obj.?));
    return deque.len;
}

/// Deque dealloc
fn deque_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const deque: *DequeObject = @ptrCast(@alignCast(self_obj.?));

    // Clear all items
    while (deque.len > 0) {
        const item = deque_pop(self_obj);
        if (item) |i| i.ob_refcnt -= 1;
    }

    // Free blocks
    var block = deque.leftblock;
    while (block) |b| {
        const next = b.next;
        allocator.destroy(b);
        block = next;
    }

    const ptr: [*]u8 = @ptrCast(deque);
    allocator.free(ptr[0..@sizeOf(DequeObject)]);
}

// ============================================================================
// DEFAULTDICT IMPLEMENTATION
// ============================================================================

/// DefaultDictObject - Dict with default factory
pub const DefaultDictObject = extern struct {
    dict: cpython.PyObject, // PyDict_Type base
    default_factory: ?*cpython.PyObject,
};

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub export var DequeType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "collections.deque",
    .tp_basicsize = @sizeOf(DequeObject),
    .tp_itemsize = 0,
    .tp_dealloc = deque_dealloc,
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
    .tp_doc = "A list-like sequence optimized for data accesses near its endpoints.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(DequeObject, "weakreflist"),
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
};

// ============================================================================
// MODULE DEFINITION
// ============================================================================

pub export var _collectionsmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_collections",
    .m_doc = "High performance data structures.",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__collections() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    const module = module_mod.PyModule_Create(&_collectionsmodule);
    if (module == null) return null;

    // Add deque type to module
    _ = module_mod.PyModule_AddObject(module, "deque", @ptrCast(&DequeType));

    return module;
}
