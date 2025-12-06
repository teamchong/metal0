/// Unicode Writer Implementation - Efficient Unicode String Builder
///
/// Implements CPython's Objects/unicode_writer.c
/// Provides _PyUnicodeWriter for building Unicode strings efficiently
///
/// Reference: cpython/Objects/unicode_writer.c
/// This is the core string building infrastructure used throughout CPython

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// OVERALLOCATION SETTINGS
// ============================================================================

// On Windows, overallocate by 50% (factor 2)
// On Linux, overallocate by 25% (factor 4)
const OVERALLOCATE_FACTOR: usize = if (@import("builtin").os.tag == .windows) 2 else 4;

// ============================================================================
// TYPE DEFINITIONS - Exact CPython Layout
// ============================================================================

/// _PyUnicodeWriter - efficient Unicode string builder
/// Reference: cpython/Include/cpython/unicodeobject.h
///
/// typedef struct {
///     PyObject *buffer;
///     void *data;
///     int kind;
///     Py_UCS4 maxchar;
///     Py_ssize_t size;
///     Py_ssize_t pos;
///     Py_ssize_t min_length;
///     Py_UCS4 min_char;
///     unsigned char overallocate;
///     unsigned char readonly;
/// } _PyUnicodeWriter;
pub const _PyUnicodeWriter = extern struct {
    buffer: ?*cpython.PyObject, // 8 bytes - output buffer
    data: ?*anyopaque, // 8 bytes - pointer to buffer data
    kind: c_int, // 4 bytes - PyUnicode_KIND (1, 2, or 4)
    maxchar: u32, // 4 bytes - maximum character in buffer
    size: isize, // 8 bytes - allocated size
    pos: isize, // 8 bytes - current write position
    min_length: isize, // 8 bytes - minimum length hint
    min_char: u32, // 4 bytes - minimum character (usually 127 for ASCII)
    overallocate: u8, // 1 byte - whether to overallocate
    readonly: u8, // 1 byte - whether buffer is readonly (copy-on-write)
    _padding: [2]u8, // 2 bytes - alignment padding
};

// Verify _PyUnicodeWriter size: 8+8+4+4+8+8+8+4+1+1+2 = 56 bytes
comptime {
    if (@sizeOf(_PyUnicodeWriter) != 56) {
        @compileError("_PyUnicodeWriter size mismatch with CPython");
    }
}

/// PyUnicodeWriter - public API wrapper (same as _PyUnicodeWriter)
pub const PyUnicodeWriter = _PyUnicodeWriter;

// ============================================================================
// WRITER IMPLEMENTATION
// ============================================================================

/// Update writer state after buffer change
fn _PyUnicodeWriter_Update(writer: *_PyUnicodeWriter) void {
    if (writer.buffer) |buf| {
        const pyunicode = @import("unicodeobject.zig");
        writer.maxchar = pyunicode.PyUnicode_MAX_CHAR_VALUE(buf);
        writer.data = pyunicode.PyUnicode_DATA(buf);

        if (writer.readonly == 0) {
            writer.kind = pyunicode.PyUnicode_KIND(buf);
            writer.size = pyunicode.PyUnicode_GetLength(buf);
        } else {
            // Copy-on-write mode
            writer.kind = 0;
            writer.size = 0;
        }
    }
}

/// Initialize a Unicode writer
pub export fn _PyUnicodeWriter_Init(writer: *_PyUnicodeWriter) void {
    writer.* = .{
        .buffer = null,
        .data = null,
        .kind = 0,
        .maxchar = 0,
        .size = 0,
        .pos = 0,
        .min_length = 0,
        .min_char = 127, // ASCII is the bare minimum
        .overallocate = 0,
        .readonly = 0,
        ._padding = [_]u8{0} ** 2,
    };
}

/// Initialize writer with an existing buffer
pub export fn _PyUnicodeWriter_InitWithBuffer(writer: *_PyUnicodeWriter, buffer: ?*cpython.PyObject) void {
    _PyUnicodeWriter_Init(writer);

    if (buffer) |buf| {
        writer.buffer = buf;
        buf.ob_refcnt += 1;
        _PyUnicodeWriter_Update(writer);
        writer.readonly = 1; // Mark as copy-on-write
    }
}

/// Create a new PyUnicodeWriter
pub export fn PyUnicodeWriter_Create(length: isize) ?*PyUnicodeWriter {
    if (length < 0) {
        return null;
    }

    const mem = allocator.alignedAlloc(u8, @alignOf(PyUnicodeWriter), @sizeOf(PyUnicodeWriter)) catch return null;
    const writer: *PyUnicodeWriter = @ptrCast(@alignCast(mem.ptr));

    _PyUnicodeWriter_Init(writer);

    if (_PyUnicodeWriter_Prepare(writer, length, 127) < 0) {
        PyUnicodeWriter_Discard(writer);
        return null;
    }
    writer.overallocate = 1;

    return writer;
}

/// Discard a PyUnicodeWriter without returning a result
pub export fn PyUnicodeWriter_Discard(writer: ?*PyUnicodeWriter) void {
    if (writer == null) return;

    _PyUnicodeWriter_Dealloc(writer.?);

    const ptr: [*]u8 = @ptrCast(writer.?);
    allocator.free(ptr[0..@sizeOf(PyUnicodeWriter)]);
}

/// Deallocate writer resources (but not the writer struct itself)
pub export fn _PyUnicodeWriter_Dealloc(writer: *_PyUnicodeWriter) void {
    if (writer.buffer) |buf| {
        buf.ob_refcnt -= 1;
        if (buf.ob_refcnt <= 0) {
            // Free the buffer
            const pyunicode = @import("unicodeobject.zig");
            _ = pyunicode;
            // TODO: proper deallocation
        }
        writer.buffer = null;
    }
}

/// Prepare writer for writing `length` characters with max char `maxchar`
pub export fn _PyUnicodeWriter_Prepare(writer: *_PyUnicodeWriter, length: isize, maxchar: u32) c_int {
    if (length <= 0) return 0;

    const pyunicode = @import("unicodeobject.zig");

    // Check if we need to allocate or reallocate
    const new_len = writer.pos + length;

    if (writer.buffer == null) {
        // First allocation
        var alloc_len = new_len;
        if (writer.overallocate != 0) {
            alloc_len = alloc_len + alloc_len / OVERALLOCATE_FACTOR;
        }

        const buffer = pyunicode.PyUnicode_New(alloc_len, maxchar);
        if (buffer == null) return -1;

        writer.buffer = buffer;
        _PyUnicodeWriter_Update(writer);
        return 0;
    }

    // Check if we have enough space
    if (new_len <= writer.size and maxchar <= writer.maxchar) {
        return 0;
    }

    // Need to resize or upgrade
    var alloc_len = new_len;
    if (writer.overallocate != 0) {
        alloc_len = alloc_len + alloc_len / OVERALLOCATE_FACTOR;
    }

    const new_maxchar = if (maxchar > writer.maxchar) maxchar else writer.maxchar;

    // Create new buffer
    const new_buffer = pyunicode.PyUnicode_New(alloc_len, new_maxchar);
    if (new_buffer == null) return -1;

    // Copy existing content
    if (writer.pos > 0 and writer.buffer != null) {
        pyunicode._PyUnicode_FastCopyCharacters(new_buffer, 0, writer.buffer.?, 0, writer.pos);
    }

    // Release old buffer
    if (writer.buffer) |buf| {
        buf.ob_refcnt -= 1;
    }

    writer.buffer = new_buffer;
    _PyUnicodeWriter_Update(writer);

    return 0;
}

/// Prepare writer for writing a character with given kind
pub export fn _PyUnicodeWriter_PrepareKind(writer: *_PyUnicodeWriter, kind: c_int) c_int {
    const maxchar: u32 = switch (kind) {
        1 => 0xFF, // PyUnicode_1BYTE_KIND
        2 => 0xFFFF, // PyUnicode_2BYTE_KIND
        4 => 0x10FFFF, // PyUnicode_4BYTE_KIND
        else => return -1,
    };

    return _PyUnicodeWriter_Prepare(writer, 0, maxchar);
}

/// Write a single character
pub export fn _PyUnicodeWriter_WriteChar(writer: *_PyUnicodeWriter, ch: u32) c_int {
    if (_PyUnicodeWriter_Prepare(writer, 1, ch) < 0) {
        return -1;
    }

    if (writer.buffer) |buf| {
        const pyunicode = @import("unicodeobject.zig");
        pyunicode.PyUnicode_WRITE(writer.kind, writer.data, writer.pos, ch);
        writer.pos += 1;
        _ = buf;
    }

    return 0;
}

/// Write a Unicode string
pub export fn _PyUnicodeWriter_WriteStr(writer: *_PyUnicodeWriter, str: ?*cpython.PyObject) c_int {
    if (str == null) return -1;

    const pyunicode = @import("unicodeobject.zig");
    const length = pyunicode.PyUnicode_GetLength(str.?);
    if (length < 0) return -1;
    if (length == 0) return 0;

    const maxchar = pyunicode.PyUnicode_MAX_CHAR_VALUE(str.?);
    if (_PyUnicodeWriter_Prepare(writer, length, maxchar) < 0) {
        return -1;
    }

    if (writer.buffer != null) {
        pyunicode._PyUnicode_FastCopyCharacters(writer.buffer.?, writer.pos, str.?, 0, length);
        writer.pos += length;
    }

    return 0;
}

/// Write a substring
pub export fn _PyUnicodeWriter_WriteSubstring(writer: *_PyUnicodeWriter, str: ?*cpython.PyObject, start: isize, end: isize) c_int {
    if (str == null) return -1;

    const length = end - start;
    if (length <= 0) return 0;

    const pyunicode = @import("unicodeobject.zig");
    const maxchar = pyunicode.PyUnicode_MAX_CHAR_VALUE(str.?);

    if (_PyUnicodeWriter_Prepare(writer, length, maxchar) < 0) {
        return -1;
    }

    if (writer.buffer != null) {
        pyunicode._PyUnicode_FastCopyCharacters(writer.buffer.?, writer.pos, str.?, start, length);
        writer.pos += length;
    }

    return 0;
}

/// Write an ASCII string
pub export fn _PyUnicodeWriter_WriteASCIIString(writer: *_PyUnicodeWriter, str: [*:0]const u8, len: isize) c_int {
    const length = if (len < 0) @as(isize, @intCast(std.mem.len(str))) else len;
    if (length == 0) return 0;

    if (_PyUnicodeWriter_Prepare(writer, length, 127) < 0) {
        return -1;
    }

    if (writer.data) |data| {
        const dest: [*]u8 = @ptrCast(data);
        @memcpy(dest[@intCast(writer.pos)..@intCast(writer.pos + length)], str[0..@intCast(length)]);
        writer.pos += length;
    }

    return 0;
}

/// Write a Latin-1 string
pub export fn _PyUnicodeWriter_WriteLatin1String(writer: *_PyUnicodeWriter, str: [*]const u8, len: isize) c_int {
    if (len <= 0) return 0;

    // Find max character
    var maxchar: u32 = 0;
    for (str[0..@intCast(len)]) |c| {
        if (c > maxchar) maxchar = c;
    }

    if (_PyUnicodeWriter_Prepare(writer, len, maxchar) < 0) {
        return -1;
    }

    if (writer.data) |data| {
        if (writer.kind == 1) {
            // Direct copy
            const dest: [*]u8 = @ptrCast(data);
            @memcpy(dest[@intCast(writer.pos)..@intCast(writer.pos + len)], str[0..@intCast(len)]);
        } else {
            // Need to expand
            const pyunicode = @import("unicodeobject.zig");
            for (0..@intCast(len)) |i| {
                pyunicode.PyUnicode_WRITE(writer.kind, data, writer.pos + @as(isize, @intCast(i)), str[i]);
            }
        }
        writer.pos += len;
    }

    return 0;
}

/// Finish writing and return the Unicode string
pub export fn _PyUnicodeWriter_Finish(writer: *_PyUnicodeWriter) ?*cpython.PyObject {
    if (writer.pos == 0) {
        _PyUnicodeWriter_Dealloc(writer);
        const pyunicode = @import("unicodeobject.zig");
        return pyunicode._PyUnicode_GetEmpty();
    }

    const result = writer.buffer;
    if (result) |buf| {
        // Truncate to actual length if needed
        const pyunicode = @import("unicodeobject.zig");
        const length = pyunicode.PyUnicode_GetLength(buf);
        if (writer.pos < length) {
            // Resize to actual length
            _ = pyunicode.PyUnicode_Resize(&writer.buffer, writer.pos);
        }
    }

    writer.buffer = null;
    return result;
}

/// Public API: Finish and return result
pub export fn PyUnicodeWriter_Finish(writer: ?*PyUnicodeWriter) ?*cpython.PyObject {
    if (writer == null) return null;

    const result = _PyUnicodeWriter_Finish(writer.?);

    // Free the writer struct
    const ptr: [*]u8 = @ptrCast(writer.?);
    allocator.free(ptr[0..@sizeOf(PyUnicodeWriter)]);

    return result;
}

/// Public API: Write a string
pub export fn PyUnicodeWriter_WriteStr(writer: ?*PyUnicodeWriter, str: ?*cpython.PyObject) c_int {
    if (writer == null) return -1;
    return _PyUnicodeWriter_WriteStr(writer.?, str);
}

/// Public API: Write a character
pub export fn PyUnicodeWriter_WriteChar(writer: ?*PyUnicodeWriter, ch: u32) c_int {
    if (writer == null) return -1;
    return _PyUnicodeWriter_WriteChar(writer.?, ch);
}

/// Public API: Write a UTF-8 string
pub export fn PyUnicodeWriter_WriteUTF8(writer: ?*PyUnicodeWriter, str: [*:0]const u8, len: isize) c_int {
    if (writer == null) return -1;

    // For ASCII strings, use the fast path
    const length = if (len < 0) @as(isize, @intCast(std.mem.len(str))) else len;

    // Check if all ASCII
    var all_ascii = true;
    for (str[0..@intCast(length)]) |c| {
        if (c >= 0x80) {
            all_ascii = false;
            break;
        }
    }

    if (all_ascii) {
        return _PyUnicodeWriter_WriteASCIIString(writer.?, str, length);
    }

    // Need to decode UTF-8
    const pyunicode = @import("unicodeobject.zig");
    const unicode = pyunicode.PyUnicode_DecodeUTF8(str, length, null);
    if (unicode == null) return -1;

    const result = _PyUnicodeWriter_WriteStr(writer.?, unicode);
    unicode.?.ob_refcnt -= 1;

    return result;
}

/// Public API: Write repr of object
pub export fn PyUnicodeWriter_WriteRepr(writer: ?*PyUnicodeWriter, obj: ?*cpython.PyObject) c_int {
    if (writer == null) return -1;
    if (obj == null) return -1;

    const object_mod = @import("object.zig");
    const repr = object_mod.PyObject_Repr(obj);
    if (repr == null) return -1;

    const result = _PyUnicodeWriter_WriteStr(writer.?, repr);
    repr.?.ob_refcnt -= 1;

    return result;
}

/// Public API: Write substring
pub export fn PyUnicodeWriter_WriteSubstring(writer: ?*PyUnicodeWriter, str: ?*cpython.PyObject, start: isize, end: isize) c_int {
    if (writer == null) return -1;
    return _PyUnicodeWriter_WriteSubstring(writer.?, str, start, end);
}
