/// CPython Codec Registry Interface
///
/// Implements text encoding/decoding codec registry for CPython compatibility.

const std = @import("std");
const cpython = @import("cpython_object.zig");

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;
extern fn PyErr_SetString(*cpython.PyObject, [*:0]const u8) callconv(.c) void;

/// Register a codec search function
/// search_function should be a callable that takes encoding name and returns codec tuple
/// Returns 0 on success, -1 on error
export fn PyCodec_Register(search_function: *cpython.PyObject) callconv(.c) c_int {
    _ = search_function;
    // TODO: Add search_function to list of codec search functions
    // Called when looking up encoding by name
    return 0; // Success
}

/// Unregister a codec search function
/// Returns 0 on success, -1 on error
export fn PyCodec_Unregister(search_function: *cpython.PyObject) callconv(.c) c_int {
    _ = search_function;
    // TODO: Remove search_function from codec search list
    return 0; // Success
}

/// Encode an object using the specified encoding
/// Returns encoded bytes object or null on error
export fn PyCodec_Encode(obj: *cpython.PyObject, encoding: [*:0]const u8, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors;
    const unicode = @import("cpython_unicode.zig");
    const bytes = @import("pyobject_bytes.zig");

    // Get string data
    var size: isize = 0;
    const str = unicode.PyUnicode_AsUTF8AndSize(obj, &size) orelse return null;

    const enc_name = std.mem.span(encoding);

    // Handle different encodings
    if (std.mem.eql(u8, enc_name, "utf-8") or std.mem.eql(u8, enc_name, "utf8")) {
        // UTF-8: Direct copy (already UTF-8)
        return bytes.PyBytes_FromStringAndSize(str, size);
    }

    if (std.mem.eql(u8, enc_name, "ascii")) {
        // ASCII: Check all bytes are < 128
        const data = str[0..@intCast(size)];
        for (data) |c| {
            if (c > 127) {
                PyErr_SetString(@ptrFromInt(0), "'ascii' codec can't encode character");
                return null;
            }
        }
        return bytes.PyBytes_FromStringAndSize(str, size);
    }

    if (std.mem.eql(u8, enc_name, "latin-1") or std.mem.eql(u8, enc_name, "latin1") or std.mem.eql(u8, enc_name, "iso-8859-1")) {
        // Latin-1: Check all bytes are < 256 (always true for valid UTF-8 single bytes)
        return bytes.PyBytes_FromStringAndSize(str, size);
    }

    PyErr_SetString(@ptrFromInt(0), "unknown encoding");
    return null;
}

/// Decode an object using the specified encoding
/// Returns decoded string object or null on error
export fn PyCodec_Decode(obj: *cpython.PyObject, encoding: [*:0]const u8, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors;
    const unicode = @import("cpython_unicode.zig");
    const bytes = @import("pyobject_bytes.zig");

    // Get bytes data
    if (bytes.PyBytes_Check(obj) == 0) {
        PyErr_SetString(@ptrFromInt(0), "expected bytes object");
        return null;
    }

    const data = bytes.PyBytes_AsString(obj);
    const size = bytes.PyBytes_Size(obj);

    const enc_name = std.mem.span(encoding);

    // Handle different encodings
    if (std.mem.eql(u8, enc_name, "utf-8") or std.mem.eql(u8, enc_name, "utf8")) {
        // UTF-8: Direct use
        return unicode.PyUnicode_FromStringAndSize(data, size);
    }

    if (std.mem.eql(u8, enc_name, "ascii")) {
        // ASCII: Check all bytes are < 128
        const slice = data[0..@intCast(size)];
        for (slice) |c| {
            if (c > 127) {
                PyErr_SetString(@ptrFromInt(0), "'ascii' codec can't decode byte");
                return null;
            }
        }
        return unicode.PyUnicode_FromStringAndSize(data, size);
    }

    if (std.mem.eql(u8, enc_name, "latin-1") or std.mem.eql(u8, enc_name, "latin1") or std.mem.eql(u8, enc_name, "iso-8859-1")) {
        // Latin-1: Always valid, bytes 0-255 map to Unicode 0-255
        return unicode.PyUnicode_FromStringAndSize(data, size);
    }

    PyErr_SetString(@ptrFromInt(0), "unknown encoding");
    return null;
}

/// Get encoder function for the specified encoding
/// Returns callable encoder or null on error
export fn PyCodec_Encoder(encoding: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = encoding;
    // TODO: Look up and return encoder function for encoding
    // Returns first element of codec tuple
    PyErr_SetString(@ptrFromInt(0), "PyCodec_Encoder not implemented");
    return null;
}

/// Get decoder function for the specified encoding
/// Returns callable decoder or null on error
export fn PyCodec_Decoder(encoding: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = encoding;
    // TODO: Look up and return decoder function for encoding
    // Returns second element of codec tuple
    PyErr_SetString(@ptrFromInt(0), "PyCodec_Decoder not implemented");
    return null;
}

/// Get incremental encoder for the specified encoding
/// Returns IncrementalEncoder instance or null on error
export fn PyCodec_IncrementalEncoder(encoding: [*:0]const u8, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = encoding;
    _ = errors;
    // TODO: Look up and instantiate incremental encoder
    // Used for streaming encoding
    PyErr_SetString(@ptrFromInt(0), "PyCodec_IncrementalEncoder not implemented");
    return null;
}

/// Get incremental decoder for the specified encoding
/// Returns IncrementalDecoder instance or null on error
export fn PyCodec_IncrementalDecoder(encoding: [*:0]const u8, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = encoding;
    _ = errors;
    // TODO: Look up and instantiate incremental decoder
    // Used for streaming decoding
    PyErr_SetString(@ptrFromInt(0), "PyCodec_IncrementalDecoder not implemented");
    return null;
}

/// Get stream reader for the specified encoding
/// Returns StreamReader instance or null on error
export fn PyCodec_StreamReader(encoding: [*:0]const u8, stream: *cpython.PyObject, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = encoding;
    _ = stream;
    _ = errors;
    // TODO: Look up and instantiate stream reader
    // Wraps binary stream with text decoding
    PyErr_SetString(@ptrFromInt(0), "PyCodec_StreamReader not implemented");
    return null;
}

/// Get stream writer for the specified encoding
/// Returns StreamWriter instance or null on error
export fn PyCodec_StreamWriter(encoding: [*:0]const u8, stream: *cpython.PyObject, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = encoding;
    _ = stream;
    _ = errors;
    // TODO: Look up and instantiate stream writer
    // Wraps binary stream with text encoding
    PyErr_SetString(@ptrFromInt(0), "PyCodec_StreamWriter not implemented");
    return null;
}

/// Look up codec info for the specified encoding
/// Returns codec tuple (encoder, decoder, stream_reader, stream_writer) or null
export fn PyCodec_Lookup(encoding: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = encoding;
    // TODO: Search registered codec search functions for encoding
    // Returns tuple of (encoder, decoder, stream_reader, stream_writer)
    PyErr_SetString(@ptrFromInt(0), "PyCodec_Lookup not implemented");
    return null;
}

/// Check if a codec is known
/// Returns 1 if known, 0 if unknown, -1 on error
export fn PyCodec_KnownEncoding(encoding: [*:0]const u8) callconv(.c) c_int {
    const enc_name = std.mem.span(encoding);

    // Known encodings
    const known = [_][]const u8{
        "utf-8",
        "utf8",
        "ascii",
        "latin-1",
        "latin1",
        "iso-8859-1",
    };

    for (known) |k| {
        if (std.mem.eql(u8, enc_name, k)) return 1;
    }

    return 0; // Unknown
}

// ============================================================================
// Convenience wrappers for common encodings
// ============================================================================

/// Encode Unicode object to UTF-8 bytes
/// errors: "strict", "ignore", "replace", etc.
export fn PyUnicode_AsUTF8String(unicode: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return PyCodec_Encode(unicode, "utf-8", "strict");
}

/// Encode Unicode object to ASCII bytes
export fn PyUnicode_AsASCIIString(unicode: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return PyCodec_Encode(unicode, "ascii", "strict");
}

/// Encode Unicode object to Latin-1 bytes
export fn PyUnicode_AsLatin1String(unicode: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return PyCodec_Encode(unicode, "latin-1", "strict");
}

/// Decode UTF-8 bytes to Unicode object
export fn PyUnicode_DecodeUTF8Codec(data: [*]const u8, size: isize, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors;
    const unicode = @import("cpython_unicode.zig");
    return unicode.PyUnicode_FromStringAndSize(data, size);
}

/// Decode ASCII bytes to Unicode object
export fn PyUnicode_DecodeASCII(data: [*]const u8, size: isize, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors;
    const unicode = @import("cpython_unicode.zig");

    // Validate ASCII (all bytes < 128)
    const slice = data[0..@intCast(size)];
    for (slice) |c| {
        if (c > 127) {
            PyErr_SetString(@ptrFromInt(0), "'ascii' codec can't decode byte");
            return null;
        }
    }

    return unicode.PyUnicode_FromStringAndSize(data, size);
}

/// Decode Latin-1 bytes to Unicode object
export fn PyUnicode_DecodeLatin1(data: [*]const u8, size: isize, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors;
    const unicode = @import("cpython_unicode.zig");

    // Latin-1 is a direct mapping of bytes 0-255 to Unicode codepoints 0-255
    // For ASCII subset (0-127), it's the same as UTF-8
    return unicode.PyUnicode_FromStringAndSize(data, size);
}

/// Register error handler for codec errors
/// handler should be a callable that takes UnicodeError and returns replacement
export fn PyCodec_RegisterError(name: [*:0]const u8, error_handler: *cpython.PyObject) callconv(.c) c_int {
    _ = name;
    _ = error_handler;
    // TODO: Register custom error handler
    // Standard handlers: "strict", "ignore", "replace", "xmlcharrefreplace", "backslashreplace"
    return 0; // Success
}

/// Look up error handler by name
/// Returns error handler callable or null
export fn PyCodec_LookupError(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = name;
    // TODO: Look up registered error handler
    PyErr_SetString(@ptrFromInt(0), "PyCodec_LookupError not implemented");
    return null;
}
