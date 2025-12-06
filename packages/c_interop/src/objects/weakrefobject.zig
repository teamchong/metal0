/// Weak Reference Object Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/weakrefobject.c
/// Weak references allow referencing objects without preventing garbage collection
///
/// Reference: cpython/Objects/weakrefobject.c
///            cpython/Include/cpython/weakrefobject.h
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// PyWeakReference - Weak reference object
/// Reference: cpython/Include/cpython/weakrefobject.h
///
/// struct _PyWeakReference {
///     PyObject_HEAD
///     PyObject *wr_object;
///     PyObject *wr_callback;
///     Py_hash_t hash;
///     PyWeakReference *wr_prev;
///     PyWeakReference *wr_next;
///     vectorcallfunc vectorcall;
/// };
pub const PyWeakReference = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    wr_object: ?*cpython.PyObject, // 8 bytes - the referenced object (stealth reference)
    wr_callback: ?*cpython.PyObject, // 8 bytes - callback when object dies
    hash: isize, // 8 bytes - cached hash (-1 if not computed)
    wr_prev: ?*PyWeakReference, // 8 bytes - prev in doubly-linked list
    wr_next: ?*PyWeakReference, // 8 bytes - next in doubly-linked list
    vectorcall: cpython.vectorcallfunc, // 8 bytes - for callable proxy
};

// Verify PyWeakReference size: 16 + 8*6 = 64 bytes
comptime {
    if (@sizeOf(PyWeakReference) != 64) {
        @compileError("PyWeakReference size mismatch with CPython");
    }
}

// ============================================================================
// WEAK REFERENCE TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for weak reference
fn weakref_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const wr: *PyWeakReference = @ptrCast(@alignCast(self_obj.?));

    // Clear from list if still in one
    _PyWeakref_ClearRef(wr);

    // Decref callback
    if (wr.wr_callback) |callback| {
        callback.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(wr);
    allocator.free(ptr[0..@sizeOf(PyWeakReference)]);
}

/// Traverse for weak reference (GC)
fn weakref_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const wr: *PyWeakReference = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (wr.wr_callback) |callback| {
            const result = v(callback, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Clear for weak reference (GC)
fn weakref_clear(self_obj: ?*cpython.PyObject) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const wr: *PyWeakReference = @ptrCast(@alignCast(self_obj.?));

    _PyWeakref_ClearRef(wr);

    if (wr.wr_callback) |callback| {
        callback.ob_refcnt -= 1;
        wr.wr_callback = null;
    }

    return 0;
}

/// Repr for weak reference
fn weakref_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const wr: *PyWeakReference = @ptrCast(@alignCast(self_obj.?));

    // Format: <weakref at 0xADDR; to 'type' at 0xADDR>
    // or: <weakref at 0xADDR; dead>
    _ = wr;
    return null;
}

/// Hash for weak reference
fn weakref_hash(self_obj: ?*cpython.PyObject) callconv(.C) isize {
    if (self_obj == null) return -1;
    const wr: *PyWeakReference = @ptrCast(@alignCast(self_obj.?));

    // Use cached hash if available
    if (wr.hash != -1) {
        return wr.hash;
    }

    // Get hash from referenced object
    const obj = wr.wr_object orelse return -1;
    if (obj.ob_type.tp_hash) |hash_fn| {
        wr.hash = hash_fn(obj);
        return wr.hash;
    }

    return -1;
}

/// Rich comparison for weak reference
fn weakref_richcompare(self_obj: *cpython.PyObject, other: *cpython.PyObject, op: c_int) callconv(.C) ?*cpython.PyObject {
    if (!PyWeakref_Check(self_obj) or !PyWeakref_Check(other)) {
        return null;
    }

    const self: *PyWeakReference = @ptrCast(@alignCast(self_obj));
    const other_wr: *PyWeakReference = @ptrCast(@alignCast(other));

    // Compare referenced objects
    const self_obj_ref = self.wr_object orelse return null;
    const other_obj_ref = other_wr.wr_object orelse return null;

    if (self_obj_ref.ob_type.tp_richcompare) |cmp_fn| {
        return cmp_fn(self_obj_ref, other_obj_ref, op);
    }

    return null;
}

/// Call for weak reference (get referenced object)
fn weakref_call(self_obj: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    if (self_obj == null) return null;

    return PyWeakref_GetObject(self_obj);
}

/// _PyWeakref_RefType - the weakref.ref type object
pub export var _PyWeakref_RefType: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "weakref.ref",
    .tp_basicsize = @sizeOf(PyWeakReference),
    .tp_itemsize = 0,
    .tp_dealloc = weakref_dealloc,
    .tp_vectorcall_offset = @offsetOf(PyWeakReference, "vectorcall"),
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = weakref_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = weakref_hash,
    .tp_call = weakref_call,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "A weak reference to an object.\n\nref(ob, callback=None) -- create a weak reference to 'ob'.\nIf callback is not None, it will be called when 'ob' is about to be\nfinalized.",
    .tp_traverse = weakref_traverse,
    .tp_clear = weakref_clear,
    .tp_richcompare = weakref_richcompare,
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
};

/// _PyWeakref_ProxyType - the weakref.proxy type object
pub export var _PyWeakref_ProxyType: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "weakref.proxy",
    .tp_basicsize = @sizeOf(PyWeakReference),
    .tp_itemsize = 0,
    .tp_dealloc = weakref_dealloc,
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
    .tp_traverse = weakref_traverse,
    .tp_clear = weakref_clear,
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
};

/// _PyWeakref_CallableProxyType - the weakref.CallableProxyType type object
pub export var _PyWeakref_CallableProxyType: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "weakref.CallableProxyType",
    .tp_basicsize = @sizeOf(PyWeakReference),
    .tp_itemsize = 0,
    .tp_dealloc = weakref_dealloc,
    .tp_vectorcall_offset = @offsetOf(PyWeakReference, "vectorcall"),
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = weakref_call,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = null,
    .tp_traverse = weakref_traverse,
    .tp_clear = weakref_clear,
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
};

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// Check if object is a weak reference
pub inline fn PyWeakref_Check(obj: ?*cpython.PyObject) bool {
    if (obj == null) return false;
    return obj.?.ob_type == &_PyWeakref_RefType or
        obj.?.ob_type == &_PyWeakref_ProxyType or
        obj.?.ob_type == &_PyWeakref_CallableProxyType;
}

/// Check if object is exactly a weak reference (not a subclass)
pub inline fn PyWeakref_CheckRefExact(obj: ?*cpython.PyObject) bool {
    if (obj == null) return false;
    return obj.?.ob_type == &_PyWeakref_RefType;
}

/// Check if object is a weak proxy
pub inline fn PyWeakref_CheckProxy(obj: ?*cpython.PyObject) bool {
    if (obj == null) return false;
    return obj.?.ob_type == &_PyWeakref_ProxyType or
        obj.?.ob_type == &_PyWeakref_CallableProxyType;
}

/// Create a new weak reference
pub export fn PyWeakref_NewRef(ob: ?*cpython.PyObject, callback: ?*cpython.PyObject) ?*cpython.PyObject {
    if (ob == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyWeakReference), @sizeOf(PyWeakReference)) catch return null;
    const wr: *PyWeakReference = @ptrCast(@alignCast(mem.ptr));

    // Incref callback if provided
    if (callback) |cb| {
        cb.ob_refcnt += 1;
    }

    wr.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &_PyWeakref_RefType,
        },
        .wr_object = ob, // Stealth reference - don't incref
        .wr_callback = callback,
        .hash = -1,
        .wr_prev = null,
        .wr_next = null,
        .vectorcall = null,
    };

    // TODO: Insert into object's weakref list

    return @ptrCast(wr);
}

/// Create a new weak proxy
pub export fn PyWeakref_NewProxy(ob: ?*cpython.PyObject, callback: ?*cpython.PyObject) ?*cpython.PyObject {
    if (ob == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyWeakReference), @sizeOf(PyWeakReference)) catch return null;
    const wr: *PyWeakReference = @ptrCast(@alignCast(mem.ptr));

    // Determine if object is callable
    const is_callable = if (ob.?.ob_type.tp_call != null) true else false;

    // Incref callback if provided
    if (callback) |cb| {
        cb.ob_refcnt += 1;
    }

    wr.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = if (is_callable) &_PyWeakref_CallableProxyType else &_PyWeakref_ProxyType,
        },
        .wr_object = ob, // Stealth reference
        .wr_callback = callback,
        .hash = -1,
        .wr_prev = null,
        .wr_next = null,
        .vectorcall = if (is_callable) ob.?.ob_type.tp_vectorcall else null,
    };

    // TODO: Insert into object's weakref list

    return @ptrCast(wr);
}

/// Get object from weak reference (returns borrowed reference)
pub export fn PyWeakref_GetObject(ref: ?*cpython.PyObject) ?*cpython.PyObject {
    if (ref == null) return null;
    if (!PyWeakref_Check(ref)) return null;

    const wr: *PyWeakReference = @ptrCast(@alignCast(ref.?));

    // Return None if dead
    if (wr.wr_object == null) {
        const none = @import("noneobject.zig");
        return none._Py_NoneStruct();
    }

    // Check if object is dead (refcount 0 due to trashcan)
    if (wr.wr_object.?.ob_refcnt == 0) {
        const none = @import("noneobject.zig");
        return none._Py_NoneStruct();
    }

    return wr.wr_object;
}

/// Get object from weak reference (returns new reference)
pub export fn PyWeakref_GetRef(ref: ?*cpython.PyObject, pobj: *?*cpython.PyObject) c_int {
    if (ref == null) {
        pobj.* = null;
        return -1;
    }

    const obj = PyWeakref_GetObject(ref);
    if (obj == null) {
        pobj.* = null;
        return 0;
    }

    // Check if it's None (dead reference)
    const none = @import("noneobject.zig");
    if (obj == none._Py_NoneStruct()) {
        pobj.* = null;
        return 0;
    }

    obj.?.ob_refcnt += 1;
    pobj.* = obj;
    return 1;
}

/// Clear a weak reference (internal)
pub export fn _PyWeakref_ClearRef(self: *PyWeakReference) void {
    // Remove from doubly-linked list
    if (self.wr_prev) |prev| {
        prev.wr_next = self.wr_next;
    }
    if (self.wr_next) |next| {
        next.wr_prev = self.wr_prev;
    }

    self.wr_prev = null;
    self.wr_next = null;
    self.wr_object = null;
}

/// Check if weak reference is dead
pub export fn PyWeakref_IsDead(ref: ?*cpython.PyObject) c_int {
    if (ref == null) return 1;
    if (!PyWeakref_Check(ref)) return 1;

    const wr: *PyWeakReference = @ptrCast(@alignCast(ref.?));

    if (wr.wr_object == null) return 1;
    if (wr.wr_object.?.ob_refcnt == 0) return 1;

    return 0;
}

/// Clear all weak references to an object
pub export fn PyObject_ClearWeakRefs(obj: ?*cpython.PyObject) void {
    if (obj == null) return;

    // TODO: Iterate through object's weakref list and clear all refs
    // This requires accessing the object's tp_weaklistoffset
}
