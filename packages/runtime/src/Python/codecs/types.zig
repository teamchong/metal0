/// codecs/types - Codec Type Definitions
/// Core types for codec system

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
// Function Signatures
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

// ============================================================================
// Codec Info
// ============================================================================

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

/// Codec search function type
pub const CodecSearchFn = *const fn (encoding: []const u8) ?*const CodecInfo;

// ============================================================================
// Error Handler Types
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
