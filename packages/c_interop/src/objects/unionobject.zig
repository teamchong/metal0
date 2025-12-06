/// Union Object Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/unionobject.c
/// UnionType for PEP 604 union syntax: int | str
///
/// Reference: cpython/Objects/unionobject.c
///            cpython/Include/cpython/unionobject.h
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// unionobject - Union type for PEP 604
/// Reference: cpython/Objects/unionobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *args;
///     PyObject *parameters;
/// } unionobject;
pub const unionobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    args: ?*cpython.PyObject, // 8 bytes - tuple of types in the union
    parameters: ?*cpython.PyObject, // 8 bytes - tuple of type params (for Generic[T] | Generic[S])
};

// Verify unionobject size: 16 + 8 + 8 = 32 bytes
comptime {
    if (@sizeOf(unionobject) != 32) {
        @compileError("unionobject size mismatch with CPython");
    }
}

// ============================================================================
// UNION TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for union type
fn union_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const u: *unionobject = @ptrCast(@alignCast(self_obj.?));

    if (u.args) |args| args.ob_refcnt -= 1;
    if (u.parameters) |params| params.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(u);
    allocator.free(ptr[0..@sizeOf(unionobject)]);
}

/// Repr for union type (e.g., "int | str")
fn union_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const u: *unionobject = @ptrCast(@alignCast(self_obj.?));

    if (u.args == null) {
        const pyunicode = @import("unicodeobject.zig");
        return pyunicode.PyUnicode_FromString("Union");
    }

    // Build repr by joining type reprs with " | "
    // TODO: Properly format all args
    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("... | ...");
}

/// Hash for union type
fn union_hash(self_obj: ?*cpython.PyObject) callconv(.C) isize {
    if (self_obj == null) return -1;
    const u: *unionobject = @ptrCast(@alignCast(self_obj.?));

    // Hash based on args tuple
    if (u.args) |args| {
        if (args.ob_type.tp_hash) |hash_fn| {
            return hash_fn(args);
        }
    }

    return -1;
}

/// Traverse for union type (GC)
fn union_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const u: *unionobject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (u.args) |args| {
            const result = v(args, arg);
            if (result != 0) return result;
        }
        if (u.parameters) |params| {
            const result = v(params, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Clear for union type (GC)
fn union_clear(self_obj: ?*cpython.PyObject) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const u: *unionobject = @ptrCast(@alignCast(self_obj.?));

    if (u.args) |args| {
        args.ob_refcnt -= 1;
        u.args = null;
    }
    if (u.parameters) |params| {
        params.ob_refcnt -= 1;
        u.parameters = null;
    }
    return 0;
}

/// Rich comparison for union type
fn union_richcompare(self_obj: *cpython.PyObject, other: *cpython.PyObject, op: c_int) callconv(.C) ?*cpython.PyObject {
    const pybool = @import("boolobject.zig");
    const object_mod = @import("object.zig");

    // Only support == and !=
    if (op != object_mod.Py_EQ and op != object_mod.Py_NE) {
        return &object_mod._Py_NotImplementedStruct;
    }

    // Must be another union
    if (other.ob_type != &PyUnion_Type) {
        if (op == object_mod.Py_EQ) return pybool.Py_False;
        return pybool.Py_True;
    }

    const u1: *unionobject = @ptrCast(@alignCast(self_obj));
    const u2: *unionobject = @ptrCast(@alignCast(other));

    // Compare args tuples
    // Two unions are equal if they have the same set of types (order doesn't matter)
    if (u1.args == null and u2.args == null) {
        if (op == object_mod.Py_EQ) return pybool.Py_True;
        return pybool.Py_False;
    }
    if (u1.args == null or u2.args == null) {
        if (op == object_mod.Py_EQ) return pybool.Py_False;
        return pybool.Py_True;
    }

    // TODO: Compare as sets (unordered comparison)
    // For now, just compare tuples directly
    const result = object_mod.PyObject_RichCompareBool(u1.args, u2.args, op);
    if (result < 0) return null;
    if (result != 0) return pybool.Py_True;
    return pybool.Py_False;
}

/// getattro for union type
fn union_getattro(self_obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    const u: *unionobject = @ptrCast(@alignCast(self_obj));
    const pyunicode = @import("unicodeobject.zig");

    // Check for special attributes
    const name_str = pyunicode.PyUnicode_AsUTF8(name);
    if (name_str == null) return null;

    const name_len = std.mem.len(name_str.?);

    // __args__
    if (name_len == 8 and std.mem.eql(u8, name_str.?[0..8], "__args__")) {
        if (u.args) |args| {
            args.ob_refcnt += 1;
            return args;
        }
        // Return empty tuple
        return null;
    }

    // __parameters__
    if (name_len == 14 and std.mem.eql(u8, name_str.?[0..14], "__parameters__")) {
        if (u.parameters) |params| {
            params.ob_refcnt += 1;
            return params;
        }
        // Return empty tuple
        return null;
    }

    // __origin__
    if (name_len == 10 and std.mem.eql(u8, name_str.?[0..10], "__origin__")) {
        // Return types.UnionType
        const type_obj: *cpython.PyObject = @ptrCast(&PyUnion_Type);
        type_obj.ob_refcnt += 1;
        return type_obj;
    }

    return null;
}

/// or (|) operator for union type - create new union
fn union_or(self_obj: *cpython.PyObject, other: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    return _Py_union_type_or(self_obj, other);
}

/// Number methods for union type
var union_as_number = cpython.PyNumberMethods{
    .nb_or = union_or,
};

/// PyUnion_Type - the Union type object
pub export var PyUnion_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "types.UnionType",
    .tp_basicsize = @sizeOf(unionobject),
    .tp_itemsize = 0,
    .tp_dealloc = union_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = union_repr,
    .tp_as_number = &union_as_number,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = union_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = union_getattro,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Represent a union of types.\n\nE.g. for Union[int, str] or the shorthand int | str.",
    .tp_traverse = union_traverse,
    .tp_clear = union_clear,
    .tp_richcompare = union_richcompare,
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
    .tp_new = null, // Cannot be directly instantiated
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

/// Check if object is a union type
pub export fn _PyUnion_Check(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    return if (op.?.ob_type == &PyUnion_Type) 1 else 0;
}

/// Create a new union type from two operands
pub export fn _Py_union_type_or(self_obj: ?*cpython.PyObject, other: ?*cpython.PyObject) ?*cpython.PyObject {
    if (self_obj == null or other == null) return null;

    // Flatten existing unions and create new tuple of args
    var args_list: [32]?*cpython.PyObject = undefined;
    var count: usize = 0;

    // Collect args from self
    if (_PyUnion_Check(self_obj.?) != 0) {
        const u: *unionobject = @ptrCast(@alignCast(self_obj.?));
        if (u.args) |args| {
            // Iterate tuple
            const tuple = @import("tupleobject.zig");
            const size = tuple.PyTuple_Size(args);
            for (0..@intCast(size)) |i| {
                if (count >= args_list.len) break;
                args_list[count] = tuple.PyTuple_GetItem(args, @intCast(i));
                count += 1;
            }
        }
    } else {
        if (count < args_list.len) {
            args_list[count] = self_obj;
            count += 1;
        }
    }

    // Collect args from other
    if (_PyUnion_Check(other.?) != 0) {
        const u: *unionobject = @ptrCast(@alignCast(other.?));
        if (u.args) |args| {
            const tuple = @import("tupleobject.zig");
            const size = tuple.PyTuple_Size(args);
            for (0..@intCast(size)) |i| {
                if (count >= args_list.len) break;
                args_list[count] = tuple.PyTuple_GetItem(args, @intCast(i));
                count += 1;
            }
        }
    } else {
        if (count < args_list.len) {
            args_list[count] = other;
            count += 1;
        }
    }

    // TODO: Deduplicate types in args_list

    // Create new tuple from args
    const tuple = @import("tupleobject.zig");
    const args_tuple = tuple.PyTuple_New(@intCast(count));
    if (args_tuple == null) return null;

    for (0..count) |i| {
        if (args_list[i]) |item| {
            item.ob_refcnt += 1;
            tuple.PyTuple_SetItem(args_tuple, @intCast(i), item);
        }
    }

    // Create new union object
    return _Py_union_new(args_tuple);
}

/// Create a new union from args tuple
pub export fn _Py_union_new(args: ?*cpython.PyObject) ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(unionobject), @sizeOf(unionobject)) catch return null;
    const u: *unionobject = @ptrCast(@alignCast(mem.ptr));

    u.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyUnion_Type,
        },
        .args = args,
        .parameters = null,
    };

    if (args) |a| {
        a.ob_refcnt += 1;
    }

    // Extract type parameters from args
    u.parameters = extract_type_parameters(args);

    return @ptrCast(u);
}

/// Extract type parameters from union args
fn extract_type_parameters(args: ?*cpython.PyObject) ?*cpython.PyObject {
    if (args == null) return null;

    // Collect all TypeVar, ParamSpec, TypeVarTuple from args
    var params_list: [16]?*cpython.PyObject = undefined;
    var count: usize = 0;

    const tuple = @import("tupleobject.zig");
    const typevar = @import("typevarobject.zig");
    const size = tuple.PyTuple_Size(args.?);

    for (0..@intCast(size)) |i| {
        const item = tuple.PyTuple_GetItem(args.?, @intCast(i));
        if (item == null) continue;

        // Check if it's a TypeVar, ParamSpec, or TypeVarTuple
        if (item.?.ob_type == &typevar.PyTypeVar_Type or
            item.?.ob_type == &typevar.PyParamSpec_Type or
            item.?.ob_type == &typevar.PyTypeVarTuple_Type)
        {
            if (count < params_list.len) {
                params_list[count] = item;
                count += 1;
            }
        }

        // Also check for Generic aliases that have parameters
        // TODO: Check __parameters__ of generic aliases
    }

    if (count == 0) return null;

    // Create tuple of parameters
    const params_tuple = tuple.PyTuple_New(@intCast(count));
    if (params_tuple == null) return null;

    for (0..count) |i| {
        if (params_list[i]) |item| {
            item.ob_refcnt += 1;
            tuple.PyTuple_SetItem(params_tuple, @intCast(i), item);
        }
    }

    return params_tuple;
}

/// Get the args tuple from a union
pub export fn _Py_union_args(union_obj: ?*cpython.PyObject) ?*cpython.PyObject {
    if (union_obj == null) return null;
    if (_PyUnion_Check(union_obj.?) == 0) return null;

    const u: *unionobject = @ptrCast(@alignCast(union_obj.?));
    if (u.args) |args| {
        args.ob_refcnt += 1;
        return args;
    }
    return null;
}

/// Check if a value is an instance of any type in the union
pub export fn _Py_union_isinstance(union_obj: ?*cpython.PyObject, instance: ?*cpython.PyObject) c_int {
    if (union_obj == null or instance == null) return -1;
    if (_PyUnion_Check(union_obj.?) == 0) return -1;

    const u: *unionobject = @ptrCast(@alignCast(union_obj.?));
    if (u.args == null) return 0;

    const tuple = @import("tupleobject.zig");
    const size = tuple.PyTuple_Size(u.args.?);

    for (0..@intCast(size)) |i| {
        const type_item = tuple.PyTuple_GetItem(u.args.?, @intCast(i));
        if (type_item == null) continue;

        // Check isinstance
        const type_obj = @import("typeobject.zig");
        const type_ptr: *cpython.PyTypeObject = @ptrCast(@alignCast(type_item.?));
        if (type_obj.PyType_IsSubtype(instance.?.ob_type, type_ptr) != 0) {
            return 1;
        }
    }

    return 0;
}

/// Check if a type is a subclass of any type in the union
pub export fn _Py_union_issubclass(union_obj: ?*cpython.PyObject, cls: ?*cpython.PyTypeObject) c_int {
    if (union_obj == null or cls == null) return -1;
    if (_PyUnion_Check(union_obj.?) == 0) return -1;

    const u: *unionobject = @ptrCast(@alignCast(union_obj.?));
    if (u.args == null) return 0;

    const tuple = @import("tupleobject.zig");
    const size = tuple.PyTuple_Size(u.args.?);

    for (0..@intCast(size)) |i| {
        const type_item = tuple.PyTuple_GetItem(u.args.?, @intCast(i));
        if (type_item == null) continue;

        const type_obj = @import("typeobject.zig");
        const type_ptr: *cpython.PyTypeObject = @ptrCast(@alignCast(type_item.?));
        if (type_obj.PyType_IsSubtype(cls.?, type_ptr) != 0) {
            return 1;
        }
    }

    return 0;
}

/// Subscript for union (e.g., Union[T][int])
pub export fn _Py_union_subscript(union_obj: ?*cpython.PyObject, item: ?*cpython.PyObject) ?*cpython.PyObject {
    if (union_obj == null or item == null) return null;
    if (_PyUnion_Check(union_obj.?) == 0) return null;

    const u: *unionobject = @ptrCast(@alignCast(union_obj.?));
    if (u.args == null or u.parameters == null) {
        // No parameters to substitute
        union_obj.?.ob_refcnt += 1;
        return union_obj;
    }

    // TODO: Substitute type parameters with provided values
    // This is complex and requires walking through all args and replacing TypeVars

    union_obj.?.ob_refcnt += 1;
    return union_obj;
}

/// Flatten nested unions into a single level
pub export fn _Py_flatten_union_types(args: ?*cpython.PyObject) ?*cpython.PyObject {
    if (args == null) return null;

    var flat_list: [64]?*cpython.PyObject = undefined;
    var count: usize = 0;

    const tuple = @import("tupleobject.zig");
    const size = tuple.PyTuple_Size(args.?);

    for (0..@intCast(size)) |i| {
        const item = tuple.PyTuple_GetItem(args.?, @intCast(i));
        if (item == null) continue;

        if (_PyUnion_Check(item.?) != 0) {
            // Recursively flatten
            const u: *unionobject = @ptrCast(@alignCast(item.?));
            if (u.args) |nested_args| {
                const nested_flat = _Py_flatten_union_types(nested_args);
                if (nested_flat) |nf| {
                    defer nf.ob_refcnt -= 1;
                    const nested_size = tuple.PyTuple_Size(nf);
                    for (0..@intCast(nested_size)) |j| {
                        if (count >= flat_list.len) break;
                        flat_list[count] = tuple.PyTuple_GetItem(nf, @intCast(j));
                        count += 1;
                    }
                }
            }
        } else {
            if (count < flat_list.len) {
                flat_list[count] = item;
                count += 1;
            }
        }
    }

    // Create flattened tuple
    const result = tuple.PyTuple_New(@intCast(count));
    if (result == null) return null;

    for (0..count) |i| {
        if (flat_list[i]) |item| {
            item.ob_refcnt += 1;
            tuple.PyTuple_SetItem(result, @intCast(i), item);
        }
    }

    return result;
}
