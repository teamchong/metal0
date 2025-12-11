/// codecs/stream_api - Stateful Codec API
/// Provides incremental encoders/decoders and stream readers/writers

const std = @import("std");
const types = @import("types.zig");
const registry = @import("registry.zig");

const IncrementalEncoder = types.IncrementalEncoder;
const IncrementalDecoder = types.IncrementalDecoder;
const StreamReader = types.StreamReader;
const StreamWriter = types.StreamWriter;

// ============================================================================
// Stateful Codec API
// ============================================================================

/// Get an incremental encoder
/// Mirrors: PyCodec_IncrementalEncoder
pub fn getIncrementalEncoder(encoding: []const u8, errors: []const u8) !IncrementalEncoder {
    _ = errors;
    const codec = try registry.lookup(encoding);
    if (codec.incrementalencoder) |enc| {
        return enc;
    }
    return error.IncrementalEncoderNotAvailable;
}

/// Get an incremental decoder
/// Mirrors: PyCodec_IncrementalDecoder
pub fn getIncrementalDecoder(encoding: []const u8, errors: []const u8) !IncrementalDecoder {
    _ = errors;
    const codec = try registry.lookup(encoding);
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
    const codec = try registry.lookup(encoding);
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
    const codec = try registry.lookup(encoding);
    if (codec.streamwriter) |writer| {
        return writer;
    }
    return error.StreamWriterNotAvailable;
}
