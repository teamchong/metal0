/// Descriptor Objects Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/descrobject.c
/// Descriptors provide attribute access protocol for Python objects.
///
/// Reference: cpython/Objects/descrobject.c
///            cpython/Include/descrobject.h
///            cpython/Include/cpython/descrobject.h
///            cpython/Include/internal/pycore_descrobject.h
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// TYPE DEFINITIONS - Wrapper function signatures
// ============================================================================

/// Wrapper function type for slot methods
pub const wrapperfunc = ?*const fn (?*cpython.PyObject, ?*cpython.PyObject, ?*anyopaque) callconv(.C) ?*cpython.PyObject;

/// Wrapper function with keywords
pub const wrapperfunc_kwds = ?*const fn (?*cpython.PyObject, ?*cpython.PyObject, ?*anyopaque, ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject;

/// Wrapper base structure - describes a slot method
/// Reference: cpython/Include/cpython/descrobject.h
///
/// struct wrapperbase {
///     const char *name;
///     int offset;
///     void *function;
///     wrapperfunc wrapper;
///     const char *doc;
///     int flags;
///     PyObject *name_strobj;
/// };
pub const wrapperbase = extern struct {
    name: ?[*:0]const u8, // Method name
    offset: c_int, // Slot offset in type object
    function: ?*anyopaque, // Function pointer
    wrapper: wrapperfunc, // Wrapper function
    doc: ?[*:0]const u8, // Documentation string
    flags: c_int, // Flags (PyWrapperFlag_*)
    name_strobj: ?*cpython.PyObject, // Interned name string
};

/// Wrapper flags
pub const PyWrapperFlag_KEYWORDS: c_int = 1;

// ============================================================================
// DESCRIPTOR BASE STRUCTURES - Exact CPython Layout
// ============================================================================

/// PyDescrObject - Base descriptor object
/// Reference: cpython/Include/cpython/descrobject.h
///
/// typedef struct {
///     PyObject_HEAD
///     PyTypeObject *d_type;
///     PyObject *d_name;
///     PyObject *d_qualname;
/// } PyDescrObject;
pub const PyDescrObject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    d_type: ?*cpython.PyTypeObject, // Type this descriptor belongs to
    d_name: ?*cpython.PyObject, // Name of the attribute
    d_qualname: ?*cpython.PyObject, // Qualified name
};

// Verify PyDescrObject size: 16 + 8 + 8 + 8 = 40 bytes
comptime {
    if (@sizeOf(PyDescrObject) != 40) {
        @compileError("PyDescrObject size mismatch with CPython");
    }
}

/// PyMethodDescrObject - Method descriptor (for C methods)
/// Reference: cpython/Include/cpython/descrobject.h
///
/// typedef struct {
///     PyDescr_COMMON;
///     PyMethodDef *d_method;
///     vectorcallfunc vectorcall;
/// } PyMethodDescrObject;
pub const PyMethodDescrObject = extern struct {
    // PyDescr_COMMON expanded
    ob_base: cpython.PyObject, // 16 bytes
    d_type: ?*cpython.PyTypeObject, // 8 bytes
    d_name: ?*cpython.PyObject, // 8 bytes
    d_qualname: ?*cpython.PyObject, // 8 bytes
    // Method-specific fields
    d_method: ?*const cpython.PyMethodDef, // 8 bytes
    vectorcall: cpython.vectorcallfunc, // 8 bytes
};

// Verify PyMethodDescrObject size: 40 + 8 + 8 = 56 bytes
comptime {
    if (@sizeOf(PyMethodDescrObject) != 56) {
        @compileError("PyMethodDescrObject size mismatch with CPython");
    }
}

/// PyMemberDescrObject - Member descriptor (for struct member access)
/// Reference: cpython/Include/cpython/descrobject.h
///
/// typedef struct {
///     PyDescr_COMMON;
///     PyMemberDef *d_member;
/// } PyMemberDescrObject;
pub const PyMemberDescrObject = extern struct {
    // PyDescr_COMMON expanded
    ob_base: cpython.PyObject, // 16 bytes
    d_type: ?*cpython.PyTypeObject, // 8 bytes
    d_name: ?*cpython.PyObject, // 8 bytes
    d_qualname: ?*cpython.PyObject, // 8 bytes
    // Member-specific fields
    d_member: ?*const cpython.PyMemberDef, // 8 bytes
};

// Verify PyMemberDescrObject size: 40 + 8 = 48 bytes
comptime {
    if (@sizeOf(PyMemberDescrObject) != 48) {
        @compileError("PyMemberDescrObject size mismatch with CPython");
    }
}

/// PyGetSetDescrObject - GetSet descriptor (for property-like access)
/// Reference: cpython/Include/cpython/descrobject.h
///
/// typedef struct {
///     PyDescr_COMMON;
///     PyGetSetDef *d_getset;
/// } PyGetSetDescrObject;
pub const PyGetSetDescrObject = extern struct {
    // PyDescr_COMMON expanded
    ob_base: cpython.PyObject, // 16 bytes
    d_type: ?*cpython.PyTypeObject, // 8 bytes
    d_name: ?*cpython.PyObject, // 8 bytes
    d_qualname: ?*cpython.PyObject, // 8 bytes
    // GetSet-specific fields
    d_getset: ?*const cpython.PyGetSetDef, // 8 bytes
};

// Verify PyGetSetDescrObject size: 40 + 8 = 48 bytes
comptime {
    if (@sizeOf(PyGetSetDescrObject) != 48) {
        @compileError("PyGetSetDescrObject size mismatch with CPython");
    }
}

/// PyWrapperDescrObject - Wrapper descriptor (for slot wrappers)
/// Reference: cpython/Include/cpython/descrobject.h
///
/// typedef struct {
///     PyDescr_COMMON;
///     struct wrapperbase *d_base;
///     void *d_wrapped;
/// } PyWrapperDescrObject;
pub const PyWrapperDescrObject = extern struct {
    // PyDescr_COMMON expanded
    ob_base: cpython.PyObject, // 16 bytes
    d_type: ?*cpython.PyTypeObject, // 8 bytes
    d_name: ?*cpython.PyObject, // 8 bytes
    d_qualname: ?*cpython.PyObject, // 8 bytes
    // Wrapper-specific fields
    d_base: ?*wrapperbase, // 8 bytes
    d_wrapped: ?*anyopaque, // 8 bytes - the actual function pointer
};

// Verify PyWrapperDescrObject size: 40 + 8 + 8 = 56 bytes
comptime {
    if (@sizeOf(PyWrapperDescrObject) != 56) {
        @compileError("PyWrapperDescrObject size mismatch with CPython");
    }
}

// ============================================================================
// MAPPING PROXY OBJECT - Exact CPython Layout
// ============================================================================

/// mappingproxyobject - Read-only proxy for mappings
/// Reference: cpython/Objects/descrobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *mapping;
/// } mappingproxyobject;
pub const mappingproxyobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    mapping: ?*cpython.PyObject, // 8 bytes - the wrapped mapping
};

// Verify mappingproxyobject size: 16 + 8 = 24 bytes
comptime {
    if (@sizeOf(mappingproxyobject) != 24) {
        @compileError("mappingproxyobject size mismatch with CPython");
    }
}

// ============================================================================
// WRAPPER OBJECT - Exact CPython Layout
// ============================================================================

/// wrapperobject - Bound wrapper for slot methods
/// Reference: cpython/Objects/descrobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     PyWrapperDescrObject *descr;
///     PyObject *self;
/// } wrapperobject;
pub const wrapperobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    descr: ?*PyWrapperDescrObject, // 8 bytes
    self: ?*cpython.PyObject, // 8 bytes
};

// Verify wrapperobject size: 16 + 8 + 8 = 32 bytes
comptime {
    if (@sizeOf(wrapperobject) != 32) {
        @compileError("wrapperobject size mismatch with CPython");
    }
}

// ============================================================================
// PROPERTY OBJECT - Exact CPython Layout
// ============================================================================

/// propertyobject - Built-in property type
/// Reference: cpython/Include/internal/pycore_descrobject.h
///
/// typedef struct {
///     PyObject_HEAD
///     PyObject *prop_get;
///     PyObject *prop_set;
///     PyObject *prop_del;
///     PyObject *prop_doc;
///     PyObject *prop_name;
///     int getter_doc;
/// } propertyobject;
pub const propertyobject = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    prop_get: ?*cpython.PyObject, // 8 bytes - getter function
    prop_set: ?*cpython.PyObject, // 8 bytes - setter function
    prop_del: ?*cpython.PyObject, // 8 bytes - deleter function
    prop_doc: ?*cpython.PyObject, // 8 bytes - docstring
    prop_name: ?*cpython.PyObject, // 8 bytes - property name
    getter_doc: c_int, // 4 bytes - flag: doc came from getter
    _padding: [4]u8 = [_]u8{0} ** 4, // 4 bytes padding for alignment
};

// Verify propertyobject size: 16 + 8*5 + 4 + 4 = 64 bytes
comptime {
    if (@sizeOf(propertyobject) != 64) {
        @compileError("propertyobject size mismatch with CPython");
    }
}

// ============================================================================
// MEMBER TYPE CONSTANTS
// ============================================================================

// Member types (from structmember.h)
pub const Py_T_SHORT: c_int = 0;
pub const Py_T_INT: c_int = 1;
pub const Py_T_LONG: c_int = 2;
pub const Py_T_FLOAT: c_int = 3;
pub const Py_T_DOUBLE: c_int = 4;
pub const Py_T_STRING: c_int = 5;
pub const _Py_T_OBJECT: c_int = 6; // Deprecated
pub const Py_T_CHAR: c_int = 7;
pub const Py_T_BYTE: c_int = 8;
pub const Py_T_UBYTE: c_int = 9;
pub const Py_T_USHORT: c_int = 10;
pub const Py_T_UINT: c_int = 11;
pub const Py_T_ULONG: c_int = 12;
pub const Py_T_STRING_INPLACE: c_int = 13;
pub const Py_T_BOOL: c_int = 14;
pub const Py_T_OBJECT_EX: c_int = 16;
pub const Py_T_LONGLONG: c_int = 17;
pub const Py_T_ULONGLONG: c_int = 18;
pub const Py_T_PYSSIZET: c_int = 19;
pub const _Py_T_NONE: c_int = 20; // Deprecated

// Member flags
pub const Py_READONLY: c_int = 1;
pub const Py_AUDIT_READ: c_int = 2;
pub const _Py_WRITE_RESTRICTED: c_int = 4; // Deprecated
pub const Py_RELATIVE_OFFSET: c_int = 8;

// ============================================================================
// TYPE OBJECTS
// ============================================================================

/// Common dealloc for all descriptors
fn descr_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const descr: *PyDescrObject = @ptrCast(@alignCast(self_obj.?));

    // Decref type, name, and qualname
    if (descr.d_type) |tp| {
        const tp_obj: *cpython.PyObject = @ptrCast(tp);
        tp_obj.ob_refcnt -= 1;
    }
    if (descr.d_name) |name| {
        name.ob_refcnt -= 1;
    }
    if (descr.d_qualname) |qualname| {
        qualname.ob_refcnt -= 1;
    }

    // Free the object
    const ptr: [*]u8 = @ptrCast(descr);
    allocator.free(ptr[0..@sizeOf(PyDescrObject)]);
}

/// Method descriptor dealloc
fn method_descr_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const descr: *PyMethodDescrObject = @ptrCast(@alignCast(self_obj.?));

    // Decref type, name, and qualname
    if (descr.d_type) |tp| {
        const tp_obj: *cpython.PyObject = @ptrCast(tp);
        tp_obj.ob_refcnt -= 1;
    }
    if (descr.d_name) |name| {
        name.ob_refcnt -= 1;
    }
    if (descr.d_qualname) |qualname| {
        qualname.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(descr);
    allocator.free(ptr[0..@sizeOf(PyMethodDescrObject)]);
}

/// Descriptor repr helper
fn descr_repr_helper(descr: *PyDescrObject, kind: [*:0]const u8) ?*cpython.PyObject {
    _ = descr;
    _ = kind;
    // TODO: Implement proper repr using PyUnicode_FromFormat
    return null;
}

/// Method descriptor repr
fn method_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const descr: *PyDescrObject = @ptrCast(@alignCast(self_obj.?));
    return descr_repr_helper(descr, "method");
}

/// Member descriptor repr
fn member_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const descr: *PyDescrObject = @ptrCast(@alignCast(self_obj.?));
    return descr_repr_helper(descr, "member");
}

/// GetSet descriptor repr
fn getset_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const descr: *PyDescrObject = @ptrCast(@alignCast(self_obj.?));
    return descr_repr_helper(descr, "attribute");
}

/// Wrapper descriptor repr
fn wrapperdescr_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const descr: *PyDescrObject = @ptrCast(@alignCast(self_obj.?));
    return descr_repr_helper(descr, "slot wrapper");
}

/// Common descriptor traverse for GC
fn descr_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const descr: *PyDescrObject = @ptrCast(@alignCast(self_obj.?));

    // Visit the type
    if (descr.d_type) |tp| {
        const tp_obj: *cpython.PyObject = @ptrCast(tp);
        if (visit) |v| {
            const result = v(tp_obj, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

/// Method descriptor get
fn method_descr_get(self_obj: *cpython.PyObject, obj: ?*cpython.PyObject, type_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    const descr: *PyMethodDescrObject = @ptrCast(@alignCast(self_obj));

    if (obj == null) {
        // Unbound access - return descriptor itself
        self_obj.ob_refcnt += 1;
        return self_obj;
    }

    // Type check
    if (descr.d_type) |expected_type| {
        if (obj.?.ob_type != expected_type) {
            // Type mismatch - would raise TypeError in CPython
            return null;
        }
    }

    // Return bound method
    const pymethod = @import("methodobject.zig");
    return pymethod.PyCFunction_NewEx(descr.d_method, obj, null);
}

/// Member descriptor get
fn member_descr_get(self_obj: *cpython.PyObject, obj: ?*cpython.PyObject, type_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    const descr: *PyMemberDescrObject = @ptrCast(@alignCast(self_obj));

    if (obj == null) {
        self_obj.ob_refcnt += 1;
        return self_obj;
    }

    // Type check
    if (descr.d_type) |expected_type| {
        if (obj.?.ob_type != expected_type) {
            return null;
        }
    }

    // Get member value using PyMember_GetOne
    if (descr.d_member) |member| {
        return PyMember_GetOne(@ptrCast(obj.?), member);
    }
    return null;
}

/// Member descriptor set
fn member_descr_set(self_obj: *cpython.PyObject, obj: *cpython.PyObject, value: ?*cpython.PyObject) callconv(.C) c_int {
    const descr: *PyMemberDescrObject = @ptrCast(@alignCast(self_obj));

    // Type check
    if (descr.d_type) |expected_type| {
        if (obj.ob_type != expected_type) {
            return -1;
        }
    }

    // Set member value using PyMember_SetOne
    if (descr.d_member) |member| {
        return PyMember_SetOne(@ptrCast(obj), member, value);
    }
    return -1;
}

/// GetSet descriptor get
fn getset_descr_get(self_obj: *cpython.PyObject, obj: ?*cpython.PyObject, type_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    const descr: *PyGetSetDescrObject = @ptrCast(@alignCast(self_obj));

    if (obj == null) {
        self_obj.ob_refcnt += 1;
        return self_obj;
    }

    // Type check
    if (descr.d_type) |expected_type| {
        if (obj.?.ob_type != expected_type) {
            return null;
        }
    }

    // Call getter
    if (descr.d_getset) |getset| {
        if (getset.get) |getter_ptr| {
            const getter: *const fn (*cpython.PyObject, ?*anyopaque) callconv(.C) ?*cpython.PyObject = @ptrCast(getter_ptr);
            return getter(obj.?, getset.closure);
        }
    }
    return null;
}

/// GetSet descriptor set
fn getset_descr_set(self_obj: *cpython.PyObject, obj: *cpython.PyObject, value: ?*cpython.PyObject) callconv(.C) c_int {
    const descr: *PyGetSetDescrObject = @ptrCast(@alignCast(self_obj));

    // Type check
    if (descr.d_type) |expected_type| {
        if (obj.ob_type != expected_type) {
            return -1;
        }
    }

    // Call setter
    if (descr.d_getset) |getset| {
        if (getset.set) |setter_ptr| {
            const setter: *const fn (*cpython.PyObject, ?*cpython.PyObject, ?*anyopaque) callconv(.C) c_int = @ptrCast(setter_ptr);
            return setter(obj, value, getset.closure);
        }
    }
    return -1;
}

/// Wrapper descriptor get
fn wrapperdescr_get(self_obj: *cpython.PyObject, obj: ?*cpython.PyObject, type_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;

    if (obj == null) {
        self_obj.ob_refcnt += 1;
        return self_obj;
    }

    // Create wrapper object
    return PyWrapper_New(self_obj, obj.?);
}

// ============================================================================
// TYPE OBJECT DEFINITIONS
// ============================================================================

pub export var PyMethodDescr_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "method_descriptor",
    .tp_basicsize = @sizeOf(PyMethodDescrObject),
    .tp_itemsize = 0,
    .tp_dealloc = method_descr_dealloc,
    .tp_vectorcall_offset = @offsetOf(PyMethodDescrObject, "vectorcall"),
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = method_repr,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null, // Uses vectorcall
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = null,
    .tp_traverse = descr_traverse,
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
    .tp_descr_get = method_descr_get,
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

pub export var PyClassMethodDescr_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "classmethod_descriptor",
    .tp_basicsize = @sizeOf(PyMethodDescrObject),
    .tp_itemsize = 0,
    .tp_dealloc = method_descr_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = method_repr,
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
    .tp_traverse = descr_traverse,
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
    .tp_descr_get = null, // classmethod_get TODO
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

pub export var PyMemberDescr_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "member_descriptor",
    .tp_basicsize = @sizeOf(PyMemberDescrObject),
    .tp_itemsize = 0,
    .tp_dealloc = descr_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = member_repr,
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
    .tp_traverse = descr_traverse,
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
    .tp_descr_get = member_descr_get,
    .tp_descr_set = member_descr_set,
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

pub export var PyGetSetDescr_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "getset_descriptor",
    .tp_basicsize = @sizeOf(PyGetSetDescrObject),
    .tp_itemsize = 0,
    .tp_dealloc = descr_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = getset_repr,
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
    .tp_traverse = descr_traverse,
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
    .tp_descr_get = getset_descr_get,
    .tp_descr_set = getset_descr_set,
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

pub export var PyWrapperDescr_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "wrapper_descriptor",
    .tp_basicsize = @sizeOf(PyWrapperDescrObject),
    .tp_itemsize = 0,
    .tp_dealloc = descr_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = wrapperdescr_repr,
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
    .tp_traverse = descr_traverse,
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
    .tp_descr_get = wrapperdescr_get,
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

// Mapping proxy as_mapping
var mappingproxy_as_mapping: cpython.PyMappingMethods = .{
    .mp_length = mappingproxy_len,
    .mp_subscript = mappingproxy_getitem,
    .mp_ass_subscript = null,
};

fn mappingproxy_len(self_obj: *cpython.PyObject) callconv(.C) isize {
    const pp: *mappingproxyobject = @ptrCast(@alignCast(self_obj));
    if (pp.mapping) |mapping| {
        // TODO: Call PyObject_Size
        _ = mapping;
    }
    return 0;
}

fn mappingproxy_getitem(self_obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    const pp: *mappingproxyobject = @ptrCast(@alignCast(self_obj));
    if (pp.mapping) |mapping| {
        // TODO: Call PyObject_GetItem
        _ = mapping;
        _ = key;
    }
    return null;
}

fn mappingproxy_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const pp: *mappingproxyobject = @ptrCast(@alignCast(self_obj.?));

    if (pp.mapping) |mapping| {
        mapping.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(pp);
    allocator.free(ptr[0..@sizeOf(mappingproxyobject)]);
}

fn mappingproxy_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const pp: *mappingproxyobject = @ptrCast(@alignCast(self_obj.?));

    if (pp.mapping) |mapping| {
        if (visit) |v| {
            const result = v(mapping, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

pub export var PyDictProxy_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "mappingproxy",
    .tp_basicsize = @sizeOf(mappingproxyobject),
    .tp_itemsize = 0,
    .tp_dealloc = mappingproxy_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = &mappingproxy_as_mapping,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Read-only proxy of a mapping.",
    .tp_traverse = mappingproxy_traverse,
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

// Property type
fn property_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const prop: *propertyobject = @ptrCast(@alignCast(self_obj.?));

    if (prop.prop_get) |g| g.ob_refcnt -= 1;
    if (prop.prop_set) |s| s.ob_refcnt -= 1;
    if (prop.prop_del) |d| d.ob_refcnt -= 1;
    if (prop.prop_doc) |doc| doc.ob_refcnt -= 1;
    if (prop.prop_name) |name| name.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(prop);
    allocator.free(ptr[0..@sizeOf(propertyobject)]);
}

fn property_descr_get(self_obj: *cpython.PyObject, obj: ?*cpython.PyObject, type_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = type_obj;
    const prop: *propertyobject = @ptrCast(@alignCast(self_obj));

    if (obj == null) {
        self_obj.ob_refcnt += 1;
        return self_obj;
    }

    if (prop.prop_get == null) {
        return null; // Would raise AttributeError
    }

    // Call getter with obj using PyObject_CallOneArg
    const call = @import("call.zig");
    return call.PyObject_CallOneArg(prop.prop_get, obj);
}

fn property_descr_set(self_obj: *cpython.PyObject, obj: *cpython.PyObject, value: ?*cpython.PyObject) callconv(.C) c_int {
    const prop: *propertyobject = @ptrCast(@alignCast(self_obj));
    const call = @import("call.zig");

    if (value == null) {
        // Delete operation
        if (prop.prop_del == null) {
            return -1; // Would raise AttributeError: can't delete
        }
        const result = call.PyObject_CallOneArg(prop.prop_del, obj);
        if (result == null) return -1;
        result.?.ob_refcnt -= 1; // Discard return value
        return 0;
    } else {
        // Set operation
        if (prop.prop_set == null) {
            return -1; // Would raise AttributeError: can't set
        }
        // Need to call with two args: (obj, value)
        const tuple = @import("tupleobject.zig");
        const args = tuple.PyTuple_New(2);
        if (args == null) return -1;

        obj.ob_refcnt += 1;
        _ = tuple.PyTuple_SetItem(args.?, 0, obj);
        value.?.ob_refcnt += 1;
        _ = tuple.PyTuple_SetItem(args.?, 1, value.?);

        const result = call.PyObject_Call(prop.prop_set, args, null);
        args.?.ob_refcnt -= 1;

        if (result == null) return -1;
        result.?.ob_refcnt -= 1; // Discard return value
        return 0;
    }
}

fn property_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const prop: *propertyobject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (prop.prop_get) |g| {
            const result = v(g, arg);
            if (result != 0) return result;
        }
        if (prop.prop_set) |s| {
            const result = v(s, arg);
            if (result != 0) return result;
        }
        if (prop.prop_del) |d| {
            const result = v(d, arg);
            if (result != 0) return result;
        }
        if (prop.prop_doc) |doc| {
            const result = v(doc, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

pub export var PyProperty_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "property",
    .tp_basicsize = @sizeOf(propertyobject),
    .tp_itemsize = 0,
    .tp_dealloc = property_dealloc,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_HAVE_GC | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "Property attribute.\n\nfget\n  function to be used for getting an attribute value\nfset\n  function to be used for setting an attribute value\nfdel\n  function to be used for del'ing an attribute\ndoc\n  docstring\n\nTypical use is to define a managed attribute x:\n\nclass C(object):\n    def getx(self): return self._x\n    def setx(self, value): self._x = value\n    def delx(self): del self._x\n    x = property(getx, setx, delx, \"I'm the 'x' property.\")",
    .tp_traverse = property_traverse,
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
    .tp_descr_get = property_descr_get,
    .tp_descr_set = property_descr_set,
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

// Method wrapper type
fn wrapper_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const wp: *wrapperobject = @ptrCast(@alignCast(self_obj.?));

    if (wp.descr) |d| {
        const d_obj: *cpython.PyObject = @ptrCast(d);
        d_obj.ob_refcnt -= 1;
    }
    if (wp.self) |s| {
        s.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(wp);
    allocator.free(ptr[0..@sizeOf(wrapperobject)]);
}

fn wrapper_traverse(self_obj: ?*cpython.PyObject, visit: cpython.visitproc, arg: ?*anyopaque) callconv(.C) c_int {
    if (self_obj == null) return 0;
    const wp: *wrapperobject = @ptrCast(@alignCast(self_obj.?));

    if (visit) |v| {
        if (wp.descr) |d| {
            const d_obj: *cpython.PyObject = @ptrCast(d);
            const result = v(d_obj, arg);
            if (result != 0) return result;
        }
        if (wp.self) |s| {
            const result = v(s, arg);
            if (result != 0) return result;
        }
    }
    return 0;
}

pub export var _PyMethodWrapper_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "method-wrapper",
    .tp_basicsize = @sizeOf(wrapperobject),
    .tp_itemsize = 0,
    .tp_dealloc = wrapper_dealloc,
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
    .tp_traverse = wrapper_traverse,
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
// PUBLIC API - Exported with C linkage
// ============================================================================

/// Create a new method descriptor
pub export fn PyDescr_NewMethod(type_obj: ?*cpython.PyTypeObject, method: ?*const cpython.PyMethodDef) ?*cpython.PyObject {
    if (type_obj == null or method == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyMethodDescrObject), @sizeOf(PyMethodDescrObject)) catch return null;
    const descr: *PyMethodDescrObject = @ptrCast(@alignCast(mem.ptr));

    descr.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyMethodDescr_Type,
        },
        .d_type = type_obj,
        .d_name = null,
        .d_qualname = null,
        .d_method = method,
        .vectorcall = null, // TODO: Set appropriate vectorcall based on ml_flags
    };

    // Incref type
    const type_obj_ptr: *cpython.PyObject = @ptrCast(type_obj.?);
    type_obj_ptr.ob_refcnt += 1;

    // Create name string
    if (method.?.ml_name) |name| {
        const pyunicode = @import("unicodeobject.zig");
        descr.d_name = pyunicode.PyUnicode_FromString(name);
    }

    return @ptrCast(descr);
}

/// Create a new classmethod descriptor
pub export fn PyDescr_NewClassMethod(type_obj: ?*cpython.PyTypeObject, method: ?*const cpython.PyMethodDef) ?*cpython.PyObject {
    if (type_obj == null or method == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyMethodDescrObject), @sizeOf(PyMethodDescrObject)) catch return null;
    const descr: *PyMethodDescrObject = @ptrCast(@alignCast(mem.ptr));

    descr.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyClassMethodDescr_Type,
        },
        .d_type = type_obj,
        .d_name = null,
        .d_qualname = null,
        .d_method = method,
        .vectorcall = null,
    };

    const type_obj_ptr: *cpython.PyObject = @ptrCast(type_obj.?);
    type_obj_ptr.ob_refcnt += 1;

    if (method.?.ml_name) |name| {
        const pyunicode = @import("unicodeobject.zig");
        descr.d_name = pyunicode.PyUnicode_FromString(name);
    }

    return @ptrCast(descr);
}

/// Create a new member descriptor
pub export fn PyDescr_NewMember(type_obj: ?*cpython.PyTypeObject, member: ?*const cpython.PyMemberDef) ?*cpython.PyObject {
    if (type_obj == null or member == null) return null;

    // Check for Py_RELATIVE_OFFSET which is not supported via this API
    if (member.?.flags & Py_RELATIVE_OFFSET != 0) {
        return null;
    }

    const mem = allocator.alignedAlloc(u8, @alignOf(PyMemberDescrObject), @sizeOf(PyMemberDescrObject)) catch return null;
    const descr: *PyMemberDescrObject = @ptrCast(@alignCast(mem.ptr));

    descr.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyMemberDescr_Type,
        },
        .d_type = type_obj,
        .d_name = null,
        .d_qualname = null,
        .d_member = member,
    };

    const type_obj_ptr: *cpython.PyObject = @ptrCast(type_obj.?);
    type_obj_ptr.ob_refcnt += 1;

    if (member.?.name) |name| {
        const pyunicode = @import("unicodeobject.zig");
        descr.d_name = pyunicode.PyUnicode_FromString(name);
    }

    return @ptrCast(descr);
}

/// Create a new getset descriptor
pub export fn PyDescr_NewGetSet(type_obj: ?*cpython.PyTypeObject, getset: ?*const cpython.PyGetSetDef) ?*cpython.PyObject {
    if (type_obj == null or getset == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyGetSetDescrObject), @sizeOf(PyGetSetDescrObject)) catch return null;
    const descr: *PyGetSetDescrObject = @ptrCast(@alignCast(mem.ptr));

    descr.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyGetSetDescr_Type,
        },
        .d_type = type_obj,
        .d_name = null,
        .d_qualname = null,
        .d_getset = getset,
    };

    const type_obj_ptr: *cpython.PyObject = @ptrCast(type_obj.?);
    type_obj_ptr.ob_refcnt += 1;

    if (getset.?.name) |name| {
        const pyunicode = @import("unicodeobject.zig");
        descr.d_name = pyunicode.PyUnicode_FromString(name);
    }

    return @ptrCast(descr);
}

/// Create a new wrapper descriptor
pub export fn PyDescr_NewWrapper(type_obj: ?*cpython.PyTypeObject, base: ?*wrapperbase, wrapped: ?*anyopaque) ?*cpython.PyObject {
    if (type_obj == null or base == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyWrapperDescrObject), @sizeOf(PyWrapperDescrObject)) catch return null;
    const descr: *PyWrapperDescrObject = @ptrCast(@alignCast(mem.ptr));

    descr.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyWrapperDescr_Type,
        },
        .d_type = type_obj,
        .d_name = null,
        .d_qualname = null,
        .d_base = base,
        .d_wrapped = wrapped,
    };

    const type_obj_ptr: *cpython.PyObject = @ptrCast(type_obj.?);
    type_obj_ptr.ob_refcnt += 1;

    if (base.?.name) |name| {
        const pyunicode = @import("unicodeobject.zig");
        descr.d_name = pyunicode.PyUnicode_FromString(name);
    }

    return @ptrCast(descr);
}

/// Check if object is a data descriptor (has __set__)
pub export fn PyDescr_IsData(descr: ?*cpython.PyObject) c_int {
    if (descr == null) return 0;
    const tp = descr.?.ob_type;
    return if (tp.tp_descr_set != null) 1 else 0;
}

/// Create a new mapping proxy
pub export fn PyDictProxy_New(mapping: ?*cpython.PyObject) ?*cpython.PyObject {
    if (mapping == null) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(mappingproxyobject), @sizeOf(mappingproxyobject)) catch return null;
    const pp: *mappingproxyobject = @ptrCast(@alignCast(mem.ptr));

    pp.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyDictProxy_Type,
        },
        .mapping = mapping,
    };

    mapping.?.ob_refcnt += 1;

    return @ptrCast(pp);
}

/// Create a new wrapper object (bound method wrapper)
pub export fn PyWrapper_New(descr: ?*cpython.PyObject, self: ?*cpython.PyObject) ?*cpython.PyObject {
    if (descr == null or self == null) return null;

    // Verify descr is a PyWrapperDescrObject
    if (descr.?.ob_type != &PyWrapperDescr_Type) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(wrapperobject), @sizeOf(wrapperobject)) catch return null;
    const wp: *wrapperobject = @ptrCast(@alignCast(mem.ptr));

    wp.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &_PyMethodWrapper_Type,
        },
        .descr = @ptrCast(@alignCast(descr.?)),
        .self = self,
    };

    descr.?.ob_refcnt += 1;
    self.?.ob_refcnt += 1;

    return @ptrCast(wp);
}

/// Get member value from object
pub export fn PyMember_GetOne(addr: [*]const u8, member: ?*const cpython.PyMemberDef) ?*cpython.PyObject {
    if (member == null) return null;

    const m = member.?;
    const ptr = addr + @as(usize, @intCast(m.offset));

    switch (m.@"type") {
        Py_T_BOOL => {
            const val = @as(*const u8, @ptrCast(ptr)).*;
            const pylong = @import("longobject.zig");
            return pylong.PyLong_FromLong(if (val != 0) 1 else 0);
        },
        Py_T_BYTE => {
            const val = @as(*const i8, @ptrCast(@alignCast(ptr))).*;
            const pylong = @import("longobject.zig");
            return pylong.PyLong_FromLong(@intCast(val));
        },
        Py_T_UBYTE => {
            const val = @as(*const u8, @ptrCast(ptr)).*;
            const pylong = @import("longobject.zig");
            return pylong.PyLong_FromLong(@intCast(val));
        },
        Py_T_SHORT => {
            const val = @as(*align(1) const i16, @ptrCast(ptr)).*;
            const pylong = @import("longobject.zig");
            return pylong.PyLong_FromLong(@intCast(val));
        },
        Py_T_USHORT => {
            const val = @as(*align(1) const u16, @ptrCast(ptr)).*;
            const pylong = @import("longobject.zig");
            return pylong.PyLong_FromLong(@intCast(val));
        },
        Py_T_INT => {
            const val = @as(*align(1) const c_int, @ptrCast(ptr)).*;
            const pylong = @import("longobject.zig");
            return pylong.PyLong_FromLong(@intCast(val));
        },
        Py_T_UINT => {
            const val = @as(*align(1) const c_uint, @ptrCast(ptr)).*;
            const pylong = @import("longobject.zig");
            return pylong.PyLong_FromUnsignedLong(@intCast(val));
        },
        Py_T_LONG => {
            const val = @as(*align(1) const c_long, @ptrCast(ptr)).*;
            const pylong = @import("longobject.zig");
            return pylong.PyLong_FromLong(val);
        },
        Py_T_ULONG => {
            const val = @as(*align(1) const c_ulong, @ptrCast(ptr)).*;
            const pylong = @import("longobject.zig");
            return pylong.PyLong_FromUnsignedLong(val);
        },
        Py_T_PYSSIZET => {
            const val = @as(*align(1) const isize, @ptrCast(ptr)).*;
            const pylong = @import("longobject.zig");
            return pylong.PyLong_FromSsize_t(val);
        },
        Py_T_FLOAT => {
            const val = @as(*align(1) const f32, @ptrCast(ptr)).*;
            const pyfloat = @import("floatobject.zig");
            return pyfloat.PyFloat_FromDouble(@floatCast(val));
        },
        Py_T_DOUBLE => {
            const val = @as(*align(1) const f64, @ptrCast(ptr)).*;
            const pyfloat = @import("floatobject.zig");
            return pyfloat.PyFloat_FromDouble(val);
        },
        Py_T_OBJECT_EX, _Py_T_OBJECT => {
            const obj = @as(*align(1) const ?*cpython.PyObject, @ptrCast(ptr)).*;
            if (obj) |o| {
                o.ob_refcnt += 1;
                return o;
            }
            // Would raise AttributeError for T_OBJECT_EX
            return null;
        },
        else => return null,
    }
}

/// Set member value on object
pub export fn PyMember_SetOne(addr: [*]u8, member: ?*const cpython.PyMemberDef, value: ?*cpython.PyObject) c_int {
    if (member == null) return -1;

    const m = member.?;

    // Check readonly
    if (m.flags & Py_READONLY != 0) {
        return -1;
    }

    const ptr = addr + @as(usize, @intCast(m.offset));

    // Handle deletion
    if (value == null) {
        if (m.@"type" == Py_T_OBJECT_EX or m.@"type" == _Py_T_OBJECT) {
            const obj_ptr = @as(*align(1) ?*cpython.PyObject, @ptrCast(ptr));
            if (obj_ptr.*) |old| {
                old.ob_refcnt -= 1;
            }
            obj_ptr.* = null;
            return 0;
        }
        return -1;
    }

    switch (m.@"type") {
        Py_T_BOOL => {
            const pylong = @import("longobject.zig");
            const v = pylong.PyLong_AsLong(value.?);
            @as(*u8, @ptrCast(ptr)).* = if (v != 0) 1 else 0;
            return 0;
        },
        Py_T_BYTE => {
            const pylong = @import("longobject.zig");
            const v = pylong.PyLong_AsLong(value.?);
            @as(*align(1) i8, @ptrCast(ptr)).* = @truncate(v);
            return 0;
        },
        Py_T_INT => {
            const pylong = @import("longobject.zig");
            const v = pylong.PyLong_AsLong(value.?);
            @as(*align(1) c_int, @ptrCast(ptr)).* = @intCast(v);
            return 0;
        },
        Py_T_LONG => {
            const pylong = @import("longobject.zig");
            const v = pylong.PyLong_AsLong(value.?);
            @as(*align(1) c_long, @ptrCast(ptr)).* = v;
            return 0;
        },
        Py_T_PYSSIZET => {
            const pylong = @import("longobject.zig");
            const v = pylong.PyLong_AsSsize_t(value.?);
            @as(*align(1) isize, @ptrCast(ptr)).* = v;
            return 0;
        },
        Py_T_FLOAT => {
            const pyfloat = @import("floatobject.zig");
            const v = pyfloat.PyFloat_AsDouble(value.?);
            @as(*align(1) f32, @ptrCast(ptr)).* = @floatCast(v);
            return 0;
        },
        Py_T_DOUBLE => {
            const pyfloat = @import("floatobject.zig");
            const v = pyfloat.PyFloat_AsDouble(value.?);
            @as(*align(1) f64, @ptrCast(ptr)).* = v;
            return 0;
        },
        Py_T_OBJECT_EX, _Py_T_OBJECT => {
            const obj_ptr = @as(*align(1) ?*cpython.PyObject, @ptrCast(ptr));
            if (obj_ptr.*) |old| {
                old.ob_refcnt -= 1;
            }
            value.?.ob_refcnt += 1;
            obj_ptr.* = value;
            return 0;
        },
        else => return -1,
    }
}
