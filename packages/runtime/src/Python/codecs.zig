/// codecs - Codec Registry and Encoding/Decoding Support
/// Mirrors cpython/Python/codecs.c
///
/// This module provides:
/// - Codec registry (search path and cache)
/// - Encoding/decoding functions
/// - Error handlers (strict, ignore, replace, etc.)
/// - Codec lookup and normalization
///
/// Architecture:
/// - codecs/types.zig - Type definitions
/// - codecs/registry.zig - Codec registration and lookup
/// - codecs/normalization.zig - Encoding name normalization
/// - codecs/error_handlers.zig - Error handler system
/// - codecs/encodings.zig - Known encodings and aliases
/// - codecs/stream_api.zig - Stateful codec API
/// - codecs/backslash.zig - Backslash encoding utilities

const std = @import("std");

// Import submodules
const types = @import("codecs/types.zig");
const registry = @import("codecs/registry.zig");
const normalization = @import("codecs/normalization.zig");
const error_handlers = @import("codecs/error_handlers.zig");
const encodings = @import("codecs/encodings.zig");
const stream_api = @import("codecs/stream_api.zig");
const backslash = @import("codecs/backslash.zig");

// ============================================================================
// Re-export Types
// ============================================================================

pub const hexdigits = types.hexdigits;
pub const builtin_error_handlers = types.builtin_error_handlers;
pub const EncodeFn = types.EncodeFn;
pub const DecodeFn = types.DecodeFn;
pub const StreamReader = types.StreamReader;
pub const StreamWriter = types.StreamWriter;
pub const IncrementalEncoder = types.IncrementalEncoder;
pub const IncrementalDecoder = types.IncrementalDecoder;
pub const CodecInfo = types.CodecInfo;
pub const CodecSearchFn = types.CodecSearchFn;
pub const ErrorHandlerResult = types.ErrorHandlerResult;
pub const ErrorHandlerFn = types.ErrorHandlerFn;

// ============================================================================
// Re-export Registry API
// ============================================================================

pub const CodecRegistry = registry.CodecRegistry;
pub const register = registry.register;
pub const unregister = registry.unregister;
pub const lookup = registry.lookup;

// ============================================================================
// Re-export Normalization
// ============================================================================

pub const normalizeEncoding = normalization.normalizeEncoding;
pub const isValidEncodingName = normalization.isValidEncodingName;

// ============================================================================
// Re-export Error Handlers
// ============================================================================

pub const registerError = error_handlers.registerError;
pub const lookupError = error_handlers.lookupError;
pub const strictErrors = error_handlers.strictErrors;
pub const ignoreErrors = error_handlers.ignoreErrors;
pub const replaceErrors = error_handlers.replaceErrors;
pub const xmlcharrefreplaceErrors = error_handlers.xmlcharrefreplaceErrors;
pub const backslashreplaceErrors = error_handlers.backslashreplaceErrors;

// ============================================================================
// Re-export Known Encodings
// ============================================================================

pub const isKnownTextEncoding = encodings.isKnownTextEncoding;
pub const getCanonicalName = encodings.getCanonicalName;

// ============================================================================
// Re-export Stream API
// ============================================================================

pub const getIncrementalEncoder = stream_api.getIncrementalEncoder;
pub const getIncrementalDecoder = stream_api.getIncrementalDecoder;
pub const getStreamReader = stream_api.getStreamReader;
pub const getStreamWriter = stream_api.getStreamWriter;

// ============================================================================
// Re-export Backslash Encoding
// ============================================================================

pub const backslashEncode = backslash.backslashEncode;

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
// Initialization
// ============================================================================

/// Initialize the codec subsystem
pub fn init() void {
    registry.init();
    error_handlers.init();
}

/// Finalize the codec subsystem
pub fn fini() void {
    registry.fini();
}
