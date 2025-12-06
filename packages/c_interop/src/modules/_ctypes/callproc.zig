/// _ctypes/callproc - Foreign function call procedures
///
/// Implements CPython's Modules/_ctypes/callproc.c
/// Provides the mechanism for calling foreign functions
///
/// Reference: cpython/Modules/_ctypes/callproc.c
const std = @import("std");
const cpython = @import("../../include/object.zig");
const ctypes = @import("ctypes.zig");

const allocator = ctypes.allocator;

// ============================================================================
// PCARG METHODS
// ============================================================================

/// PyCArg_new - Create new PyCArg object
fn PyCArg_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    _ = type_obj;

    const mem = allocator.alignedAlloc(u8, @alignOf(ctypes.PyCArgObject), @sizeOf(ctypes.PyCArgObject)) catch return null;
    const carg: *ctypes.PyCArgObject = @ptrCast(@alignCast(mem.ptr));

    carg.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyCArg_Type },
        .pffi_type = null,
        .tag = 0,
        .value = undefined,
        .obj = null,
        .size = 0,
    };

    return @ptrCast(carg);
}

/// PyCArg_dealloc - Destructor
fn PyCArg_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const carg: *ctypes.PyCArgObject = @ptrCast(@alignCast(self.?));

    if (carg.obj) |p| p.ob_refcnt -= 1;

    const ptr: [*]u8 = @ptrCast(carg);
    allocator.free(ptr[0..@sizeOf(ctypes.PyCArgObject)]);
}

/// PyCArg_repr - String representation
fn PyCArg_repr(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const carg: *ctypes.PyCArgObject = @ptrCast(@alignCast(self.?));
    _ = carg;
    return null;
}

// ============================================================================
// CALL HELPERS
// ============================================================================

/// _ctypes_callproc - Call a C function
pub export fn _ctypes_callproc(
    pProc: ?*anyopaque,
    arguments: ?*cpython.PyObject,
    flags: c_int,
    argtypes: ?*cpython.PyObject,
    restype: ?*cpython.PyObject,
    checker: ?*cpython.PyObject,
) callconv(.c) ?*cpython.PyObject {
    _ = pProc;
    _ = arguments;
    _ = flags;
    _ = argtypes;
    _ = restype;
    _ = checker;

    // TODO: Implement foreign function call using libffi
    // 1. Convert Python arguments to C arguments
    // 2. Set up ffi_cif structure
    // 3. Call ffi_call
    // 4. Convert return value to Python

    return null;
}

/// _ctypes_get_ffi_type - Get ffi_type for a ctypes type
pub export fn _ctypes_get_ffi_type(obj: ?*cpython.PyObject) callconv(.c) ?*anyopaque {
    if (obj == null) return null;

    // Get StgDict from type
    const stgdict = @import("stgdict.zig").PyObject_stgdict(obj);
    if (stgdict == null) return null;

    return stgdict.?.ffi_type_pointer;
}

/// ConvParam - Convert a Python object to a C parameter
pub export fn ConvParam(obj: ?*cpython.PyObject, index: c_int, pa: ?*ctypes.PyCArgObject) callconv(.c) c_int {
    if (obj == null or pa == null) return -1;
    _ = index;

    // Handle different Python types
    // - None -> NULL pointer
    // - int -> c_long
    // - float -> c_double
    // - bytes -> char*
    // - str -> wchar_t*
    // - CData -> pointer to data
    // - callable -> callback

    return 0;
}

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub export var PyCArg_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_ctypes.CArgObject",
    .tp_basicsize = @sizeOf(ctypes.PyCArgObject),
    .tp_itemsize = 0,
    .tp_dealloc = PyCArg_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = PyCArg_repr,
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
    .tp_doc = "C argument object",
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
    .tp_new = PyCArg_new,
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
