/// CPython File I/O Interface
///
/// Implements PyFile_* functions for file object operations.

const std = @import("std");
const cpython = @import("object.zig");
const traits = @import("../objects/typetraits.zig");

// ============================================================================
// FILE TYPE DEFINITIONS
// ============================================================================

/// Minimal file object representation
pub const PyFileObject = extern struct {
    ob_base: cpython.PyObject,
    // File objects in Python 3 are mostly in io module
    // This is a simplified stub
};

// ============================================================================
// FILE CHECK FUNCTIONS
// ============================================================================

/// Check if object is a file-like object (has write method)
pub export fn PyFile_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    // Check for file-like objects (have read/write methods)
    const type_obj = cpython.Py_TYPE(obj);

    // Check if type name contains "file" or "io"
    if (type_obj.tp_name) |name| {
        const name_str = std.mem.span(name);
        if (std.mem.indexOf(u8, name_str, "file") != null or
            std.mem.indexOf(u8, name_str, "File") != null or
            std.mem.indexOf(u8, name_str, "IO") != null or
            std.mem.indexOf(u8, name_str, "io") != null)
        {
            return 1;
        }
    }

    // Check for buffer protocol
    if (type_obj.tp_as_buffer != null) return 1;

    return 0;
}

// ============================================================================
// FILE WRITE FUNCTIONS
// ============================================================================

/// Write object to file using its repr
pub export fn PyFile_WriteObject(obj: *cpython.PyObject, file: *cpython.PyObject, flags: c_int) callconv(.c) c_int {
    _ = flags;

    // Get string representation
    const type_obj = cpython.Py_TYPE(obj);
    const str_obj: ?*cpython.PyObject = if (type_obj.tp_str) |str_fn| str_fn(obj) else if (type_obj.tp_repr) |repr_fn| repr_fn(obj) else null;

    if (str_obj) |s| {
        defer traits.decref(s);
        return PyFile_WriteString(getUTF8(s), file);
    }

    return -1;
}

/// Write C string to file object
/// Calls the file's write() method if available, otherwise writes to stdout
pub export fn PyFile_WriteString(str: [*:0]const u8, file: *cpython.PyObject) callconv(.c) c_int {
    const cstr = std.mem.span(str);
    if (cstr.len == 0) return 0;

    // Try to call file.write() method
    const type_obj = cpython.Py_TYPE(file);

    // Check if it's a FileIO with fd
    if (type_obj == &PyFileIO_Type) {
        const wrapper: *PyFileWrapper = @ptrCast(@alignCast(file));
        if (wrapper.fd >= 0) {
            const posix = std.posix;
            _ = posix.write(@intCast(wrapper.fd), cstr) catch return -1;
            return 0;
        }
    }

    // Check tp_methods for write method
    if (type_obj.tp_methods) |methods| {
        var i: usize = 0;
        while (methods[i].ml_name != null) : (i += 1) {
            if (std.mem.eql(u8, std.mem.span(methods[i].ml_name.?), "write")) {
                // Found write method - call it
                const pybytes = @import("../objects/bytesobject.zig");
                const bytes_obj = pybytes.PyBytes_FromStringAndSize(str, @intCast(cstr.len));
                if (bytes_obj) |b| {
                    defer b.ob_refcnt -= 1;
                    if (methods[i].ml_meth) |meth| {
                        const result = meth(file, @ptrCast(b));
                        if (result != null) {
                            result.?.ob_refcnt -= 1;
                            return 0;
                        }
                    }
                }
                break;
            }
        }
    }

    // Fallback: write to stdout
    _ = std.io.getStdOut().write(cstr) catch return -1;
    return 0;
}

// ============================================================================
// FILE CREATION FUNCTIONS
// ============================================================================

/// File wrapper object for file descriptor
pub const PyFileWrapper = extern struct {
    ob_base: cpython.PyObject,
    fd: c_int,
    name: ?*cpython.PyObject,
    mode: ?*cpython.PyObject,
    closefd: c_int,
};

pub var PyFileIO_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "FileIO",
    .tp_basicsize = @sizeOf(PyFileWrapper),
    .tp_itemsize = 0,
    .tp_dealloc = file_dealloc,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
};

fn file_dealloc(self: *cpython.PyObject) callconv(.c) void {
    const fw: *PyFileWrapper = @ptrCast(@alignCast(self));
    if (fw.closefd != 0 and fw.fd >= 0) {
        _ = std.c.close(fw.fd);
    }
    if (fw.name) |n| traits.decref(n);
    if (fw.mode) |m| traits.decref(m);
    std.heap.c_allocator.destroy(fw);
}

/// Create file object from file descriptor
pub export fn PyFile_FromFd(fd: c_int, name: ?[*:0]const u8, mode: [*:0]const u8, buffering: c_int, encoding: ?[*:0]const u8, errors: ?[*:0]const u8, newline: ?[*:0]const u8, closefd: c_int) callconv(.c) ?*cpython.PyObject {
    _ = buffering;
    _ = encoding;
    _ = errors;
    _ = newline;

    const pyunicode = @import("../objects/unicodeobject.zig");
    const fw = std.heap.c_allocator.create(PyFileWrapper) catch return null;

    fw.ob_base.ob_refcnt = 1;
    fw.ob_base.ob_type = &PyFileIO_Type;
    fw.fd = fd;
    fw.closefd = closefd;

    if (name) |n| {
        fw.name = pyunicode.PyUnicode_FromString(n);
    } else {
        fw.name = null;
    }
    fw.mode = pyunicode.PyUnicode_FromString(mode);

    return @ptrCast(&fw.ob_base);
}

/// Read a line from file
pub export fn PyFile_GetLine(file: *cpython.PyObject, n: c_int) callconv(.c) ?*cpython.PyObject {
    const pyunicode = @import("../objects/unicodeobject.zig");

    // Check if it's our file wrapper
    if (cpython.Py_TYPE(file) == &PyFileIO_Type) {
        const fw: *PyFileWrapper = @ptrCast(@alignCast(file));
        if (fw.fd < 0) return null;

        // Read line from fd
        var buf: [4096]u8 = undefined;
        var pos: usize = 0;
        const max_len: usize = if (n > 0) @intCast(n) else buf.len - 1;

        while (pos < max_len) {
            var c: [1]u8 = undefined;
            const bytes_read = std.c.read(fw.fd, &c, 1);
            if (bytes_read <= 0) break;
            buf[pos] = c[0];
            pos += 1;
            if (c[0] == '\n') break;
        }

        if (pos == 0) return null;
        return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(pos));
    }

    // Try calling readline method on file object
    const call = @import("call.zig");
    return call.PyObject_CallMethod(file, "readline", null);
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

fn getUTF8(obj: *cpython.PyObject) [*:0]const u8 {
    const pyunicode = @import("unicodeobject.zig");
    return pyunicode.PyUnicode_AsUTF8(obj) orelse "";
}

// ============================================================================
// TESTS
// ============================================================================

test "file function exports" {
    _ = PyFile_Check;
    _ = PyFile_WriteObject;
    _ = PyFile_WriteString;
}
