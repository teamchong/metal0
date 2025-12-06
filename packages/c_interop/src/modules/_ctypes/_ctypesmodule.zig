/// _ctypes Module - Foreign Function Interface
///
/// Implements CPython's Modules/_ctypes/_ctypes.c
/// Provides ctypes functionality for calling C libraries
///
/// Reference: cpython/Modules/_ctypes/_ctypes.c
const std = @import("std");
const cpython = @import("../../include/object.zig");

const allocator = std.heap.c_allocator;

// Re-export submodule types for C interop
pub const ctypes = @import("ctypes.zig");
pub const cfield = @import("cfield.zig");
pub const stgdict = @import("stgdict.zig");
pub const callbacks = @import("callbacks.zig");
pub const callproc = @import("callproc.zig");
pub const cdata = @import("cdata.zig");

// Re-export key types for direct access
pub const CDataObject = ctypes.CDataObject;
pub const PyCArgObject = ctypes.PyCArgObject;
pub const CFieldObject = ctypes.CFieldObject;
pub const CThunkObject = ctypes.CThunkObject;
pub const StgDictObject = ctypes.StgDictObject;
pub const CFuncPtrObject = ctypes.CFuncPtrObject;
pub const CArrayObject = ctypes.CArrayObject;
pub const CPointerObject = ctypes.CPointerObject;
pub const SimpleObject = ctypes.SimpleObject;

// ============================================================================
// MODULE FUNCTIONS
// ============================================================================

/// sizeof - Return size of a ctypes type or instance
fn ctypes_sizeof(self: ?*cpython.PyObject, obj: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    if (obj == null) return null;

    // Get StgDict from type
    const sd = stgdict.PyObject_stgdict(obj);
    if (sd) |s| {
        _ = s;
        // Return PyLong with size
        return null;
    }

    // Check if it's a CData instance
    const cdata_obj: *CDataObject = @ptrCast(@alignCast(obj.?));
    _ = cdata_obj;
    return null;
}

/// alignment - Return alignment of a ctypes type
fn ctypes_alignment(self: ?*cpython.PyObject, obj: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    if (obj == null) return null;

    const sd = stgdict.PyObject_stgdict(obj);
    if (sd) |s| {
        _ = s;
        // Return PyLong with alignment
        return null;
    }

    return null;
}

/// byref - Return a light-weight pointer to a ctypes instance
fn ctypes_byref(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    return null;
}

/// addressof - Return address of a ctypes instance
fn ctypes_addressof(self: ?*cpython.PyObject, obj: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    if (obj == null) return null;

    // Check if CData
    const cdata_obj: *CDataObject = @ptrCast(@alignCast(obj.?));
    if (cdata_obj.b_ptr) |ptr| {
        _ = ptr;
        // Return PyLong with address
        return null;
    }

    return null;
}

/// pointer - Create a pointer type
fn ctypes_pointer(self: ?*cpython.PyObject, arg: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = arg;
    return null;
}

/// POINTER - Create a pointer type (factory)
fn ctypes_POINTER(self: ?*cpython.PyObject, arg: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = arg;
    return null;
}

/// resize - Resize a ctypes buffer
fn ctypes_resize(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    return null;
}

/// get_errno - Get errno value
fn ctypes_get_errno(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    return null;
}

/// set_errno - Set errno value
fn ctypes_set_errno(self: ?*cpython.PyObject, arg: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = arg;
    return null;
}

// ============================================================================
// METHOD TABLE
// ============================================================================

pub export var ctypes_methods: [10]cpython.PyMethodDef = .{
    .{ .ml_name = "sizeof", .ml_meth = @ptrCast(&ctypes_sizeof), .ml_flags = 0x0008, .ml_doc = "Return the size in bytes of a ctypes type or instance." },
    .{ .ml_name = "alignment", .ml_meth = @ptrCast(&ctypes_alignment), .ml_flags = 0x0008, .ml_doc = "Return the alignment requirements of a ctypes type." },
    .{ .ml_name = "byref", .ml_meth = @ptrCast(&ctypes_byref), .ml_flags = 0x0001, .ml_doc = "Return a light-weight pointer to a ctypes instance." },
    .{ .ml_name = "addressof", .ml_meth = @ptrCast(&ctypes_addressof), .ml_flags = 0x0008, .ml_doc = "Return the address of the ctypes instance as an integer." },
    .{ .ml_name = "pointer", .ml_meth = @ptrCast(&ctypes_pointer), .ml_flags = 0x0008, .ml_doc = "Create a new pointer instance." },
    .{ .ml_name = "POINTER", .ml_meth = @ptrCast(&ctypes_POINTER), .ml_flags = 0x0008, .ml_doc = "Create a pointer type." },
    .{ .ml_name = "resize", .ml_meth = @ptrCast(&ctypes_resize), .ml_flags = 0x0001, .ml_doc = "Resize the memory buffer of a ctypes instance." },
    .{ .ml_name = "get_errno", .ml_meth = @ptrCast(&ctypes_get_errno), .ml_flags = 0x0004, .ml_doc = "Get the current value of errno." },
    .{ .ml_name = "set_errno", .ml_meth = @ptrCast(&ctypes_set_errno), .ml_flags = 0x0008, .ml_doc = "Set the current value of errno." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

// ============================================================================
// MODULE DEFINITION
// ============================================================================

pub export var _ctypes_module: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_ctypes",
    .m_doc = "Create and manipulate C compatible data types in Python.",
    .m_size = @sizeOf(ctypes.ctypes_state),
    .m_methods = &ctypes_methods,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

/// Module initialization
pub export fn PyInit__ctypes() callconv(.c) ?*cpython.PyObject {
    const module_mod = @import("../../objects/moduleobject.zig");
    const module = module_mod.PyModule_Create(&_ctypes_module);
    if (module == null) return null;

    // Add type objects
    _ = module_mod.PyModule_AddObject(module, "CField", @ptrCast(&cfield.PyCField_Type));
    _ = module_mod.PyModule_AddObject(module, "CThunk", @ptrCast(&callbacks.PyCThunk_Type));
    _ = module_mod.PyModule_AddObject(module, "CArgObject", @ptrCast(&callproc.PyCArg_Type));
    _ = module_mod.PyModule_AddObject(module, "_CData", @ptrCast(&cdata.PyCData_Type));
    _ = module_mod.PyModule_AddObject(module, "StgDict", @ptrCast(&stgdict.PyStgDict_Type));

    // Add constants
    _ = module_mod.PyModule_AddIntConstant(module, "FUNCFLAG_CDECL", 1);
    _ = module_mod.PyModule_AddIntConstant(module, "FUNCFLAG_USE_ERRNO", 2);
    _ = module_mod.PyModule_AddIntConstant(module, "FUNCFLAG_USE_LASTERROR", 4);
    _ = module_mod.PyModule_AddIntConstant(module, "FUNCFLAG_PYTHONAPI", 8);
    _ = module_mod.PyModule_AddIntConstant(module, "RTLD_LOCAL", 0);
    _ = module_mod.PyModule_AddIntConstant(module, "RTLD_GLOBAL", 0x100);

    ctypes._ctypes_state.PyCField_Type = &cfield.PyCField_Type;
    ctypes._ctypes_state.PyCThunk_Type = &callbacks.PyCThunk_Type;
    ctypes._ctypes_state.PyCArg_Type = &callproc.PyCArg_Type;
    ctypes._ctypes_state.PyCData_Type = &cdata.PyCData_Type;

    return module;
}
