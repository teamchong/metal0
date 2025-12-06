/// codecs - Codec Registry and Encoding/Decoding Support
/// Mirrors cpython/Python/codecs.c
///
/// This module provides:
/// - Codec registry (search path and cache)
/// - Encoding/decoding functions
/// - Error handlers (strict, ignore, replace, etc.)
/// - Codec lookup and normalization

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Hex digit characters for escape sequences
pub const hexdigits = "0123456789abcdef";

/// Built-in error handler names
pub const builtin_error_handlers = [_][]const u8{
    "strict",
    "ignore",
    "replace",
    "xmlcharrefreplace",
    "backslashreplace",
    "namereplace",
    "surrogatepass",
    "surrogateescape",
};

// ============================================================================
// Codec Info
// ============================================================================

/// Encode function signature
pub const EncodeFn = *const fn (input: []const u8, errors: []const u8) anyerror![]const u8;

/// Decode function signature
pub const DecodeFn = *const fn (input: []const u8, errors: []const u8) anyerror![]const u8;

/// Stream reader/writer types (opaque for now)
pub const StreamReader = *anyopaque;
pub const StreamWriter = *anyopaque;

/// Incremental encoder/decoder types
pub const IncrementalEncoder = *anyopaque;
pub const IncrementalDecoder = *anyopaque;

/// Codec information tuple
/// Mirrors: PyCodec codec tuple (encode, decode, streamreader, streamwriter)
pub const CodecInfo = struct {
    name: []const u8,
    encode: ?EncodeFn = null,
    decode: ?DecodeFn = null,
    incrementalencoder: ?IncrementalEncoder = null,
    incrementaldecoder: ?IncrementalDecoder = null,
    streamreader: ?StreamReader = null,
    streamwriter: ?StreamWriter = null,
};

// ============================================================================
// Codec Search Function
// ============================================================================

/// Codec search function type
pub const CodecSearchFn = *const fn (encoding: []const u8) ?*const CodecInfo;

// ============================================================================
// Codec Registry State
// ============================================================================

/// Maximum number of search functions
const MAX_SEARCH_FUNCTIONS = 32;

/// Maximum cache entries
const MAX_CACHE_ENTRIES = 256;

/// Codec registry state
pub const CodecRegistry = struct {
    /// Search functions (in order of registration)
    search_path: [MAX_SEARCH_FUNCTIONS]?CodecSearchFn = [_]?CodecSearchFn{null} ** MAX_SEARCH_FUNCTIONS,
    search_path_len: usize = 0,

    /// Codec cache (normalized encoding -> codec info)
    cache_keys: [MAX_CACHE_ENTRIES][]const u8 = undefined,
    cache_values: [MAX_CACHE_ENTRIES]?*const CodecInfo = [_]?*const CodecInfo{null} ** MAX_CACHE_ENTRIES,
    cache_len: usize = 0,

    /// Mutex for thread safety
    mutex: std.Thread.Mutex = .{},

    /// Whether the registry is initialized
    initialized: bool = false,

    /// Initialize the registry
    pub fn init(self: *CodecRegistry) void {
        self.search_path_len = 0;
        self.cache_len = 0;
        self.initialized = true;
    }

    /// Register a codec search function
    pub fn register(self: *CodecRegistry, search_fn: CodecSearchFn) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.search_path_len >= MAX_SEARCH_FUNCTIONS) {
            return error.TooManySearchFunctions;
        }

        self.search_path[self.search_path_len] = search_fn;
        self.search_path_len += 1;
    }

    /// Unregister a codec search function
    pub fn unregister(self: *CodecRegistry, search_fn: CodecSearchFn) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.search_path_len) {
            if (self.search_path[i] == search_fn) {
                // Shift remaining entries
                var j = i;
                while (j + 1 < self.search_path_len) : (j += 1) {
                    self.search_path[j] = self.search_path[j + 1];
                }
                self.search_path_len -= 1;
                // Clear cache
                self.clearCache();
                return;
            }
            i += 1;
        }
    }

    /// Clear the codec cache
    pub fn clearCache(self: *CodecRegistry) void {
        self.cache_len = 0;
    }

    /// Lookup codec in cache
    fn lookupCache(self: *CodecRegistry, normalized: []const u8) ?*const CodecInfo {
        for (0..self.cache_len) |i| {
            if (std.mem.eql(u8, self.cache_keys[i], normalized)) {
                return self.cache_values[i];
            }
        }
        return null;
    }

    /// Add codec to cache
    fn addToCache(self: *CodecRegistry, normalized: []const u8, codec: *const CodecInfo) void {
        if (self.cache_len >= MAX_CACHE_ENTRIES) {
            // Simple eviction: clear entire cache
            self.clearCache();
        }
        self.cache_keys[self.cache_len] = normalized;
        self.cache_values[self.cache_len] = codec;
        self.cache_len += 1;
    }

    /// Lookup a codec by encoding name
    pub fn lookup(self: *CodecRegistry, encoding: []const u8) !*const CodecInfo {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Normalize encoding name
        var normalized_buf: [256]u8 = undefined;
        const normalized = normalizeEncoding(&normalized_buf, encoding);

        // Check cache first
        if (self.lookupCache(normalized)) |codec| {
            return codec;
        }

        // Search through registered functions
        if (self.search_path_len == 0) {
            return error.NoCodecSearchFunctions;
        }

        for (0..self.search_path_len) |i| {
            if (self.search_path[i]) |search_fn| {
                if (search_fn(normalized)) |codec| {
                    self.addToCache(normalized, codec);
                    return codec;
                }
            }
        }

        return error.UnknownEncoding;
    }
};

/// Global codec registry
var global_registry: CodecRegistry = .{};

// ============================================================================
// Encoding Name Normalization
// ============================================================================

/// Normalize an encoding name:
/// - Convert to lowercase
/// - Replace spaces and underscores with hyphens
/// Mirrors: normalizestring() in codecs.c
pub fn normalizeEncoding(buf: []u8, encoding: []const u8) []const u8 {
    const len = @min(encoding.len, buf.len - 1);
    for (0..len) |i| {
        var ch = encoding[i];
        if (ch == ' ' or ch == '_') {
            ch = '-';
        } else if (ch >= 'A' and ch <= 'Z') {
            ch = ch - 'A' + 'a';
        }
        buf[i] = ch;
    }
    return buf[0..len];
}

/// Check if encoding name is valid ASCII
pub fn isValidEncodingName(encoding: []const u8) bool {
    for (encoding) |ch| {
        if (ch > 127) return false;
    }
    return encoding.len > 0;
}

// ============================================================================
// Public API - Registration
// ============================================================================

/// Register a codec search function
/// Mirrors: PyCodec_Register
pub fn register(search_fn: CodecSearchFn) !void {
    return global_registry.register(search_fn);
}

/// Unregister a codec search function
/// Mirrors: PyCodec_Unregister
pub fn unregister(search_fn: CodecSearchFn) void {
    global_registry.unregister(search_fn);
}

/// Lookup a codec by name
/// Mirrors: _PyCodec_Lookup, PyCodec_Lookup
pub fn lookup(encoding: []const u8) !*const CodecInfo {
    if (!global_registry.initialized) {
        global_registry.init();
    }
    return global_registry.lookup(encoding);
}

// ============================================================================
// Public API - Encoding/Decoding
// ============================================================================

/// Encode a string using the named codec
/// Mirrors: PyCodec_Encode
pub fn encode(object: []const u8, encoding: []const u8, errors: []const u8) ![]const u8 {
    const codec = try lookup(encoding);
    if (codec.encode) |encode_fn| {
        return encode_fn(object, errors);
    }
    return error.EncoderNotAvailable;
}

/// Decode a string using the named codec
/// Mirrors: PyCodec_Decode
pub fn decode(object: []const u8, encoding: []const u8, errors: []const u8) ![]const u8 {
    const codec = try lookup(encoding);
    if (codec.decode) |decode_fn| {
        return decode_fn(object, errors);
    }
    return error.DecoderNotAvailable;
}

// ============================================================================
// Error Handlers
// ============================================================================

/// Error handler result
pub const ErrorHandlerResult = struct {
    replacement: []const u8,
    new_position: usize,
};

/// Error handler function type
pub const ErrorHandlerFn = *const fn (
    exc_type: []const u8,
    exc_object: []const u8,
    start: usize,
    end: usize,
    reason: []const u8,
) anyerror!ErrorHandlerResult;

/// Registered error handlers
const MAX_ERROR_HANDLERS = 32;

var error_handlers: [MAX_ERROR_HANDLERS]struct {
    name: []const u8,
    handler: ?ErrorHandlerFn,
} = undefined;
var error_handlers_len: usize = 0;

/// Initialize with built-in error handlers
fn initBuiltinErrorHandlers() void {
    // These will be populated with actual implementations
    error_handlers_len = 0;
}

/// Register an error handler
/// Mirrors: PyCodec_RegisterError
pub fn registerError(name: []const u8, handler: ErrorHandlerFn) !void {
    if (error_handlers_len >= MAX_ERROR_HANDLERS) {
        return error.TooManyErrorHandlers;
    }
    error_handlers[error_handlers_len] = .{
        .name = name,
        .handler = handler,
    };
    error_handlers_len += 1;
}

/// Lookup an error handler
/// Mirrors: PyCodec_LookupError
pub fn lookupError(name: []const u8) !ErrorHandlerFn {
    for (0..error_handlers_len) |i| {
        if (std.mem.eql(u8, error_handlers[i].name, name)) {
            if (error_handlers[i].handler) |handler| {
                return handler;
            }
        }
    }
    return error.UnknownErrorHandler;
}

// ============================================================================
// Built-in Error Handlers
// ============================================================================

/// Strict error handler - raises exception
pub fn strictErrors(
    exc_type: []const u8,
    exc_object: []const u8,
    start: usize,
    end: usize,
    reason: []const u8,
) anyerror!ErrorHandlerResult {
    _ = exc_type;
    _ = exc_object;
    _ = start;
    _ = end;
    _ = reason;
    return error.UnicodeError;
}

/// Ignore error handler - skips bad characters
pub fn ignoreErrors(
    _: []const u8,
    _: []const u8,
    _: usize,
    end: usize,
    _: []const u8,
) anyerror!ErrorHandlerResult {
    return .{
        .replacement = "",
        .new_position = end,
    };
}

/// Replace error handler - inserts replacement character
pub fn replaceErrors(
    _: []const u8,
    _: []const u8,
    _: usize,
    end: usize,
    _: []const u8,
) anyerror!ErrorHandlerResult {
    return .{
        .replacement = "\xef\xbf\xbd", // U+FFFD in UTF-8
        .new_position = end,
    };
}

/// XML character reference replacement
pub fn xmlcharrefreplaceErrors(
    _: []const u8,
    _: []const u8,
    _: usize,
    end: usize,
    _: []const u8,
) anyerror!ErrorHandlerResult {
    // Would generate &#NNNN; references
    return .{
        .replacement = "?",
        .new_position = end,
    };
}

/// Backslash escape replacement
pub fn backslashreplaceErrors(
    _: []const u8,
    _: []const u8,
    _: usize,
    end: usize,
    _: []const u8,
) anyerror!ErrorHandlerResult {
    // Would generate \xNN or \uNNNN escapes
    return .{
        .replacement = "?",
        .new_position = end,
    };
}

// ============================================================================
// Known Encodings
// ============================================================================

/// Check if an encoding is a known text encoding
pub fn isKnownTextEncoding(encoding: []const u8) bool {
    var buf: [256]u8 = undefined;
    const normalized = normalizeEncoding(&buf, encoding);

    const known = [_][]const u8{
        "utf-8",
        "utf-16",
        "utf-16-le",
        "utf-16-be",
        "utf-32",
        "utf-32-le",
        "utf-32-be",
        "ascii",
        "latin-1",
        "iso-8859-1",
        "cp1252",
        "utf-7",
    };

    for (known) |enc| {
        if (std.mem.eql(u8, normalized, enc)) {
            return true;
        }
    }
    return false;
}

/// Get the canonical name for an encoding alias
pub fn getCanonicalName(encoding: []const u8) []const u8 {
    var buf: [256]u8 = undefined;
    const normalized = normalizeEncoding(&buf, encoding);

    // Common aliases
    if (std.mem.eql(u8, normalized, "utf8") or
        std.mem.eql(u8, normalized, "utf-8"))
    {
        return "utf-8";
    }

    if (std.mem.eql(u8, normalized, "latin1") or
        std.mem.eql(u8, normalized, "latin-1") or
        std.mem.eql(u8, normalized, "iso-8859-1") or
        std.mem.eql(u8, normalized, "iso8859-1"))
    {
        return "iso-8859-1";
    }

    if (std.mem.eql(u8, normalized, "ascii") or
        std.mem.eql(u8, normalized, "us-ascii"))
    {
        return "ascii";
    }

    return encoding;
}

// ============================================================================
// Stateful Codec API
// ============================================================================

/// Get an incremental encoder
/// Mirrors: PyCodec_IncrementalEncoder
pub fn getIncrementalEncoder(encoding: []const u8, errors: []const u8) !IncrementalEncoder {
    _ = errors;
    const codec = try lookup(encoding);
    if (codec.incrementalencoder) |enc| {
        return enc;
    }
    return error.IncrementalEncoderNotAvailable;
}

/// Get an incremental decoder
/// Mirrors: PyCodec_IncrementalDecoder
pub fn getIncrementalDecoder(encoding: []const u8, errors: []const u8) !IncrementalDecoder {
    _ = errors;
    const codec = try lookup(encoding);
    if (codec.incrementaldecoder) |dec| {
        return dec;
    }
    return error.IncrementalDecoderNotAvailable;
}

/// Get a stream reader
/// Mirrors: PyCodec_StreamReader
pub fn getStreamReader(encoding: []const u8, stream: anytype, errors: []const u8) !StreamReader {
    _ = stream;
    _ = errors;
    const codec = try lookup(encoding);
    if (codec.streamreader) |reader| {
        return reader;
    }
    return error.StreamReaderNotAvailable;
}

/// Get a stream writer
/// Mirrors: PyCodec_StreamWriter
pub fn getStreamWriter(encoding: []const u8, stream: anytype, errors: []const u8) !StreamWriter {
    _ = stream;
    _ = errors;
    const codec = try lookup(encoding);
    if (codec.streamwriter) |writer| {
        return writer;
    }
    return error.StreamWriterNotAvailable;
}

// ============================================================================
// Backslash Encoding (for repr)
// ============================================================================

/// Encode string with backslash escapes
pub fn backslashEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (input) |ch| {
        switch (ch) {
            '\\' => try result.appendSlice("\\\\"),
            '\n' => try result.appendSlice("\\n"),
            '\r' => try result.appendSlice("\\r"),
            '\t' => try result.appendSlice("\\t"),
            else => {
                if (ch < 32 or ch >= 127) {
                    try result.appendSlice("\\x");
                    try result.append(hexdigits[ch >> 4]);
                    try result.append(hexdigits[ch & 0xf]);
                } else {
                    try result.append(ch);
                }
            },
        }
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the codec subsystem
pub fn init() void {
    global_registry.init();
    initBuiltinErrorHandlers();
}

/// Finalize the codec subsystem
pub fn fini() void {
    global_registry.clearCache();
}

// ============================================================================
// Tests
// ============================================================================

test "normalize encoding" {
    var buf: [256]u8 = undefined;

    const n1 = normalizeEncoding(&buf, "UTF-8");
    try std.testing.expectEqualStrings("utf-8", n1);

    const n2 = normalizeEncoding(&buf, "ISO_8859_1");
    try std.testing.expectEqualStrings("iso-8859-1", n2);

    const n3 = normalizeEncoding(&buf, "US ASCII");
    try std.testing.expectEqualStrings("us-ascii", n3);
}

test "known encodings" {
    try std.testing.expect(isKnownTextEncoding("utf-8"));
    try std.testing.expect(isKnownTextEncoding("UTF-8"));
    try std.testing.expect(isKnownTextEncoding("ascii"));
    try std.testing.expect(!isKnownTextEncoding("unknown-encoding"));
}

test "canonical names" {
    try std.testing.expectEqualStrings("utf-8", getCanonicalName("utf8"));
    try std.testing.expectEqualStrings("utf-8", getCanonicalName("UTF-8"));
    try std.testing.expectEqualStrings("iso-8859-1", getCanonicalName("latin1"));
    try std.testing.expectEqualStrings("ascii", getCanonicalName("us-ascii"));
}

test "backslash encode" {
    const allocator = std.testing.allocator;

    const result = try backslashEncode(allocator, "hello\nworld");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello\\nworld", result);

    const result2 = try backslashEncode(allocator, "tab\there");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("tab\\there", result2);
}

test "error handlers" {
    const result = try ignoreErrors("", "", 0, 5, "");
    try std.testing.expectEqualStrings("", result.replacement);
    try std.testing.expectEqual(@as(usize, 5), result.new_position);
}
