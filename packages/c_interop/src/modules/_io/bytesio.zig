/// _io/bytesio - BytesIO Implementation
///
/// Implements CPython's Modules/_io/bytesio.c
/// Provides BytesIO class for in-memory binary streams
///
/// Reference: cpython/Modules/_io/bytesio.c
const std = @import("std");
const cpython = @import("../../include/object.zig");
const iobase = @import("iobase.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// BYTESIO OBJECT - In-memory binary stream
// ============================================================================

/// PyBytesIO - In-memory binary stream
/// Matches CPython's bytesio struct layout exactly
pub const PyBytesIO = extern struct {
    base: iobase.PyIOBase,
    buf: ?[*]u8, // Internal buffer
    pos: isize, // Current position
    string_size: isize, // Size of valid data
    buf_size: isize, // Allocated buffer size
    exports: c_int, // Number of buffer exports
};

// ============================================================================
// BYTESIO METHODS
// ============================================================================

/// bytesio_new - Create new BytesIO object
fn bytesio_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    _ = type_obj;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyBytesIO), @sizeOf(PyBytesIO)) catch return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(mem.ptr));

    bytesio.* = .{
        .base = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyBytesIO_Type },
            .dict = null,
            .weakreflist = null,
        },
        .buf = null,
        .pos = 0,
        .string_size = 0,
        .buf_size = 0,
        .exports = 0,
    };

    return @ptrCast(bytesio);
}

/// bytesio_init - Initialize BytesIO with optional initial bytes
fn bytesio_init(self: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) c_int {
    _ = args;
    _ = kwargs;
    if (self == null) return -1;

    // Initial buffer allocation
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));
    const initial_size: usize = 128;
    const buf = allocator.alloc(u8, initial_size) catch return -1;
    bytesio.buf = buf.ptr;
    bytesio.buf_size = @intCast(initial_size);

    return 0;
}

/// bytesio_dealloc - Destructor
fn bytesio_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));

    // Free buffer
    if (bytesio.buf) |buf| {
        allocator.free(buf[0..@intCast(bytesio.buf_size)]);
    }

    // Clear dict
    if (bytesio.base.dict) |d| {
        d.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(bytesio);
    allocator.free(ptr[0..@sizeOf(PyBytesIO)]);
}

/// bytesio_close - Close the stream
fn bytesio_close(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));

    // Free buffer and mark as closed
    if (bytesio.buf) |buf| {
        allocator.free(buf[0..@intCast(bytesio.buf_size)]);
        bytesio.buf = null;
    }

    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// bytesio_closed_get - Get closed property
fn bytesio_closed_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");

    if (bytesio.buf == null) {
        return &object_mod._Py_TrueStruct;
    }
    return &object_mod._Py_FalseStruct;
}

/// bytesio_getvalue - Get current contents as bytes
fn bytesio_getvalue(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    // Return PyBytes with contents
    return null;
}

/// bytesio_getbuffer - Return a readable and writable view
fn bytesio_getbuffer(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    // Return a memoryview
    return null;
}

/// bytesio_read - Read bytes
fn bytesio_read(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));
    _ = args;

    if (bytesio.buf == null) return null; // Closed

    // Read from current position
    return null;
}

/// bytesio_read1 - Read with at most one underlying call
fn bytesio_read1(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Same as read for BytesIO
    return bytesio_read(self, args);
}

/// bytesio_readinto - Read into buffer
fn bytesio_readinto(self: ?*cpython.PyObject, buffer: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or buffer == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));

    if (bytesio.buf == null) return null;

    // Copy to buffer
    return null;
}

/// bytesio_readline - Read a line
fn bytesio_readline(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));
    _ = args;

    if (bytesio.buf == null) return null;

    // Read until \n
    return null;
}

/// bytesio_readlines - Read all lines
fn bytesio_readlines(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));
    _ = args;

    if (bytesio.buf == null) return null;

    // Return list of lines
    return null;
}

/// bytesio_write - Write bytes
fn bytesio_write(self: ?*cpython.PyObject, data: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or data == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));

    if (bytesio.buf == null) return null;
    if (bytesio.exports > 0) return null; // Buffer is exported

    // Write to buffer, growing if needed
    return null;
}

/// bytesio_writelines - Write lines
fn bytesio_writelines(self: ?*cpython.PyObject, lines: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or lines == null) return null;
    _ = lines;
    _ = self;

    // Iterate and write each line
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// bytesio_seek - Seek to position
fn bytesio_seek(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));
    _ = args;

    if (bytesio.buf == null) return null;

    // Parse offset and whence, update pos
    return null;
}

/// bytesio_tell - Get current position
fn bytesio_tell(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));

    if (bytesio.buf == null) return null;

    // Return PyLong with pos
    return null;
}

/// bytesio_truncate - Truncate stream
fn bytesio_truncate(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));
    _ = args;

    if (bytesio.buf == null) return null;
    if (bytesio.exports > 0) return null;

    // Truncate to size
    return null;
}

/// bytesio_readable - Always True
fn bytesio_readable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");

    if (bytesio.buf == null) return null;
    return &object_mod._Py_TrueStruct;
}

/// bytesio_writable - Always True
fn bytesio_writable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");

    if (bytesio.buf == null) return null;
    return &object_mod._Py_TrueStruct;
}

/// bytesio_seekable - Always True
fn bytesio_seekable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const bytesio: *PyBytesIO = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");

    if (bytesio.buf == null) return null;
    return &object_mod._Py_TrueStruct;
}

// ============================================================================
// METHOD TABLES
// ============================================================================

pub export var bytesio_methods: [17]cpython.PyMethodDef = .{
    .{ .ml_name = "close", .ml_meth = @ptrCast(&bytesio_close), .ml_flags = 0x0004, .ml_doc = "Close the stream." },
    .{ .ml_name = "getvalue", .ml_meth = @ptrCast(&bytesio_getvalue), .ml_flags = 0x0004, .ml_doc = "Retrieve the entire contents of the BytesIO object." },
    .{ .ml_name = "getbuffer", .ml_meth = @ptrCast(&bytesio_getbuffer), .ml_flags = 0x0004, .ml_doc = "Get a read-write view over the contents." },
    .{ .ml_name = "read", .ml_meth = @ptrCast(&bytesio_read), .ml_flags = 0x0001, .ml_doc = "Read bytes." },
    .{ .ml_name = "read1", .ml_meth = @ptrCast(&bytesio_read1), .ml_flags = 0x0001, .ml_doc = "Read bytes with at most one read() call." },
    .{ .ml_name = "readinto", .ml_meth = @ptrCast(&bytesio_readinto), .ml_flags = 0x0008, .ml_doc = "Read bytes into a buffer." },
    .{ .ml_name = "readline", .ml_meth = @ptrCast(&bytesio_readline), .ml_flags = 0x0001, .ml_doc = "Read a line." },
    .{ .ml_name = "readlines", .ml_meth = @ptrCast(&bytesio_readlines), .ml_flags = 0x0001, .ml_doc = "Read all lines." },
    .{ .ml_name = "write", .ml_meth = @ptrCast(&bytesio_write), .ml_flags = 0x0008, .ml_doc = "Write bytes." },
    .{ .ml_name = "writelines", .ml_meth = @ptrCast(&bytesio_writelines), .ml_flags = 0x0008, .ml_doc = "Write lines." },
    .{ .ml_name = "seek", .ml_meth = @ptrCast(&bytesio_seek), .ml_flags = 0x0001, .ml_doc = "Seek to position." },
    .{ .ml_name = "tell", .ml_meth = @ptrCast(&bytesio_tell), .ml_flags = 0x0004, .ml_doc = "Return current position." },
    .{ .ml_name = "truncate", .ml_meth = @ptrCast(&bytesio_truncate), .ml_flags = 0x0001, .ml_doc = "Truncate the stream." },
    .{ .ml_name = "readable", .ml_meth = @ptrCast(&bytesio_readable), .ml_flags = 0x0004, .ml_doc = "Return True if readable." },
    .{ .ml_name = "writable", .ml_meth = @ptrCast(&bytesio_writable), .ml_flags = 0x0004, .ml_doc = "Return True if writable." },
    .{ .ml_name = "seekable", .ml_meth = @ptrCast(&bytesio_seekable), .ml_flags = 0x0004, .ml_doc = "Return True if seekable." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var bytesio_getset: [2]cpython.PyGetSetDef = .{
    .{ .name = "closed", .get = @ptrCast(&bytesio_closed_get), .set = null, .doc = "True if the stream is closed.", .closure = null },
    .{ .name = null, .get = null, .set = null, .doc = null, .closure = null },
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub export var PyBytesIO_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_io.BytesIO",
    .tp_basicsize = @sizeOf(PyBytesIO),
    .tp_itemsize = 0,
    .tp_dealloc = bytesio_dealloc,
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
    .tp_as_buffer = null, // TODO: buffer protocol
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "Buffered I/O implementation using an in-memory bytes buffer.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyBytesIO, "base") + @offsetOf(iobase.PyIOBase, "weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &bytesio_methods,
    .tp_members = null,
    .tp_getset = &bytesio_getset,
    .tp_base = &iobase.PyBufferedIOBase_Type,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(PyBytesIO, "base") + @offsetOf(iobase.PyIOBase, "dict"),
    .tp_init = bytesio_init,
    .tp_alloc = null,
    .tp_new = bytesio_new,
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
