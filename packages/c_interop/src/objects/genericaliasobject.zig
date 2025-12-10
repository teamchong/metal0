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
///     Py_ssize_t it_index;  /* Current index */
/// } gaiterobject;
pub const gaiterobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    obj: ?*cpython.PyObject, // 8 bytes - object being iterated (NULL when exhausted)
    it_index: isize, // 8 bytes - current iteration index
};

// Verify gaiterobject size: 16 + 8 + 8 = 32 bytes
comptime {
    if (@sizeOf(gaiterobject) != 32) {
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

    const pyunicode = @import("unicodeobject.zig");
    const pytuple = @import("tupleobject.zig");

    // Build representation as "origin[arg1, arg2, ...]"
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;

    // Add starred prefix if needed
    if (alias.starred) {
        buf[pos] = '*';
        pos += 1;
    }

    // Get origin name
    if (alias.origin) |origin| {
        const origin_type: *cpython.PyTypeObject = @ptrCast(@alignCast(origin));
        if (origin_type.tp_name != null) {
            const name = std.mem.span(origin_type.tp_name.?);
            const len = @min(name.len, buf.len - pos);
            @memcpy(buf[pos..][0..len], name[0..len]);
            pos += len;
        }
    }

    // Add opening bracket
    if (pos < buf.len) {
        buf[pos] = '[';
        pos += 1;
    }

    // Add args
    if (alias.args) |args| {
        const size = pytuple.PyTuple_Size(args);
        for (0..@intCast(size)) |i| {
            if (i > 0 and pos + 2 < buf.len) {
                buf[pos] = ',';
                buf[pos + 1] = ' ';
                pos += 2;
            }

            const item = pytuple.PyTuple_GetItem(args, @intCast(i));
            if (item == null) continue;

            // Get repr for this type
            var name_buf: [256]u8 = undefined;
            const name_slice = getTypeRepr(item.?, &name_buf);

            if (pos + name_slice.len < buf.len) {
                @memcpy(buf[pos..][0..name_slice.len], name_slice);
                pos += name_slice.len;
            }
        }
    }

    // Add closing bracket
    if (pos < buf.len) {
        buf[pos] = ']';
        pos += 1;
    }

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(pos));
}

/// Get the repr name for a type object
fn getTypeRepr(obj: *cpython.PyObject, buf: []u8) []const u8 {
    // If it's a type, get tp_name
    const type_obj: *cpython.PyTypeObject = @ptrCast(@alignCast(obj));
    if (type_obj.tp_name != null) {
        const name = std.mem.span(type_obj.tp_name.?);
        const len = @min(name.len, buf.len);
        @memcpy(buf[0..len], name[0..len]);
        return buf[0..len];
    }

    // Fall back to repr
    if (obj.ob_type.tp_repr) |repr_fn| {
        const repr_obj = repr_fn(obj);
        if (repr_obj) |r| {
            defer r.ob_refcnt -= 1;
            const pyunicode = @import("unicodeobject.zig");
            const str = pyunicode.PyUnicode_AsUTF8(r);
            if (str != null) {
                const s = std.mem.span(str.?);
                const len = @min(s.len, buf.len);
                @memcpy(buf[0..len], s[0..len]);
                return buf[0..len];
            }
        }
    }

    const default = "<type>";
    @memcpy(buf[0..default.len], default);
    return buf[0..default.len];
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

/// Get item (subscript) for generic alias - creates nested generic like list[int][str]
fn ga_getitem(self_obj: *cpython.PyObject, item: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    const alias: *gaobject = @ptrCast(@alignCast(self_obj));

    // Get parameters of this generic alias
    const parameters = alias.parameters orelse {
        // No type parameters to substitute - this shouldn't happen normally but handle it
        return Py_GenericAlias(alias.origin, item);
    };

    const pytuple = @import("tupleobject.zig");
    const params_count = pytuple.PyTuple_Size(parameters);

    if (params_count == 0) {
        // No parameters to substitute
        return Py_GenericAlias(alias.origin, item);
    }

    // Get the substitution items
    var items_tuple: ?*cpython.PyObject = null;
    var items_count: isize = 0;

    if (pytuple.PyTuple_Check(item) != 0) {
        items_tuple = item;
        items_count = pytuple.PyTuple_Size(item);
    } else {
        items_count = 1;
    }

    // Check we have the right number of items
    if (items_count != params_count) {
        // Wrong number of type arguments - in CPython this raises TypeError
        // For now, just return null
        return null;
    }

    // Substitute type parameters in args
    const args_count = pytuple.PyTuple_Size(alias.args orelse return null);
    const new_args = pytuple.PyTuple_New(args_count);
    if (new_args == null) return null;

    for (0..@intCast(args_count)) |i| {
        const arg = pytuple.PyTuple_GetItem(alias.args.?, @intCast(i));
        if (arg == null) continue;

        // Check if this arg is one of our parameters
        var substituted = false;
        for (0..@intCast(params_count)) |j| {
            const param = pytuple.PyTuple_GetItem(parameters, @intCast(j));
            if (param != null and param.? == arg.?) {
                // Substitute with corresponding item
                const replacement = if (items_tuple) |it|
                    pytuple.PyTuple_GetItem(it, @intCast(j))
                else
                    item;

                if (replacement) |r| {
                    r.ob_refcnt += 1;
                    _ = pytuple.PyTuple_SetItem(new_args, @intCast(i), r);
                    substituted = true;
                }
                break;
            }
        }

        if (!substituted) {
            // Keep original arg
            arg.?.ob_refcnt += 1;
            _ = pytuple.PyTuple_SetItem(new_args, @intCast(i), arg.?);
        }
    }

    return Py_GenericAlias(alias.origin, new_args);
}

/// Instance check (__instancecheck__)
fn ga_instancecheck(self_obj: ?*cpython.PyObject, instance: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null or instance == null) return null;
    const alias: *gaobject = @ptrCast(@alignCast(self_obj.?));
    const pybool = @import("boolobject.zig");

    // Check if instance is an instance of origin (ignoring type args)
    if (alias.origin) |origin| {
        const origin_type: *cpython.PyTypeObject = @ptrCast(@alignCast(origin));
        const typeobj = @import("typeobject.zig");

        // Check if instance's type is a subtype of origin
        if (typeobj.PyType_IsSubtype(instance.?.ob_type, origin_type) != 0) {
            return pybool.Py_True;
        }
    }

    return pybool.Py_False;
}

/// Subclass check (__subclasscheck__)
fn ga_subclasscheck(self_obj: ?*cpython.PyObject, subclass: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null or subclass == null) return null;
    const alias: *gaobject = @ptrCast(@alignCast(self_obj.?));
    const pybool = @import("boolobject.zig");

    // Check if subclass is a subclass of origin (ignoring type args)
    if (alias.origin) |origin| {
        const origin_type: *cpython.PyTypeObject = @ptrCast(@alignCast(origin));
        const subclass_type: *cpython.PyTypeObject = @ptrCast(@alignCast(subclass.?));
        const typeobj = @import("typeobject.zig");

        if (typeobj.PyType_IsSubtype(subclass_type, origin_type) != 0) {
            return pybool.Py_True;
        }
    }

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

    // Get args from the generic alias object
    const alias: *gaobject = @ptrCast(@alignCast(iter.obj.?));
    const args = alias.args orelse return null;

    const pytuple = @import("tupleobject.zig");
    const size = pytuple.PyTuple_Size(args);

    // Check if iterator is exhausted
    if (iter.it_index >= size) {
        // Mark as exhausted
        iter.obj.?.ob_refcnt -= 1;
        iter.obj = null;
        return null;
    }

    // Get next item
    const item = pytuple.PyTuple_GetItem(args, iter.it_index);
    iter.it_index += 1;

    if (item) |i| {
        i.ob_refcnt += 1;
        return i;
    }
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
    const typevar = @import("typevarobject.zig");
    const nargs = pytuple.PyTuple_Size(args.?);
    if (nargs < 0) return null;

    // First pass: count actual type parameters (TypeVar, ParamSpec, TypeVarTuple)
    var param_count: isize = 0;
    var iarg: isize = 0;
    while (iarg < nargs) : (iarg += 1) {
        const arg = pytuple.PyTuple_GetItem(args.?, iarg);
        if (arg == null) continue;

        // Check if arg is a TypeVar, ParamSpec, or TypeVarTuple
        if (arg.?.ob_type == &typevar.PyTypeVar_Type or
            arg.?.ob_type == &typevar.PyParamSpec_Type or
            arg.?.ob_type == &typevar.PyTypeVarTuple_Type)
        {
            param_count += 1;
        }
        // Also check for generic aliases that have __parameters__
        else if (_PyGenericAlias_Check(arg) != 0) {
            const nested: *gaobject = @ptrCast(@alignCast(arg.?));
            if (nested.parameters) |nested_params| {
                param_count += pytuple.PyTuple_Size(nested_params);
            }
        }
    }

    if (param_count == 0) return null;

    // Create parameters tuple with exact size
    const parameters = pytuple.PyTuple_New(param_count);
    if (parameters == null) return null;

    // Second pass: collect type parameters
    var iparam: isize = 0;
    iarg = 0;
    while (iarg < nargs) : (iarg += 1) {
        const arg = pytuple.PyTuple_GetItem(args.?, iarg);
        if (arg == null) continue;

        // Check if arg is a TypeVar, ParamSpec, or TypeVarTuple
        if (arg.?.ob_type == &typevar.PyTypeVar_Type or
            arg.?.ob_type == &typevar.PyParamSpec_Type or
            arg.?.ob_type == &typevar.PyTypeVarTuple_Type)
        {
            arg.?.ob_refcnt += 1;
            _ = pytuple.PyTuple_SetItem(parameters.?, iparam, arg.?);
            iparam += 1;
        }
        // Also collect from nested generic aliases
        else if (_PyGenericAlias_Check(arg) != 0) {
            const nested: *gaobject = @ptrCast(@alignCast(arg.?));
            if (nested.parameters) |nested_params| {
                const nested_size = pytuple.PyTuple_Size(nested_params);
                var j: isize = 0;
                while (j < nested_size) : (j += 1) {
                    const nested_param = pytuple.PyTuple_GetItem(nested_params, j);
                    if (nested_param) |np| {
                        // Check for duplicates
                        var is_dup = false;
                        var k: isize = 0;
                        while (k < iparam) : (k += 1) {
                            if (pytuple.PyTuple_GetItem(parameters.?, k) == np) {
                                is_dup = true;
                                break;
                            }
                        }
                        if (!is_dup and iparam < param_count) {
                            np.ob_refcnt += 1;
                            _ = pytuple.PyTuple_SetItem(parameters.?, iparam, np);
                            iparam += 1;
                        }
                    }
                }
            }
        }
    }

    return parameters;
}

/// Substitute type parameters
/// self: the GenericAlias object
/// args: the args tuple from the GenericAlias
/// parameters: the type parameters to substitute
/// item: the substitution value(s) (single value or tuple)
pub export fn _Py_subs_parameters(
    self: ?*cpython.PyObject,
    args: ?*cpython.PyObject,
    parameters: ?*cpython.PyObject,
    item: ?*cpython.PyObject,
) ?*cpython.PyObject {
    if (self == null or args == null or parameters == null or item == null) return null;

    const pytuple = @import("tupleobject.zig");
    const nparams = pytuple.PyTuple_Size(parameters.?);
    const nargs = pytuple.PyTuple_Size(args.?);

    if (nparams <= 0) {
        // No parameters to substitute
        args.?.ob_refcnt += 1;
        return args;
    }

    // Get items as tuple (normalize single value to tuple)
    var items_tuple: ?*cpython.PyObject = null;
    var nitems: isize = 0;
    var owns_items_tuple = false;

    if (pytuple.PyTuple_Check(item.?) != 0) {
        items_tuple = item;
        nitems = pytuple.PyTuple_Size(item.?);
    } else {
        items_tuple = pytuple.PyTuple_Pack(1, item.?);
        owns_items_tuple = true;
        nitems = 1;
    }

    defer {
        if (owns_items_tuple and items_tuple != null) {
            items_tuple.?.ob_refcnt -= 1;
        }
    }

    // Must have same number of items as parameters
    if (nitems != nparams) {
        // TypeError: wrong number of arguments
        return null;
    }

    // Create new args tuple with substituted values
    const new_args = pytuple.PyTuple_New(nargs);
    if (new_args == null) return null;

    var i: isize = 0;
    while (i < nargs) : (i += 1) {
        const arg = pytuple.PyTuple_GetItem(args.?, i);
        if (arg == null) continue;

        var substituted = false;

        // Check if this arg matches any parameter
        var j: isize = 0;
        while (j < nparams) : (j += 1) {
            const param = pytuple.PyTuple_GetItem(parameters.?, j);
            if (param != null and param.? == arg.?) {
                // Substitute with corresponding item
                const subst_val = pytuple.PyTuple_GetItem(items_tuple.?, j);
                if (subst_val) |sv| {
                    sv.ob_refcnt += 1;
                    _ = pytuple.PyTuple_SetItem(new_args.?, i, sv);
                    substituted = true;
                }
                break;
            }
        }

        // If arg is itself a GenericAlias, recursively substitute its parameters
        if (!substituted and _PyGenericAlias_Check(arg) != 0) {
            const nested: *gaobject = @ptrCast(@alignCast(arg.?));
            if (nested.parameters != null and nested.args != null) {
                const substituted_nested = _Py_subs_parameters(
                    arg,
                    nested.args,
                    nested.parameters,
                    item,
                );
                if (substituted_nested) |sn| {
                    // Create new generic alias with substituted args
                    const new_nested = Py_GenericAlias(nested.origin, sn);
                    sn.ob_refcnt -= 1;
                    if (new_nested) |nn| {
                        _ = pytuple.PyTuple_SetItem(new_args.?, i, nn);
                        substituted = true;
                    }
                }
            }
        }

        if (!substituted) {
            // Keep original arg
            arg.?.ob_refcnt += 1;
            _ = pytuple.PyTuple_SetItem(new_args.?, i, arg.?);
        }
    }

    return new_args;
}
