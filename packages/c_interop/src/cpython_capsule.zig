/// CPython Capsule API
///
/// Capsules are used to pass opaque C pointers through Python.
/// Critical for NumPy's C API exposure.

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

/// Capsule destructor function type
pub const PyCapsule_Destructor = *const fn (?*anyopaque) callconv(.c) void;

/// Capsule object
pub const PyCapsuleObject = extern struct {
    ob_base: cpython.PyObject,
    pointer: ?*anyopaque,
    name: ?[*:0]const u8,
    context: ?*anyopaque,
    destructor: ?PyCapsule_Destructor,
};

/// Create new capsule
export fn PyCapsule_New(pointer: ?*anyopaque, name: ?[*:0]const u8, destructor: ?PyCapsule_Destructor) callconv(.c) ?*cpython.PyObject {
    const capsule = allocator.create(PyCapsuleObject) catch return null;
    
    capsule.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = undefined, // TODO: &PyCapsule_Type
    };
    
    capsule.pointer = pointer;
    capsule.name = name;
    capsule.context = null;
    capsule.destructor = destructor;
    
    return @ptrCast(&capsule.ob_base);
}

/// Get pointer from capsule
export fn PyCapsule_GetPointer(capsule: *cpython.PyObject, name: ?[*:0]const u8) callconv(.c) ?*anyopaque {
    const cap = @as(*PyCapsuleObject, @ptrCast(capsule));
    
    // Verify name matches
    if (name) |n| {
        if (cap.name) |cap_name| {
            if (!std.mem.eql(u8, std.mem.span(n), std.mem.span(cap_name))) {
                return null;
            }
        } else {
            return null;
        }
    }
    
    return cap.pointer;
}

/// Set pointer in capsule
export fn PyCapsule_SetPointer(capsule: *cpython.PyObject, pointer: ?*anyopaque) callconv(.c) c_int {
    const cap = @as(*PyCapsuleObject, @ptrCast(capsule));
    cap.pointer = pointer;
    return 0;
}

/// Get capsule name
export fn PyCapsule_GetName(capsule: *cpython.PyObject) callconv(.c) ?[*:0]const u8 {
    const cap = @as(*PyCapsuleObject, @ptrCast(capsule));
    return cap.name;
}

/// Set capsule name
export fn PyCapsule_SetName(capsule: *cpython.PyObject, name: ?[*:0]const u8) callconv(.c) c_int {
    const cap = @as(*PyCapsuleObject, @ptrCast(capsule));
    cap.name = name;
    return 0;
}

/// Get capsule destructor
export fn PyCapsule_GetDestructor(capsule: *cpython.PyObject) callconv(.c) ?PyCapsule_Destructor {
    const cap = @as(*PyCapsuleObject, @ptrCast(capsule));
    return cap.destructor;
}

/// Set capsule destructor
export fn PyCapsule_SetDestructor(capsule: *cpython.PyObject, destructor: ?PyCapsule_Destructor) callconv(.c) c_int {
    const cap = @as(*PyCapsuleObject, @ptrCast(capsule));
    cap.destructor = destructor;
    return 0;
}

/// Get capsule context
export fn PyCapsule_GetContext(capsule: *cpython.PyObject) callconv(.c) ?*anyopaque {
    const cap = @as(*PyCapsuleObject, @ptrCast(capsule));
    return cap.context;
}

/// Set capsule context
export fn PyCapsule_SetContext(capsule: *cpython.PyObject, context: ?*anyopaque) callconv(.c) c_int {
    const cap = @as(*PyCapsuleObject, @ptrCast(capsule));
    cap.context = context;
    return 0;
}

/// Check if object is capsule
export fn PyCapsule_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    // TODO: Check type
    return 0;
}

// Tests
test "capsule exports" {
    _ = PyCapsule_New;
    _ = PyCapsule_GetPointer;
}
