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
// MEMBER TYPE CONSTANTS (from structmember.h)
// ============================================================================
const T_OBJECT_EX: c_int = 16; // PyObject* with NULL check

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
// METHOD GETSET DEFINITIONS
// ============================================================================

/// Getter for __func__ attribute
fn method_get_func(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.C) ?*cpython.PyObject {
    if (self == null) return null;
    const m: *PyMethodObject = @ptrCast(@alignCast(self.?));
    if (m.im_func) |func| {
        func.ob_refcnt += 1;
        return func;
    }
    return null;
}

/// Getter for __self__ attribute
fn method_get_self(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.C) ?*cpython.PyObject {
    if (self == null) return null;
    const m: *PyMethodObject = @ptrCast(@alignCast(self.?));
    if (m.im_self) |im_self| {
        im_self.ob_refcnt += 1;
        return im_self;
    }
    return null;
}

/// method_getset - getset descriptors for method type
var method_getset = [_]cpython.PyGetSetDef{
    .{
        .name = "__func__",
        .get = @ptrCast(&method_get_func),
        .set = null,
        .doc = "the function (or other callable) implementing a method",
        .closure = null,
    },
    .{
        .name = "__self__",
        .get = @ptrCast(&method_get_self),
        .set = null,
        .doc = "the instance to which a method is bound",
        .closure = null,
    },
    .{ .name = null, .get = null, .set = null, .doc = null, .closure = null }, // Sentinel
};

/// method_memberlist - member descriptors for method type
var method_memberlist = [_]cpython.PyMemberDef{
    .{
        .name = "__func__",
        .type = T_OBJECT_EX,
        .offset = @offsetOf(PyMethodObject, "im_func"),
        .flags = 1, // READONLY
        .doc = "the function (or other callable) implementing a method",
    },
    .{
        .name = "__self__",
        .type = T_OBJECT_EX,
        .offset = @offsetOf(PyMethodObject, "im_self"),
        .flags = 1, // READONLY
        .doc = "the instance to which a method is bound",
    },
    .{ .name = null, .type = 0, .offset = 0, .flags = 0, .doc = null }, // Sentinel
};

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
    .tp_methods = null, // Method has no methods
    .tp_members = &method_memberlist,
    .tp_getset = &method_getset,
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
    const weakref = @import("weakrefobject.zig");

    // Clear weak references if any
    if (im.im_weakreflist != null) {
        weakref.PyObject_ClearWeakRefs(op);
    }

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
    const im: *PyMethodObject = @ptrCast(@alignCast(op.?));
    const pyunicode = @import("unicodeobject.zig");

    // Format as "<bound method Class.method of <instance>>"
    var buf: [512]u8 = undefined;
    var pos: usize = 0;

    const prefix = "<bound method ";
    @memcpy(buf[pos..][0..prefix.len], prefix);
    pos += prefix.len;

    // Get function name
    if (im.im_func) |func| {
        // Try to get __qualname__ or __name__ from function
        if (cpython.PyObject_GetAttrString(func, "__qualname__")) |qname| {
            defer cpython.Py_DECREF(qname);
            if (pyunicode.PyUnicode_Check(qname) != 0) {
                const name_str = pyunicode.PyUnicode_AsUTF8(qname);
                if (name_str) |ns| {
                    const name_slice = std.mem.span(ns);
                    const name_len = @min(name_slice.len, buf.len - pos - 100);
                    @memcpy(buf[pos..][0..name_len], name_slice[0..name_len]);
                    pos += name_len;
                }
            }
        } else if (cpython.PyObject_GetAttrString(func, "__name__")) |name| {
            defer cpython.Py_DECREF(name);
            if (pyunicode.PyUnicode_Check(name) != 0) {
                const name_str = pyunicode.PyUnicode_AsUTF8(name);
                if (name_str) |ns| {
                    const name_slice = std.mem.span(ns);
                    const name_len = @min(name_slice.len, buf.len - pos - 100);
                    @memcpy(buf[pos..][0..name_len], name_slice[0..name_len]);
                    pos += name_len;
                }
            }
        }
    }

    const of_str = " of ";
    @memcpy(buf[pos..][0..of_str.len], of_str);
    pos += of_str.len;

    // Get repr of self
    if (im.im_self) |self| {
        if (self.ob_type.tp_repr) |repr_fn| {
            const self_repr = repr_fn(self);
            if (self_repr) |sr| {
                defer cpython.Py_DECREF(sr);
                const repr_str = pyunicode.PyUnicode_AsUTF8(sr);
                if (repr_str) |rs| {
                    const repr_slice = std.mem.span(rs);
                    const repr_len = @min(repr_slice.len, buf.len - pos - 10);
                    @memcpy(buf[pos..][0..repr_len], repr_slice[0..repr_len]);
                    pos += repr_len;
                }
            }
        }
    }

    buf[pos] = '>';
    pos += 1;

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(pos));
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
    if (self == null or other == null) return cpython.Py_NotImplemented;

    // Both must be methods for comparison
    if (!PyMethod_Check(self) or !PyMethod_Check(other)) {
        return cpython.Py_NotImplemented;
    }

    const im1: *PyMethodObject = @ptrCast(@alignCast(self.?));
    const im2: *PyMethodObject = @ptrCast(@alignCast(other.?));
    const object_mod = @import("object.zig");
    const pybool = @import("boolobject.zig");

    // Methods are equal if both func and self are equal
    const func_eq = if (im1.im_func != null and im2.im_func != null)
        object_mod.PyObject_RichCompareBool(im1.im_func.?, im2.im_func.?, object_mod.Py_EQ)
    else if (im1.im_func == null and im2.im_func == null)
        @as(c_int, 1)
    else
        @as(c_int, 0);

    const self_eq = if (im1.im_self != null and im2.im_self != null)
        object_mod.PyObject_RichCompareBool(im1.im_self.?, im2.im_self.?, object_mod.Py_EQ)
    else if (im1.im_self == null and im2.im_self == null)
        @as(c_int, 1)
    else
        @as(c_int, 0);

    const are_equal = (func_eq == 1 and self_eq == 1);

    if (op == object_mod.Py_EQ) {
        return if (are_equal) pybool.Py_True else pybool.Py_False;
    } else if (op == object_mod.Py_NE) {
        return if (are_equal) pybool.Py_False else pybool.Py_True;
    }

    // Other comparisons not supported for methods
    return cpython.Py_NotImplemented;
}

fn method_getattro(self: ?*cpython.PyObject, name: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self == null or name == null) return null;
    const im: *PyMethodObject = @ptrCast(@alignCast(self.?));
    const pyunicode = @import("unicodeobject.zig");

    // Check for special method attributes
    if (pyunicode.PyUnicode_Check(name) != 0) {
        const attr_name = pyunicode.PyUnicode_AsUTF8(name);
        if (attr_name) |an| {
            const name_slice = std.mem.span(an);

            // __func__ - return the underlying function
            if (std.mem.eql(u8, name_slice, "__func__")) {
                if (im.im_func) |func| {
                    cpython.Py_INCREF(func);
                    return func;
                }
                return null;
            }

            // __self__ - return the bound instance
            if (std.mem.eql(u8, name_slice, "__self__")) {
                if (im.im_self) |s| {
                    cpython.Py_INCREF(s);
                    return s;
                }
                return null;
            }
        }
    }

    // Forward other attribute access to the underlying function
    if (im.im_func) |func| {
        return cpython.PyObject_GetAttr(func, name);
    }
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
    _ = kwargs;

    // method(function, instance)
    if (args == null) return null;

    const tuple = @import("tupleobject.zig");
    const size = tuple.PyTuple_Size(args);
    if (size != 2) {
        // TypeError: method() takes exactly 2 arguments
        return null;
    }

    const func = tuple.PyTuple_GetItem(args, 0);
    const self = tuple.PyTuple_GetItem(args, 1);

    if (func == null or self == null) return null;

    // Check that func is callable
    if (!cpython.PyCallable_Check(func.?)) {
        // TypeError: first argument must be callable
        return null;
    }

    return PyMethod_New(func, self);
}

fn method_vectorcall(method_obj: ?*cpython.PyObject, args: [*]const ?*cpython.PyObject, nargsf: usize, kwnames: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (method_obj == null) return null;
    const im: *PyMethodObject = @ptrCast(@alignCast(method_obj.?));

    const func = im.im_func orelse return null;
    const self = im.im_self orelse return null;

    // Extract nargs from nargsf (lower bits)
    const nargs = nargsf & ~@as(usize, 0x8000000000000000);

    // Build new args array with self prepended
    var new_args: [64]?*cpython.PyObject = undefined;
    new_args[0] = self;

    // Copy remaining args
    const copy_count = @min(nargs, 63);
    for (0..copy_count) |i| {
        new_args[i + 1] = args[i];
    }

    // Call the underlying function with vectorcall if available
    const tp = func.ob_type;
    if (tp.tp_vectorcall_offset != 0) {
        // Get vectorcall from object at offset
        const offset: usize = @intCast(tp.tp_vectorcall_offset);
        const func_bytes: [*]const u8 = @ptrCast(func);
        const vc_ptr: *const ?cpython.vectorcallfunc = @ptrCast(@alignCast(func_bytes + offset));
        if (vc_ptr.*) |vc| {
            return vc(func, @ptrCast(&new_args), nargs + 1, kwnames);
        }
    }

    // Fallback to tp_call
    if (tp.tp_call) |call| {
        // Build tuple and dict from args
        const tuple = @import("tupleobject.zig");
        const args_tuple = tuple.PyTuple_New(@intCast(nargs + 1));
        if (args_tuple == null) return null;

        for (0..nargs + 1) |i| {
            if (new_args[i]) |arg| {
                cpython.Py_INCREF(arg);
                _ = tuple.PyTuple_SetItem(args_tuple.?, @intCast(i), arg);
            }
        }

        const result = call(func, args_tuple, null);
        cpython.Py_DECREF(args_tuple.?);
        return result;
    }

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
    if (op == null) return null;
    const pyunicode = @import("unicodeobject.zig");

    // Format as "<instancemethod at 0xXXX>"
    var buf: [128]u8 = undefined;
    const addr = @intFromPtr(op.?);

    // Build the hex address string
    var hex_buf: [16]u8 = undefined;
    var hex_len: usize = 0;
    var val = addr;
    if (val == 0) {
        hex_buf[0] = '0';
        hex_len = 1;
    } else {
        while (val > 0) : (hex_len += 1) {
            const digit = val % 16;
            hex_buf[hex_len] = if (digit < 10) @intCast('0' + digit) else @intCast('a' + digit - 10);
            val /= 16;
        }
    }

    // Build result
    var pos: usize = 0;
    const prefix = "<instancemethod at 0x";
    @memcpy(buf[pos..][0..prefix.len], prefix);
    pos += prefix.len;

    // Reverse copy hex digits
    var i: usize = 0;
    while (i < hex_len) : (i += 1) {
        buf[pos + i] = hex_buf[hex_len - 1 - i];
    }
    pos += hex_len;

    buf[pos] = '>';
    pos += 1;

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(pos));
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
    _ = kwargs;

    // instancemethod(function)
    if (args == null) return null;

    const tuple = @import("tupleobject.zig");
    const size = tuple.PyTuple_Size(args);
    if (size != 1) {
        // TypeError: instancemethod() takes exactly 1 argument
        return null;
    }

    const func = tuple.PyTuple_GetItem(args, 0);
    if (func == null) return null;

    // Check that func is callable
    if (!cpython.PyCallable_Check(func.?)) {
        // TypeError: first argument must be callable
        return null;
    }

    return PyInstanceMethod_New(func);
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
