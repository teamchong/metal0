/// _io/fileio - FileIO Implementation
///
/// Implements CPython's Modules/_io/fileio.c
/// Provides FileIO class for raw file I/O operations
///
/// Reference: cpython/Modules/_io/fileio.c
const std = @import("std");
const cpython = @import("../../include/object.zig");
const iobase = @import("iobase.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// FILEIO OBJECT - Raw file I/O
// ============================================================================

/// PyFileIO - Raw file I/O object
/// Matches CPython's fileio struct layout exactly
pub const PyFileIO = extern struct {
    base: iobase.PyIOBase,
    fd: c_int, // File descriptor
    created: c_int, // Whether file was created
    readable: c_int, // 1 if readable
    writable: c_int, // 1 if writable
    appending: c_int, // 1 if appending
    seekable: c_int, // 1 if seekable, 0 if not, -1 if unknown
    closefd: c_int, // 1 if fd should be closed
    mode: [6]u8, // Mode string (e.g., "rb", "w+b")
    blksize: usize, // Block size for reads
    finalizing: c_int, // Set when being finalized
};

// ============================================================================
// FILEIO METHODS
// ============================================================================

/// fileio_new - Create new FileIO object
fn fileio_new(type_obj: ?*cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    _ = type_obj;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyFileIO), @sizeOf(PyFileIO)) catch return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(mem.ptr));

    fileio.* = .{
        .base = .{
            .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyFileIO_Type },
            .dict = null,
            .weakreflist = null,
        },
        .fd = -1,
        .created = 0,
        .readable = 0,
        .writable = 0,
        .appending = 0,
        .seekable = -1, // Unknown
        .closefd = 1,
        .mode = [_]u8{ 0, 0, 0, 0, 0, 0 },
        .blksize = 8192,
        .finalizing = 0,
    };

    return @ptrCast(fileio);
}

/// fileio_init - Initialize FileIO with file/fd and mode
fn fileio_init(self: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) c_int {
    _ = args;
    _ = kwargs;
    if (self == null) return -1;

    // Parse arguments: (file, mode='r', closefd=True, opener=None)
    // For now, basic implementation
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));

    // Default mode is 'r' for reading
    fileio.readable = 1;
    fileio.mode[0] = 'r';
    fileio.mode[1] = 'b';
    fileio.mode[2] = 0;

    return 0;
}

/// fileio_dealloc - Destructor
fn fileio_dealloc(self: ?*cpython.PyObject) callconv(.c) void {
    if (self == null) return;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));

    // Close file descriptor if needed
    if (fileio.closefd != 0 and fileio.fd >= 0) {
        // Close the fd using posix close
        _ = std.c.close(fileio.fd);
    }

    // Clear dict
    if (fileio.base.dict) |d| {
        d.ob_refcnt -= 1;
    }

    // Free memory
    const ptr: [*]u8 = @ptrCast(fileio);
    allocator.free(ptr[0..@sizeOf(PyFileIO)]);
}

/// fileio_close - Close the file
fn fileio_close(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));

    if (fileio.fd >= 0 and fileio.closefd != 0) {
        _ = std.c.close(fileio.fd);
        fileio.fd = -1;
    }

    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// fileio_closed_get - Get closed property
fn fileio_closed_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");

    if (fileio.fd < 0) {
        return &object_mod._Py_TrueStruct;
    }
    return &object_mod._Py_FalseStruct;
}

/// fileio_read - Read up to size bytes from file descriptor
fn fileio_read(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));

    if (fileio.fd < 0) return null; // Closed
    if (fileio.readable == 0) return null; // Not readable

    // Parse size argument (default -1 = read all)
    var size: isize = -1;
    if (args) |a| {
        const tuple = @import("../../objects/tupleobject.zig");
        if (tuple.PyTuple_Check(a) != 0 and tuple.PyTuple_Size(a) > 0) {
            const pylong = @import("../../objects/longobject.zig");
            const size_obj = tuple.PyTuple_GetItem(a, 0);
            if (size_obj != null and pylong.PyLong_Check(size_obj.?) != 0) {
                size = @intCast(pylong.PyLong_AsLong(size_obj.?));
            }
        }
    }

    // Use POSIX read
    const posix = std.posix;
    const pybytes = @import("../../objects/bytesobject.zig");

    if (size < 0) {
        // Read all - use stat to get file size first
        const stat_result = posix.fstat(@intCast(fileio.fd));
        if (stat_result) |stat| {
            size = @intCast(stat.size);
        } else |_| {
            size = 65536; // Fallback buffer size
        }
    }

    if (size == 0) {
        return pybytes.PyBytes_FromStringAndSize("", 0);
    }

    // Allocate buffer and read
    const buffer = allocator.alloc(u8, @intCast(size)) catch return null;
    defer allocator.free(buffer);

    const bytes_read = posix.read(@intCast(fileio.fd), buffer) catch |err| {
        _ = err;
        return null;
    };

    return pybytes.PyBytes_FromStringAndSize(@ptrCast(buffer.ptr), @intCast(bytes_read));
}

/// fileio_readall - Read all remaining bytes from file
fn fileio_readall(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));

    if (fileio.fd < 0) return null;
    if (fileio.readable == 0) return null;

    const posix = std.posix;
    const pybytes = @import("../../objects/bytesobject.zig");

    // Get file size using fstat
    var total_size: usize = 0;
    const stat_result = posix.fstat(@intCast(fileio.fd));
    if (stat_result) |stat| {
        // Get current position
        const pos = posix.lseek(@intCast(fileio.fd), 0, .CUR) catch 0;
        if (stat.size > pos) {
            total_size = @intCast(stat.size - @as(i64, @intCast(pos)));
        }
    } else |_| {
        total_size = 65536; // Fallback
    }

    if (total_size == 0) {
        return pybytes.PyBytes_FromStringAndSize("", 0);
    }

    // Read in chunks and accumulate
    var result: std.ArrayList(u8) = .{};
    defer result.deinit(allocator);

    var chunk: [8192]u8 = undefined;
    while (true) {
        const bytes_read = posix.read(@intCast(fileio.fd), &chunk) catch break;
        if (bytes_read == 0) break;
        result.appendSlice(allocator, chunk[0..bytes_read]) catch break;
    }

    return pybytes.PyBytes_FromStringAndSize(@ptrCast(result.items.ptr), @intCast(result.items.len));
}

/// fileio_readinto - Read into a buffer object
fn fileio_readinto(self: ?*cpython.PyObject, buffer: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or buffer == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));

    if (fileio.fd < 0) return null;
    if (fileio.readable == 0) return null;

    const posix = std.posix;
    const pylong = @import("../../objects/longobject.zig");

    // Get buffer protocol info
    // For simplicity, assume buffer is a bytearray with direct access
    const pybytearray = @import("../../objects/bytearrayobject.zig");
    if (pybytearray.PyByteArray_Check(buffer.?) != 0) {
        const buf_ptr = pybytearray.PyByteArray_AsString(buffer.?);
        const buf_size = pybytearray.PyByteArray_Size(buffer.?);

        if (buf_ptr == null or buf_size <= 0) return pylong.PyLong_FromLong(0);

        const bytes_read = posix.read(@intCast(fileio.fd), buf_ptr.?[0..@intCast(buf_size)]) catch |_| {
            return null;
        };

        return pylong.PyLong_FromLong(@intCast(bytes_read));
    }

    return null;
}

/// fileio_write - Write bytes to file descriptor
fn fileio_write(self: ?*cpython.PyObject, data: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null or data == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));

    if (fileio.fd < 0) return null;
    if (fileio.writable == 0) return null;

    const posix = std.posix;
    const pybytes = @import("../../objects/bytesobject.zig");
    const pylong = @import("../../objects/longobject.zig");

    // Get data as bytes
    var data_ptr: [*]const u8 = undefined;
    var data_len: usize = 0;

    if (pybytes.PyBytes_Check(data.?) != 0) {
        data_ptr = @ptrCast(pybytes.PyBytes_AsString(data.?) orelse return null);
        data_len = @intCast(pybytes.PyBytes_Size(data.?));
    } else {
        const pybytearray = @import("../../objects/bytearrayobject.zig");
        if (pybytearray.PyByteArray_Check(data.?) != 0) {
            data_ptr = @ptrCast(pybytearray.PyByteArray_AsString(data.?) orelse return null);
            data_len = @intCast(pybytearray.PyByteArray_Size(data.?));
        } else {
            return null; // Unsupported type
        }
    }

    if (data_len == 0) {
        return pylong.PyLong_FromLong(0);
    }

    // Write to file descriptor
    const bytes_written = posix.write(@intCast(fileio.fd), data_ptr[0..data_len]) catch |_| {
        return null;
    };

    return pylong.PyLong_FromLong(@intCast(bytes_written));
}

/// fileio_seek - Seek to position
fn fileio_seek(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));
    _ = args;

    if (fileio.fd < 0) return null;

    // Parse offset and whence, call lseek
    return null;
}

/// fileio_tell - Get current position
fn fileio_tell(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));

    if (fileio.fd < 0) return null;

    // lseek(fd, 0, SEEK_CUR)
    return null;
}

/// fileio_truncate - Truncate file
fn fileio_truncate(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));
    _ = args;

    if (fileio.fd < 0) return null;
    if (fileio.writable == 0) return null;

    // ftruncate(fd, size)
    return null;
}

/// fileio_fileno - Return file descriptor
fn fileio_fileno(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));

    if (fileio.fd < 0) return null;

    // Return PyLong with fd value
    return null;
}

/// fileio_isatty - Check if terminal
fn fileio_isatty(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");

    if (fileio.fd < 0) return null;

    // isatty(fd)
    if (std.c.isatty(fileio.fd) != 0) {
        return &object_mod._Py_TrueStruct;
    }
    return &object_mod._Py_FalseStruct;
}

/// fileio_readable - Check if readable
fn fileio_readable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");

    if (fileio.readable != 0) {
        return &object_mod._Py_TrueStruct;
    }
    return &object_mod._Py_FalseStruct;
}

/// fileio_writable - Check if writable
fn fileio_writable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");

    if (fileio.writable != 0) {
        return &object_mod._Py_TrueStruct;
    }
    return &object_mod._Py_FalseStruct;
}

/// fileio_seekable - Check if seekable
fn fileio_seekable(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");

    if (fileio.fd < 0) return null;

    // Check if seekable (lazy, cache result)
    if (fileio.seekable == -1) {
        // Try lseek to check
        const pos = std.c.lseek(fileio.fd, 0, std.c.SEEK.CUR);
        fileio.seekable = if (pos >= 0) 1 else 0;
    }

    if (fileio.seekable != 0) {
        return &object_mod._Py_TrueStruct;
    }
    return &object_mod._Py_FalseStruct;
}

/// fileio_mode_get - Get mode property
fn fileio_mode_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    _ = self;
    // Return mode as string
    return null;
}

/// fileio_closefd_get - Get closefd property
fn fileio_closefd_get(self: ?*cpython.PyObject, _: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    const fileio: *PyFileIO = @ptrCast(@alignCast(self.?));
    const object_mod = @import("../../objects/object.zig");

    if (fileio.closefd != 0) {
        return &object_mod._Py_TrueStruct;
    }
    return &object_mod._Py_FalseStruct;
}

/// fileio_repr - String representation
fn fileio_repr(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (self == null) return null;
    // "<_io.FileIO name='...' mode='rb' closefd=True>"
    return null;
}

// ============================================================================
// METHOD TABLES
// ============================================================================

pub export var fileio_methods: [14]cpython.PyMethodDef = .{
    .{ .ml_name = "close", .ml_meth = @ptrCast(&fileio_close), .ml_flags = 0x0004, .ml_doc = "Close the file." },
    .{ .ml_name = "read", .ml_meth = @ptrCast(&fileio_read), .ml_flags = 0x0001, .ml_doc = "Read at most size bytes." },
    .{ .ml_name = "readall", .ml_meth = @ptrCast(&fileio_readall), .ml_flags = 0x0004, .ml_doc = "Read all data from the file." },
    .{ .ml_name = "readinto", .ml_meth = @ptrCast(&fileio_readinto), .ml_flags = 0x0008, .ml_doc = "Read bytes into a buffer." },
    .{ .ml_name = "write", .ml_meth = @ptrCast(&fileio_write), .ml_flags = 0x0008, .ml_doc = "Write bytes to the file." },
    .{ .ml_name = "seek", .ml_meth = @ptrCast(&fileio_seek), .ml_flags = 0x0001, .ml_doc = "Seek to a position." },
    .{ .ml_name = "tell", .ml_meth = @ptrCast(&fileio_tell), .ml_flags = 0x0004, .ml_doc = "Return current position." },
    .{ .ml_name = "truncate", .ml_meth = @ptrCast(&fileio_truncate), .ml_flags = 0x0001, .ml_doc = "Truncate the file." },
    .{ .ml_name = "fileno", .ml_meth = @ptrCast(&fileio_fileno), .ml_flags = 0x0004, .ml_doc = "Return the file descriptor." },
    .{ .ml_name = "isatty", .ml_meth = @ptrCast(&fileio_isatty), .ml_flags = 0x0004, .ml_doc = "Return True if this is a terminal." },
    .{ .ml_name = "readable", .ml_meth = @ptrCast(&fileio_readable), .ml_flags = 0x0004, .ml_doc = "Return True if file is readable." },
    .{ .ml_name = "writable", .ml_meth = @ptrCast(&fileio_writable), .ml_flags = 0x0004, .ml_doc = "Return True if file is writable." },
    .{ .ml_name = "seekable", .ml_meth = @ptrCast(&fileio_seekable), .ml_flags = 0x0004, .ml_doc = "Return True if file is seekable." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var fileio_getset: [4]cpython.PyGetSetDef = .{
    .{ .name = "closed", .get = @ptrCast(&fileio_closed_get), .set = null, .doc = "True if the file is closed.", .closure = null },
    .{ .name = "mode", .get = @ptrCast(&fileio_mode_get), .set = null, .doc = "String giving the file mode.", .closure = null },
    .{ .name = "closefd", .get = @ptrCast(&fileio_closefd_get), .set = null, .doc = "True if the file descriptor will be closed.", .closure = null },
    .{ .name = null, .get = null, .set = null, .doc = null, .closure = null },
};

// ============================================================================
// TYPE OBJECT
// ============================================================================

pub export var PyFileIO_Type: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_io.FileIO",
    .tp_basicsize = @sizeOf(PyFileIO),
    .tp_itemsize = 0,
    .tp_dealloc = fileio_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = fileio_repr,
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
    .tp_doc = "Open a file.\n\nThe mode can be 'r' (default), 'w', 'x' or 'a' for reading,\nwriting, exclusive creation or appending. The file will be created if it\ndoesn't exist when opened for writing or appending; it will be truncated\nwhen opened for writing. A FileExistsError will be raised if it already\nexists when opened for creating. Opening a file for creating implies\nwriting, so this mode behaves in a similar way to 'w'. Add a 'b' to the\nmode for binary mode. Add a '+' to the mode to allow simultaneous reading\nand writing.",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = @offsetOf(PyFileIO, "base") + @offsetOf(iobase.PyIOBase, "weakreflist"),
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = &fileio_methods,
    .tp_members = null,
    .tp_getset = &fileio_getset,
    .tp_base = &iobase.PyRawIOBase_Type,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = @offsetOf(PyFileIO, "base") + @offsetOf(iobase.PyIOBase, "dict"),
    .tp_init = fileio_init,
    .tp_alloc = null,
    .tp_new = fileio_new,
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
// C API FUNCTIONS
// ============================================================================

/// Create FileIO from file descriptor
pub export fn PyFileIO_FromFd(fd: c_int, name: ?*cpython.PyObject, mode: [*:0]const u8, closefd: c_int) callconv(.c) ?*cpython.PyObject {
    _ = name;

    const obj = fileio_new(&PyFileIO_Type, null, null);
    if (obj == null) return null;

    const fileio: *PyFileIO = @ptrCast(@alignCast(obj.?));
    fileio.fd = fd;
    fileio.closefd = closefd;

    // Parse mode
    var i: usize = 0;
    while (mode[i] != 0 and i < 5) : (i += 1) {
        fileio.mode[i] = mode[i];
        switch (mode[i]) {
            'r' => fileio.readable = 1,
            'w', 'a', 'x' => fileio.writable = 1,
            '+' => {
                fileio.readable = 1;
                fileio.writable = 1;
            },
            else => {},
        }
    }
    fileio.mode[i] = 0;

    return obj;
}
