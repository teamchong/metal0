/// Generic Alias Object Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/genericaliasobject.c
/// types.GenericAlias - used to represent e.g. list[int]
///
/// Reference: cpython/Objects/genericaliasobject.c
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// gaobject - GenericAlias object
/// Reference: cpython/Objects/genericaliasobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *origin;
///     PyObject *args;
///     PyObject *parameters;
///     PyObject *weakreflist;
///     bool starred;
///     vectorcallfunc vectorcall;
/// } gaobject;
pub const gaobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    origin: ?*cpython.PyObject, // 8 bytes - the generic type (e.g., list)
    args: ?*cpython.PyObject, // 8 bytes - type arguments tuple (e.g., (int,))
    parameters: ?*cpython.PyObject, // 8 bytes - type parameters
    weakreflist: ?*cpython.PyObject, // 8 bytes - weak references
    starred: bool, // 1 byte - whether we're a starred type, e.g. *tuple[int]
    _padding1: [7]u8 = [_]u8{0} ** 7, // 7 bytes padding
    vectorcall: cpython.vectorcallfunc, // 8 bytes
};

// Verify gaobject size: 16 + 8*4 + 1 + 7 + 8 = 64 bytes
comptime {
    if (@sizeOf(gaobject) != 64) {
        @compileError("gaobject size mismatch with CPython");
    }
}

/// gaiterobject - GenericAlias iterator
/// Reference: cpython/Objects/genericaliasobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *obj;  /* Set to NULL when iterator is exhausted */
/// } gaiterobject;
pub const gaiterobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    obj: ?*cpython.PyObject, // 8 bytes - object being iterated (NULL when exhausted)
};

// Verify gaiterobject size: 16 + 8 = 24 bytes
comptime {
    if (@sizeOf(gaiterobject) != 24) {
        @compileError("gaiterobject size mismatch with CPython");
    }
}

// ============================================================================
// GENERIC ALIAS TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for generic alias
fn ga_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const alias: *gaobject = @ptrCast(@alignCast(self_obj.?));

    // Clear weak references
    // TODO: FT_CLEAR_WEAKREFS

    // Decref origin
    if (alias.origin) |origin| {
        origin.ob_refcnt -= 1;
    }

    // Decref args
    if (alias.args) |args| {
        args.ob_refcnt -= 1;
    }

    // Decref parameters
    if (alias.parameters) |params| {
        params.ob_refcnt -= 1;
    }

    // Free the object
    const ptr: [*]u8 = @ptrCast(alias);
    allocator.free(ptr[0..@sizeOf(gaobject)]);
}

/// Traverse for generic alias (GC)
fn ga_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const alias: *gaobject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (alias.origin) |origin| {
            const result = v(origin, arg);
            if (result != 0) return result;
        }
        if (alias.args) |args| {
            const result = v(args, arg);
            if (result != 0) return result;
        }
        if (alias.parameters) |params| {
            const result = v(params, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Repr for generic alias (e.g., "list[int]")
fn ga_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const alias: *gaobject = @ptrCast(@alignCast(self_obj.?));

    // TODO: Proper implementation using _Py_typing_type_repr
    _ = alias;
    return null;
}

/// Hash for generic alias
fn ga_hash(self_obj: ?*cpython.PyObject) callconv(.C) isize {
    if (self_obj == null) return -1;
    const alias: *gaobject = @ptrCast(@alignCast(self_obj.?));

    // Hash is based on origin and args
    var hash: isize = 0;

    if (alias.origin) |origin| {
        const origin_hash = if (origin.ob_type.tp_hash) |hash_fn|
            hash_fn(origin)
        else
            @as(isize, @intCast(@intFromPtr(origin)));
        hash ^= origin_hash;
    }

    if (alias.args) |args| {
        const args_hash = if (args.ob_type.tp_hash) |hash_fn|
            hash_fn(args)
        else
            @as(isize, @intCast(@intFromPtr(args)));
        hash ^= args_hash;
    }

    if (hash == -1) hash = -2;
    return hash;
}

/// Call generic alias (instantiation)
fn ga_call(self_obj: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const alias: *gaobject = @ptrCast(@alignCast(self_obj.?));

    // Delegate to origin's __call__
    if (alias.origin) |origin| {
        if (origin.ob_type.tp_call) |call_fn| {
            return call_fn(origin, args, kwargs);
        }
    }
    return null;
}

/// Get item (subscript) for generic alias
fn ga_getitem(self_obj: *cpython.PyObject, item: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = self_obj;
    _ = item;
    // TODO: Implement generic alias subscripting for nested generics
    return null;
}

/// Instance check (__instancecheck__)
fn ga_instancecheck(self_obj: ?*cpython.PyObject, instance: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null or instance == null) return null;
    const alias: *gaobject = @ptrCast(@alignCast(self_obj.?));

    // Check if instance is an instance of origin
    if (alias.origin) |origin| {
        // TODO: PyObject_IsInstance
        _ = origin;
    }

    // Return False by default
    const pybool = @import("boolobject.zig");
    return pybool.Py_False;
}

/// Subclass check (__subclasscheck__)
fn ga_subclasscheck(self_obj: ?*cpython.PyObject, subclass: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null or subclass == null) return null;
    const alias: *gaobject = @ptrCast(@alignCast(self_obj.?));

    // Check if subclass is a subclass of origin
    if (alias.origin) |origin| {
        // TODO: PyObject_IsSubclass
        _ = origin;
    }

    // Return False by default
    const pybool = @import("boolobject.zig");
    return pybool.Py_False;
}

// Mapping methods for subscript
var ga_as_mapping: cpython.PyMappingMethods = .{
    .mp_length = null,
    .mp_subscript = ga_getitem,
    .mp_ass_subscript = null,
};

/// PyGenericAlias_Type - the GenericAlias type object
pub export var Py_GenericAliasType: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "types.GenericAlias",
    .tp_basicsize = @sizeOf(gaobject),
    .tp_itemsize = 0,
    .tp_dealloc = ga_dealloc,
    .tp_vectorcall_offset = @offsetOf(gaobject, "vectorcall"),
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = ga_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = &ga_as_mapping,
    .tp_hash = ga_hash,
    .tp_call = ga_call,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "Represent a PEP 585 generic type\n\ne.g. for t = list[int], t.__origin__ is list and t.__args__ is (int,).",
    .tp_traverse = ga_traverse,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(gaobject, "weakreflist"),
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
// GENERIC ALIAS ITERATOR IMPLEMENTATION
// ============================================================================

/// Dealloc for iterator
fn gaiter_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const iter: *gaiterobject = @ptrCast(@alignCast(self_obj.?));

    if (iter.obj) |obj| {
        obj.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(iter);
    allocator.free(ptr[0..@sizeOf(gaiterobject)]);
}

/// Traverse for iterator (GC)
fn gaiter_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const iter: *gaiterobject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (iter.obj) |obj| {
            const result = v(obj, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Iterator self-return
fn gaiter_iter(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    self_obj.?.ob_refcnt += 1;
    return self_obj;
}

/// Get next from iterator
fn gaiter_next(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const iter: *gaiterobject = @ptrCast(@alignCast(self_obj.?));

    if (iter.obj == null) return null;

    // TODO: Get next item from args tuple
    return null;
}

/// Py_GenericAliasIterType - the GenericAlias iterator type object
pub export var Py_GenericAliasIterType: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "generic_alias_iterator",
    .tp_basicsize = @sizeOf(gaiterobject),
    .tp_itemsize = 0,
    .tp_dealloc = gaiter_dealloc,
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
    .tp_traverse = gaiter_traverse,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = gaiter_iter,
    .tp_iternext = gaiter_next,
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

/// Create a new GenericAlias object
/// This is the Py_GenericAlias function used by types for __class_getitem__
pub export fn Py_GenericAlias(origin: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    if (origin == null or args == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(gaobject), @sizeOf(gaobject)) catch return null;
    const alias: *gaobject = @ptrCast(@alignCast(mem.ptr));

    // Ensure args is a tuple
    var args_tuple: ?*cpython.PyObject = args;
    const pytuple = @import("tupleobject.zig");

    if (!pytuple.PyTuple_Check(args.?)) {
        // Wrap single argument in tuple
        args_tuple = pytuple.PyTuple_Pack(1, args.?);
        if (args_tuple == null) {
            allocator.free(mem);
            return null;
        }
    } else {
        args.?.ob_refcnt += 1;
    }

    // Incref origin
    origin.?.ob_refcnt += 1;

    alias.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &Py_GenericAliasType,
        },
        .origin = origin,
        .args = args_tuple,
        .parameters = null, // Will be computed lazily
        .weakreflist = null,
        .starred = false,
        .vectorcall = null,
    };

    return @ptrCast(alias);
}

/// Check if object is a GenericAlias
pub export fn _PyGenericAlias_Check(obj: ?*cpython.PyObject) c_int {
    if (obj == null) return 0;
    return if (obj.?.ob_type == &Py_GenericAliasType) 1 else 0;
}

/// Make parameters tuple from args
/// Used internally to extract type parameters from generic args
pub export fn _Py_make_parameters(args: ?*cpython.PyObject) ?*cpython.PyObject {
    if (args == null) return null;

    const pytuple = @import("tupleobject.zig");
    const nargs = pytuple.PyTuple_Size(args.?);
    if (nargs < 0) return null;

    // Create parameters tuple
    const parameters = pytuple.PyTuple_New(nargs);
    if (parameters == null) return null;

    var iparam: isize = 0;
    var iarg: isize = 0;
    while (iarg < nargs) : (iarg += 1) {
        const arg = pytuple.PyTuple_GetItem(args.?, iarg);
        if (arg == null) continue;

        // TODO: Check if arg is a TypeVar or ParamSpec
        // For now, just add all args as parameters
        arg.?.ob_refcnt += 1;
        _ = pytuple.PyTuple_SetItem(parameters.?, iparam, arg.?);
        iparam += 1;
    }

    // Resize tuple to actual parameter count
    // TODO: _PyTuple_Resize

    return parameters;
}

/// Substitute type parameters
pub export fn _Py_subs_parameters(
    self: ?*cpython.PyObject,
    args: ?*cpython.PyObject,
    parameters: ?*cpython.PyObject,
    item: ?*cpython.PyObject,
) ?*cpython.PyObject {
    _ = self;
    _ = args;
    _ = parameters;
    _ = item;
    // TODO: Implement type parameter substitution
    return null;
}
