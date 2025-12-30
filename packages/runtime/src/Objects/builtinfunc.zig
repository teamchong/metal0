/// PyBuiltinFunction - Callable wrapper for builtin functions
/// Used by eval() to call Python builtins like len(), bool(), int(), etc.
const std = @import("std");
const cpython = @import("../cpython.zig");
const PyObject = cpython.PyObject;
const PyVarObject = cpython.PyVarObject;
const PyTypeObject = cpython.PyTypeObject;
const Py_ssize_t = cpython.Py_ssize_t;

/// Function signature for builtin functions
/// Takes allocator and slice of PyObject args, returns PyObject result
pub const BuiltinFn = *const fn (std.mem.Allocator, []*PyObject) anyerror!*PyObject;

/// PyBuiltinFunctionObject - A callable builtin function
pub const PyBuiltinFunctionObject = extern struct {
    ob_base: PyObject,
    // We use anyopaque to store the function pointer since extern struct
    // can't have Zig function pointers directly
    ml_meth: ?*anyopaque,
    ml_name: ?[*:0]const u8,
};

/// Type object for builtin functions
pub var PyBuiltinFunction_Type: PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = undefined, // Will be set to &PyType_Type
        },
        .ob_size = 0,
    },
    .tp_name = "builtin_function_or_method",
    .tp_basicsize = @sizeOf(PyBuiltinFunctionObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_flags = cpython.Py_TPFLAGS.DEFAULT,
    .tp_doc = null,
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

/// Check if object is a PyBuiltinFunction
pub inline fn PyBuiltinFunction_Check(op: *PyObject) bool {
    return cpython.Py_IS_TYPE(op, &PyBuiltinFunction_Type);
}

/// PyBuiltinFunction API
pub const PyBuiltinFunction = struct {
    /// Create a new builtin function object
    pub fn create(allocator: std.mem.Allocator, name: [*:0]const u8, func: BuiltinFn) !*PyObject {
        const obj = try allocator.create(PyBuiltinFunctionObject);
        obj.* = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &PyBuiltinFunction_Type,
            },
            .ml_meth = @ptrCast(@constCast(func)),
            .ml_name = name,
        };
        return @ptrCast(obj);
    }

    /// Call the builtin function with arguments
    pub fn call(obj: *PyObject, allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
        std.debug.assert(PyBuiltinFunction_Check(obj));
        const func_obj: *PyBuiltinFunctionObject = @ptrCast(@alignCast(obj));

        if (func_obj.ml_meth) |meth_ptr| {
            const func: BuiltinFn = @ptrCast(@alignCast(meth_ptr));
            return func(allocator, args);
        }
        return error.NullFunction;
    }

    /// Get the name of the function
    pub fn getName(obj: *PyObject) ?[*:0]const u8 {
        std.debug.assert(PyBuiltinFunction_Check(obj));
        const func_obj: *PyBuiltinFunctionObject = @ptrCast(@alignCast(obj));
        return func_obj.ml_name;
    }
};
