/// _io/iobase - IO Base Classes Implementation
///
/// Implements CPython's Modules/_io/iobase.c
/// Provides _IOBase, _RawIOBase, _BufferedIOBase, _TextIOBase abstract classes
///
/// Reference: cpython/Modules/_io/iobase.c
const std = @import("std");
const cpython = @import("../../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// IOBASE OBJECT - Abstract base for all I/O
// ============================================================================

/// PyIOBase - Abstract base class for all I/O classes
/// Matches CPython's iobase struct layout exactly
pub const PyIOBase = extern struct {
    ob_base: cpython.PyObject,
    dict: ?*cpython.PyObject, // __dict__ attribute
    weakreflist: ?*cpython.PyObject, // Weak reference list
};

// ============================================================================
// IOBASE METHODS
// ============================================================================

/// iobase_close - Close the IO stream
fn iobase_close(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    // Set __closed = True equivalent
    // Abstract - subclasses override
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// iobase_closed - Check if stream is closed
fn iobase_closed_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    _ = self;
    // Default implementation - subclasses override
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_FalseStruct;
}

/// iobase_flush - Flush write buffers
fn iobase_flush(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    // Check if closed first
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// iobase_seek - Move to new position
fn iobase_seek(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    // Raise UnsupportedOperation by default
    return null;
}

/// iobase_tell - Return current position
fn iobase_tell(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    // Default: seek(0, SEEK_CUR)
    return null;
}

/// iobase_truncate - Truncate file to size
fn iobase_truncate(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    // Raise UnsupportedOperation by default
    return null;
}

/// iobase_readable - Return True if readable
fn iobase_readable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_FalseStruct;
}

/// iobase_writable - Return True if writable
fn iobase_writable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_FalseStruct;
}

/// iobase_seekable - Return True if seekable
fn iobase_seekable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_FalseStruct;
}

/// iobase_fileno - Return file descriptor
fn iobase_fileno(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    // Raise UnsupportedOperation
    return null;
}

/// iobase_isatty - Return True if terminal
fn iobase_isatty(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_FalseStruct;
}

/// iobase_readline - Read a line
fn iobase_readline(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    // Default implementation using read(1)
    return null;
}

/// iobase_readlines - Read all lines
fn iobase_readlines(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    // Default implementation using readline
    return null;
}

/// iobase_writelines - Write lines
fn iobase_writelines(self: ?*cpython.PyObject, lines: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = lines;
    // Default implementation iterating and calling write
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// iobase_iter - Return iterator
fn iobase_iter(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self) |s| {
        s.ob_refcnt += 1;
        return s;
    }
    return null;
}

/// iobase_iternext - Get next line
fn iobase_iternext(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    // Call readline, return null on empty
    return null;
}

/// iobase_enter - Context manager enter
fn iobase_enter(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self) |s| {
        s.ob_refcnt += 1;
        return s;
    }
    return null;
}

/// iobase_exit - Context manager exit
fn iobase_exit(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    return iobase_close(self);
}

/// iobase_dealloc - Destructor
fn iobase_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const io: *PyIOBase = @ptrCast(@alignCast(self.?));

    // Clear dict
    if (io.dict) |d| {
        d.ob_refcnt -= 1;
    }

    // Free memory
    const ptr: [*]u8 = @ptrCast(io);
    allocator.free(ptr[0..@sizeOf(PyIOBase)]);
}

// ============================================================================
// METHOD TABLES
// ============================================================================

pub export var iobase_methods: [16]cpython.PyMethodDef = .{
    .{ .ml_name = "close", .ml_meth = @ptrCast(&iobase_close), .ml_flags = 0x0004, .ml_doc = "Flush and close the IO object." },
    .{ .ml_name = "flush", .ml_meth = @ptrCast(&iobase_flush), .ml_flags = 0x0004, .ml_doc = "Flush write buffers, if applicable." },
    .{ .ml_name = "seek", .ml_meth = @ptrCast(&iobase_seek), .ml_flags = 0x0001, .ml_doc = "Change stream position." },
    .{ .ml_name = "tell", .ml_meth = @ptrCast(&iobase_tell), .ml_flags = 0x0004, .ml_doc = "Return current stream position." },
    .{ .ml_name = "truncate", .ml_meth = @ptrCast(&iobase_truncate), .ml_flags = 0x0001, .ml_doc = "Truncate file to size." },
    .{ .ml_name = "readable", .ml_meth = @ptrCast(&iobase_readable), .ml_flags = 0x0004, .ml_doc = "Return True if the stream is readable." },
    .{ .ml_name = "writable", .ml_meth = @ptrCast(&iobase_writable), .ml_flags = 0x0004, .ml_doc = "Return True if the stream is writable." },
    .{ .ml_name = "seekable", .ml_meth = @ptrCast(&iobase_seekable), .ml_flags = 0x0004, .ml_doc = "Return True if the stream is seekable." },
    .{ .ml_name = "fileno", .ml_meth = @ptrCast(&iobase_fileno), .ml_flags = 0x0004, .ml_doc = "Return underlying file descriptor." },
    .{ .ml_name = "isatty", .ml_meth = @ptrCast(&iobase_isatty), .ml_flags = 0x0004, .ml_doc = "Return True if this is a terminal." },
    .{ .ml_name = "readline", .ml_meth = @ptrCast(&iobase_readline), .ml_flags = 0x0001, .ml_doc = "Read a line from the stream." },
    .{ .ml_name = "readlines", .ml_meth = @ptrCast(&iobase_readlines), .ml_flags = 0x0001, .ml_doc = "Read all lines from the stream." },
    .{ .ml_name = "writelines", .ml_meth = @ptrCast(&iobase_writelines), .ml_flags = 0x0008, .ml_doc = "Write lines to the stream." },
    .{ .ml_name = "__enter__", .ml_meth = @ptrCast(&iobase_enter), .ml_flags = 0x0004, .ml_doc = "Context manager enter." },
    .{ .ml_name = "__exit__", .ml_meth = @ptrCast(&iobase_exit), .ml_flags = 0x0001, .ml_doc = "Context manager exit." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null }, // Sentinel
};

pub export var iobase_getset: [2]cpython.PyGetSetDef = .{
    .{ .name = "closed", .get = @ptrCast(&iobase_closed_get), .set = null, .doc = "True if the stream is closed.", .closure = null },
    .{ .name = null, .get = null, .set = null, .doc = null, .closure = null }, // Sentinel
};

// ============================================================================
// TYPE OBJECTS
// ============================================================================

/// PyIOBase_Type - Base type for all I/O classes
pub export var PyIOBase_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_io._IOBase",
    .tp_basicsize = @sizeOf(PyIOBase),
    .tp_itemsize = 0,
    .tp_dealloc = iobase_dealloc,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_HAVE_GC,
    .tp_doc = "The abstract base class for all I/O classes.\n\nThis class provides dummy implementations for many methods that\nderived classes can override selectively; the default\nimplementations represent a file that cannot be read, written or\nseeked.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyIOBase, "weakreflist"),
    .tp_iter = iobase_iter,
    .tp_iternext = iobase_iternext,
    .tp_methods = &iobase_methods,
    .tp_members = null,
    .tp_getset = &iobase_getset,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(PyIOBase, "dict"),
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
// RAW I/O BASE
// ============================================================================

/// PyRawIOBase - Base class for raw binary I/O
pub const PyRawIOBase = extern struct {
    base: PyIOBase,
};

/// rawiobase_read - Read n bytes
fn rawiobase_read(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    // Default: call readall if n < 0, otherwise readinto
    return null;
}

/// rawiobase_readall - Read all bytes
fn rawiobase_readall(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    // Read until EOF
    return null;
}

/// rawiobase_readinto - Read into buffer
fn rawiobase_readinto(self: ?*cpython.PyObject, buffer: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = buffer;
    // Abstract - must be implemented
    return null;
}

/// rawiobase_write - Write bytes
fn rawiobase_write(self: ?*cpython.PyObject, data: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = data;
    // Abstract - must be implemented
    return null;
}

pub export var rawiobase_methods: [5]cpython.PyMethodDef = .{
    .{ .ml_name = "read", .ml_meth = @ptrCast(&rawiobase_read), .ml_flags = 0x0001, .ml_doc = "Read and return up to n bytes." },
    .{ .ml_name = "readall", .ml_meth = @ptrCast(&rawiobase_readall), .ml_flags = 0x0004, .ml_doc = "Read until EOF." },
    .{ .ml_name = "readinto", .ml_meth = @ptrCast(&rawiobase_readinto), .ml_flags = 0x0008, .ml_doc = "Read bytes into buffer." },
    .{ .ml_name = "write", .ml_meth = @ptrCast(&rawiobase_write), .ml_flags = 0x0008, .ml_doc = "Write bytes." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var PyRawIOBase_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_io._RawIOBase",
    .tp_basicsize = @sizeOf(PyRawIOBase),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "Base class for raw binary I/O.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &rawiobase_methods,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyIOBase_Type,
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
// BUFFERED I/O BASE
// ============================================================================

/// PyBufferedIOBase - Base class for buffered I/O
pub const PyBufferedIOBase = extern struct {
    base: PyIOBase,
};

/// bufferediobase_read - Read n bytes
fn bufferediobase_read(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    return null;
}

/// bufferediobase_read1 - Read up to n bytes with at most one raw read
fn bufferediobase_read1(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    return null;
}

/// bufferediobase_readinto - Read into buffer
fn bufferediobase_readinto(self: ?*cpython.PyObject, buffer: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = buffer;
    return null;
}

/// bufferediobase_readinto1 - Read into buffer with at most one raw read
fn bufferediobase_readinto1(self: ?*cpython.PyObject, buffer: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = buffer;
    return null;
}

/// bufferediobase_write - Write bytes
fn bufferediobase_write(self: ?*cpython.PyObject, data: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = data;
    return null;
}

/// bufferediobase_detach - Disconnect underlying raw stream
fn bufferediobase_detach(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    return null;
}

pub export var bufferediobase_methods: [7]cpython.PyMethodDef = .{
    .{ .ml_name = "read", .ml_meth = @ptrCast(&bufferediobase_read), .ml_flags = 0x0001, .ml_doc = "Read and return up to n bytes." },
    .{ .ml_name = "read1", .ml_meth = @ptrCast(&bufferediobase_read1), .ml_flags = 0x0001, .ml_doc = "Read up to n bytes with at most one raw read." },
    .{ .ml_name = "readinto", .ml_meth = @ptrCast(&bufferediobase_readinto), .ml_flags = 0x0008, .ml_doc = "Read bytes into buffer." },
    .{ .ml_name = "readinto1", .ml_meth = @ptrCast(&bufferediobase_readinto1), .ml_flags = 0x0008, .ml_doc = "Read bytes into buffer with at most one raw read." },
    .{ .ml_name = "write", .ml_meth = @ptrCast(&bufferediobase_write), .ml_flags = 0x0008, .ml_doc = "Write bytes." },
    .{ .ml_name = "detach", .ml_meth = @ptrCast(&bufferediobase_detach), .ml_flags = 0x0004, .ml_doc = "Disconnect underlying raw stream." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var PyBufferedIOBase_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_io._BufferedIOBase",
    .tp_basicsize = @sizeOf(PyBufferedIOBase),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "Base class for buffered I/O objects.\n\nThe main difference with RawIOBase is that the read() method\nsupports omitting the size argument, and does not have a default\nimplementation that defers to readinto().",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &bufferediobase_methods,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyIOBase_Type,
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
// TEXT I/O BASE
// ============================================================================

/// PyTextIOBase - Base class for text I/O
pub const PyTextIOBase = extern struct {
    base: PyIOBase,
};

/// textiobase_read - Read n characters
fn textiobase_read(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    return null;
}

/// textiobase_readline - Read a line
fn textiobase_readline(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    return null;
}

/// textiobase_write - Write string
fn textiobase_write(self: ?*cpython.PyObject, data: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = data;
    return null;
}

/// textiobase_detach - Disconnect underlying binary stream
fn textiobase_detach(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    return null;
}

/// textiobase_encoding_get - Get encoding property
fn textiobase_encoding_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    _ = self;
    return null;
}

/// textiobase_newlines_get - Get newlines property
fn textiobase_newlines_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    _ = self;
    return null;
}

/// textiobase_errors_get - Get errors property
fn textiobase_errors_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    _ = self;
    return null;
}

pub export var textiobase_methods: [5]cpython.PyMethodDef = .{
    .{ .ml_name = "read", .ml_meth = @ptrCast(&textiobase_read), .ml_flags = 0x0001, .ml_doc = "Read at most n characters." },
    .{ .ml_name = "readline", .ml_meth = @ptrCast(&textiobase_readline), .ml_flags = 0x0001, .ml_doc = "Read a line." },
    .{ .ml_name = "write", .ml_meth = @ptrCast(&textiobase_write), .ml_flags = 0x0008, .ml_doc = "Write string." },
    .{ .ml_name = "detach", .ml_meth = @ptrCast(&textiobase_detach), .ml_flags = 0x0004, .ml_doc = "Disconnect underlying binary stream." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var textiobase_getset: [4]cpython.PyGetSetDef = .{
    .{ .name = "encoding", .get = @ptrCast(&textiobase_encoding_get), .set = null, .doc = "Encoding of the text stream.", .closure = null },
    .{ .name = "newlines", .get = @ptrCast(&textiobase_newlines_get), .set = null, .doc = "Line endings translated so far.", .closure = null },
    .{ .name = "errors", .get = @ptrCast(&textiobase_errors_get), .set = null, .doc = "Error setting of the decoder or encoder.", .closure = null },
    .{ .name = null, .get = null, .set = null, .doc = null, .closure = null },
};

pub export var PyTextIOBase_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_io._TextIOBase",
    .tp_basicsize = @sizeOf(PyTextIOBase),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "Base class for text I/O.\n\nThis class provides a character and line based interface to stream\nI/O. There is no readinto() method because Python's character strings\nare immutable.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &textiobase_methods,
    .tp_members = null,
    .tp_getset = &textiobase_getset,
    .tp_base = &PyIOBase_Type,
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
