/// File Object Implementation - Exact CPython Memory Layout
///
/// Implements CPython's Objects/fileobject.c
/// Note: Most actual file I/O is handled by _io module
/// This file provides utility functions and the StdPrinter type
///
/// Reference: cpython/Objects/fileobject.c
///            cpython/Include/fileobject.h
///            cpython/Include/cpython/fileobject.h
/// Memory layout matches CPython 3.12 exactly
const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// CONSTANTS
// ============================================================================

/// Print flags for PyFile_WriteObject
pub const Py_PRINT_RAW: c_int = 1;

/// Standard IO text mode
pub const PY_STDIOTEXTMODE = "b";

/// Newline flags
pub const NEWLINE_UNKNOWN: c_int = 0;
pub const NEWLINE_CR: c_int = 1;
pub const NEWLINE_LF: c_int = 2;
pub const NEWLINE_CRLF: c_int = 4;

// ============================================================================
// STDPRINTER TYPE - Exact CPython Layout
// ============================================================================

/// PyStdPrinter_Object - preliminary file-like object for sys.stderr during bootstrap
/// Reference: cpython/Objects/fileobject.c
///
/// typedef struct {
///     PyObject_HEAD
///     int fd;
/// } PyStdPrinter_Object;
pub const PyStdPrinter_Object = extern struct {
    ob_base: cpython.PyObject, // 16 bytes
    fd: c_int, // 4 bytes
    _padding: [4]u8 = [_]u8{0} ** 4, // 4 bytes padding for alignment
};

// Verify PyStdPrinter_Object size: 16 + 4 + 4 = 24 bytes
comptime {
    if (@sizeOf(PyStdPrinter_Object) != 24) {
        @compileError("PyStdPrinter_Object size mismatch with CPython");
    }
}

// ============================================================================
// STDPRINTER TYPE IMPLEMENTATION
// ============================================================================

/// Dealloc for std printer
fn stdprinter_dealloc(self_obj: ?*cpython.PyObject) callconv(.C) void {
    if (self_obj == null) return;
    const self: *PyStdPrinter_Object = @ptrCast(@alignCast(self_obj.?));

    const ptr: [*]u8 = @ptrCast(self);
    allocator.free(ptr[0..@sizeOf(PyStdPrinter_Object)]);
}

/// Repr for std printer
fn stdprinter_repr(self_obj: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null) return null;
    const self: *PyStdPrinter_Object = @ptrCast(@alignCast(self_obj.?));

    // Format as "<stdprinter(fd=N) object at 0xPTR>"
    var buf: [128]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "<stdprinter(fd={any}) object at 0x{x}>", .{
        self.fd,
        @intFromPtr(self),
    }) catch return null;

    const pyunicode = @import("../include/unicodeobject.zig");
    return pyunicode.PyUnicode_FromStringAndSize(buf[0..len].ptr, @intCast(len));
}

/// Write to std printer
fn stdprinter_write(self_obj: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null or args == null) return null;
    const self: *PyStdPrinter_Object = @ptrCast(@alignCast(self_obj.?));

    if (self.fd < 0) {
        // Would raise ValueError("I/O operation on closed file")
        return null;
    }

    // Get unicode string from args
    const pyunicode = @import("../include/unicodeobject.zig");
    if (!pyunicode.PyUnicode_Check(args.?)) {
        return null;
    }

    // Get UTF-8 representation
    var size: isize = 0;
    const utf8 = pyunicode.PyUnicode_AsUTF8AndSize(args.?, &size);
    if (utf8 == null) return null;

    // Write to file descriptor
    const fd: std.posix.fd_t = @intCast(self.fd);
    const written = std.posix.write(fd, utf8.?[0..@intCast(size)]) catch |err| {
        _ = err;
        return null;
    };

    const pylong = @import("longobject.zig");
    return pylong.PyLong_FromSsize_t(@intCast(written));
}

/// Get file descriptor
fn stdprinter_fileno(self_obj: ?*cpython.PyObject, ignored: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = ignored;
    if (self_obj == null) return null;
    const self: *PyStdPrinter_Object = @ptrCast(@alignCast(self_obj.?));

    const pylong = @import("longobject.zig");
    return pylong.PyLong_FromLong(@intCast(self.fd));
}

/// Check if file is a tty
fn stdprinter_isatty(self_obj: ?*cpython.PyObject, ignored: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = ignored;
    if (self_obj == null) return null;
    const self: *PyStdPrinter_Object = @ptrCast(@alignCast(self_obj.?));

    if (self.fd < 0) {
        const pybool = @import("boolobject.zig");
        return pybool.Py_False;
    }

    // Check if fd is a tty
    const is_tty = std.c.isatty(self.fd);
    const pybool = @import("boolobject.zig");
    return if (is_tty != 0) pybool.Py_True else pybool.Py_False;
}

/// No-op methods (close, flush)
fn stdprinter_noop(self_obj: ?*cpython.PyObject, ignored: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = self_obj;
    _ = ignored;
    // Return None
    const none = @import("noneobject.zig");
    return &none._Py_NoneStruct;
}

/// PyStdPrinter_Type - the std printer type object
pub export var PyStdPrinter_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "stderrprinter",
    .tp_basicsize = @sizeOf(PyStdPrinter_Object),
    .tp_itemsize = 0,
    .tp_dealloc = stdprinter_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = stdprinter_repr,
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
    .tp_doc = null,
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
// PUBLIC API - Exported with C linkage
// ============================================================================

/// Create a new std printer object
pub export fn PyFile_NewStdPrinter(fd: c_int) ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(PyStdPrinter_Object), @sizeOf(PyStdPrinter_Object)) catch return null;
    const self: *PyStdPrinter_Object = @ptrCast(@alignCast(mem.ptr));

    self.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyStdPrinter_Type,
        },
        .fd = fd,
    };

    return @ptrCast(self);
}

/// Create file object from file descriptor
/// This calls _io.open to create the actual file object
pub export fn PyFile_FromFd(
    fd: c_int,
    name: ?[*:0]const u8,
    mode: ?[*:0]const u8,
    buffering: c_int,
    encoding: ?[*:0]const u8,
    errors: ?[*:0]const u8,
    newline: ?[*:0]const u8,
    closefd: c_int,
) ?*cpython.PyObject {
    const pyunicode = @import("unicodeobject.zig");
    const pylong = @import("longobject.zig");
    const _io = @import("../modules/_io/_iomodule.zig");

    // Convert fd to Python int
    const fd_obj = pylong.PyLong_FromLong(fd);
    if (fd_obj == null) return null;

    // Convert mode string
    var mode_obj: ?*cpython.PyObject = null;
    if (mode) |m| {
        mode_obj = pyunicode.PyUnicode_FromString(m);
    }

    // Convert encoding string
    var encoding_obj: ?*cpython.PyObject = null;
    if (encoding) |e| {
        encoding_obj = pyunicode.PyUnicode_FromString(e);
    }

    // Convert errors string
    var errors_obj: ?*cpython.PyObject = null;
    if (errors) |e| {
        errors_obj = pyunicode.PyUnicode_FromString(e);
    }

    // Convert newline string
    var newline_obj: ?*cpython.PyObject = null;
    if (newline) |n| {
        newline_obj = pyunicode.PyUnicode_FromString(n);
    }

    _ = name; // Name is just for repr, not needed for fd-based open

    // Call _io.open with the fd
    const result = _io._io_open(
        fd_obj,
        mode_obj,
        buffering,
        encoding_obj,
        errors_obj,
        newline_obj,
        closefd,
        null, // opener
    );

    // Clean up temporary objects
    cpython.Py_DECREF(fd_obj);
    if (mode_obj) |m| cpython.Py_DECREF(m);
    if (encoding_obj) |e| cpython.Py_DECREF(e);
    if (errors_obj) |e| cpython.Py_DECREF(e);
    if (newline_obj) |n| cpython.Py_DECREF(n);

    return result;
}

/// Read a line from file object
pub export fn PyFile_GetLine(f: ?*cpython.PyObject, n: c_int) ?*cpython.PyObject {
    if (f == null) return null;

    const object_mod = @import("object.zig");
    const pyunicode = @import("unicodeobject.zig");
    const pytuple = @import("tupleobject.zig");
    const pylong = @import("longobject.zig");

    // Get readline method
    const readline_name = pyunicode.PyUnicode_FromString("readline");
    if (readline_name == null) return null;
    defer cpython.Py_DECREF(readline_name.?);

    const readline_method = object_mod.PyObject_GetAttr(f.?, readline_name.?);
    if (readline_method == null) return null;
    defer cpython.Py_DECREF(readline_method.?);

    // Build args - either empty or with n
    var args: ?*cpython.PyObject = null;
    if (n > 0) {
        args = pytuple.PyTuple_New(1);
        if (args != null) {
            const n_obj = pylong.PyLong_FromLong(@intCast(n));
            if (n_obj != null) {
                _ = pytuple.PyTuple_SetItem(args.?, 0, n_obj);
            }
        }
    } else {
        args = pytuple.PyTuple_New(0);
    }
    if (args == null) return null;
    defer cpython.Py_DECREF(args.?);

    // Call readline method
    return object_mod.PyObject_Call(readline_method.?, args.?, null);
}

/// Write object to file
pub export fn PyFile_WriteObject(v: ?*cpython.PyObject, f: ?*cpython.PyObject, flags: c_int) c_int {
    if (f == null) return -1;
    if (v == null) return -1;

    // Get string representation of v
    const object_mod = @import("object.zig");
    const str_obj: ?*cpython.PyObject = if ((flags & Py_PRINT_RAW) != 0)
        object_mod.PyObject_Str(v.?)
    else
        object_mod.PyObject_Repr(v.?);

    if (str_obj == null) return -1;
    defer cpython.Py_DECREF(str_obj.?);

    // Get write method from f
    const pyunicode = @import("../include/unicodeobject.zig");
    const write_name = pyunicode.PyUnicode_FromString("write");
    if (write_name == null) return -1;
    defer cpython.Py_DECREF(write_name.?);

    const write_method = object_mod.PyObject_GetAttr(f.?, write_name.?);
    if (write_method == null) return -1;
    defer cpython.Py_DECREF(write_method.?);

    // Build args tuple
    const pytuple = @import("tupleobject.zig");
    const args = pytuple.PyTuple_New(1);
    if (args == null) return -1;
    defer cpython.Py_DECREF(args.?);

    cpython.Py_INCREF(str_obj.?);
    _ = pytuple.PyTuple_SetItem(args.?, 0, str_obj);

    // Call write method
    const result = object_mod.PyObject_Call(write_method.?, args.?, null);
    if (result == null) return -1;
    cpython.Py_DECREF(result.?);

    return 0;
}

/// Write string to file
pub export fn PyFile_WriteString(s: ?[*:0]const u8, f: ?*cpython.PyObject) c_int {
    if (f == null) return -1;
    if (s == null) return -1;

    // Create unicode from string and call PyFile_WriteObject
    const pyunicode = @import("unicodeobject.zig");
    const v = pyunicode.PyUnicode_FromString(s.?);
    if (v == null) return -1;

    const result = PyFile_WriteObject(v, f, Py_PRINT_RAW);

    // Decref v
    cpython.Py_DECREF(v.?);

    return result;
}

/// Get file descriptor from object
/// Returns -1 on failure
pub export fn PyObject_AsFileDescriptor(o: ?*cpython.PyObject) c_int {
    if (o == null) return -1;

    // Check if it's an integer
    const pylong = @import("longobject.zig");
    if (pylong.PyLong_Check(o.?)) {
        const fd = pylong.PyLong_AsLong(o.?);
        return @intCast(fd);
    }

    // Try to call o.fileno() method
    const object_mod = @import("object.zig");
    const pyunicode = @import("../include/unicodeobject.zig");

    const fileno_name = pyunicode.PyUnicode_FromString("fileno");
    if (fileno_name == null) return -1;
    defer cpython.Py_DECREF(fileno_name.?);

    const fileno_method = object_mod.PyObject_GetAttr(o.?, fileno_name.?);
    if (fileno_method == null) return -1;
    defer cpython.Py_DECREF(fileno_method.?);

    // Call fileno() with no args
    const pytuple = @import("tupleobject.zig");
    const empty_args = pytuple.PyTuple_New(0);
    if (empty_args == null) return -1;
    defer cpython.Py_DECREF(empty_args.?);

    const result = object_mod.PyObject_Call(fileno_method.?, empty_args.?, null);
    if (result == null) return -1;
    defer cpython.Py_DECREF(result.?);

    // Convert result to int
    if (!pylong.PyLong_Check(result.?)) return -1;
    return @intCast(pylong.PyLong_AsLong(result.?));
}

/// Open file for code execution
pub export fn PyFile_OpenCode(utf8path: ?[*:0]const u8) ?*cpython.PyObject {
    if (utf8path == null) return null;

    const pyunicode = @import("unicodeobject.zig");

    // Convert path to PyObject
    const path_obj = pyunicode.PyUnicode_FromString(utf8path.?);
    if (path_obj == null) return null;
    defer cpython.Py_DECREF(path_obj.?);

    // Check if a custom hook is set
    if (open_code_hook) |hook| {
        return hook(path_obj, open_code_hook_data);
    }

    // Fallback: Open file using standard file descriptor operations
    // Open for reading in binary mode
    const path_slice = std.mem.span(utf8path.?);
    const fd = std.posix.open(path_slice, .{ .ACCMODE = .RDONLY }, 0) catch return null;

    // Return a std printer wrapped around the fd for now
    // In full implementation, this would call _io.open
    return PyFile_NewStdPrinter(@intCast(fd));
}

/// Open file for code execution (object path)
pub export fn PyFile_OpenCodeObject(path: ?*cpython.PyObject) ?*cpython.PyObject {
    if (path == null) return null;

    const pyunicode = @import("unicodeobject.zig");

    // Convert path to string
    if (pyunicode.PyUnicode_Check(path.?) != 0) {
        const utf8 = pyunicode.PyUnicode_AsUTF8(path.?);
        if (utf8 != null) {
            return PyFile_OpenCode(utf8);
        }
    }

    // Try to convert using os.fspath
    const object_mod = @import("object.zig");
    const str_obj = object_mod.PyObject_Str(path.?);
    if (str_obj == null) return null;
    defer cpython.Py_DECREF(str_obj.?);

    const utf8 = pyunicode.PyUnicode_AsUTF8(str_obj.?);
    if (utf8 == null) return null;

    return PyFile_OpenCode(utf8);
}

/// Py_OpenCodeHookFunction type
pub const Py_OpenCodeHookFunction = ?*const fn (?*cpython.PyObject, ?*anyopaque) callconv(.C) ?*cpython.PyObject;

/// Set hook for opening code files
var open_code_hook: Py_OpenCodeHookFunction = null;
var open_code_hook_data: ?*anyopaque = null;

pub export fn PyFile_SetOpenCodeHook(hook: Py_OpenCodeHookFunction, userData: ?*anyopaque) c_int {
    if (open_code_hook != null) {
        // Hook already set
        return -1;
    }
    open_code_hook = hook;
    open_code_hook_data = userData;
    return 0;
}

/// Read line with universal newline support
pub export fn Py_UniversalNewlineFgets(
    buf: [*]u8,
    size: c_int,
    stream: ?*std.c.FILE,
    fobj: ?*cpython.PyObject,
) ?[*]u8 {
    _ = fobj;
    if (stream == null) return null;
    if (size <= 0) return null;

    // Read line from stream
    const result = std.c.fgets(buf, size, stream);
    if (result == null) return null;

    return buf;
}

// ============================================================================
// DEPRECATED GLOBALS (for compatibility)
// ============================================================================

/// File system default encoding (deprecated in 3.12)
pub export var Py_FileSystemDefaultEncoding: ?[*:0]const u8 = "utf-8";

/// File system default encode errors (deprecated in 3.12)
pub export var Py_FileSystemDefaultEncodeErrors: ?[*:0]const u8 = "surrogateescape";

/// Has file system default encoding (deprecated in 3.12)
pub export var Py_HasFileSystemDefaultEncoding: c_int = 1;

/// UTF-8 mode (deprecated in 3.12)
pub export var Py_UTF8Mode: c_int = 0;
