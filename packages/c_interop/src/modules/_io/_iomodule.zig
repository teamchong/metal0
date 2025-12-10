/// _io Module - Core I/O Implementation
///
/// Implements CPython's Modules/_io/_iomodule.c
/// Provides the core I/O classes: RawIOBase, BufferedIOBase, TextIOBase
/// and their concrete implementations.
///
/// Reference: cpython/Modules/_io/_iomodule.c
const std = @import("std");
const cpython = @import("../../include/object.zig");

const allocator = std.heap.c_allocator;

// Re-export submodule types for C interop
pub const iobase = @import("iobase.zig");
pub const fileio = @import("fileio.zig");
pub const bytesio = @import("bytesio.zig");
pub const stringio = @import("stringio.zig");
pub const bufferedio = @import("bufferedio.zig");
pub const textio = @import("textio.zig");

// Re-export key types for direct access
pub const PyIOBase = iobase.PyIOBase;
pub const PyRawIOBase = iobase.PyRawIOBase;
pub const PyBufferedIOBase = iobase.PyBufferedIOBase;
pub const PyTextIOBase = iobase.PyTextIOBase;
pub const PyFileIO = fileio.PyFileIO;
pub const PyBytesIO = bytesio.PyBytesIO;
pub const PyStringIO = stringio.PyStringIO;
pub const PyBufferedReader = bufferedio.PyBufferedReader;
pub const PyBufferedWriter = bufferedio.PyBufferedWriter;
pub const PyBufferedRWPair = bufferedio.PyBufferedRWPair;
pub const PyBufferedRandom = bufferedio.PyBufferedRandom;
pub const PyTextIOWrapper = textio.PyTextIOWrapper;

// ============================================================================
// MODULE STATE
// ============================================================================

/// Module state structure
pub const _PyIO_State = extern struct {
    initialized: c_int,
    locale_module: ?*cpython.PyObject,
    unsupported_operation: ?*cpython.PyObject,
};

/// Global module state
var io_state: _PyIO_State = .{
    .initialized = 0,
    .locale_module = null,
    .unsupported_operation = null,
};

// ============================================================================
// IO BASE TYPES - See iobase.zig for definitions
// ============================================================================
// All base types (PyIOBase, PyRawIOBase, PyBufferedIOBase, PyTextIOBase)
// are defined in iobase.zig and re-exported above

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Check if object is a valid file descriptor
pub export fn _PyIO_check_fd(fd: c_int) callconv(.c) c_int {
    if (fd < 0) return -1;
    // Could check validity with fcntl on Unix
    return 0;
}

/// Get block size for file
pub export fn _PyIO_get_blksize(fd: c_int) callconv(.c) usize {
    _ = fd;
    // Default block size
    return 8192;
}

// ============================================================================
// OPEN FUNCTION
// ============================================================================

/// io.open() - Open file and return stream
/// This is the main entry point for Python's open() builtin
pub export fn PyIO_open(
    file: ?*cpython.PyObject,
    mode: ?*cpython.PyObject,
    buffering: c_int,
    encoding: ?*cpython.PyObject,
    errors: ?*cpython.PyObject,
    newline: ?*cpython.PyObject,
    closefd: c_int,
    opener: ?*cpython.PyObject,
) callconv(.c) ?*cpython.PyObject {
    const pyunicode = @import("../../objects/unicodeobject.zig");
    const pylong = @import("../../objects/longobject.zig");

    // Parse mode string to determine read/write/binary/text
    var reading = false;
    var writing = false;
    var appending = false;
    var binary = false;
    var creating = false;

    if (mode) |m| {
        if (pyunicode.PyUnicode_Check(m) != 0) {
            const mode_str = pyunicode.PyUnicode_AsUTF8(m);
            if (mode_str) |ms| {
                const mode_slice = std.mem.span(ms);
                for (mode_slice) |c| {
                    switch (c) {
                        'r' => reading = true,
                        'w' => writing = true,
                        'a' => appending = true,
                        'b' => binary = true,
                        '+' => {
                            reading = true;
                            writing = true;
                        },
                        'x' => creating = true,
                        else => {},
                    }
                }
            }
        }
    } else {
        reading = true; // Default mode is 'r'
    }

    // Default to reading if nothing specified
    if (!reading and !writing and !appending) {
        reading = true;
    }

    // Get file descriptor or path
    var fd: c_int = -1;
    if (file) |f| {
        if (pylong.PyLong_Check(f)) {
            fd = @intCast(pylong.PyLong_AsLong(f));
        }
    }

    // Create FileIO for raw access
    const raw = fileio.PyFileIO_New(file, mode, if (closefd != 0) true else false, opener);
    if (raw == null) return null;

    // For binary mode, wrap in BufferedReader/Writer
    if (binary) {
        if (buffering == 0) {
            // Unbuffered - return raw FileIO
            return @ptrCast(raw);
        }

        // Determine buffer size
        const buf_size: usize = if (buffering > 0) @intCast(buffering) else 8192;

        if (reading and !writing) {
            return bufferedio.PyBufferedReader_New(@ptrCast(raw), buf_size);
        } else if (writing and !reading) {
            return bufferedio.PyBufferedWriter_New(@ptrCast(raw), buf_size);
        } else {
            return bufferedio.PyBufferedRandom_New(@ptrCast(raw), buf_size);
        }
    }

    // Text mode - wrap in TextIOWrapper
    const buf_size: usize = if (buffering > 0) @intCast(buffering) else 8192;
    const buffered: ?*cpython.PyObject = blk: {
        if (reading and !writing) {
            break :blk bufferedio.PyBufferedReader_New(@ptrCast(raw), buf_size);
        } else if (writing and !reading) {
            break :blk bufferedio.PyBufferedWriter_New(@ptrCast(raw), buf_size);
        } else {
            break :blk bufferedio.PyBufferedRandom_New(@ptrCast(raw), buf_size);
        }
    };

    if (buffered == null) {
        cpython.Py_DECREF(@ptrCast(raw));
        return null;
    }

    _ = fd;
    _ = errors;
    _ = newline;

    // Create TextIOWrapper
    return textio.PyTextIOWrapper_New(buffered, encoding, errors, newline, true);
}

// ============================================================================
// TYPE OBJECTS - Defined in submodules, referenced here
// ============================================================================
// Type objects are defined in their respective submodules:
// - iobase.zig: PyIOBase_Type, PyRawIOBase_Type, PyBufferedIOBase_Type, PyTextIOBase_Type
// - fileio.zig: PyFileIO_Type
// - bytesio.zig: PyBytesIO_Type
// - stringio.zig: PyStringIO_Type
// - bufferedio.zig: PyBufferedReader_Type, PyBufferedWriter_Type, PyBufferedRWPair_Type, PyBufferedRandom_Type
// - textio.zig: PyTextIOWrapper_Type

// ============================================================================
// MODULE DEFINITION
// ============================================================================

pub export var _io_module: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_io",
    .m_doc = "The io module provides the Python interfaces to stream handling.",
    .m_size = @sizeOf(_PyIO_State),
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

/// Module initialization
pub export fn PyInit__io() callconv(.c) ?*cpython.PyObject {
    const module_mod = @import("../../objects/moduleobject.zig");
    const module = module_mod.PyModule_Create(&_io_module);
    if (module == null) return null;

    // Add base types from iobase.zig
    _ = module_mod.PyModule_AddObject(module, "_IOBase", @ptrCast(&iobase.PyIOBase_Type));
    _ = module_mod.PyModule_AddObject(module, "_RawIOBase", @ptrCast(&iobase.PyRawIOBase_Type));
    _ = module_mod.PyModule_AddObject(module, "_BufferedIOBase", @ptrCast(&iobase.PyBufferedIOBase_Type));
    _ = module_mod.PyModule_AddObject(module, "_TextIOBase", @ptrCast(&iobase.PyTextIOBase_Type));

    // Add concrete types from submodules
    _ = module_mod.PyModule_AddObject(module, "FileIO", @ptrCast(&fileio.PyFileIO_Type));
    _ = module_mod.PyModule_AddObject(module, "BytesIO", @ptrCast(&bytesio.PyBytesIO_Type));
    _ = module_mod.PyModule_AddObject(module, "StringIO", @ptrCast(&stringio.PyStringIO_Type));
    _ = module_mod.PyModule_AddObject(module, "BufferedReader", @ptrCast(&bufferedio.PyBufferedReader_Type));
    _ = module_mod.PyModule_AddObject(module, "BufferedWriter", @ptrCast(&bufferedio.PyBufferedWriter_Type));
    _ = module_mod.PyModule_AddObject(module, "BufferedRWPair", @ptrCast(&bufferedio.PyBufferedRWPair_Type));
    _ = module_mod.PyModule_AddObject(module, "BufferedRandom", @ptrCast(&bufferedio.PyBufferedRandom_Type));
    _ = module_mod.PyModule_AddObject(module, "TextIOWrapper", @ptrCast(&textio.PyTextIOWrapper_Type));

    // Add constants
    _ = module_mod.PyModule_AddIntConstant(module, "DEFAULT_BUFFER_SIZE", bufferedio.DEFAULT_BUFFER_SIZE);

    io_state.initialized = 1;
    return module;
}
