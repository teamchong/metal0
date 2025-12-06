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

    // TODO: Return PyUnicode_FromFormat("<stdprinter(fd=%d) object at %p>", ...)
    _ = self;
    return null;
}

/// Write to std printer
fn stdprinter_write(self_obj: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    if (self_obj == null or args == null) return null;
    const self: *PyStdPrinter_Object = @ptrCast(@alignCast(self_obj.?));

    if (self.fd < 0) {
        // Would raise ValueError("I/O operation on closed file")
        return null;
    }

    // TODO: Parse args to get unicode string
    // Convert to UTF-8 and write to fd
    // For now, just return the length

    const pylong = @import("longobject.zig");
    return pylong.PyLong_FromSsize_t(0);
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
    return none._Py_NoneStruct();
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
    _ = name;
    _ = mode;
    _ = buffering;
    _ = encoding;
    _ = errors;
    _ = newline;
    _ = closefd;

    // TODO: Import _io and call open()
    // For now, just return a std printer for the fd
    return PyFile_NewStdPrinter(fd);
}

/// Read a line from file object
pub export fn PyFile_GetLine(f: ?*cpython.PyObject, n: c_int) ?*cpython.PyObject {
    if (f == null) return null;

    // TODO: Call f.readline() or f.readline(n)
    _ = n;
    return null;
}

/// Write object to file
pub export fn PyFile_WriteObject(v: ?*cpython.PyObject, f: ?*cpython.PyObject, flags: c_int) c_int {
    if (f == null) return -1;
    if (v == null) return -1;

    // TODO: Get write method from f
    // If flags & Py_PRINT_RAW, use str(v), else use repr(v)
    // Call f.write(str_or_repr)
    _ = flags;
    return 0;
}

/// Write string to file
pub export fn PyFile_WriteString(s: ?[*:0]const u8, f: ?*cpython.PyObject) c_int {
    if (f == null) return -1;
    if (s == null) return -1;

    // TODO: Create unicode from string and call PyFile_WriteObject
    const pyunicode = @import("unicodeobject.zig");
    const v = pyunicode.PyUnicode_FromString(s.?);
    if (v == null) return -1;

    const result = PyFile_WriteObject(v, f, Py_PRINT_RAW);

    // Decref v
    v.?.ob_refcnt -= 1;

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

    // TODO: Try to call o.fileno() method
    return -1;
}

/// Open file for code execution
pub export fn PyFile_OpenCode(utf8path: ?[*:0]const u8) ?*cpython.PyObject {
    if (utf8path == null) return null;

    // TODO: Open file using custom hook or fallback to io.open
    return null;
}

/// Open file for code execution (object path)
pub export fn PyFile_OpenCodeObject(path: ?*cpython.PyObject) ?*cpython.PyObject {
    if (path == null) return null;

    // TODO: Convert path to string and call PyFile_OpenCode
    return null;
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
