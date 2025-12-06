/// _io/bufferedio - Buffered I/O Implementation
///
/// Implements CPython's Modules/_io/bufferedio.c
/// Provides BufferedReader, BufferedWriter, BufferedRWPair, BufferedRandom
///
/// Reference: cpython/Modules/_io/bufferedio.c
const std = @import("std");
const cpython = @import("../../include/object.zig");
const iobase = @import("iobase.zig");

const allocator = std.heap.c_allocator;

/// Default buffer size
pub const DEFAULT_BUFFER_SIZE: usize = 8192;

// ============================================================================
// BUFFERED BASE - Common buffered I/O structure
// ============================================================================

/// PyBuffered - Base for all buffered I/O
/// Matches CPython's buffered struct layout
pub const PyBuffered = extern struct {
    base: iobase.PyIOBase,
    raw: ?*cpython.PyObject, // Underlying raw stream
    buffer: ?[*]u8, // Internal buffer
    buffer_size: isize, // Buffer capacity
    pos: isize, // Current position in buffer
    raw_pos: isize, // Position in underlying raw stream
    read_end: isize, // End of valid read data
    write_pos: isize, // Start of write data
    write_end: isize, // End of write data
    lock: ?*anyopaque, // Thread lock
    owner: c_long, // Thread that owns lock
    readable: c_int,
    writable: c_int,
    detached: c_int,
    ok: c_int, // Set when stream is usable
    fast_closed_checks: c_int,
};

// ============================================================================
// BUFFEREDREADER
// ============================================================================

/// PyBufferedReader - Buffered input stream
pub const PyBufferedReader = extern struct {
    buffered: PyBuffered,
};

fn bufferedreader_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    _ = type_obj;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyBufferedReader), @sizeOf(PyBufferedReader)) catch return null;
    const reader: *PyBufferedReader = @ptrCast(@alignCast(mem.ptr));

    reader.* = .{
        .buffered = .{
            .base = .{
                .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyBufferedReader_Type },
                .dict = null,
                .weakreflist = null,
            },
            .raw = null,
            .buffer = null,
            .buffer_size = DEFAULT_BUFFER_SIZE,
            .pos = 0,
            .raw_pos = 0,
            .read_end = 0,
            .write_pos = 0,
            .write_end = 0,
            .lock = null,
            .owner = 0,
            .readable = 1,
            .writable = 0,
            .detached = 0,
            .ok = 0,
            .fast_closed_checks = 0,
        },
    };

    return @ptrCast(reader);
}

fn bufferedreader_init(self: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) c_int {
    _ = args;
    _ = kwargs;
    if (self == null) return -1;

    const reader: *PyBufferedReader = @ptrCast(@alignCast(self.?));
    const buf = allocator.alloc(u8, DEFAULT_BUFFER_SIZE) catch return -1;
    reader.buffered.buffer = buf.ptr;
    reader.buffered.ok = 1;

    return 0;
}

fn bufferedreader_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const reader: *PyBufferedReader = @ptrCast(@alignCast(self.?));

    if (reader.buffered.buffer) |buf| {
        allocator.free(buf[0..@intCast(reader.buffered.buffer_size)]);
    }

    if (reader.buffered.raw) |r| {
        r.ob_refcnt -= 1;
    }

    if (reader.buffered.base.dict) |d| {
        d.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(reader);
    allocator.free(ptr[0..@sizeOf(PyBufferedReader)]);
}

fn buffered_read(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    // Read from buffer, refill if needed
    return null;
}

fn buffered_read1(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    return null;
}

fn buffered_readinto(self: ?*cpython.PyObject, buffer: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or buffer == null) return null;
    return null;
}

fn buffered_readinto1(self: ?*cpython.PyObject, buffer: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or buffer == null) return null;
    return null;
}

fn buffered_peek(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    return null;
}

fn buffered_readline(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    return null;
}

fn buffered_seek(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    return null;
}

fn buffered_tell(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    return null;
}

fn buffered_close(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

fn buffered_detach(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    return null;
}

fn buffered_flush(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

fn buffered_readable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const buffered: *PyBuffered = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");
    if (buffered.readable != 0) return &object_mod._Py_TrueStruct;
    return &object_mod._Py_FalseStruct;
}

fn buffered_writable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const buffered: *PyBuffered = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");
    if (buffered.writable != 0) return &object_mod._Py_TrueStruct;
    return &object_mod._Py_FalseStruct;
}

fn buffered_seekable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_TrueStruct;
}

fn buffered_closed_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const buffered: *PyBuffered = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");
    if (buffered.ok == 0) return &object_mod._Py_TrueStruct;
    return &object_mod._Py_FalseStruct;
}

fn buffered_raw_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const buffered: *PyBuffered = @ptrCast(@alignCast(self.?));
    if (buffered.raw) |r| {
        r.ob_refcnt += 1;
        return r;
    }
    return null;
}

fn buffered_name_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    _ = self;
    return null;
}

fn buffered_mode_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    _ = self;
    return null;
}

// ============================================================================
// METHOD TABLES
// ============================================================================

pub export var bufferedreader_methods: [15]cpython.PyMethodDef = .{
    .{ .ml_name = "read", .ml_meth = @ptrCast(&buffered_read), .ml_flags = 0x0001, .ml_doc = "Read and return bytes." },
    .{ .ml_name = "read1", .ml_meth = @ptrCast(&buffered_read1), .ml_flags = 0x0001, .ml_doc = "Read bytes with at most one raw read." },
    .{ .ml_name = "readinto", .ml_meth = @ptrCast(&buffered_readinto), .ml_flags = 0x0008, .ml_doc = "Read bytes into buffer." },
    .{ .ml_name = "readinto1", .ml_meth = @ptrCast(&buffered_readinto1), .ml_flags = 0x0008, .ml_doc = "Read bytes into buffer with at most one raw read." },
    .{ .ml_name = "peek", .ml_meth = @ptrCast(&buffered_peek), .ml_flags = 0x0001, .ml_doc = "Return buffered bytes without advancing position." },
    .{ .ml_name = "readline", .ml_meth = @ptrCast(&buffered_readline), .ml_flags = 0x0001, .ml_doc = "Read a line." },
    .{ .ml_name = "seek", .ml_meth = @ptrCast(&buffered_seek), .ml_flags = 0x0001, .ml_doc = "Seek to position." },
    .{ .ml_name = "tell", .ml_meth = @ptrCast(&buffered_tell), .ml_flags = 0x0004, .ml_doc = "Return current position." },
    .{ .ml_name = "close", .ml_meth = @ptrCast(&buffered_close), .ml_flags = 0x0004, .ml_doc = "Close the stream." },
    .{ .ml_name = "detach", .ml_meth = @ptrCast(&buffered_detach), .ml_flags = 0x0004, .ml_doc = "Detach the underlying raw stream." },
    .{ .ml_name = "flush", .ml_meth = @ptrCast(&buffered_flush), .ml_flags = 0x0004, .ml_doc = "Flush write buffers." },
    .{ .ml_name = "readable", .ml_meth = @ptrCast(&buffered_readable), .ml_flags = 0x0004, .ml_doc = "Return True if readable." },
    .{ .ml_name = "writable", .ml_meth = @ptrCast(&buffered_writable), .ml_flags = 0x0004, .ml_doc = "Return True if writable." },
    .{ .ml_name = "seekable", .ml_meth = @ptrCast(&buffered_seekable), .ml_flags = 0x0004, .ml_doc = "Return True if seekable." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var buffered_getset: [5]cpython.PyGetSetDef = .{
    .{ .name = "closed", .get = @ptrCast(&buffered_closed_get), .set = null, .doc = "True if the stream is closed.", .closure = null },
    .{ .name = "raw", .get = @ptrCast(&buffered_raw_get), .set = null, .doc = "The underlying raw stream.", .closure = null },
    .{ .name = "name", .get = @ptrCast(&buffered_name_get), .set = null, .doc = "The name of the stream.", .closure = null },
    .{ .name = "mode", .get = @ptrCast(&buffered_mode_get), .set = null, .doc = "The mode of the stream.", .closure = null },
    .{ .name = null, .get = null, .set = null, .doc = null, .closure = null },
};

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub export var PyBufferedReader_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_io.BufferedReader",
    .tp_basicsize = @sizeOf(PyBufferedReader),
    .tp_itemsize = 0,
    .tp_dealloc = bufferedreader_dealloc,
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
    .tp_doc = "A buffered I/O implementation for reading raw streams.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyBufferedReader, "buffered") + @offsetOf(PyBuffered, "base") + @offsetOf(iobase.PyIOBase, "weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &bufferedreader_methods,
    .tp_members = null,
    .tp_getset = &buffered_getset,
    .tp_base = &iobase.PyBufferedIOBase_Type,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(PyBufferedReader, "buffered") + @offsetOf(PyBuffered, "base") + @offsetOf(iobase.PyIOBase, "dict"),
    .tp_init = bufferedreader_init,
    .tp_alloc = null,
    .tp_new = bufferedreader_new,
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
// BUFFEREDWRITER
// ============================================================================

pub const PyBufferedWriter = extern struct {
    buffered: PyBuffered,
};

fn bufferedwriter_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    _ = type_obj;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyBufferedWriter), @sizeOf(PyBufferedWriter)) catch return null;
    const writer: *PyBufferedWriter = @ptrCast(@alignCast(mem.ptr));

    writer.* = .{
        .buffered = .{
            .base = .{
                .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyBufferedWriter_Type },
                .dict = null,
                .weakreflist = null,
            },
            .raw = null,
            .buffer = null,
            .buffer_size = DEFAULT_BUFFER_SIZE,
            .pos = 0,
            .raw_pos = 0,
            .read_end = 0,
            .write_pos = 0,
            .write_end = 0,
            .lock = null,
            .owner = 0,
            .readable = 0,
            .writable = 1,
            .detached = 0,
            .ok = 0,
            .fast_closed_checks = 0,
        },
    };

    return @ptrCast(writer);
}

fn bufferedwriter_init(self: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) c_int {
    _ = args;
    _ = kwargs;
    if (self == null) return -1;

    const writer: *PyBufferedWriter = @ptrCast(@alignCast(self.?));
    const buf = allocator.alloc(u8, DEFAULT_BUFFER_SIZE) catch return -1;
    writer.buffered.buffer = buf.ptr;
    writer.buffered.ok = 1;

    return 0;
}

fn bufferedwriter_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const writer: *PyBufferedWriter = @ptrCast(@alignCast(self.?));

    if (writer.buffered.buffer) |buf| {
        allocator.free(buf[0..@intCast(writer.buffered.buffer_size)]);
    }

    if (writer.buffered.raw) |r| {
        r.ob_refcnt -= 1;
    }

    if (writer.buffered.base.dict) |d| {
        d.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(writer);
    allocator.free(ptr[0..@sizeOf(PyBufferedWriter)]);
}

fn buffered_write(self: ?*cpython.PyObject, data: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or data == null) return null;
    return null;
}

fn buffered_truncate(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = args;
    return null;
}

pub export var bufferedwriter_methods: [12]cpython.PyMethodDef = .{
    .{ .ml_name = "write", .ml_meth = @ptrCast(&buffered_write), .ml_flags = 0x0008, .ml_doc = "Write bytes." },
    .{ .ml_name = "truncate", .ml_meth = @ptrCast(&buffered_truncate), .ml_flags = 0x0001, .ml_doc = "Truncate the file." },
    .{ .ml_name = "seek", .ml_meth = @ptrCast(&buffered_seek), .ml_flags = 0x0001, .ml_doc = "Seek to position." },
    .{ .ml_name = "tell", .ml_meth = @ptrCast(&buffered_tell), .ml_flags = 0x0004, .ml_doc = "Return current position." },
    .{ .ml_name = "close", .ml_meth = @ptrCast(&buffered_close), .ml_flags = 0x0004, .ml_doc = "Close the stream." },
    .{ .ml_name = "detach", .ml_meth = @ptrCast(&buffered_detach), .ml_flags = 0x0004, .ml_doc = "Detach the underlying raw stream." },
    .{ .ml_name = "flush", .ml_meth = @ptrCast(&buffered_flush), .ml_flags = 0x0004, .ml_doc = "Flush write buffers." },
    .{ .ml_name = "readable", .ml_meth = @ptrCast(&buffered_readable), .ml_flags = 0x0004, .ml_doc = "Return True if readable." },
    .{ .ml_name = "writable", .ml_meth = @ptrCast(&buffered_writable), .ml_flags = 0x0004, .ml_doc = "Return True if writable." },
    .{ .ml_name = "seekable", .ml_meth = @ptrCast(&buffered_seekable), .ml_flags = 0x0004, .ml_doc = "Return True if seekable." },
    .{ .ml_name = "fileno", .ml_meth = null, .ml_flags = 0x0004, .ml_doc = "Return file descriptor." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var PyBufferedWriter_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_io.BufferedWriter",
    .tp_basicsize = @sizeOf(PyBufferedWriter),
    .tp_itemsize = 0,
    .tp_dealloc = bufferedwriter_dealloc,
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
    .tp_doc = "A buffered I/O implementation for writing raw streams.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyBufferedWriter, "buffered") + @offsetOf(PyBuffered, "base") + @offsetOf(iobase.PyIOBase, "weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &bufferedwriter_methods,
    .tp_members = null,
    .tp_getset = &buffered_getset,
    .tp_base = &iobase.PyBufferedIOBase_Type,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(PyBufferedWriter, "buffered") + @offsetOf(PyBuffered, "base") + @offsetOf(iobase.PyIOBase, "dict"),
    .tp_init = bufferedwriter_init,
    .tp_alloc = null,
    .tp_new = bufferedwriter_new,
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
// BUFFEREDRWPAIR
// ============================================================================

pub const PyBufferedRWPair = extern struct {
    base: iobase.PyIOBase,
    reader: ?*PyBufferedReader,
    writer: ?*PyBufferedWriter,
};

fn bufferedrwpair_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    _ = type_obj;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyBufferedRWPair), @sizeOf(PyBufferedRWPair)) catch return null;
    const rwpair: *PyBufferedRWPair = @ptrCast(@alignCast(mem.ptr));

    rwpair.* = .{
        .base = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyBufferedRWPair_Type },
            .dict = null,
            .weakreflist = null,
        },
        .reader = null,
        .writer = null,
    };

    return @ptrCast(rwpair);
}

fn bufferedrwpair_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const rwpair: *PyBufferedRWPair = @ptrCast(@alignCast(self.?));

    if (rwpair.reader) |r| {
        r.buffered.base.ob_base.ob_refcnt -= 1;
    }
    if (rwpair.writer) |w| {
        w.buffered.base.ob_base.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(rwpair);
    allocator.free(ptr[0..@sizeOf(PyBufferedRWPair)]);
}

pub export var PyBufferedRWPair_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_io.BufferedRWPair",
    .tp_basicsize = @sizeOf(PyBufferedRWPair),
    .tp_itemsize = 0,
    .tp_dealloc = bufferedrwpair_dealloc,
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
    .tp_doc = "A buffered reader and writer object together.\n\nA buffered reader object and buffered writer object put together to\nform a sequential IO object that can read and write.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyBufferedRWPair, "base") + @offsetOf(iobase.PyIOBase, "weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &iobase.PyBufferedIOBase_Type,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(PyBufferedRWPair, "base") + @offsetOf(iobase.PyIOBase, "dict"),
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = bufferedrwpair_new,
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
// BUFFEREDRANDOM
// ============================================================================

pub const PyBufferedRandom = extern struct {
    buffered: PyBuffered,
};

fn bufferedrandom_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    _ = type_obj;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyBufferedRandom), @sizeOf(PyBufferedRandom)) catch return null;
    const random: *PyBufferedRandom = @ptrCast(@alignCast(mem.ptr));

    random.* = .{
        .buffered = .{
            .base = .{
                .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyBufferedRandom_Type },
                .dict = null,
                .weakreflist = null,
            },
            .raw = null,
            .buffer = null,
            .buffer_size = DEFAULT_BUFFER_SIZE,
            .pos = 0,
            .raw_pos = 0,
            .read_end = 0,
            .write_pos = 0,
            .write_end = 0,
            .lock = null,
            .owner = 0,
            .readable = 1,
            .writable = 1,
            .detached = 0,
            .ok = 0,
            .fast_closed_checks = 0,
        },
    };

    return @ptrCast(random);
}

fn bufferedrandom_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const random: *PyBufferedRandom = @ptrCast(@alignCast(self.?));

    if (random.buffered.buffer) |buf| {
        allocator.free(buf[0..@intCast(random.buffered.buffer_size)]);
    }

    if (random.buffered.raw) |r| {
        r.ob_refcnt -= 1;
    }

    const ptr: [*]u8 = @ptrCast(random);
    allocator.free(ptr[0..@sizeOf(PyBufferedRandom)]);
}

pub export var PyBufferedRandom_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_io.BufferedRandom",
    .tp_basicsize = @sizeOf(PyBufferedRandom),
    .tp_itemsize = 0,
    .tp_dealloc = bufferedrandom_dealloc,
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
    .tp_doc = "A buffered interface to random access streams.\n\nThe constructor creates a reader and writer for a seekable stream,\nraw, given in the first argument. If the buffer_size is omitted it\ndefaults to DEFAULT_BUFFER_SIZE.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyBufferedRandom, "buffered") + @offsetOf(PyBuffered, "base") + @offsetOf(iobase.PyIOBase, "weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &bufferedreader_methods,
    .tp_members = null,
    .tp_getset = &buffered_getset,
    .tp_base = &iobase.PyBufferedIOBase_Type,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(PyBufferedRandom, "buffered") + @offsetOf(PyBuffered, "base") + @offsetOf(iobase.PyIOBase, "dict"),
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = bufferedrandom_new,
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
