/// Class Object Implementation - Exact CPython Memory Layout
///
/// Class object implementation (dead now except for methods)
/// Contains PyMethodObject (bound methods) and PyInstanceMethodObject
///
/// Reference: cpython/Objects/classobject.c
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - EXACT CPYTHON LAYOUT
// ============================================================================

/// PyMethodObject - Bound method object (EXACT CPython layout)
/// Reference: cpython/Include/cpython/classobject.h
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *im_func;   /* The callable object implementing the method */
///     PyObject *im_self;   /* The instance it is bound to */
///     PyObject *im_weakreflist; /* List of weak references */
///     vectorcallfunc vectorcall;
/// } PyMethodObject;
pub const PyMethodObject = extern struct {
    ob_base: cpython.PyObject, // PyObject_HEAD (16 bytes)
    im_func: ?*cpython.PyObject, // The callable implementing the method
    im_self: ?*cpython.PyObject, // The instance it is bound to
    im_weakreflist: ?*cpython.PyObject, // List of weak references
    vectorcall: cpython.vectorcallfunc, // Vectorcall function pointer
};

// Verify layout
comptime {
    // PyMethodObject: PyObject(16) + im_func(8) + im_self(8) + im_weakreflist(8) + vectorcall(8) = 48 bytes
    if (@sizeOf(PyMethodObject) != 48) {
        @compileError("PyMethodObject size mismatch with CPython");
    }
}

/// PyInstanceMethodObject - Unbound instance method (EXACT CPython layout)
/// Reference: cpython/Include/cpython/classobject.h
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *func;
/// } PyInstanceMethodObject;
pub const PyInstanceMethodObject = extern struct {
    ob_base: cpython.PyObject, // PyObject_HEAD (16 bytes)
    func: ?*cpython.PyObject, // The underlying function
};

// Verify layout
comptime {
    // PyInstanceMethodObject: PyObject(16) + func(8) = 24 bytes
    if (@sizeOf(PyInstanceMethodObject) != 24) {
        @compileError("PyInstanceMethodObject size mismatch with CPython");
    }
}

// ============================================================================
// TYPE OBJECTS
// ============================================================================

/// PyMethod_Type - the type object for bound methods
pub export var PyMethod_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "method",
    .tp_basicsize = @sizeOf(PyMethodObject),
    .tp_itemsize = 0,
    .tp_dealloc = method_dealloc,
    .tp_vectorcall_offset = @offsetOf(PyMethodObject, "vectorcall"),
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = method_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = method_hash,
    .tp_call = null, // Uses vectorcall
    .tp_str = null,
    .tp_getattro = method_getattro,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_HAVE_VECTORCALL,
    .tp_doc = "method(function, instance)\n\nCreate a bound instance method object.",
    .tp_traverse = method_traverse,
    .tp_clear = method_clear,
    .tp_richcompare = method_richcompare,
    .tp_weaklistoffset = @offsetOf(PyMethodObject, "im_weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null, // TODO: method_methods
    .tp_members = null, // TODO: method_memberlist
    .tp_getset = null, // TODO: method_getset
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = method_descr_get,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = method_new,
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
    .tp_watched = 0,
};

/// PyInstanceMethod_Type - the type object for instance methods
pub export var PyInstanceMethod_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "instancemethod",
    .tp_basicsize = @sizeOf(PyInstanceMethodObject),
    .tp_itemsize = 0,
    .tp_dealloc = instancemethod_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = instancemethod_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = instancemethod_call,
    .tp_str = null,
    .tp_getattro = instancemethod_getattro,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "instancemethod(function)\n\nBind a function to a class.",
    .tp_traverse = instancemethod_traverse,
    .tp_clear = instancemethod_clear,
    .tp_richcompare = instancemethod_richcompare,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = instancemethod_descr_get,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = instancemethod_new,
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
    .tp_watched = 0,
};

// ============================================================================
// INTERNAL HELPER FUNCTIONS - PyMethodObject
// ============================================================================

fn method_dealloc(op: ?*cpython.PyObject) callconv(.C) void {
    if (op == null) return;
    const im: *PyMethodObject = @ptrCast(@alignCast(op.?));

    // Clear weak references
    // TODO: FT_CLEAR_WEAKREFS

    // Decref func and self
    if (im.im_func) |func| {
        cpython.Py_DECREF(func);
    }
    if (im.im_self) |self| {
        cpython.Py_DECREF(self);
    }

    // Free the object
    const ptr: [*]u8 = @ptrCast(im);
    allocator.free(ptr[0..@sizeOf(PyMethodObject)]);
}

fn method_repr(op: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (op == null) return null;
    // TODO: Format as "<bound method Class.method of <instance>>"
    return null;
}

fn method_hash(op: ?*cpython.PyObject) callconv(.C) isize {
    if (op == null) return -1;
    const im: *PyMethodObject = @ptrCast(@alignCast(op.?));

    // Combine hash of func and self
    var x: isize = 0;
    if (im.im_self) |self| {
        x = cpython.PyObject_Hash(self);
        if (x == -1) return -1;
    }
    if (im.im_func) |func| {
        const y = cpython.PyObject_Hash(func);
        if (y == -1) return -1;
        x ^= y;
    }
    if (x == -1) x = -2;
    return x;
}

fn method_traverse(self: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self == null) return 0;
    const im: *PyMethodObject = @ptrCast(@alignCast(self.?));

    if (im.im_func) |func| {
        if (visit) |v| {
            const result = v(func, arg);
            if (result != 0) return result;
        }
    }
    if (im.im_self) |s| {
        if (visit) |v| {
            const result = v(s, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

fn method_clear(self: ?*cpython.PyObject) callconv(.C) c_int {
    if (self == null) return 0;
    const im: *PyMethodObject = @ptrCast(@alignCast(self.?));

    if (im.im_func) |func| {
        cpython.Py_DECREF(func);
        im.im_func = null;
    }
    if (im.im_self) |s| {
        cpython.Py_DECREF(s);
        im.im_self = null;
    }
    return 0;
}

fn method_richcompare(self: ?*cpython.PyObject, other: ?*cpython.PyObject, op: c_int) callconv(.C) ?*cpython.PyObject {
    _ = self;
    _ = other;
    _ = op;
    // TODO: Implement rich comparison
    return null;
}

fn method_getattro(self: ?*cpython.PyObject, name: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = self;
    _ = name;
    // TODO: Get attribute from method
    return null;
}

fn method_descr_get(self: ?*cpython.PyObject, obj: ?*cpython.PyObject, typ: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = obj;
    _ = typ;
    // Method is already bound, just return self with incref
    if (self) |s| {
        cpython.Py_INCREF(s);
        return s;
    }
    return null;
}

fn method_new(typ: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = typ;
    _ = args;
    _ = kwargs;
    // TODO: Parse args and create method
    return null;
}

fn method_vectorcall(method: ?*cpython.PyObject, args: [*]const ?*cpython.PyObject, nargsf: usize, kwnames: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = method;
    _ = args;
    _ = nargsf;
    _ = kwnames;
    // TODO: Implement vectorcall
    return null;
}

// ============================================================================
// INTERNAL HELPER FUNCTIONS - PyInstanceMethodObject
// ============================================================================

fn instancemethod_dealloc(op: ?*cpython.PyObject) callconv(.C) void {
    if (op == null) return;
    const im: *PyInstanceMethodObject = @ptrCast(@alignCast(op.?));

    if (im.func) |func| {
        cpython.Py_DECREF(func);
    }

    const ptr: [*]u8 = @ptrCast(im);
    allocator.free(ptr[0..@sizeOf(PyInstanceMethodObject)]);
}

fn instancemethod_repr(op: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = op;
    // TODO: Format as "<instancemethod at 0xXXX>"
    return null;
}

fn instancemethod_call(op: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (op == null) return null;
    const im: *PyInstanceMethodObject = @ptrCast(@alignCast(op.?));

    if (im.func) |func| {
        // Call the underlying function
        const tp = func.ob_type;
        if (tp.tp_call) |call| {
            return call(func, args, kwargs);
        }
    }
    return null;
}

fn instancemethod_traverse(self: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self == null) return 0;
    const im: *PyInstanceMethodObject = @ptrCast(@alignCast(self.?));

    if (im.func) |func| {
        if (visit) |v| {
            return v(func, arg);
        }
    }
    return 0;
}

fn instancemethod_clear(self: ?*cpython.PyObject) callconv(.C) c_int {
    if (self == null) return 0;
    const im: *PyInstanceMethodObject = @ptrCast(@alignCast(self.?));

    if (im.func) |func| {
        cpython.Py_DECREF(func);
        im.func = null;
    }
    return 0;
}

fn instancemethod_richcompare(self: ?*cpython.PyObject, other: ?*cpython.PyObject, op: c_int) callconv(.C) ?*cpython.PyObject {
    _ = self;
    _ = other;
    _ = op;
    return null;
}

fn instancemethod_getattro(self: ?*cpython.PyObject, name: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self == null) return null;
    const im: *PyInstanceMethodObject = @ptrCast(@alignCast(self.?));

    // Forward attribute access to the underlying function
    if (im.func) |func| {
        return cpython.PyObject_GetAttr(func, name);
    }
    return null;
}

fn instancemethod_descr_get(self: ?*cpython.PyObject, obj: ?*cpython.PyObject, typ: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = typ;

    if (self == null) return null;
    const im: *PyInstanceMethodObject = @ptrCast(@alignCast(self.?));

    if (obj == null) {
        // Unbound access - return the underlying function
        if (im.func) |func| {
            cpython.Py_INCREF(func);
            return func;
        }
        return null;
    }

    // Bound access - create a new bound method
    if (im.func) |func| {
        return PyMethod_New(func, obj);
    }
    return null;
}

fn instancemethod_new(typ: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = typ;
    _ = args;
    _ = kwargs;
    // TODO: Parse args
    return null;
}

// ============================================================================
// PUBLIC API - Exported with C linkage
// ============================================================================

/// PyMethod_New - Create a new bound method
pub export fn PyMethod_New(func: ?*cpython.PyObject, self: ?*cpython.PyObject) ?*cpython.PyObject {
    if (self == null) {
        // PyErr_BadInternalCall();
        return null;
    }

    // Allocate method object
    const mem = allocator.alignedAlloc(u8, @alignOf(PyMethodObject), @sizeOf(PyMethodObject)) catch return null;
    const im: *PyMethodObject = @ptrCast(@alignCast(mem.ptr));

    im.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyMethod_Type,
        },
        .im_func = func,
        .im_self = self,
        .im_weakreflist = null,
        .vectorcall = method_vectorcall,
    };

    // Incref func and self
    if (func) |f| cpython.Py_INCREF(f);
    if (self) |s| cpython.Py_INCREF(s);

    return @ptrCast(im);
}

/// PyMethod_Function - Get the function from a method
pub export fn PyMethod_Function(im: ?*cpython.PyObject) ?*cpython.PyObject {
    if (im == null) return null;
    if (!PyMethod_Check(im)) {
        // PyErr_BadInternalCall();
        return null;
    }
    const method: *PyMethodObject = @ptrCast(@alignCast(im.?));
    return method.im_func;
}

/// PyMethod_Self - Get the self from a method
pub export fn PyMethod_Self(im: ?*cpython.PyObject) ?*cpython.PyObject {
    if (im == null) return null;
    if (!PyMethod_Check(im)) {
        // PyErr_BadInternalCall();
        return null;
    }
    const method: *PyMethodObject = @ptrCast(@alignCast(im.?));
    return method.im_self;
}

/// PyInstanceMethod_New - Create a new instance method
pub export fn PyInstanceMethod_New(func: ?*cpython.PyObject) ?*cpython.PyObject {
    if (func == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyInstanceMethodObject), @sizeOf(PyInstanceMethodObject)) catch return null;
    const im: *PyInstanceMethodObject = @ptrCast(@alignCast(mem.ptr));

    im.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyInstanceMethod_Type,
        },
        .func = func,
    };

    cpython.Py_INCREF(func);
    return @ptrCast(im);
}

/// PyInstanceMethod_Function - Get the function from an instance method
pub export fn PyInstanceMethod_Function(im: ?*cpython.PyObject) ?*cpython.PyObject {
    if (im == null) return null;
    if (!PyInstanceMethod_Check(im)) {
        // PyErr_BadInternalCall();
        return null;
    }
    const method: *PyInstanceMethodObject = @ptrCast(@alignCast(im.?));
    return method.func;
}

// ============================================================================
// TYPE CHECKING
// ============================================================================

/// Check if object is a bound method
pub inline fn PyMethod_Check(op: ?*cpython.PyObject) bool {
    if (op == null) return false;
    return op.?.ob_type == &PyMethod_Type;
}

/// Check if object is an instance method
pub inline fn PyInstanceMethod_Check(op: ?*cpython.PyObject) bool {
    if (op == null) return false;
    return op.?.ob_type == &PyInstanceMethod_Type;
}

/// Get function from method (no type check)
pub inline fn PyMethod_GET_FUNCTION(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;
    const method: *PyMethodObject = @ptrCast(@alignCast(op.?));
    return method.im_func;
}

/// Get self from method (no type check)
pub inline fn PyMethod_GET_SELF(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;
    const method: *PyMethodObject = @ptrCast(@alignCast(op.?));
    return method.im_self;
}

/// Get function from instance method (no type check)
pub inline fn PyInstanceMethod_GET_FUNCTION(op: ?*cpython.PyObject) ?*cpython.PyObject {
    if (op == null) return null;
    const method: *PyInstanceMethodObject = @ptrCast(@alignCast(op.?));
    return method.func;
}
