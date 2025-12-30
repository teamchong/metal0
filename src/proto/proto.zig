//! Protocol decoding for Lance and Parquet metadata.
//!
//! This module provides wire format decoders:
//! - Protobuf: For Lance file metadata
//! - Thrift TCompactProtocol: For Parquet file metadata
//!
//! Both are read-only since LanceQL only reads files.

const std = @import("std");

pub const decoder = @import("decoder.zig");
pub const lance_messages = @import("lance_messages.zig");
pub const schema = @import("schema.zig");
pub const thrift = @import("thrift.zig");

// Re-export Protobuf types
pub const ProtoDecoder = decoder.ProtoDecoder;
pub const WireType = decoder.WireType;
pub const DecodeError = decoder.DecodeError;

pub const ColumnMetadata = lance_messages.ColumnMetadata;
pub const Page = lance_messages.Page;
pub const Encoding = lance_messages.Encoding;

pub const Schema = schema.Schema;
pub const Field = schema.Field;
pub const FieldType = schema.FieldType;

// Re-export Thrift types
pub const ThriftDecoder = thrift.ThriftDecoder;
pub const CompactType = thrift.CompactType;
pub const ThriftError = thrift.ThriftError;

test {
    std.testing.refAllDecls(@This());
}
