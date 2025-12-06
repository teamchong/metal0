/// _ctypes/cdata - CData base type implementation
///
/// Implements CPython's CDataObject base type
/// Provides base functionality for all ctypes data objects
///
/// Reference: cpython/Modules/_ctypes/_ctypes.c (CData_* functions)
const std = @import("std");
const cpython = @import("../../include/object.zig");
const ctypes = @import("ctypes.zig");

const allocator = ctypes.allocator;

// ============================================================================
// CDATA METHODS
// ============================================================================

/// CData_new - Create new CData object
fn CData_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;

    if (type_obj == null) return null;

    // Get size from StgDict
    const stgdict = @import("stgdict.zig").PyType_stgdict(@ptrCast(type_obj));
    const size: usize = if (stgdict) |sd| @intCast(sd.size) else @sizeOf(ctypes.CDataObject);

    const total_size = @sizeOf(ctypes.CDataObject);
    const mem = allocator.alignedAlloc(u8, @alignOf(ctypes.CDataObject), total_size) catch return null;
    const cdata: *ctypes.CDataObject = @ptrCast(@alignCast(mem.ptr));

    cdata.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = type_obj },
        .b_ptr = null,
        .b_needsfree = 0,
        .b_base = null,
        .b_size = @intCast(size),
        .b_length = 0,
        .b_index = 0,
        .b_objects = null,
        .b_value = undefined,
    };

    // Use internal buffer if small enough
    if (size <= @sizeOf(ctypes.UnionValue)) {
        cdata.b_ptr = @ptrCast(&cdata.b_value);
    } else {
        // Allocate external buffer
        const buf = allocator.alloc(u8, size) catch {
            allocator.free(mem);
            return null;
        };
        cdata.b_ptr = buf.ptr;
        cdata.b_needsfree = 1;
    }

    return @ptrCast(cdata);
}

/// CData_init - Initialize CData
fn CData_init(self: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) c_int {
    _ = args;
    _ = kwargs;
    if (self == null) return -1;
    return 0;
}

/// CData_dealloc - Destructor
fn CData_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const cdata: *ctypes.CDataObject = @ptrCast(@alignCast(self.?));

    // Free external buffer if allocated
    if (cdata.b_needsfree != 0 and cdata.b_ptr != null) {
        allocator.free(cdata.b_ptr.?[0..@intCast(cdata.b_size)]);
    }

    // Decref base object
    if (cdata.b_base) |base| {
        const base_obj: *cpython.PyObject = @ptrCast(base);
        base_obj.ob_refcnt -= 1;
    }

    // Decref objects dict
    if (cdata.b_objects) |obj| {
        obj.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(cdata);
    allocator.free(ptr[0..@sizeOf(ctypes.CDataObject)]);
}

/// CData_traverse - GC traversal
fn CData_traverse(self: ?*cpython.PyObject, visit: ?*const fn (?*cpython.PyObject, ?*anyopaque) callconv(.c) c_int, arg: ?*anyopaque) callconv(.c) c_int {
    if (self == null) return 0;
    const cdata: *ctypes.CDataObject = @ptrCast(@alignCast(self.?));

    if (cdata.b_objects) |obj| {
        if (visit) |v| {
            const result = v(obj, arg);
            if (result != 0) return result;
        }
    }

    if (cdata.b_base) |base| {
        if (visit) |v| {
            const result = v(@ptrCast(base), arg);
            if (result != 0) return result;
        }
    }

    return 0;
}

/// CData_clear - Clear references for GC
fn CData_clear(self: ?*cpython.PyObject) callconv(.c) c_int {
    if (self == null) return 0;
    const cdata: *ctypes.CDataObject = @ptrCast(@alignCast(self.?));

    if (cdata.b_objects) |obj| {
        obj.ob_refcnt -= 1;
        cdata.b_objects = null;
    }

    return 0;
}

/// CData_reduce - Pickle support
fn CData_reduce(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    return null;
}

/// CData_setstate - Unpickle support
fn CData_setstate(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    return null;
}

// ============================================================================
// BUFFER PROTOCOL
// ============================================================================

/// CData_getbuffer - Buffer protocol getbuffer
fn CData_getbuffer(self: ?*cpython.PyObject, view: ?*cpython.Py_buffer, flags: c_int) callconv(.c) c_int {
    if (self == null or view == null) return -1;
    const cdata: *ctypes.CDataObject = @ptrCast(@alignCast(self.?));
    _ = flags;

    view.?.buf = cdata.b_ptr;
    view.?.len = cdata.b_size;
    view.?.readonly = 0;
    view.?.itemsize = 1;
    view.?.format = null;
    view.?.ndim = 1;
    view.?.shape = null;
    view.?.strides = null;
    view.?.suboffsets = null;
    view.?.internal = null;

    self.?.ob_refcnt += 1;
    view.?.obj = self;

    return 0;
}

/// CData_releasebuffer - Buffer protocol releasebuffer
fn CData_releasebuffer(self: ?*cpython.PyObject, view: ?*cpython.Py_buffer) callconv(.c) void {
    _ = self;
    _ = view;
}

// ============================================================================
// METHOD TABLE
// ============================================================================

pub export var CData_methods: [3]cpython.PyMethodDef = .{
    .{ .ml_name = "__reduce__", .ml_meth = @ptrCast(&CData_reduce), .ml_flags = 0x0004, .ml_doc = "Pickle support" },
    .{ .ml_name = "__setstate__", .ml_meth = @ptrCast(&CData_setstate), .ml_flags = 0x0008, .ml_doc = "Unpickle support" },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var CData_as_buffer: cpython.PyBufferProcs = .{
    .bf_getbuffer = CData_getbuffer,
    .bf_releasebuffer = CData_releasebuffer,
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub export var PyCData_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_ctypes._CData",
    .tp_basicsize = @sizeOf(ctypes.CDataObject),
    .tp_itemsize = 0,
    .tp_dealloc = CData_dealloc,
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
    .tp_as_buffer = &CData_as_buffer,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Base class for ctypes data objects",
    .tp_traverse = CData_traverse,
    .tp_clear = CData_clear,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &CData_methods,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = CData_init,
    .tp_alloc = null,
    .tp_new = CData_new,
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
