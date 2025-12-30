//! File format parsing module.
//!
//! This module handles parsing columnar file formats:
//! - Lance: 40-byte footer, protobuf metadata
//! - Parquet: Thrift metadata, various encodings/compressions

const std = @import("std");

// Lance format
pub const footer = @import("footer.zig");
pub const version = @import("version.zig");
pub const lance_file = @import("lance_file.zig");

// Parquet format
pub const parquet_metadata = @import("parquet_metadata.zig");
pub const parquet_file = @import("parquet_file.zig");

// Re-export Lance types
pub const Footer = footer.Footer;
pub const Version = version.Version;
pub const LANCE_MAGIC = footer.LANCE_MAGIC;
pub const FOOTER_SIZE = footer.FOOTER_SIZE;
pub const LanceFile = lance_file.LanceFile;
pub const readFile = lance_file.readFile;

// Re-export Parquet types
pub const ParquetFile = parquet_file.ParquetFile;
pub const ParquetError = parquet_file.ParquetError;
pub const ParquetType = parquet_metadata.Type;
pub const ParquetEncoding = parquet_metadata.Encoding;
pub const CompressionCodec = parquet_metadata.CompressionCodec;
pub const FileMetaData = parquet_metadata.FileMetaData;
pub const RowGroup = parquet_metadata.RowGroup;
pub const ColumnChunk = parquet_metadata.ColumnChunk;
pub const SchemaElement = parquet_metadata.SchemaElement;
pub const PageHeader = parquet_metadata.PageHeader;

test {
    std.testing.refAllDecls(@This());
}
