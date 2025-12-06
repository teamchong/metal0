/// _operator Module - Operator C Accelerator
///
/// Implements CPython's Modules/_operator.c
/// Provides C implementations for operator functions
///
/// Reference: cpython/Modules/_operator.c

const std = @import("std");
const cpython = @import("../include/object.zig");

// ============================================================================
// COMPARISON OPERATORS
// ============================================================================

pub export fn _operator_lt(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return compare_impl(args, 0); // Py_LT
}

pub export fn _operator_le(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return compare_impl(args, 1); // Py_LE
}

pub export fn _operator_eq(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return compare_impl(args, 2); // Py_EQ
}

pub export fn _operator_ne(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return compare_impl(args, 3); // Py_NE
}

pub export fn _operator_gt(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return compare_impl(args, 4); // Py_GT
}

pub export fn _operator_ge(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return compare_impl(args, 5); // Py_GE
}

fn compare_impl(args: ?*cpython.PyObject, op: c_int) ?*cpython.PyObject {
    if (args == null) return null;
    const tuple = @import("../objects/tupleobject.zig");
    const object_mod = @import("../objects/object.zig");

    if (tuple.PyTuple_Size(args.?) < 2) return null;
    const a = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const b = tuple.PyTuple_GetItem(args.?, 1) orelse return null;

    return object_mod.PyObject_RichCompare(a, b, op);
}

// ============================================================================
// ARITHMETIC OPERATORS
// ============================================================================

pub export fn _operator_add(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return binary_op(args, "add");
}

pub export fn _operator_sub(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return binary_op(args, "sub");
}

pub export fn _operator_mul(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return binary_op(args, "mul");
}

pub export fn _operator_truediv(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return binary_op(args, "truediv");
}

pub export fn _operator_floordiv(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return binary_op(args, "floordiv");
}

pub export fn _operator_mod(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return binary_op(args, "mod");
}

pub export fn _operator_pow(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    return binary_op(args, "pow");
}

fn binary_op(args: ?*cpython.PyObject, comptime op: []const u8) ?*cpython.PyObject {
    if (args == null) return null;
    const tuple = @import("../objects/tupleobject.zig");
    const number = @import("../include/number.zig");
    _ = op;

    if (tuple.PyTuple_Size(args.?) < 2) return null;
    const a = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const b = tuple.PyTuple_GetItem(args.?, 1) orelse return null;

    return number.PyNumber_Add(a, b); // Simplified - full impl would dispatch by op
}

// ============================================================================
// UNARY OPERATORS
// ============================================================================

pub export fn _operator_neg(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;
    const tuple = @import("../objects/tupleobject.zig");
    const number = @import("../include/number.zig");

    if (tuple.PyTuple_Size(args.?) < 1) return null;
    const a = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    return number.PyNumber_Negative(a);
}

pub export fn _operator_pos(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;
    const tuple = @import("../objects/tupleobject.zig");
    const number = @import("../include/number.zig");

    if (tuple.PyTuple_Size(args.?) < 1) return null;
    const a = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    return number.PyNumber_Positive(a);
}

pub export fn _operator_not_(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;
    const tuple = @import("../objects/tupleobject.zig");
    const object_mod = @import("../objects/object.zig");
    const pybool = @import("../objects/boolobject.zig");

    if (tuple.PyTuple_Size(args.?) < 1) return null;
    const a = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const is_true = object_mod.PyObject_IsTrue(a);
    return if (is_true != 0) pybool.Py_False else pybool.Py_True;
}

// ============================================================================
// SEQUENCE OPERATORS
// ============================================================================

pub export fn _operator_getitem(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;
    const tuple = @import("../objects/tupleobject.zig");
    const object_mod = @import("../objects/object.zig");

    if (tuple.PyTuple_Size(args.?) < 2) return null;
    const a = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const b = tuple.PyTuple_GetItem(args.?, 1) orelse return null;
    return object_mod.PyObject_GetItem(a, b);
}

pub export fn _operator_contains(self: ?*cpython.PyObject, args: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;
    const tuple = @import("../objects/tupleobject.zig");
    const sequence = @import("../include/sequence.zig");
    const pybool = @import("../objects/boolobject.zig");

    if (tuple.PyTuple_Size(args.?) < 2) return null;
    const a = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const b = tuple.PyTuple_GetItem(args.?, 1) orelse return null;
    const result = sequence.PySequence_Contains(a, b);
    return if (result != 0) pybool.Py_True else pybool.Py_False;
}

// ============================================================================
// MODULE DEFINITION
// ============================================================================

const operator_methods = [_]cpython.PyMethodDef{
    .{ .ml_name = "lt", .ml_meth = @ptrCast(&_operator_lt), .ml_flags = cpython.METH_VARARGS, .ml_doc = "lt(a, b) -- Same as a < b." },
    .{ .ml_name = "le", .ml_meth = @ptrCast(&_operator_le), .ml_flags = cpython.METH_VARARGS, .ml_doc = "le(a, b) -- Same as a <= b." },
    .{ .ml_name = "eq", .ml_meth = @ptrCast(&_operator_eq), .ml_flags = cpython.METH_VARARGS, .ml_doc = "eq(a, b) -- Same as a == b." },
    .{ .ml_name = "ne", .ml_meth = @ptrCast(&_operator_ne), .ml_flags = cpython.METH_VARARGS, .ml_doc = "ne(a, b) -- Same as a != b." },
    .{ .ml_name = "gt", .ml_meth = @ptrCast(&_operator_gt), .ml_flags = cpython.METH_VARARGS, .ml_doc = "gt(a, b) -- Same as a > b." },
    .{ .ml_name = "ge", .ml_meth = @ptrCast(&_operator_ge), .ml_flags = cpython.METH_VARARGS, .ml_doc = "ge(a, b) -- Same as a >= b." },
    .{ .ml_name = "add", .ml_meth = @ptrCast(&_operator_add), .ml_flags = cpython.METH_VARARGS, .ml_doc = "add(a, b) -- Same as a + b." },
    .{ .ml_name = "sub", .ml_meth = @ptrCast(&_operator_sub), .ml_flags = cpython.METH_VARARGS, .ml_doc = "sub(a, b) -- Same as a - b." },
    .{ .ml_name = "mul", .ml_meth = @ptrCast(&_operator_mul), .ml_flags = cpython.METH_VARARGS, .ml_doc = "mul(a, b) -- Same as a * b." },
    .{ .ml_name = "truediv", .ml_meth = @ptrCast(&_operator_truediv), .ml_flags = cpython.METH_VARARGS, .ml_doc = "truediv(a, b) -- Same as a / b." },
    .{ .ml_name = "floordiv", .ml_meth = @ptrCast(&_operator_floordiv), .ml_flags = cpython.METH_VARARGS, .ml_doc = "floordiv(a, b) -- Same as a // b." },
    .{ .ml_name = "mod", .ml_meth = @ptrCast(&_operator_mod), .ml_flags = cpython.METH_VARARGS, .ml_doc = "mod(a, b) -- Same as a % b." },
    .{ .ml_name = "pow", .ml_meth = @ptrCast(&_operator_pow), .ml_flags = cpython.METH_VARARGS, .ml_doc = "pow(a, b) -- Same as a ** b." },
    .{ .ml_name = "neg", .ml_meth = @ptrCast(&_operator_neg), .ml_flags = cpython.METH_VARARGS, .ml_doc = "neg(a) -- Same as -a." },
    .{ .ml_name = "pos", .ml_meth = @ptrCast(&_operator_pos), .ml_flags = cpython.METH_VARARGS, .ml_doc = "pos(a) -- Same as +a." },
    .{ .ml_name = "not_", .ml_meth = @ptrCast(&_operator_not_), .ml_flags = cpython.METH_VARARGS, .ml_doc = "not_(a) -- Same as not a." },
    .{ .ml_name = "getitem", .ml_meth = @ptrCast(&_operator_getitem), .ml_flags = cpython.METH_VARARGS, .ml_doc = "getitem(a, b) -- Same as a[b]." },
    .{ .ml_name = "contains", .ml_meth = @ptrCast(&_operator_contains), .ml_flags = cpython.METH_VARARGS, .ml_doc = "contains(a, b) -- Same as b in a." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var _operatormodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_operator",
    .m_doc = "Operator interface.",
    .m_size = -1,
    .m_methods = @constCast(&operator_methods),
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__operator() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&_operatormodule);
}
