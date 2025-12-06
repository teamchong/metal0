/// Namespace Object Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/namespaceobject.c
/// types.SimpleNamespace - a simple object subclass with attribute access
///
/// Reference: cpython/Objects/namespaceobject.c
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// _PyNamespaceObject - SimpleNamespace object
/// Reference: cpython/Objects/namespaceobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *ns_dict;
/// } _PyNamespaceObject;
pub const _PyNamespaceObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    ns_dict: ?*cpython.PyObject, // 8 bytes - namespace dictionary
};

// Verify _PyNamespaceObject size: 16 + 8 = 24 bytes
comptime {
    if (@sizeOf(_PyNamespaceObject) != 24) {
        @compileError("_PyNamespaceObject size mismatch with CPython");
    }
}

// ============================================================================
// NAMESPACE TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for namespace
fn namespace_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const ns: *_PyNamespaceObject = @ptrCast(@alignCast(self_obj.?));

    if (ns.ns_dict) |dict| {
        dict.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(ns);
    allocator.free(ptr[0..@sizeOf(_PyNamespaceObject)]);
}

/// Traverse for namespace (GC)
fn namespace_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const ns: *_PyNamespaceObject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (ns.ns_dict) |dict| {
            const result = v(dict, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Clear for namespace (GC)
fn namespace_clear(self_obj: ?*cpython.PyObject) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const ns: *_PyNamespaceObject = @ptrCast(@alignCast(self_obj.?));

    if (ns.ns_dict) |dict| {
        dict.ob_refcnt -= 1;
        ns.ns_dict = null;
    }
    return 0;
}

/// Repr for namespace
fn namespace_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const ns: *_PyNamespaceObject = @ptrCast(@alignCast(self_obj.?));

    // TODO: Format as "namespace(key=value, ...)"
    _ = ns;
    return null;
}

/// Rich comparison for namespace
fn namespace_richcompare(self_obj: *cpython.PyObject, other: *cpython.PyObject, op: c_int) callconv(.C) ?*cpython.PyObject {
    if (self_obj.ob_type != &_PyNamespace_Type or other.ob_type != &_PyNamespace_Type) {
        // Return NotImplemented
        return null;
    }

    const self: *_PyNamespaceObject = @ptrCast(@alignCast(self_obj));
    const other_ns: *_PyNamespaceObject = @ptrCast(@alignCast(other));

    // Compare dictionaries
    if (self.ns_dict != null and other_ns.ns_dict != null) {
        // TODO: PyObject_RichCompare for dicts
        _ = op;
    }

    return null;
}

/// Init for namespace
fn namespace_init(self_obj: *cpython.PyObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) c_int {
    const ns: *_PyNamespaceObject = @ptrCast(@alignCast(self_obj));
    _ = args;

    // Create empty dict if needed
    if (ns.ns_dict == null) {
        const pydict = @import("dictobject.zig");
        ns.ns_dict = pydict.PyDict_New();
        if (ns.ns_dict == null) return -1;
    }

    // Update with kwargs if provided
    if (kwargs) |kw| {
        // TODO: PyDict_Update
        _ = kw;
    }

    return 0;
}

/// New for namespace
fn namespace_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = args;
    _ = kwargs;

    const mem = allocator.alignedAlloc(u8, @alignOf(_PyNamespaceObject), @sizeOf(_PyNamespaceObject)) catch return null;
    const ns: *_PyNamespaceObject = @ptrCast(@alignCast(mem.ptr));

    ns.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &_PyNamespace_Type,
        },
        .ns_dict = null,
    };

    return @ptrCast(ns);
}

/// _PyNamespace_Type - the SimpleNamespace type object
pub export var _PyNamespace_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "types.SimpleNamespace",
    .tp_basicsize = @sizeOf(_PyNamespaceObject),
    .tp_itemsize = 0,
    .tp_dealloc = namespace_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = namespace_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null, // Uses default
    .tp_setattro = null, // Uses default
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "A simple attribute-based namespace.\n\nSimpleNamespace(**kwargs)",
    .tp_traverse = namespace_traverse,
    .tp_clear = namespace_clear,
    .tp_richcompare = namespace_richcompare,
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
    .tp_dictoffset = @offsetOf(_PyNamespaceObject, "ns_dict"),
    .tp_init = namespace_init,
    .tp_alloc = null,
    .tp_new = namespace_new,
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

/// Create a new SimpleNamespace object
pub export fn _PyNamespace_New(dict: ?*cpython.PyObject) ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(_PyNamespaceObject), @sizeOf(_PyNamespaceObject)) catch return null;
    const ns: *_PyNamespaceObject = @ptrCast(@alignCast(mem.ptr));

    var ns_dict = dict;
    if (ns_dict == null) {
        const pydict = @import("dictobject.zig");
        ns_dict = pydict.PyDict_New();
        if (ns_dict == null) {
            allocator.free(mem);
            return null;
        }
    } else {
        ns_dict.?.ob_refcnt += 1;
    }

    ns.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &_PyNamespace_Type,
        },
        .ns_dict = ns_dict,
    };

    return @ptrCast(ns);
}
