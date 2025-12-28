/// PyCapsule - Opaque Pointer Container
/// Mirrors cpython/Objects/capsule.c
///
/// Capsules are the standard way to pass C pointers between Python modules.
/// PyTorch uses them extensively for tensor handles.
///
/// Reference: https://docs.python.org/3/c-api/capsule.html

const std = @import("std");
const Allocator = std.mem.Allocator;
const cpython = @import("../cpython.zig");
const PyObject = cpython.PyObject;
const PyTypeObject = cpython.PyTypeObject;
const Py_ssize_t = cpython.Py_ssize_t;

// =============================================================================
// Capsule Type
// =============================================================================

/// Destructor function signature
pub const PyCapsule_Destructor = ?*const fn (*PyObject) callconv(.C) void;

/// PyCapsule object structure
pub const PyCapsule = extern struct {
    ob_base: PyObject,
    /// The opaque pointer
    pointer: ?*anyopaque,
    /// Name of the capsule (for type safety)
    name: ?[*:0]const u8,
    /// Context pointer (arbitrary user data)
    context: ?*anyopaque,
    /// Destructor function (called on dealloc)
    destructor: PyCapsule_Destructor,
};

/// Capsule type object
pub var PyCapsule_Type: PyTypeObject = blk: {
    var t = cpython.makeTypeObject("PyCapsule", @sizeOf(PyCapsule), 0);
    t.tp_dealloc = capsule_dealloc;
    t.tp_repr = capsule_repr;
    t.tp_flags = cpython.Py_TPFLAGS.DEFAULT;
    t.tp_doc = "Capsule objects let you wrap a C pointer in a Python object.";
    break :blk t;
};

fn capsule_dealloc(op: *PyObject) callconv(.C) void {
    const capsule: *PyCapsule = @ptrCast(@alignCast(op));
    if (capsule.destructor) |destructor| {
        destructor(op);
    }
    // Note: We don't free the capsule itself here as it may be from an arena
}

fn capsule_repr(op: *PyObject) callconv(.C) *PyObject {
    _ = op;
    // Would return "<capsule object \"name\" at 0x...>"
    return cpython.Py_None;
}

// =============================================================================
// Capsule API Functions
// =============================================================================

/// Create a new capsule
/// Returns new reference or NULL on failure
pub fn PyCapsule_New(
    pointer: ?*anyopaque,
    name: ?[*:0]const u8,
    destructor: PyCapsule_Destructor,
) ?*PyObject {
    if (pointer == null and name == null) {
        // CPython requires at least one of pointer or name
        return null;
    }

    // Use c_allocator for CPython ABI compatibility
    const allocator = std.heap.c_allocator;
    const capsule = allocator.create(PyCapsule) catch return null;

    capsule.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyCapsule_Type,
        },
        .pointer = pointer,
        .name = name,
        .context = null,
        .destructor = destructor,
    };

    return @ptrCast(capsule);
}

/// Check if object is a valid capsule
pub fn PyCapsule_IsValid(op: ?*PyObject, name: ?[*:0]const u8) bool {
    const obj = op orelse return false;

    if (!PyCapsule_CheckExact(obj)) {
        return false;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(obj));

    // Pointer must not be NULL
    if (capsule.pointer == null) {
        return false;
    }

    // Name must match if provided
    if (name) |n| {
        if (capsule.name) |cn| {
            return std.mem.orderZ(u8, cn, n) == .eq;
        }
        return false;
    }

    return true;
}

/// Get the pointer from a capsule
pub fn PyCapsule_GetPointer(op: *PyObject, name: ?[*:0]const u8) ?*anyopaque {
    if (!PyCapsule_IsValid(op, name)) {
        return null;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op));
    return capsule.pointer;
}

/// Get the name from a capsule
pub fn PyCapsule_GetName(op: *PyObject) ?[*:0]const u8 {
    if (!PyCapsule_CheckExact(op)) {
        return null;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op));
    return capsule.name;
}

/// Get the context from a capsule
pub fn PyCapsule_GetContext(op: *PyObject) ?*anyopaque {
    if (!PyCapsule_CheckExact(op)) {
        return null;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op));
    return capsule.context;
}

/// Get the destructor from a capsule
pub fn PyCapsule_GetDestructor(op: *PyObject) PyCapsule_Destructor {
    if (!PyCapsule_CheckExact(op)) {
        return null;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op));
    return capsule.destructor;
}

/// Set the pointer in a capsule
pub fn PyCapsule_SetPointer(op: *PyObject, pointer: *anyopaque) c_int {
    if (!PyCapsule_CheckExact(op)) {
        return -1;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op));
    capsule.pointer = pointer;
    return 0;
}

/// Set the name of a capsule
pub fn PyCapsule_SetName(op: *PyObject, name: ?[*:0]const u8) c_int {
    if (!PyCapsule_CheckExact(op)) {
        return -1;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op));
    capsule.name = name;
    return 0;
}

/// Set the context of a capsule
pub fn PyCapsule_SetContext(op: *PyObject, context: ?*anyopaque) c_int {
    if (!PyCapsule_CheckExact(op)) {
        return -1;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op));
    capsule.context = context;
    return 0;
}

/// Set the destructor of a capsule
pub fn PyCapsule_SetDestructor(op: *PyObject, destructor: PyCapsule_Destructor) c_int {
    if (!PyCapsule_CheckExact(op)) {
        return -1;
    }

    const capsule: *PyCapsule = @ptrCast(@alignCast(op));
    capsule.destructor = destructor;
    return 0;
}

/// Import a capsule from a module attribute
/// e.g., PyCapsule_Import("numpy.core._multiarray_umath._ARRAY_API", 0)
pub fn PyCapsule_Import(name: [*:0]const u8, no_block: c_int) ?*anyopaque {
    _ = name;
    _ = no_block;
    // Would:
    // 1. Parse module.attr path
    // 2. Import module
    // 3. Get attribute
    // 4. Extract capsule pointer
    return null;
}

// =============================================================================
// Type Checking
// =============================================================================

/// Check if object is exactly a PyCapsule
pub fn PyCapsule_CheckExact(op: *PyObject) bool {
    return cpython.Py_IS_TYPE(op, &PyCapsule_Type);
}

// =============================================================================
// DLPack Support (for PyTorch/TensorFlow interop)
// =============================================================================

/// DLPack data type codes
pub const DLDataTypeCode = enum(u8) {
    kDLInt = 0,
    kDLUInt = 1,
    kDLFloat = 2,
    kDLBfloat = 4,
    kDLComplex = 5,
    kDLBool = 6,
};

/// DLPack device type
pub const DLDeviceType = enum(i32) {
    kDLCPU = 1,
    kDLCUDA = 2,
    kDLCUDAHost = 3,
    kDLOpenCL = 4,
    kDLVulkan = 7,
    kDLMetal = 8,
    kDLVPI = 9,
    kDLROCM = 10,
    kDLROCMHost = 11,
    kDLExtDev = 12,
    kDLCUDAManaged = 13,
    kDLOneAPI = 14,
    kDLWebGPU = 15,
    kDLHexagon = 16,
};

/// DLPack device context
pub const DLDevice = extern struct {
    device_type: DLDeviceType,
    device_id: c_int,
};

/// DLPack data type descriptor
pub const DLDataType = extern struct {
    code: DLDataTypeCode,
    bits: u8,
    lanes: u16,
};

/// DLPack tensor structure
pub const DLTensor = extern struct {
    /// Pointer to data buffer
    data: ?*anyopaque,
    /// Device context
    device: DLDevice,
    /// Number of dimensions
    ndim: c_int,
    /// Data type
    dtype: DLDataType,
    /// Shape array (size ndim)
    shape: [*]i64,
    /// Stride array in elements (size ndim), can be NULL
    strides: ?[*]i64,
    /// Byte offset to start of data
    byte_offset: u64,
};

/// DLPack managed tensor (includes deleter)
pub const DLManagedTensor = extern struct {
    dl_tensor: DLTensor,
    /// Manager context (passed to deleter)
    manager_ctx: ?*anyopaque,
    /// Deleter function
    deleter: ?*const fn (*DLManagedTensor) callconv(.C) void,
};

/// Create a DLPack capsule from tensor info
pub fn createDLPackCapsule(
    data: *anyopaque,
    shape: []const i64,
    strides: ?[]const i64,
    dtype: DLDataType,
    device: DLDevice,
) ?*PyObject {
    const allocator = std.heap.c_allocator;

    // Allocate managed tensor
    const managed = allocator.create(DLManagedTensor) catch return null;
    const shape_copy = allocator.alloc(i64, shape.len) catch {
        allocator.destroy(managed);
        return null;
    };
    @memcpy(shape_copy, shape);

    var strides_copy: ?[*]i64 = null;
    if (strides) |s| {
        const sc = allocator.alloc(i64, s.len) catch {
            allocator.free(shape_copy);
            allocator.destroy(managed);
            return null;
        };
        @memcpy(sc, s);
        strides_copy = sc.ptr;
    }

    managed.* = .{
        .dl_tensor = .{
            .data = data,
            .device = device,
            .ndim = @intCast(shape.len),
            .dtype = dtype,
            .shape = shape_copy.ptr,
            .strides = strides_copy,
            .byte_offset = 0,
        },
        .manager_ctx = managed,
        .deleter = dlpackDeleter,
    };

    // Wrap in capsule
    return PyCapsule_New(managed, "dltensor", capsuleDeleter);
}

fn dlpackDeleter(managed: *DLManagedTensor) callconv(.C) void {
    const allocator = std.heap.c_allocator;

    // Free shape array
    const shape_slice: []i64 = managed.dl_tensor.shape[0..@intCast(managed.dl_tensor.ndim)];
    allocator.free(shape_slice);

    // Free strides if present
    if (managed.dl_tensor.strides) |s| {
        const strides_slice: []i64 = s[0..@intCast(managed.dl_tensor.ndim)];
        allocator.free(strides_slice);
    }

    allocator.destroy(managed);
}

fn capsuleDeleter(capsule: *PyObject) callconv(.C) void {
    const ptr = PyCapsule_GetPointer(capsule, "dltensor");
    if (ptr) |p| {
        const managed: *DLManagedTensor = @ptrCast(@alignCast(p));
        if (managed.deleter) |deleter| {
            deleter(managed);
        }
    }
}

// =============================================================================
// Tests
// =============================================================================

test "capsule create and get" {
    var data: i32 = 42;
    const capsule = PyCapsule_New(&data, "test.pointer", null);
    try std.testing.expect(capsule != null);

    const ptr = PyCapsule_GetPointer(capsule.?, "test.pointer");
    try std.testing.expect(ptr != null);

    const recovered: *i32 = @ptrCast(@alignCast(ptr.?));
    try std.testing.expectEqual(@as(i32, 42), recovered.*);
}

test "capsule validation" {
    var data: i32 = 42;
    const capsule = PyCapsule_New(&data, "correct.name", null);

    try std.testing.expect(PyCapsule_IsValid(capsule, "correct.name"));
    try std.testing.expect(!PyCapsule_IsValid(capsule, "wrong.name"));
}

test "capsule name access" {
    var data: i32 = 42;
    const capsule = PyCapsule_New(&data, "test.name", null);

    const name = PyCapsule_GetName(capsule.?);
    try std.testing.expect(name != null);
    try std.testing.expect(std.mem.orderZ(u8, name.?, "test.name") == .eq);
}

test "capsule context" {
    var data: i32 = 42;
    var context: i64 = 123;
    const capsule = PyCapsule_New(&data, "test", null);

    try std.testing.expectEqual(@as(c_int, 0), PyCapsule_SetContext(capsule.?, &context));

    const ctx = PyCapsule_GetContext(capsule.?);
    const recovered: *i64 = @ptrCast(@alignCast(ctx.?));
    try std.testing.expectEqual(@as(i64, 123), recovered.*);
}

test "dlpack dtype" {
    const float32 = DLDataType{
        .code = .kDLFloat,
        .bits = 32,
        .lanes = 1,
    };
    try std.testing.expectEqual(@as(u8, 32), float32.bits);
}
