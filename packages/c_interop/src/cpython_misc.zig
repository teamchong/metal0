/// CPython Miscellaneous Utilities
///
/// Implements memory management, object utilities, and capsule API.

const std = @import("std");
const cpython = @import("cpython_object.zig");

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;
extern fn PyErr_SetString(*cpython.PyObject, [*:0]const u8) callconv(.c) void;

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
export fn PyMem_Malloc(size: usize) callconv(.c) ?*anyopaque {
    // TODO: Use Python's memory allocator with tracking
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

// ============================================================================
// Object Memory Allocators (for Python objects)
// ============================================================================

/// Allocate memory for a Python object
/// Used when creating new object instances
export fn PyObject_Malloc(size: usize) callconv(.c) ?*anyopaque {
    // TODO: Use object allocator (may use pymalloc)
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
/// Default implementation that looks up attribute in object's dict
export fn PyObject_GenericGetAttr(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = obj;
    _ = name;
    // TODO: Look up attribute in obj.__dict__
    // Then check type's MRO for descriptors
    PyErr_SetString(@ptrFromInt(0), "attribute not found");
    return null;
}

/// Generic set attribute implementation
/// Default implementation that stores attribute in object's dict
export fn PyObject_GenericSetAttr(obj: *cpython.PyObject, name: *cpython.PyObject, value: ?*cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    _ = name;
    if (value) |v| {
        // TODO: Set obj.__dict__[name] = value
        // Handle descriptors with __set__ method
        _ = v;
    } else {
        // TODO: Delete obj.__dict__[name]
    }
    return 0; // Success
}

/// Set attribute using string name
/// Convenience wrapper for PyObject_SetAttr
export fn PyObject_SetAttrString(obj: *cpython.PyObject, name: [*:0]const u8, value: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    _ = name;
    _ = value;
    // TODO: Convert name to string object and call PyObject_SetAttr
    return 0; // Success
}

/// Delete attribute using string name
export fn PyObject_DelAttrString(obj: *cpython.PyObject, name: [*:0]const u8) callconv(.c) c_int {
    _ = obj;
    _ = name;
    // TODO: Convert name to string object and call PyObject_SetAttr(obj, name, null)
    return 0; // Success
}

/// Get attribute using string name
export fn PyObject_GetAttrString(obj: *cpython.PyObject, name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = obj;
    _ = name;
    // TODO: Convert name to string object and call PyObject_GetAttr
    PyErr_SetString(@ptrFromInt(0), "attribute not found");
    return null;
}

/// Check if object has attribute (string name)
/// Returns 1 if exists, 0 if not, -1 on error
export fn PyObject_HasAttrString(obj: *cpython.PyObject, name: [*:0]const u8) callconv(.c) c_int {
    const attr = PyObject_GetAttrString(obj, name);
    if (attr) |a| {
        Py_DECREF(a);
        return 1; // Has attribute
    }
    return 0; // No attribute
}

// ============================================================================
// Capsule API - Wrapping C pointers in Python objects
// ============================================================================

/// Capsule destructor function type
pub const PyCapsule_Destructor = *const fn (*cpython.PyObject) callconv(.c) void;

/// Capsule object structure (opaque)
const PyCapsule = extern struct {
    ob_base: cpython.PyObject,
    pointer: ?*anyopaque,
    name: ?[*:0]const u8,
    context: ?*anyopaque,
    destructor: ?PyCapsule_Destructor,
};

/// Create a new capsule object
/// Wraps a C pointer in a Python object with optional destructor
export fn PyCapsule_New(pointer: *anyopaque, name: ?[*:0]const u8, destructor: ?PyCapsule_Destructor) callconv(.c) ?*cpython.PyObject {
    _ = pointer;
    _ = name;
    _ = destructor;
    // TODO: Allocate capsule object and initialize fields
    // capsule.pointer = pointer
    // capsule.name = name
    // capsule.destructor = destructor
    PyErr_SetString(@ptrFromInt(0), "PyCapsule_New not implemented");
    return null;
}

/// Get pointer from capsule object
/// name must match capsule name if not null
export fn PyCapsule_GetPointer(capsule: *cpython.PyObject, name: ?[*:0]const u8) callconv(.c) ?*anyopaque {
    _ = capsule;
    _ = name;
    // TODO: Verify capsule type and name, return pointer
    // if (name != null && capsule.name != null) verify names match
    PyErr_SetString(@ptrFromInt(0), "PyCapsule_GetPointer not implemented");
    return null;
}

/// Set pointer in capsule object
/// Returns 0 on success, -1 on error
export fn PyCapsule_SetPointer(capsule: *cpython.PyObject, pointer: *anyopaque) callconv(.c) c_int {
    _ = capsule;
    _ = pointer;
    // TODO: Verify capsule type, set pointer field
    return 0; // Success
}

/// Get capsule name
export fn PyCapsule_GetName(capsule: *cpython.PyObject) callconv(.c) ?[*:0]const u8 {
    _ = capsule;
    // TODO: Return capsule.name
    return null;
}

/// Set capsule name
/// Returns 0 on success, -1 on error
export fn PyCapsule_SetName(capsule: *cpython.PyObject, name: [*:0]const u8) callconv(.c) c_int {
    _ = capsule;
    _ = name;
    // TODO: Set capsule.name
    return 0; // Success
}

/// Get capsule destructor
export fn PyCapsule_GetDestructor(capsule: *cpython.PyObject) callconv(.c) ?PyCapsule_Destructor {
    _ = capsule;
    // TODO: Return capsule.destructor
    return null;
}

/// Set capsule destructor
/// Returns 0 on success, -1 on error
export fn PyCapsule_SetDestructor(capsule: *cpython.PyObject, destructor: PyCapsule_Destructor) callconv(.c) c_int {
    _ = capsule;
    _ = destructor;
    // TODO: Set capsule.destructor
    return 0; // Success
}

/// Get capsule context pointer
export fn PyCapsule_GetContext(capsule: *cpython.PyObject) callconv(.c) ?*anyopaque {
    _ = capsule;
    // TODO: Return capsule.context
    return null;
}

/// Set capsule context pointer
/// Returns 0 on success, -1 on error
export fn PyCapsule_SetContext(capsule: *cpython.PyObject, context: *anyopaque) callconv(.c) c_int {
    _ = capsule;
    _ = context;
    // TODO: Set capsule.context
    return 0; // Success
}

/// Check if object is a capsule
/// Returns 1 if capsule, 0 otherwise
export fn PyCapsule_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    // TODO: Check if obj.ob_type == &PyCapsule_Type
    return 0; // Not a capsule
}

/// Import pointer from module using capsule
/// Used to share C API between extensions
export fn PyCapsule_Import(name: [*:0]const u8, no_block: c_int) callconv(.c) ?*anyopaque {
    _ = name;
    _ = no_block;
    // TODO: Import module, get attribute, extract capsule pointer
    // Format: "module.attribute"
    return null;
}

// ============================================================================
// Hash utilities
// ============================================================================

/// Get hash of object
/// Returns hash value or -1 on error
export fn PyObject_Hash(obj: *cpython.PyObject) callconv(.c) isize {
    const type_obj = cpython.Py_TYPE(obj);

    if (type_obj.tp_hash) |hash_func| {
        return hash_func(obj);
    }

    // Objects without hash are unhashable
    PyErr_SetString(@ptrFromInt(0), "unhashable type");
    return -1;
}

/// Check if object is hashable
/// Returns 1 if hashable, 0 otherwise
export fn PyObject_IsHashable(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj.tp_hash != null) 1 else 0;
}
