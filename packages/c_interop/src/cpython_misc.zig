/// CPython Miscellaneous Utilities
///
/// Implements memory management, object utilities, and capsule API.

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

// Use centralized extern declarations
const Py_INCREF = traits.externs.Py_INCREF;
const Py_DECREF = traits.externs.Py_DECREF;
const PyErr_SetString = traits.externs.PyErr_SetString;

// ============================================================================
// Raw Memory Allocators (not tracked by Python)
// ============================================================================

/// Allocate raw memory (not tracked by GC)
/// Returns pointer to allocated memory or null on failure
export fn PyMem_RawMalloc(size: usize) callconv(.c) ?*anyopaque {
    return std.c.malloc(size);
}

/// Reallocate raw memory
/// Returns pointer to reallocated memory or null on failure
export fn PyMem_RawRealloc(ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    return std.c.realloc(ptr, size);
}

/// Free raw memory
export fn PyMem_RawFree(ptr: ?*anyopaque) callconv(.c) void {
    std.c.free(ptr);
}

/// Allocate zeroed raw memory
export fn PyMem_RawCalloc(nelem: usize, elsize: usize) callconv(.c) ?*anyopaque {
    return std.c.calloc(nelem, elsize);
}

// ============================================================================
// Python Memory Allocators (tracked by Python memory manager)
// ============================================================================

/// Allocate memory from Python heap
/// Similar to PyMem_RawMalloc but tracked by Python
/// Uses C malloc directly - no additional tracking in metal0's AOT model
export fn PyMem_Malloc(size: usize) callconv(.c) ?*anyopaque {
    return std.c.malloc(size);
}

/// Reallocate memory from Python heap
export fn PyMem_Realloc(ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    return std.c.realloc(ptr, size);
}

/// Free memory from Python heap
export fn PyMem_Free(ptr: ?*anyopaque) callconv(.c) void {
    std.c.free(ptr);
}

/// Allocate zeroed memory from Python heap
export fn PyMem_Calloc(nelem: usize, elsize: usize) callconv(.c) ?*anyopaque {
    return std.c.calloc(nelem, elsize);
}

/// Resize memory (NEW and DEL variants)
/// PyMem_NEW is a macro in CPython - we implement the function version
export fn PyMem_New(size: usize, count: usize) callconv(.c) ?*anyopaque {
    return PyMem_Malloc(size * count);
}

/// Memory allocator domain
pub const PyMemAllocatorDomain = enum(c_int) {
    PYMEM_DOMAIN_RAW = 0,
    PYMEM_DOMAIN_MEM = 1,
    PYMEM_DOMAIN_OBJ = 2,
};

/// Memory allocator structure
pub const PyMemAllocatorEx = extern struct {
    ctx: ?*anyopaque,
    malloc: ?*const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque,
    calloc: ?*const fn (?*anyopaque, usize, usize) callconv(.c) ?*anyopaque,
    realloc: ?*const fn (?*anyopaque, ?*anyopaque, usize) callconv(.c) ?*anyopaque,
    free: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
};

// Default allocators (store original allocators)
var raw_allocator: PyMemAllocatorEx = .{
    .ctx = null,
    .malloc = null,
    .calloc = null,
    .realloc = null,
    .free = null,
};

/// Get current memory allocator
export fn PyMem_GetAllocator(domain: c_int, allocator_out: *PyMemAllocatorEx) callconv(.c) void {
    _ = domain;
    allocator_out.* = raw_allocator;
}

/// Set memory allocator (returns 0 on success)
export fn PyMem_SetAllocator(domain: c_int, allocator_in: *const PyMemAllocatorEx) callconv(.c) void {
    _ = domain;
    raw_allocator = allocator_in.*;
}

/// Set up debug hooks on memory allocators
export fn PyMem_SetupDebugHooks() callconv(.c) void {
    // No-op in our implementation
}

// ============================================================================
// Object Memory Allocators (for Python objects)
// ============================================================================

/// Allocate memory for a Python object
/// Used when creating new object instances
/// Uses C malloc directly - metal0 doesn't use CPython's pymalloc arena
export fn PyObject_Malloc(size: usize) callconv(.c) ?*anyopaque {
    return std.c.malloc(size);
}

/// Reallocate memory for a Python object
export fn PyObject_Realloc(ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    return std.c.realloc(ptr, size);
}

/// Free memory for a Python object
export fn PyObject_Free(ptr: ?*anyopaque) callconv(.c) void {
    std.c.free(ptr);
}

/// Allocate zeroed memory for a Python object
export fn PyObject_Calloc(nelem: usize, elsize: usize) callconv(.c) ?*anyopaque {
    return std.c.calloc(nelem, elsize);
}

// ============================================================================
// Generic Attribute Access
// ============================================================================

/// Generic get attribute implementation
/// Default implementation that looks up attribute in object's dict and type
export fn PyObject_GenericGetAttr(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);

    // First, check type's tp_getattro (may have custom logic)
    if (type_obj.tp_getattro) |getattro| {
        if (getattro != PyObject_GenericGetAttr) {
            return getattro(obj, name);
        }
    }

    // Look up in type's dict (class attributes, methods)
    if (type_obj.tp_dict) |type_dict| {
        const pydict = @import("pyobject_dict.zig");
        if (pydict.PyDict_GetItem(type_dict, name)) |value| {
            // Check if it's a descriptor (has __get__)
            const value_type = cpython.Py_TYPE(value);
            if (value_type.tp_descr_get) |descr_get| {
                return descr_get(value, obj, @ptrCast(type_obj));
            }
            Py_INCREF(value);
            return value;
        }
    }

    // Look up in instance dict if available
    if (type_obj.tp_dictoffset != 0) {
        const dict_ptr = @as(*?*cpython.PyObject, @ptrFromInt(@intFromPtr(obj) + @as(usize, @intCast(type_obj.tp_dictoffset))));
        if (dict_ptr.*) |instance_dict| {
            const pydict = @import("pyobject_dict.zig");
            if (pydict.PyDict_GetItem(instance_dict, name)) |value| {
                Py_INCREF(value);
                return value;
            }
        }
    }

    PyErr_SetString(@ptrFromInt(0), "attribute not found");
    return null;
}

/// Generic get instance dict
/// Returns the __dict__ attribute of an object
export fn PyObject_GenericGetDict(obj: *cpython.PyObject, context: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    _ = context;
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_dictoffset != 0) {
        const dict_ptr = @as(*?*cpython.PyObject, @ptrFromInt(@intFromPtr(obj) + @as(usize, @intCast(type_obj.tp_dictoffset))));
        if (dict_ptr.*) |dict| {
            Py_INCREF(dict);
            return dict;
        }
        // Create new dict if none exists
        const pydict = @import("pyobject_dict.zig");
        const new_dict = pydict.PyDict_New() orelse return null;
        dict_ptr.* = new_dict;
        Py_INCREF(new_dict);
        return new_dict;
    }

    PyErr_SetString(@ptrFromInt(0), "object has no __dict__");
    return null;
}

/// Generic set instance dict
/// Sets the __dict__ attribute of an object
export fn PyObject_GenericSetDict(obj: *cpython.PyObject, value: *cpython.PyObject, context: ?*anyopaque) callconv(.c) c_int {
    _ = context;
    const type_obj = cpython.Py_TYPE(obj);

    // Check if value is a dict
    const pydict = @import("pyobject_dict.zig");
    if (pydict.PyDict_Check(value) == 0) {
        PyErr_SetString(@ptrFromInt(0), "__dict__ must be set to a dictionary");
        return -1;
    }

    if (type_obj.tp_dictoffset != 0) {
        const dict_ptr = @as(*?*cpython.PyObject, @ptrFromInt(@intFromPtr(obj) + @as(usize, @intCast(type_obj.tp_dictoffset))));

        // DECREF old dict
        if (dict_ptr.*) |old_dict| {
            Py_DECREF(old_dict);
        }

        // Set new dict (INCREF it)
        Py_INCREF(value);
        dict_ptr.* = value;
        return 0;
    }

    PyErr_SetString(@ptrFromInt(0), "object has no __dict__");
    return -1;
}

/// Generic set attribute implementation
/// Default implementation that stores attribute in object's dict
export fn PyObject_GenericSetAttr(obj: *cpython.PyObject, name: *cpython.PyObject, value: ?*cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);

    // Check for data descriptor in type (has __set__)
    if (type_obj.tp_dict) |type_dict| {
        const pydict = @import("pyobject_dict.zig");
        if (pydict.PyDict_GetItem(type_dict, name)) |descr| {
            const descr_type = cpython.Py_TYPE(descr);
            if (descr_type.tp_descr_set) |descr_set| {
                return descr_set(descr, obj, value);
            }
        }
    }

    // Store in instance dict
    if (type_obj.tp_dictoffset != 0) {
        const dict_ptr = @as(*?*cpython.PyObject, @ptrFromInt(@intFromPtr(obj) + @as(usize, @intCast(type_obj.tp_dictoffset))));
        const pydict = @import("pyobject_dict.zig");

        // Create instance dict if needed
        if (dict_ptr.* == null) {
            dict_ptr.* = pydict.PyDict_New();
            if (dict_ptr.* == null) return -1;
        }

        if (value) |v| {
            return pydict.PyDict_SetItem(dict_ptr.*.?, name, v);
        } else {
            // Delete
            return if (pydict.PyDict_DelItem(dict_ptr.*.?, name) == 0) 0 else -1;
        }
    }

    PyErr_SetString(@ptrFromInt(0), "cannot set attribute");
    return -1;
}

/// Set attribute using string name
export fn PyObject_SetAttrString(obj: *cpython.PyObject, name: [*:0]const u8, value: *cpython.PyObject) callconv(.c) c_int {
    const unicode = @import("cpython_unicode.zig");
    const name_obj = unicode.PyUnicode_FromString(name) orelse return -1;
    defer Py_DECREF(name_obj);
    return PyObject_SetAttr(obj, name_obj, value);
}

/// Delete attribute using string name
export fn PyObject_DelAttrString(obj: *cpython.PyObject, name: [*:0]const u8) callconv(.c) c_int {
    const unicode = @import("cpython_unicode.zig");
    const name_obj = unicode.PyUnicode_FromString(name) orelse return -1;
    defer Py_DECREF(name_obj);
    return PyObject_SetAttr(obj, name_obj, null);
}

/// Get attribute using string name
export fn PyObject_GetAttrString(obj: *cpython.PyObject, name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const unicode = @import("cpython_unicode.zig");
    const name_obj = unicode.PyUnicode_FromString(name) orelse return null;
    defer Py_DECREF(name_obj);
    return PyObject_GetAttr(obj, name_obj);
}

/// Get attribute using object name
export fn PyObject_GetAttr(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);

    // Use type's tp_getattro if available
    if (type_obj.tp_getattro) |getattro| {
        return getattro(obj, name);
    }

    // Fallback to generic
    return PyObject_GenericGetAttr(obj, name);
}

/// Set attribute using object name
export fn PyObject_SetAttr(obj: *cpython.PyObject, name: *cpython.PyObject, value: ?*cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);

    // Use type's tp_setattro if available
    if (type_obj.tp_setattro) |setattro| {
        return setattro(obj, name, value);
    }

    // Fallback to generic
    return PyObject_GenericSetAttr(obj, name, value);
}

/// Check if object has attribute (string name)
/// Returns 1 if exists, 0 if not
export fn PyObject_HasAttrString(obj: *cpython.PyObject, name: [*:0]const u8) callconv(.c) c_int {
    const attr = PyObject_GetAttrString(obj, name);
    if (attr) |a| {
        Py_DECREF(a);
        // Clear any error that might have been set
        const exc = @import("pyobject_exceptions.zig");
        exc.PyErr_Clear();
        return 1;
    }
    // Clear error from failed lookup
    const exc = @import("pyobject_exceptions.zig");
    exc.PyErr_Clear();
    return 0;
}

/// Check if object has attribute (object name)
export fn PyObject_HasAttr(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) c_int {
    const attr = PyObject_GetAttr(obj, name);
    if (attr) |a| {
        Py_DECREF(a);
        const exc = @import("pyobject_exceptions.zig");
        exc.PyErr_Clear();
        return 1;
    }
    const exc = @import("pyobject_exceptions.zig");
    exc.PyErr_Clear();
    return 0;
}

// ============================================================================
// Capsule API - Wrapping C pointers in Python objects
// ============================================================================

/// Capsule destructor function type
pub const PyCapsule_Destructor = *const fn (*cpython.PyObject) callconv(.c) void;

/// Capsule object structure
pub const PyCapsule = extern struct {
    ob_base: cpython.PyObject,
    pointer: ?*anyopaque,
    name: ?[*:0]const u8,
    context: ?*anyopaque,
    destructor: ?PyCapsule_Destructor,
};

/// Capsule type object
pub var PyCapsule_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "PyCapsule",
    .tp_basicsize = @intCast(@sizeOf(PyCapsule)),
    .tp_itemsize = 0,
    .tp_dealloc = capsule_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = capsule_repr,
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
    .tp_doc = "Capsule objects wrap a C pointer",
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
    .tp_watched = 0,
    .tp_versions_used = 0,
};

fn capsule_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const capsule: *PyCapsule = @ptrCast(@alignCast(obj));
    if (capsule.destructor) |destructor| {
        destructor(obj);
    }
    std.c.free(capsule);
}

fn capsule_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const capsule: *PyCapsule = @ptrCast(@alignCast(obj));
    const unicode = @import("cpython_unicode.zig");

    var buf: [128]u8 = undefined;
    const name = capsule.name orelse "NULL";
    const str = std.fmt.bufPrint(&buf, "<capsule object \"{s}\" at 0x{x}>", .{
        std.mem.span(name),
        @intFromPtr(capsule.pointer)
    }) catch return null;
    return unicode.PyUnicode_FromStringAndSize(str.ptr, @intCast(str.len));
}

/// Create a new capsule object
/// Wraps a C pointer in a Python object with optional destructor
export fn PyCapsule_New(pointer: ?*anyopaque, name: ?[*:0]const u8, destructor: ?PyCapsule_Destructor) callconv(.c) ?*cpython.PyObject {
    if (pointer == null) {
        PyErr_SetString(@ptrFromInt(0), "PyCapsule_New called with null pointer");
        return null;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(std.c.malloc(@sizeOf(PyCapsule)) orelse return null));
    capsule.ob_base.ob_refcnt = 1;
    capsule.ob_base.ob_type = &PyCapsule_Type;
    capsule.pointer = pointer;
    capsule.name = name;
    capsule.context = null;
    capsule.destructor = destructor;

    return @ptrCast(capsule);
}

/// Get pointer from capsule object
/// name must match capsule name if not null
export fn PyCapsule_GetPointer(capsule: *cpython.PyObject, name: ?[*:0]const u8) callconv(.c) ?*anyopaque {
    if (PyCapsule_CheckExact(capsule) == 0) {
        PyErr_SetString(@ptrFromInt(0), "expected a PyCapsule object");
        return null;
    }

    const cap: *PyCapsule = @ptrCast(@alignCast(capsule));

    // Verify names match if both provided
    if (name != null and cap.name != null) {
        const name_str = std.mem.span(name.?);
        const cap_name_str = std.mem.span(cap.name.?);
        if (!std.mem.eql(u8, name_str, cap_name_str)) {
            PyErr_SetString(@ptrFromInt(0), "PyCapsule_GetPointer called with incorrect name");
            return null;
        }
    } else if (name != null and cap.name == null) {
        PyErr_SetString(@ptrFromInt(0), "PyCapsule_GetPointer called with incorrect name");
        return null;
    }

    return cap.pointer;
}

/// Set pointer in capsule object
/// Returns 0 on success, -1 on error
export fn PyCapsule_SetPointer(capsule: *cpython.PyObject, pointer: *anyopaque) callconv(.c) c_int {
    if (PyCapsule_CheckExact(capsule) == 0) {
        PyErr_SetString(@ptrFromInt(0), "expected a PyCapsule object");
        return -1;
    }

    const cap: *PyCapsule = @ptrCast(@alignCast(capsule));
    cap.pointer = pointer;
    return 0;
}

/// Get capsule name
export fn PyCapsule_GetName(capsule: *cpython.PyObject) callconv(.c) ?[*:0]const u8 {
    if (PyCapsule_CheckExact(capsule) == 0) {
        return null;
    }
    const cap: *PyCapsule = @ptrCast(@alignCast(capsule));
    return cap.name;
}

/// Set capsule name
/// Returns 0 on success, -1 on error
export fn PyCapsule_SetName(capsule: *cpython.PyObject, name: [*:0]const u8) callconv(.c) c_int {
    if (PyCapsule_CheckExact(capsule) == 0) {
        return -1;
    }
    const cap: *PyCapsule = @ptrCast(@alignCast(capsule));
    cap.name = name;
    return 0;
}

/// Get capsule destructor
export fn PyCapsule_GetDestructor(capsule: *cpython.PyObject) callconv(.c) ?PyCapsule_Destructor {
    if (PyCapsule_CheckExact(capsule) == 0) {
        return null;
    }
    const cap: *PyCapsule = @ptrCast(@alignCast(capsule));
    return cap.destructor;
}

/// Set capsule destructor
/// Returns 0 on success, -1 on error
export fn PyCapsule_SetDestructor(capsule: *cpython.PyObject, destructor: PyCapsule_Destructor) callconv(.c) c_int {
    if (PyCapsule_CheckExact(capsule) == 0) {
        return -1;
    }
    const cap: *PyCapsule = @ptrCast(@alignCast(capsule));
    cap.destructor = destructor;
    return 0;
}

/// Get capsule context pointer
export fn PyCapsule_GetContext(capsule: *cpython.PyObject) callconv(.c) ?*anyopaque {
    if (PyCapsule_CheckExact(capsule) == 0) {
        return null;
    }
    const cap: *PyCapsule = @ptrCast(@alignCast(capsule));
    return cap.context;
}

/// Set capsule context pointer
/// Returns 0 on success, -1 on error
export fn PyCapsule_SetContext(capsule: *cpython.PyObject, context: *anyopaque) callconv(.c) c_int {
    if (PyCapsule_CheckExact(capsule) == 0) {
        return -1;
    }
    const cap: *PyCapsule = @ptrCast(@alignCast(capsule));
    cap.context = context;
    return 0;
}

/// Check if object is a capsule
/// Returns 1 if capsule, 0 otherwise
export fn PyCapsule_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyCapsule_Type) 1 else 0;
}

/// Import pointer from module using capsule
/// Used to share C API between extensions (format: "module.attribute")
export fn PyCapsule_Import(name: [*:0]const u8, no_block: c_int) callconv(.c) ?*anyopaque {
    _ = no_block;
    const name_str = std.mem.span(name);

    // Find the last dot to split module.attribute
    var last_dot: ?usize = null;
    for (name_str, 0..) |c, i| {
        if (c == '.') last_dot = i;
    }

    if (last_dot == null) {
        PyErr_SetString(@ptrFromInt(0), "PyCapsule_Import: name must contain a dot");
        return null;
    }

    // This requires module import machinery - stub for now
    // Full implementation would:
    // 1. Import the module (name_str[0..last_dot.?])
    // 2. Get the attribute (name_str[last_dot.?+1..])
    // 3. Extract pointer from capsule
    return null;
}

// ============================================================================
// Hash utilities
// ============================================================================

// PyObject_Hash is in cpython_object_protocol.zig

/// Check if object is hashable
/// Returns 1 if hashable, 0 otherwise
export fn PyObject_IsHashable(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj.tp_hash != null) 1 else 0;
}

/// Hash a pointer value
/// Returns hash suitable for pointer-based identity hashing
export fn _Py_HashPointer(ptr: ?*anyopaque) callconv(.c) isize {
    if (ptr == null) return 0;
    const addr = @intFromPtr(ptr);
    // Mix bits for better distribution
    return @intCast((addr >> 4) ^ (addr >> 8) ^ addr);
}

/// Hash bytes
/// Returns hash of byte array using SipHash-like algorithm
export fn _Py_HashBytes(src: [*]const u8, len: isize) callconv(.c) isize {
    if (len <= 0) return 0;
    const bytes = src[0..@intCast(len)];

    // Simple FNV-1a hash
    var hash: u64 = 0xcbf29ce484222325;
    for (bytes) |b| {
        hash ^= b;
        hash *%= 0x100000001b3;
    }

    // Ensure non-negative for Python compatibility
    return @intCast(hash & 0x7FFFFFFFFFFFFFFF);
}

/// Hash a double value
/// Returns hash consistent with integer hashing
export fn _Py_HashDouble(obj: *cpython.PyObject, value: f64) callconv(.c) isize {
    _ = obj;
    // Handle special cases
    if (std.math.isNan(value)) return 0;
    if (std.math.isInf(value)) return if (value > 0) 314159 else -314159;

    // Check if it's an integer value
    const truncated = @trunc(value);
    if (value == truncated) {
        return @intCast(@as(i64, @intFromFloat(truncated)));
    }

    // Hash the bits
    const bits: u64 = @bitCast(value);
    return @intCast((bits ^ (bits >> 32)) & 0x7FFFFFFFFFFFFFFF);
}

/// Constant used as hash for unhashable types
pub const Py_hash_t = isize;
pub const Py_uhash_t = usize;

// ============================================================================
// Object Creation and Initialization
// ============================================================================

/// Initialize a pre-allocated object
/// Sets refcount to 1 and type pointer
export fn PyObject_Init(op: *cpython.PyObject, tp: *cpython.PyTypeObject) callconv(.c) *cpython.PyObject {
    op.ob_refcnt = 1;
    op.ob_type = tp;
    return op;
}

/// Initialize a pre-allocated variable-size object
export fn PyObject_InitVar(op: *cpython.PyVarObject, tp: *cpython.PyTypeObject, size: isize) callconv(.c) *cpython.PyVarObject {
    op.ob_base.ob_refcnt = 1;
    op.ob_base.ob_type = tp;
    op.ob_size = size;
    return op;
}

/// Allocate a new object of given type (internal)
export fn _PyObject_New(tp: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    const size: usize = @intCast(tp.tp_basicsize);
    const mem = std.c.malloc(size) orelse return null;
    const obj: *cpython.PyObject = @ptrCast(@alignCast(mem));
    return PyObject_Init(obj, tp);
}

/// Allocate a new variable-size object (internal)
export fn _PyObject_NewVar(tp: *cpython.PyTypeObject, nitems: isize) callconv(.c) ?*cpython.PyVarObject {
    const basicsize: usize = @intCast(tp.tp_basicsize);
    const itemsize: usize = @intCast(tp.tp_itemsize);
    const size = basicsize + itemsize * @as(usize, @intCast(nitems));
    const mem = std.c.malloc(size) orelse return null;
    const obj: *cpython.PyVarObject = @ptrCast(@alignCast(mem));
    return PyObject_InitVar(obj, tp, nitems);
}

/// Allocate a new object using type's allocator
export fn PyObject_New(tp: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    if (tp.tp_alloc) |alloc| {
        return alloc(tp, 0);
    }
    return _PyObject_New(tp);
}

/// Allocate a new variable-size object using type's allocator
export fn PyObject_NewVar(tp: *cpython.PyTypeObject, nitems: isize) callconv(.c) ?*cpython.PyVarObject {
    if (tp.tp_alloc) |alloc| {
        const obj = alloc(tp, nitems) orelse return null;
        return @ptrCast(@alignCast(obj));
    }
    return _PyObject_NewVar(tp, nitems);
}

/// Delete an object
export fn PyObject_Del(op: ?*anyopaque) callconv(.c) void {
    if (op) |ptr| {
        std.c.free(ptr);
    }
}

// ============================================================================
// Reference Count Helpers (CPython 3.10+ style)
// ============================================================================

/// Increment reference count and return object (for chaining)
export fn Py_NewRef(obj: *cpython.PyObject) callconv(.c) *cpython.PyObject {
    Py_INCREF(obj);
    return obj;
}

/// Increment reference count of nullable object and return it
export fn Py_XNewRef(obj: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (obj) |o| {
        Py_INCREF(o);
        return o;
    }
    return null;
}

/// Alias for Py_INCREF (for compatibility)
export fn Py_IncRef(obj: *cpython.PyObject) callconv(.c) void {
    Py_INCREF(obj);
}

/// Alias for Py_DECREF (for compatibility)
export fn Py_DecRef(obj: *cpython.PyObject) callconv(.c) void {
    Py_DECREF(obj);
}

// ============================================================================
// Type Checking
// ============================================================================

/// Check if object is instance of type
/// Returns 1 if instance, 0 if not, -1 on error
export fn PyObject_IsInstance(obj: *cpython.PyObject, typeinfo: *cpython.PyObject) callconv(.c) c_int {
    const obj_type = cpython.Py_TYPE(obj);

    // Direct type check
    if (@intFromPtr(obj_type) == @intFromPtr(typeinfo)) {
        return 1;
    }

    // Check if typeinfo is a type object
    const typeinfo_as_type: *cpython.PyTypeObject = @ptrCast(@alignCast(typeinfo));

    // Check inheritance via MRO
    if (obj_type.tp_mro) |mro| {
        const pytuple = @import("pyobject_tuple.zig");
        const len = pytuple.PyTuple_Size(mro);
        var i: isize = 0;
        while (i < len) : (i += 1) {
            const base = pytuple.PyTuple_GetItem(mro, i);
            if (base) |b| {
                if (@intFromPtr(b) == @intFromPtr(typeinfo)) {
                    return 1;
                }
            }
        }
    }

    // Check subtype relationship
    return PyType_IsSubtype(obj_type, typeinfo_as_type);
}

/// Check if derived is subclass of base
/// Returns 1 if subclass, 0 if not, -1 on error
export fn PyObject_IsSubclass(derived: *cpython.PyObject, base: *cpython.PyObject) callconv(.c) c_int {
    const derived_type: *cpython.PyTypeObject = @ptrCast(@alignCast(derived));
    const base_type: *cpython.PyTypeObject = @ptrCast(@alignCast(base));
    return PyType_IsSubtype(derived_type, base_type);
}

/// Check if object's type is exactly the given type or a subtype
/// Equivalent to isinstance(obj, type)
export fn PyObject_TypeCheck(obj: *cpython.PyObject, tp: *cpython.PyTypeObject) callconv(.c) c_int {
    const obj_type = cpython.Py_TYPE(obj);
    if (obj_type == tp) return 1;
    return PyType_IsSubtype(obj_type, tp);
}

fn PyType_IsSubtype(derived: *cpython.PyTypeObject, base: *cpython.PyTypeObject) c_int {
    // Same type
    if (derived == base) return 1;

    // Check MRO
    if (derived.tp_mro) |mro| {
        const pytuple = @import("pyobject_tuple.zig");
        const len = pytuple.PyTuple_Size(mro);
        var i: isize = 0;
        while (i < len) : (i += 1) {
            const t = pytuple.PyTuple_GetItem(mro, i);
            if (t) |typ| {
                if (@intFromPtr(typ) == @intFromPtr(base)) {
                    return 1;
                }
            }
        }
    }

    // Check tp_base chain
    var current: ?*cpython.PyTypeObject = derived.tp_base;
    while (current) |tp| {
        if (tp == base) return 1;
        current = tp.tp_base;
    }

    return 0;
}

/// Get list of attribute names
export fn PyObject_Dir(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const pylist = @import("pyobject_list.zig");
    const pydict = @import("pyobject_dict.zig");

    const result = pylist.PyList_New(0) orelse return null;

    // Add instance dict keys
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj.tp_dictoffset != 0) {
        const dict_ptr = @as(*?*cpython.PyObject, @ptrFromInt(@intFromPtr(obj) + @as(usize, @intCast(type_obj.tp_dictoffset))));
        if (dict_ptr.*) |instance_dict| {
            if (pydict.PyDict_Keys(instance_dict)) |keys| {
                defer Py_DECREF(keys);
                // Add keys to result
                const pytuple = @import("pyobject_tuple.zig");
                if (pytuple.PyTuple_Check(keys) != 0) {
                    const len = pytuple.PyTuple_Size(keys);
                    var i: isize = 0;
                    while (i < len) : (i += 1) {
                        if (pytuple.PyTuple_GetItem(keys, i)) |key| {
                            _ = pylist.PyList_Append(result, key);
                        }
                    }
                }
            }
        }
    }

    // Add type dict keys
    if (type_obj.tp_dict) |type_dict| {
        if (pydict.PyDict_Keys(type_dict)) |keys| {
            defer Py_DECREF(keys);
            const pytuple = @import("pyobject_tuple.zig");
            if (pytuple.PyTuple_Check(keys) != 0) {
                const len = pytuple.PyTuple_Size(keys);
                var i: isize = 0;
                while (i < len) : (i += 1) {
                    if (pytuple.PyTuple_GetItem(keys, i)) |key| {
                        _ = pylist.PyList_Append(result, key);
                    }
                }
            }
        }
    }

    return result;
}

/// Format object using format spec
export fn PyObject_Format(obj: *cpython.PyObject, format_spec: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = format_spec;
    // Default: just return str(obj)
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj.tp_str) |str_fn| {
        return str_fn(obj);
    }
    if (type_obj.tp_repr) |repr_fn| {
        return repr_fn(obj);
    }
    PyErr_SetString(@ptrFromInt(0), "object has no string representation");
    return null;
}

// ============================================================================
// ASYNC ITERATOR PROTOCOL
// ============================================================================

/// Get async iterator (__aiter__)
export fn PyObject_GetAIter(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_as_async) |async_procs| {
        if (async_procs.am_aiter) |aiter_fn| {
            return aiter_fn(obj);
        }
    }

    PyErr_SetString(@ptrFromInt(0), "object is not async iterable");
    return null;
}

/// Get next item from async iterator (__anext__)
export fn PyObject_GetANext(aiter: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(aiter);

    if (type_obj.tp_as_async) |async_procs| {
        if (async_procs.am_anext) |anext_fn| {
            return anext_fn(aiter);
        }
    }

    PyErr_SetString(@ptrFromInt(0), "object is not an async iterator");
    return null;
}

/// Clear weak references to object
export fn PyObject_ClearWeakRefs(obj: *cpython.PyObject) callconv(.c) void {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_weaklistoffset != 0) {
        const weaklist_ptr = @as(*?*cpython.PyObject, @ptrFromInt(@intFromPtr(obj) + @as(usize, @intCast(type_obj.tp_weaklistoffset))));
        weaklist_ptr.* = null;
    }
}

/// Print object to file (or stdout)
export fn PyObject_Print(obj: *cpython.PyObject, fp: ?*anyopaque, flags: c_int) callconv(.c) c_int {
    _ = fp; // Usually FILE*, we'll use stdout

    // Get string representation based on flags
    // Py_PRINT_RAW = 1: use str(), else use repr()
    const type_obj = cpython.Py_TYPE(obj);
    const str_obj: ?*cpython.PyObject = if (flags & 1 != 0)
        (if (type_obj.tp_str) |str_fn| str_fn(obj) else null)
    else
        (if (type_obj.tp_repr) |repr_fn| repr_fn(obj) else null);

    if (str_obj) |s| {
        defer Py_DECREF(s);
        const pyunicode = @import("cpython_unicode.zig");
        if (pyunicode.PyUnicode_AsUTF8(s)) |cstr| {
            const slice = std.mem.span(cstr);
            _ = std.io.getStdOut().write(slice) catch return -1;
            return 0;
        }
    }

    return -1;
}
