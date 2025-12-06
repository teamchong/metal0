/// _functools Module - Functools C Accelerator
///
/// Implements CPython's Modules/_functoolsmodule.c
/// Provides partial, reduce, lru_cache implementations
///
/// Reference: cpython/Modules/_functoolsmodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// PARTIAL OBJECT
// ============================================================================

/// PartialObject - partial function application
pub const PartialObject = extern struct {
    ob_base: cpython.PyObject,
    func: ?*cpython.PyObject, // Wrapped function
    args: ?*cpython.PyObject, // Positional arguments (tuple)
    kw: ?*cpython.PyObject, // Keyword arguments (dict)
    dict: ?*cpython.PyObject, // __dict__
    weakreflist: ?*cpython.PyObject,
};

/// Create a new partial object
pub export fn _functools_partial_new(func: ?*cpython.PyObject, args: ?*cpython.PyObject, kw: ?*cpython.PyObject) ?*cpython.PyObject {
    if (func == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PartialObject), @sizeOf(PartialObject)) catch return null;
    const partial: *PartialObject = @ptrCast(@alignCast(mem.ptr));

    partial.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &PartialType },
        .func = func,
        .args = args,
        .kw = kw,
        .dict = null,
        .weakreflist = null,
    };

    func.?.ob_refcnt += 1;
    if (args) |a| a.ob_refcnt += 1;
    if (kw) |k| k.ob_refcnt += 1;

    return @ptrCast(partial);
}

/// Call a partial object
fn partial_call(self_obj: ?*cpython.PyObject, args: ?*cpython.PyObject, kw: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const partial: *PartialObject = @ptrCast(@alignCast(self_obj.?));

    if (partial.func == null) return null;

    // Merge args: partial.args + args
    const tuple = @import("../objects/tupleobject.zig");
    const dict = @import("../objects/dictobject.zig");

    const partial_args_len = if (partial.args) |a| tuple.PyTuple_Size(a) else 0;
    const call_args_len = if (args) |a| tuple.PyTuple_Size(a) else 0;
    const total_args = partial_args_len + call_args_len;

    const merged_args = tuple.PyTuple_New(total_args);
    if (merged_args == null) return null;

    // Copy partial args
    var i: isize = 0;
    while (i < partial_args_len) : (i += 1) {
        if (partial.args) |a| {
            const item = tuple.PyTuple_GetItem(a, i);
            if (item) |it| {
                it.ob_refcnt += 1;
                _ = tuple.PyTuple_SetItem(merged_args.?, i, it);
            }
        }
    }

    // Copy call args
    var j: isize = 0;
    while (j < call_args_len) : (j += 1) {
        if (args) |a| {
            const item = tuple.PyTuple_GetItem(a, j);
            if (item) |it| {
                it.ob_refcnt += 1;
                _ = tuple.PyTuple_SetItem(merged_args.?, partial_args_len + j, it);
            }
        }
    }

    // Merge kwargs
    var merged_kw = partial.kw;
    if (kw != null) {
        if (partial.kw != null) {
            merged_kw = dict.PyDict_Copy(partial.kw);
            if (merged_kw) |mk| {
                _ = dict.PyDict_Update(mk, kw);
            }
        } else {
            merged_kw = kw;
            if (merged_kw) |mk| mk.ob_refcnt += 1;
        }
    } else if (partial.kw) |pk| {
        pk.ob_refcnt += 1;
    }

    // Call the function
    const object_mod = @import("../objects/object.zig");
    const result = object_mod.PyObject_Call(partial.func, merged_args, merged_kw);

    merged_args.?.ob_refcnt -= 1;
    if (merged_kw != partial.kw and merged_kw != kw) {
        if (merged_kw) |mk| mk.ob_refcnt -= 1;
    }

    return result;
}

/// Partial dealloc
fn partial_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const partial: *PartialObject = @ptrCast(@alignCast(self_obj.?));

    if (partial.func) |f| f.ob_refcnt -= 1;
    if (partial.args) |a| a.ob_refcnt -= 1;
    if (partial.kw) |k| k.ob_refcnt -= 1;
    if (partial.dict) |d| d.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(partial);
    allocator.free(ptr[0..@sizeOf(PartialObject)]);
}

// ============================================================================
// REDUCE FUNCTION
// ============================================================================

/// Reduce function - apply function cumulatively
pub export fn _functools_reduce(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const object_mod = @import("../objects/object.zig");

    const nargs = tuple.PyTuple_Size(args.?);
    if (nargs < 2) return null;

    const func = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const seq = tuple.PyTuple_GetItem(args.?, 1) orelse return null;

    // Get iterator
    const iter = object_mod.PyObject_GetIter(seq) orelse return null;
    defer iter.ob_refcnt -= 1;

    // Get initial value
    var result: ?*cpython.PyObject = null;
    if (nargs >= 3) {
        result = tuple.PyTuple_GetItem(args.?, 2);
        if (result) |r| r.ob_refcnt += 1;
    } else {
        result = object_mod.PyIter_Next(iter);
        if (result == null) return null; // Empty sequence with no initial
    }

    // Apply function to each element
    while (true) {
        const item = object_mod.PyIter_Next(iter);
        if (item == null) break;

        const call_args = tuple.PyTuple_New(2);
        if (call_args == null) {
            item.ob_refcnt -= 1;
            if (result) |r| r.ob_refcnt -= 1;
            return null;
        }

        _ = tuple.PyTuple_SetItem(call_args.?, 0, result.?);
        _ = tuple.PyTuple_SetItem(call_args.?, 1, item);

        result = object_mod.PyObject_Call(func, call_args, null);
        call_args.?.ob_refcnt -= 1;

        if (result == null) return null;
    }

    return result;
}

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub export var PartialType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "functools.partial",
    .tp_basicsize = @sizeOf(PartialObject),
    .tp_itemsize = 0,
    .tp_dealloc = partial_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = partial_call,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "partial(func, *args, **keywords)",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PartialObject, "weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(PartialObject, "dict"),
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

const functools_methods = [_]cpython.PyMethodDef{
    .{
        .ml_name = "reduce",
        .ml_meth = @ptrCast(&_functools_reduce),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "reduce(function, iterable[, initializer]) -> value",
    },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var _functoolsmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_functools",
    .m_doc = "Tools for working with functions and callable objects.",
    .m_size = -1,
    .m_methods = @constCast(&functools_methods),
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__functools() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    const module = module_mod.PyModule_Create(&_functoolsmodule);
    if (module == null) return null;

    _ = module_mod.PyModule_AddObject(module, "partial", @ptrCast(&PartialType));

    return module;
}
