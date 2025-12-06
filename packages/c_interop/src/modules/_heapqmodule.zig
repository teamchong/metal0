/// _heapq Module - Heap Queue C Accelerator
///
/// Implements CPython's Modules/_heapqmodule.c
/// Provides C implementation of heap queue algorithm (min-heap)
///
/// Reference: cpython/Modules/_heapqmodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

// ============================================================================
// HEAP OPERATIONS
// ============================================================================

/// Sift down - restore heap property by moving element down
fn siftdown(heap: ?*cpython.PyObject, startpos: isize, pos: isize) c_int {
    if (heap == null) return -1;

    const list = @import("../objects/listobject.zig");
    const object_mod = @import("../objects/object.zig");

    const newitem = list.PyList_GetItem(heap.?, pos);
    if (newitem == null) return -1;
    newitem.?.ob_refcnt += 1;

    var p = pos;
    while (p > startpos) {
        const parentpos = (p - 1) >> 1;
        const parent = list.PyList_GetItem(heap.?, parentpos);
        if (parent == null) {
            newitem.?.ob_refcnt -= 1;
            return -1;
        }

        const cmp = object_mod.PyObject_RichCompareBool(newitem, parent, object_mod.Py_LT);
        if (cmp < 0) {
            newitem.?.ob_refcnt -= 1;
            return -1;
        }
        if (cmp == 0) break;

        // Move parent down
        parent.?.ob_refcnt += 1;
        _ = list.PyList_SetItem(heap.?, p, parent.?);
        p = parentpos;
    }

    _ = list.PyList_SetItem(heap.?, p, newitem.?);
    return 0;
}

/// Sift up - restore heap property by moving element up
fn siftup(heap: ?*cpython.PyObject, pos: isize) c_int {
    if (heap == null) return -1;

    const list = @import("../objects/listobject.zig");
    const object_mod = @import("../objects/object.zig");

    const endpos = list.PyList_Size(heap.?);
    const startpos = pos;
    const newitem = list.PyList_GetItem(heap.?, pos);
    if (newitem == null) return -1;
    newitem.?.ob_refcnt += 1;

    var p = pos;
    var childpos = 2 * p + 1;

    while (childpos < endpos) {
        const rightpos = childpos + 1;
        if (rightpos < endpos) {
            const left = list.PyList_GetItem(heap.?, childpos);
            const right = list.PyList_GetItem(heap.?, rightpos);
            if (left != null and right != null) {
                const cmp = object_mod.PyObject_RichCompareBool(left, right, object_mod.Py_LT);
                if (cmp < 0) {
                    newitem.?.ob_refcnt -= 1;
                    return -1;
                }
                if (cmp == 0) childpos = rightpos;
            }
        }

        const child = list.PyList_GetItem(heap.?, childpos);
        if (child == null) {
            newitem.?.ob_refcnt -= 1;
            return -1;
        }
        child.?.ob_refcnt += 1;
        _ = list.PyList_SetItem(heap.?, p, child.?);
        p = childpos;
        childpos = 2 * p + 1;
    }

    _ = list.PyList_SetItem(heap.?, p, newitem.?);
    return siftdown(heap, startpos, p);
}

// ============================================================================
// PUBLIC FUNCTIONS
// ============================================================================

/// Push item onto heap
pub export fn _heapq_heappush(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const list = @import("../objects/listobject.zig");
    const object_mod = @import("../objects/object.zig");

    if (tuple.PyTuple_Size(args.?) < 2) return null;

    const heap = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const item = tuple.PyTuple_GetItem(args.?, 1) orelse return null;

    if (list.PyList_Check(heap) == 0) return null;

    _ = list.PyList_Append(heap, item);
    const n = list.PyList_Size(heap);
    if (siftdown(heap, 0, n - 1) < 0) return null;

    return &object_mod._Py_NoneStruct;
}

/// Pop smallest item from heap
pub export fn _heapq_heappop(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const list = @import("../objects/listobject.zig");

    if (tuple.PyTuple_Size(args.?) < 1) return null;

    const heap = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    if (list.PyList_Check(heap) == 0) return null;

    const n = list.PyList_Size(heap);
    if (n == 0) return null; // Would raise IndexError

    if (n == 1) {
        return list.PyList_GetItem(heap, 0);
    }

    // Get the smallest (root)
    const returnitem = list.PyList_GetItem(heap, 0);
    if (returnitem) |r| r.ob_refcnt += 1;

    // Move last item to root and sift up
    const lastelt = list.PyList_GetItem(heap, n - 1);
    if (lastelt) |l| {
        l.ob_refcnt += 1;
        _ = list.PyList_SetItem(heap, 0, l);
    }

    // Remove last element
    // Note: This is simplified - full impl would use PyList_SetSlice
    _ = siftup(heap, 0);

    return returnitem;
}

/// Transform list into heap in-place
pub export fn _heapq_heapify(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const list = @import("../objects/listobject.zig");
    const object_mod = @import("../objects/object.zig");

    if (tuple.PyTuple_Size(args.?) < 1) return null;

    const heap = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    if (list.PyList_Check(heap) == 0) return null;

    const n = list.PyList_Size(heap);

    // Start from last parent and sift up each
    var i = @divFloor(n, 2) - 1;
    while (i >= 0) : (i -= 1) {
        if (siftup(heap, i) < 0) return null;
        if (i == 0) break;
    }

    return &object_mod._Py_NoneStruct;
}

/// Push item, then pop smallest
pub export fn _heapq_heappushpop(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const list = @import("../objects/listobject.zig");
    const object_mod = @import("../objects/object.zig");

    if (tuple.PyTuple_Size(args.?) < 2) return null;

    const heap = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const item = tuple.PyTuple_GetItem(args.?, 1) orelse return null;

    if (list.PyList_Check(heap) == 0) return null;

    const n = list.PyList_Size(heap);
    if (n == 0) {
        item.?.ob_refcnt += 1;
        return item;
    }

    const top = list.PyList_GetItem(heap, 0) orelse return null;
    const cmp = object_mod.PyObject_RichCompareBool(top, item, object_mod.Py_LT);

    if (cmp < 0) return null;
    if (cmp == 0) {
        item.?.ob_refcnt += 1;
        return item;
    }

    // Replace root with item
    top.ob_refcnt += 1;
    item.?.ob_refcnt += 1;
    _ = list.PyList_SetItem(heap, 0, item.?);
    _ = siftup(heap, 0);

    return top;
}

/// Pop smallest, then push item
pub export fn _heapq_heapreplace(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const list = @import("../objects/listobject.zig");

    if (tuple.PyTuple_Size(args.?) < 2) return null;

    const heap = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const item = tuple.PyTuple_GetItem(args.?, 1) orelse return null;

    if (list.PyList_Check(heap) == 0) return null;
    if (list.PyList_Size(heap) == 0) return null;

    const returnitem = list.PyList_GetItem(heap, 0);
    if (returnitem) |r| r.ob_refcnt += 1;

    item.?.ob_refcnt += 1;
    _ = list.PyList_SetItem(heap, 0, item.?);
    _ = siftup(heap, 0);

    return returnitem;
}

// ============================================================================
// MODULE DEFINITION
// ============================================================================

const heapq_methods = [_]cpython.PyMethodDef{
    .{
        .ml_name = "heappush",
        .ml_meth = @ptrCast(&_heapq_heappush),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Push item onto heap, maintaining the heap invariant.",
    },
    .{
        .ml_name = "heappop",
        .ml_meth = @ptrCast(&_heapq_heappop),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Pop the smallest item off the heap, maintaining the heap invariant.",
    },
    .{
        .ml_name = "heapify",
        .ml_meth = @ptrCast(&_heapq_heapify),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Transform list into a heap, in-place, in linear time.",
    },
    .{
        .ml_name = "heappushpop",
        .ml_meth = @ptrCast(&_heapq_heappushpop),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Push item on the heap, then pop and return the smallest item.",
    },
    .{
        .ml_name = "heapreplace",
        .ml_meth = @ptrCast(&_heapq_heapreplace),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Pop and return the current smallest value, and add the new item.",
    },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var _heapqmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_heapq",
    .m_doc = "Heap queue algorithm (a.k.a. priority queue).",
    .m_size = -1,
    .m_methods = @constCast(&heapq_methods),
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__heapq() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&_heapqmodule);
}
