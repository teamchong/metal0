/// TypeVar Object Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/typevarobject.c
/// TypeVar, ParamSpec, TypeVarTuple for PEP 695 type parameter syntax
///
/// Reference: cpython/Objects/typevarobject.c
///            cpython/Include/cpython/typevars.h
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// typevarobject - TypeVar for generic type parameters
/// Reference: cpython/Objects/typevarobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *name;
///     PyObject *bound;
///     PyObject *evaluate_bound;
///     PyObject *constraints;
///     PyObject *evaluate_constraints;
///     PyObject *default_value;
///     PyObject *evaluate_default;
///     bool covariant;
///     bool contravariant;
///     bool infer_variance;
/// } typevarobject;
pub const typevarobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    name: ?*cpython.PyObject, // 8 bytes - __name__
    bound: ?*cpython.PyObject, // 8 bytes - __bound__
    evaluate_bound: ?*cpython.PyObject, // 8 bytes - lazy bound evaluator
    constraints: ?*cpython.PyObject, // 8 bytes - __constraints__ tuple
    evaluate_constraints: ?*cpython.PyObject, // 8 bytes - lazy constraints evaluator
    default_value: ?*cpython.PyObject, // 8 bytes - __default__ (PEP 696)
    evaluate_default: ?*cpython.PyObject, // 8 bytes - lazy default evaluator
    covariant: bool, // 1 byte - __covariant__
    contravariant: bool, // 1 byte - __contravariant__
    infer_variance: bool, // 1 byte - __infer_variance__
    _pad: [5]u8, // 5 bytes padding
};

// Verify typevarobject size: 16 + 7*8 + 3 + 5 = 80 bytes
comptime {
    if (@sizeOf(typevarobject) != 80) {
        @compileError("typevarobject size mismatch with CPython");
    }
}

/// paramspecobject - ParamSpec for callable parameter types
/// Reference: cpython/Objects/typevarobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *name;
///     PyObject *bound;
///     PyObject *evaluate_bound;
///     PyObject *default_value;
///     PyObject *evaluate_default;
///     bool covariant;
///     bool contravariant;
///     bool infer_variance;
/// } paramspecobject;
pub const paramspecobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    name: ?*cpython.PyObject, // 8 bytes - __name__
    bound: ?*cpython.PyObject, // 8 bytes - __bound__
    evaluate_bound: ?*cpython.PyObject, // 8 bytes - lazy bound evaluator
    default_value: ?*cpython.PyObject, // 8 bytes - __default__ (PEP 696)
    evaluate_default: ?*cpython.PyObject, // 8 bytes - lazy default evaluator
    covariant: bool, // 1 byte - __covariant__
    contravariant: bool, // 1 byte - __contravariant__
    infer_variance: bool, // 1 byte - __infer_variance__
    _pad: [5]u8, // 5 bytes padding
};

// Verify paramspecobject size: 16 + 5*8 + 3 + 5 = 64 bytes
comptime {
    if (@sizeOf(paramspecobject) != 64) {
        @compileError("paramspecobject size mismatch with CPython");
    }
}

/// typevartuple - TypeVarTuple for variadic generic types
/// Reference: cpython/Objects/typevarobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *name;
///     PyObject *default_value;
///     PyObject *evaluate_default;
/// } typevartuple;
pub const typevartupleobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    name: ?*cpython.PyObject, // 8 bytes - __name__
    default_value: ?*cpython.PyObject, // 8 bytes - __default__ (PEP 696)
    evaluate_default: ?*cpython.PyObject, // 8 bytes - lazy default evaluator
};

// Verify typevartupleobject size: 16 + 3*8 = 40 bytes
comptime {
    if (@sizeOf(typevartupleobject) != 40) {
        @compileError("typevartupleobject size mismatch with CPython");
    }
}

/// paramspecargs - ParamSpec.args
pub const paramspecattrobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    origin: ?*cpython.PyObject, // 8 bytes - the ParamSpec
};

// Verify paramspecattrobject size: 16 + 8 = 24 bytes
comptime {
    if (@sizeOf(paramspecattrobject) != 24) {
        @compileError("paramspecattrobject size mismatch with CPython");
    }
}

/// typealias - PEP 695 type alias
pub const typealiasobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    name: ?*cpython.PyObject, // 8 bytes - __name__
    type_params: ?*cpython.PyObject, // 8 bytes - __type_params__ tuple
    compute_value: ?*cpython.PyObject, // 8 bytes - lazy value evaluator
    value: ?*cpython.PyObject, // 8 bytes - __value__ (cached)
    module: ?*cpython.PyObject, // 8 bytes - __module__
};

// Verify typealiasobject size: 16 + 5*8 = 56 bytes
comptime {
    if (@sizeOf(typealiasobject) != 56) {
        @compileError("typealiasobject size mismatch with CPython");
    }
}

// ============================================================================
// TYPEVAR IMPLEMENTATION
// ============================================================================

/// Dealloc for TypeVar
fn typevar_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const tv: *typevarobject = @ptrCast(@alignCast(self_obj.?));

    if (tv.name) |name| name.ob_refcnt -= 1;
    if (tv.bound) |bound| bound.ob_refcnt -= 1;
    if (tv.evaluate_bound) |eb| eb.ob_refcnt -= 1;
    if (tv.constraints) |constraints| constraints.ob_refcnt -= 1;
    if (tv.evaluate_constraints) |ec| ec.ob_refcnt -= 1;
    if (tv.default_value) |def| def.ob_refcnt -= 1;
    if (tv.evaluate_default) |ed| ed.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(tv);
    allocator.free(ptr[0..@sizeOf(typevarobject)]);
}

/// Repr for TypeVar
fn typevar_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const tv: *typevarobject = @ptrCast(@alignCast(self_obj.?));

    // Return the name
    if (tv.name) |name| {
        name.ob_refcnt += 1;
        return name;
    }

    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("TypeVar");
}

/// Hash for TypeVar
fn typevar_hash(self_obj: ?*cpython.PyObject) callconv(.C) isize {
    if (self_obj == null) return -1;
    // Hash based on identity
    return @intCast(@intFromPtr(self_obj.?) >> 4);
}

/// Traverse for TypeVar (GC)
fn typevar_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const tv: *typevarobject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (tv.bound) |bound| {
            const result = v(bound, arg);
            if (result != 0) return result;
        }
        if (tv.constraints) |constraints| {
            const result = v(constraints, arg);
            if (result != 0) return result;
        }
        if (tv.default_value) |def| {
            const result = v(def, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Clear for TypeVar (GC)
fn typevar_clear(self_obj: ?*cpython.PyObject) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const tv: *typevarobject = @ptrCast(@alignCast(self_obj.?));

    if (tv.bound) |bound| {
        bound.ob_refcnt -= 1;
        tv.bound = null;
    }
    if (tv.constraints) |constraints| {
        constraints.ob_refcnt -= 1;
        tv.constraints = null;
    }
    if (tv.default_value) |def| {
        def.ob_refcnt -= 1;
        tv.default_value = null;
    }
    return 0;
}

/// New for TypeVar
fn typevar_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = args;
    _ = kwargs;

    const mem = allocator.alignedAlloc(u8, @alignOf(typevarobject), @sizeOf(typevarobject)) catch return null;
    const tv: *typevarobject = @ptrCast(@alignCast(mem.ptr));

    tv.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyTypeVar_Type,
        },
        .name = null,
        .bound = null,
        .evaluate_bound = null,
        .constraints = null,
        .evaluate_constraints = null,
        .default_value = null,
        .evaluate_default = null,
        .covariant = false,
        .contravariant = false,
        .infer_variance = false,
        ._pad = [_]u8{0} ** 5,
    };

    return @ptrCast(tv);
}

/// PyTypeVar_Type
pub export var PyTypeVar_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "typing.TypeVar",
    .tp_basicsize = @sizeOf(typevarobject),
    .tp_itemsize = 0,
    .tp_dealloc = typevar_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = typevar_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = typevar_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Type variable.\n\nUsage::\n\n    T = TypeVar('T')  # Can be anything\n    T = TypeVar('T', int, str)  # Either int or str",
    .tp_traverse = typevar_traverse,
    .tp_clear = typevar_clear,
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
    .tp_new = typevar_new,
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
// PARAMSPEC IMPLEMENTATION
// ============================================================================

/// Dealloc for ParamSpec
fn paramspec_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const ps: *paramspecobject = @ptrCast(@alignCast(self_obj.?));

    if (ps.name) |name| name.ob_refcnt -= 1;
    if (ps.bound) |bound| bound.ob_refcnt -= 1;
    if (ps.evaluate_bound) |eb| eb.ob_refcnt -= 1;
    if (ps.default_value) |def| def.ob_refcnt -= 1;
    if (ps.evaluate_default) |ed| ed.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(ps);
    allocator.free(ptr[0..@sizeOf(paramspecobject)]);
}

/// Repr for ParamSpec
fn paramspec_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const ps: *paramspecobject = @ptrCast(@alignCast(self_obj.?));

    if (ps.name) |name| {
        name.ob_refcnt += 1;
        return name;
    }

    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("ParamSpec");
}

/// New for ParamSpec
fn paramspec_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = args;
    _ = kwargs;

    const mem = allocator.alignedAlloc(u8, @alignOf(paramspecobject), @sizeOf(paramspecobject)) catch return null;
    const ps: *paramspecobject = @ptrCast(@alignCast(mem.ptr));

    ps.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyParamSpec_Type,
        },
        .name = null,
        .bound = null,
        .evaluate_bound = null,
        .default_value = null,
        .evaluate_default = null,
        .covariant = false,
        .contravariant = false,
        .infer_variance = false,
        ._pad = [_]u8{0} ** 5,
    };

    return @ptrCast(ps);
}

/// PyParamSpec_Type
pub export var PyParamSpec_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "typing.ParamSpec",
    .tp_basicsize = @sizeOf(paramspecobject),
    .tp_itemsize = 0,
    .tp_dealloc = paramspec_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = paramspec_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = typevar_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Parameter specification variable.\n\nUsage::\n\n    P = ParamSpec('P')",
    .tp_traverse = null,
    .tp_clear = null,
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
    .tp_new = paramspec_new,
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
// TYPEVARTUPLE IMPLEMENTATION
// ============================================================================

/// Dealloc for TypeVarTuple
fn typevartuple_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const tvt: *typevartupleobject = @ptrCast(@alignCast(self_obj.?));

    if (tvt.name) |name| name.ob_refcnt -= 1;
    if (tvt.default_value) |def| def.ob_refcnt -= 1;
    if (tvt.evaluate_default) |ed| ed.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(tvt);
    allocator.free(ptr[0..@sizeOf(typevartupleobject)]);
}

/// Repr for TypeVarTuple
fn typevartuple_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const tvt: *typevartupleobject = @ptrCast(@alignCast(self_obj.?));
    const pyunicode = @import("unicodeobject.zig");

    // Return *name for unpack notation
    if (tvt.name) |name| {
        // Prepend * to the name for TypeVarTuple repr
        const name_str = pyunicode.PyUnicode_AsUTF8(name);
        if (name_str) |ns| {
            var buf: [256]u8 = undefined;
            buf[0] = '*';
            const name_slice = std.mem.span(ns);
            const copy_len = @min(name_slice.len, buf.len - 1);
            @memcpy(buf[1..][0..copy_len], name_slice[0..copy_len]);
            return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(copy_len + 1));
        }
        name.ob_refcnt += 1;
        return name;
    }

    return pyunicode.PyUnicode_FromString("*TypeVarTuple");
}

/// New for TypeVarTuple
fn typevartuple_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = args;
    _ = kwargs;

    const mem = allocator.alignedAlloc(u8, @alignOf(typevartupleobject), @sizeOf(typevartupleobject)) catch return null;
    const tvt: *typevartupleobject = @ptrCast(@alignCast(mem.ptr));

    tvt.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyTypeVarTuple_Type,
        },
        .name = null,
        .default_value = null,
        .evaluate_default = null,
    };

    return @ptrCast(tvt);
}

/// PyTypeVarTuple_Type
pub export var PyTypeVarTuple_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "typing.TypeVarTuple",
    .tp_basicsize = @sizeOf(typevartupleobject),
    .tp_itemsize = 0,
    .tp_dealloc = typevartuple_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = typevartuple_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = typevar_hash,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Type variable tuple.\n\nUsage::\n\n    Ts = TypeVarTuple('Ts')",
    .tp_traverse = null,
    .tp_clear = null,
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
    .tp_new = typevartuple_new,
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
// PARAMSPEC ARGS/KWARGS IMPLEMENTATION
// ============================================================================

/// Dealloc for ParamSpecArgs/ParamSpecKwargs
fn paramspecattr_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const psa: *paramspecattrobject = @ptrCast(@alignCast(self_obj.?));

    if (psa.origin) |origin| origin.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(psa);
    allocator.free(ptr[0..@sizeOf(paramspecattrobject)]);
}

/// PyParamSpecArgs_Type
pub export var PyParamSpecArgs_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "typing.ParamSpecArgs",
    .tp_basicsize = @sizeOf(paramspecattrobject),
    .tp_itemsize = 0,
    .tp_dealloc = paramspecattr_dealloc,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "The args for a ParamSpec object.",
    .tp_traverse = null,
    .tp_clear = null,
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

/// PyParamSpecKwargs_Type
pub export var PyParamSpecKwargs_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "typing.ParamSpecKwargs",
    .tp_basicsize = @sizeOf(paramspecattrobject),
    .tp_itemsize = 0,
    .tp_dealloc = paramspecattr_dealloc,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "The kwargs for a ParamSpec object.",
    .tp_traverse = null,
    .tp_clear = null,
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
// TYPE ALIAS IMPLEMENTATION
// ============================================================================

/// Dealloc for TypeAliasType
fn typealias_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const ta: *typealiasobject = @ptrCast(@alignCast(self_obj.?));

    if (ta.name) |name| name.ob_refcnt -= 1;
    if (ta.type_params) |tp| tp.ob_refcnt -= 1;
    if (ta.compute_value) |cv| cv.ob_refcnt -= 1;
    if (ta.value) |v| v.ob_refcnt -= 1;
    if (ta.module) |m| m.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(ta);
    allocator.free(ptr[0..@sizeOf(typealiasobject)]);
}

/// Repr for TypeAliasType
fn typealias_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const ta: *typealiasobject = @ptrCast(@alignCast(self_obj.?));

    if (ta.name) |name| {
        name.ob_refcnt += 1;
        return name;
    }

    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_FromString("TypeAliasType");
}

/// New for TypeAliasType
fn typealias_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    _ = args;
    _ = kwargs;

    const mem = allocator.alignedAlloc(u8, @alignOf(typealiasobject), @sizeOf(typealiasobject)) catch return null;
    const ta: *typealiasobject = @ptrCast(@alignCast(mem.ptr));

    ta.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyTypeAlias_Type,
        },
        .name = null,
        .type_params = null,
        .compute_value = null,
        .value = null,
        .module = null,
    };

    return @ptrCast(ta);
}

/// PyTypeAlias_Type (TypeAliasType)
pub export var PyTypeAlias_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "typing.TypeAliasType",
    .tp_basicsize = @sizeOf(typealiasobject),
    .tp_itemsize = 0,
    .tp_dealloc = typealias_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = typealias_repr,
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
    .tp_doc = "Type alias.\n\nType aliases are created using the `type` statement::\n\n    type Alias = int",
    .tp_traverse = null,
    .tp_clear = null,
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
    .tp_new = typealias_new,
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

/// Create a new TypeVar
pub export fn _Py_make_typevar(name: ?*cpython.PyObject, bound: ?*cpython.PyObject, constraints: ?*cpython.PyObject) ?*cpython.PyObject {
    const obj = typevar_new(&PyTypeVar_Type, null, null);
    if (obj == null) return null;

    const tv: *typevarobject = @ptrCast(@alignCast(obj.?));

    if (name) |n| {
        n.ob_refcnt += 1;
        tv.name = n;
    }
    if (bound) |b| {
        b.ob_refcnt += 1;
        tv.bound = b;
    }
    if (constraints) |c| {
        c.ob_refcnt += 1;
        tv.constraints = c;
    }

    return obj;
}

/// Create a new ParamSpec
pub export fn _Py_make_paramspec(name: ?*cpython.PyObject) ?*cpython.PyObject {
    const obj = paramspec_new(&PyParamSpec_Type, null, null);
    if (obj == null) return null;

    const ps: *paramspecobject = @ptrCast(@alignCast(obj.?));

    if (name) |n| {
        n.ob_refcnt += 1;
        ps.name = n;
    }

    return obj;
}

/// Create a new TypeVarTuple
pub export fn _Py_make_typevartuple(name: ?*cpython.PyObject) ?*cpython.PyObject {
    const obj = typevartuple_new(&PyTypeVarTuple_Type, null, null);
    if (obj == null) return null;

    const tvt: *typevartupleobject = @ptrCast(@alignCast(obj.?));

    if (name) |n| {
        n.ob_refcnt += 1;
        tvt.name = n;
    }

    return obj;
}

/// Create a new TypeAliasType
pub export fn _Py_make_typealias(name: ?*cpython.PyObject, type_params: ?*cpython.PyObject, value: ?*cpython.PyObject) ?*cpython.PyObject {
    const obj = typealias_new(&PyTypeAlias_Type, null, null);
    if (obj == null) return null;

    const ta: *typealiasobject = @ptrCast(@alignCast(obj.?));

    if (name) |n| {
        n.ob_refcnt += 1;
        ta.name = n;
    }
    if (type_params) |tp| {
        tp.ob_refcnt += 1;
        ta.type_params = tp;
    }
    if (value) |v| {
        v.ob_refcnt += 1;
        ta.value = v;
    }

    return obj;
}
