//! Parquet file metadata structures.
//!
//! Defines the structures for Parquet file metadata, based on the
//! Apache Parquet Thrift specification.
//! See: https://github.com/apache/parquet-format/blob/master/src/main/thrift/parquet.thrift

const std = @import("std");
const proto = @import("lanceql.proto");
const ThriftDecoder = proto.ThriftDecoder;
const CompactType = proto.CompactType;
const ThriftError = proto.ThriftError;

/// Parquet physical types
pub const Type = enum(i32) {
    boolean = 0,
    int32 = 1,
    int64 = 2,
    int96 = 3, // Deprecated, use int64 with timestamp logical type
    float = 4,
    double = 5,
    byte_array = 6,
    fixed_len_byte_array = 7,
    _,

    pub fn fromI32(val: i32) Type {
        return @enumFromInt(val);
    }
};

/// Converted/logical types (deprecated in favor of LogicalType)
pub const ConvertedType = enum(i32) {
    utf8 = 0,
    map = 1,
    map_key_value = 2,
    list = 3,
    @"enum" = 4,
    decimal = 5,
    date = 6,
    time_millis = 7,
    time_micros = 8,
    timestamp_millis = 9,
    timestamp_micros = 10,
    uint_8 = 11,
    uint_16 = 12,
    uint_32 = 13,
    uint_64 = 14,
    int_8 = 15,
    int_16 = 16,
    int_32 = 17,
    int_64 = 18,
    json = 19,
    bson = 20,
    interval = 21,
    _,

    pub fn fromI32(val: i32) ConvertedType {
        return @enumFromInt(val);
    }
};

/// Field repetition types
pub const FieldRepetitionType = enum(i32) {
    required = 0,
    optional = 1,
    repeated = 2,
    _,

    pub fn fromI32(val: i32) FieldRepetitionType {
        return @enumFromInt(val);
    }
};

/// Encoding types
pub const Encoding = enum(i32) {
    plain = 0,
    plain_dictionary = 2, // Deprecated, use rle_dictionary
    rle = 3,
    bit_packed = 4, // Deprecated
    delta_binary_packed = 5,
    delta_length_byte_array = 6,
    delta_byte_array = 7,
    rle_dictionary = 8,
    byte_stream_split = 9,
    _,

    pub fn fromI32(val: i32) Encoding {
        return @enumFromInt(val);
    }
};

/// Compression codecs
pub const CompressionCodec = enum(i32) {
    uncompressed = 0,
    snappy = 1,
    gzip = 2,
    lzo = 3,
    brotli = 4,
    lz4 = 5,
    zstd = 6,
    lz4_raw = 7,
    _,

    pub fn fromI32(val: i32) CompressionCodec {
        return @enumFromInt(val);
    }
};

/// Page types
pub const PageType = enum(i32) {
    data_page = 0,
    index_page = 1,
    dictionary_page = 2,
    data_page_v2 = 3,
    _,

    pub fn fromI32(val: i32) PageType {
        return @enumFromInt(val);
    }
};

/// Schema element (column definition)
pub const SchemaElement = struct {
    /// Physical type (null for groups)
    type_: ?Type = null,
    /// Length for FIXED_LEN_BYTE_ARRAY
    type_length: ?i32 = null,
    /// Repetition type
    repetition_type: ?FieldRepetitionType = null,
    /// Column name
    name: []const u8 = "",
    /// Number of children (for groups)
    num_children: ?i32 = null,
    /// Converted type (deprecated)
    converted_type: ?ConvertedType = null,
    /// Scale for DECIMAL
    scale: ?i32 = null,
    /// Precision for DECIMAL
    precision: ?i32 = null,
    /// Field ID
    field_id: ?i32 = null,

    pub fn decode(decoder: *ThriftDecoder, allocator: std.mem.Allocator) !SchemaElement {
        _ = allocator;
        var elem = SchemaElement{};
        decoder.resetFieldId();

        while (try decoder.readFieldHeader()) |field| {
            switch (field.field_id) {
                1 => elem.type_ = Type.fromI32(try decoder.readI32()), // type
                2 => elem.type_length = try decoder.readI32(), // type_length
                3 => elem.repetition_type = FieldRepetitionType.fromI32(try decoder.readI32()), // repetition_type
                4 => elem.name = try decoder.readString(), // name
                5 => elem.num_children = try decoder.readI32(), // num_children
                6 => elem.converted_type = ConvertedType.fromI32(try decoder.readI32()), // converted_type
                7 => elem.scale = try decoder.readI32(), // scale
                8 => elem.precision = try decoder.readI32(), // precision
                9 => elem.field_id = try decoder.readI32(), // field_id
                else => try decoder.skipField(field.field_type),
            }
        }

        return elem;
    }
};

/// Column chunk metadata
pub const ColumnChunk = struct {
    /// File path (if not in same file)
    file_path: ?[]const u8 = null,
    /// Offset of column data in file
    file_offset: i64 = 0,
    /// Column metadata (inline)
    meta_data: ?ColumnMetaData = null,
    /// Offset to start of column crypto metadata
    offset_index_offset: ?i64 = null,
    offset_index_length: ?i32 = null,
    column_index_offset: ?i64 = null,
    column_index_length: ?i32 = null,

    pub fn decode(decoder: *ThriftDecoder, allocator: std.mem.Allocator) !ColumnChunk {
        var chunk = ColumnChunk{};
        decoder.resetFieldId();

        while (try decoder.readFieldHeader()) |field| {
            // Save current field context before processing nested structures
            const current_field_id = decoder.last_field_id;

            switch (field.field_id) {
                1 => chunk.file_path = try decoder.readString(), // file_path
                2 => chunk.file_offset = try decoder.readI64(), // file_offset
                3 => chunk.meta_data = try ColumnMetaData.decode(decoder, allocator), // meta_data
                4 => chunk.offset_index_offset = try decoder.readI64(),
                5 => chunk.offset_index_length = try decoder.readI32(),
                6 => chunk.column_index_offset = try decoder.readI64(),
                7 => chunk.column_index_length = try decoder.readI32(),
                else => try decoder.skipField(field.field_type),
            }

            // Restore field context after nested structures
            decoder.last_field_id = current_field_id;
        }

        return chunk;
    }
};

/// Column metadata
pub const ColumnMetaData = struct {
    /// Physical type
    type_: Type = .boolean,
    /// Encodings used
    encodings: []Encoding = &.{},
    /// Path in schema (list of column names from root)
    path_in_schema: [][]const u8 = &.{},
    /// Compression codec
    codec: CompressionCodec = .uncompressed,
    /// Number of values in this column
    num_values: i64 = 0,
    /// Total uncompressed size of all pages
    total_uncompressed_size: i64 = 0,
    /// Total compressed size of all pages
    total_compressed_size: i64 = 0,
    /// Offset of first data page
    data_page_offset: i64 = 0,
    /// Offset of index page (if any)
    index_page_offset: ?i64 = null,
    /// Offset of dictionary page (if any)
    dictionary_page_offset: ?i64 = null,

    pub fn decode(decoder: *ThriftDecoder, allocator: std.mem.Allocator) !ColumnMetaData {
        var meta = ColumnMetaData{};
        decoder.resetFieldId();

        while (try decoder.readFieldHeader()) |field| {
            switch (field.field_id) {
                1 => meta.type_ = Type.fromI32(try decoder.readI32()), // type
                2 => { // encodings (list)
                    const list_header = try decoder.readListHeader();
                    var encodings = try allocator.alloc(Encoding, list_header.count);
                    for (0..list_header.count) |i| {
                        encodings[i] = Encoding.fromI32(try decoder.readI32());
                    }
                    meta.encodings = encodings;
                },
                3 => { // path_in_schema (list of strings)
                    const list_header = try decoder.readListHeader();
                    var path = try allocator.alloc([]const u8, list_header.count);
                    for (0..list_header.count) |i| {
                        path[i] = try decoder.readString();
                    }
                    meta.path_in_schema = path;
                },
                4 => meta.codec = CompressionCodec.fromI32(try decoder.readI32()), // codec
                5 => meta.num_values = try decoder.readI64(), // num_values
                6 => meta.total_uncompressed_size = try decoder.readI64(), // total_uncompressed_size
                7 => meta.total_compressed_size = try decoder.readI64(), // total_compressed_size
                9 => meta.data_page_offset = try decoder.readI64(), // data_page_offset
                10 => meta.index_page_offset = try decoder.readI64(), // index_page_offset
                11 => meta.dictionary_page_offset = try decoder.readI64(), // dictionary_page_offset
                else => try decoder.skipField(field.field_type),
            }
        }

        return meta;
    }
};

/// Row group metadata
pub const RowGroup = struct {
    /// Column chunks in this row group
    columns: []ColumnChunk = &.{},
    /// Total byte size of all column data
    total_byte_size: i64 = 0,
    /// Number of rows in this row group
    num_rows: i64 = 0,
    /// Sorting columns (optional)
    file_offset: ?i64 = null,
    total_compressed_size: ?i64 = null,
    ordinal: ?i16 = null,

    pub fn decode(decoder: *ThriftDecoder, allocator: std.mem.Allocator) !RowGroup {
        var rg = RowGroup{};
        decoder.resetFieldId();

        while (try decoder.readFieldHeader()) |field| {
            // Save current field context before processing nested structures
            const current_field_id = decoder.last_field_id;

            switch (field.field_id) {
                1 => { // columns (list)
                    const list_header = try decoder.readListHeader();
                    var columns = try allocator.alloc(ColumnChunk, list_header.count);
                    for (0..list_header.count) |i| {
                        columns[i] = try ColumnChunk.decode(decoder, allocator);
                    }
                    rg.columns = columns;
                },
                2 => rg.total_byte_size = try decoder.readI64(), // total_byte_size
                3 => rg.num_rows = try decoder.readI64(), // num_rows
                5 => rg.file_offset = try decoder.readI64(), // file_offset
                6 => rg.total_compressed_size = try decoder.readI64(), // total_compressed_size
                7 => rg.ordinal = try decoder.readI16(), // ordinal
                else => try decoder.skipField(field.field_type),
            }

            // Restore field context after nested structures
            decoder.last_field_id = current_field_id;
        }

        return rg;
    }
};

/// File metadata (top-level)
pub const FileMetaData = struct {
    /// Parquet format version
    version: i32 = 0,
    /// Schema elements
    schema: []SchemaElement = &.{},
    /// Number of rows in file
    num_rows: i64 = 0,
    /// Row groups
    row_groups: []RowGroup = &.{},
    /// Key-value metadata
    key_value_metadata: []KeyValue = &.{},
    /// Application that created the file
    created_by: ?[]const u8 = null,

    pub fn decode(decoder: *ThriftDecoder, allocator: std.mem.Allocator) !FileMetaData {
        var meta = FileMetaData{};
        decoder.resetFieldId();

        while (try decoder.readFieldHeader()) |field| {
            // Save current field context before processing nested structures
            const current_field_id = decoder.last_field_id;

            switch (field.field_id) {
                1 => meta.version = try decoder.readI32(), // version
                2 => { // schema (list)
                    const list_header = try decoder.readListHeader();
                    var schema = try allocator.alloc(SchemaElement, list_header.count);
                    for (0..list_header.count) |i| {
                        schema[i] = try SchemaElement.decode(decoder, allocator);
                    }
                    meta.schema = schema;
                },
                3 => meta.num_rows = try decoder.readI64(), // num_rows
                4 => { // row_groups (list)
                    const list_header = try decoder.readListHeader();
                    var row_groups = try allocator.alloc(RowGroup, list_header.count);
                    for (0..list_header.count) |i| {
                        row_groups[i] = try RowGroup.decode(decoder, allocator);
                    }
                    meta.row_groups = row_groups;
                },
                5 => { // key_value_metadata (list)
                    const list_header = try decoder.readListHeader();
                    var kv = try allocator.alloc(KeyValue, list_header.count);
                    for (0..list_header.count) |i| {
                        kv[i] = try KeyValue.decode(decoder);
                    }
                    meta.key_value_metadata = kv;
                },
                6 => meta.created_by = try decoder.readString(), // created_by
                else => try decoder.skipField(field.field_type),
            }

            // Restore field context after nested structures
            decoder.last_field_id = current_field_id;
        }

        return meta;
    }

    /// Get flat column descriptors (leaf columns only)
    pub fn getColumnDescriptors(self: FileMetaData, allocator: std.mem.Allocator) ![]ColumnDescriptor {
        var descriptors = std.ArrayListUnmanaged(ColumnDescriptor){};
        errdefer descriptors.deinit(allocator);

        var path = std.ArrayListUnmanaged([]const u8){};
        defer path.deinit(allocator);

        var idx: usize = 0;
        try self.buildColumnDescriptors(allocator, &descriptors, &path, &idx);

        return descriptors.toOwnedSlice(allocator);
    }

    fn buildColumnDescriptors(
        self: FileMetaData,
        allocator: std.mem.Allocator,
        descriptors: *std.ArrayListUnmanaged(ColumnDescriptor),
        path: *std.ArrayListUnmanaged([]const u8),
        idx: *usize,
    ) !void {
        if (idx.* >= self.schema.len) return;

        const elem = self.schema[idx.*];
        idx.* += 1;

        if (elem.num_children) |num_children| {
            // Group element - recurse into children
            try path.append(allocator, elem.name);
            for (0..@intCast(num_children)) |_| {
                try self.buildColumnDescriptors(allocator, descriptors, path, idx);
            }
            _ = path.pop();
        } else {
            // Leaf element - this is a column
            try path.append(allocator, elem.name);
            try descriptors.append(allocator, .{
                .path = try path.toOwnedSlice(allocator),
                .type_ = elem.type_ orelse .byte_array,
                .type_length = elem.type_length,
                .repetition_type = elem.repetition_type orelse .required,
                .converted_type = elem.converted_type,
                .scale = elem.scale,
                .precision = elem.precision,
            });
            // Restore path for next sibling
            path.clearRetainingCapacity();
        }
    }
};

/// Key-value metadata pair
pub const KeyValue = struct {
    key: []const u8 = "",
    value: ?[]const u8 = null,

    pub fn decode(decoder: *ThriftDecoder) !KeyValue {
        var kv = KeyValue{};
        decoder.resetFieldId();

        while (try decoder.readFieldHeader()) |field| {
            switch (field.field_id) {
                1 => kv.key = try decoder.readString(),
                2 => kv.value = try decoder.readString(),
                else => try decoder.skipField(field.field_type),
            }
        }

        return kv;
    }
};

/// Column descriptor (flattened from schema)
pub const ColumnDescriptor = struct {
    /// Full path from root
    path: [][]const u8,
    /// Physical type
    type_: Type,
    /// Length for FIXED_LEN_BYTE_ARRAY
    type_length: ?i32,
    /// Repetition type
    repetition_type: FieldRepetitionType,
    /// Converted type
    converted_type: ?ConvertedType,
    /// Scale for DECIMAL
    scale: ?i32,
    /// Precision for DECIMAL
    precision: ?i32,

    pub fn getName(self: ColumnDescriptor) []const u8 {
        if (self.path.len > 0) {
            return self.path[self.path.len - 1];
        }
        return "";
    }
};

/// Page header
pub const PageHeader = struct {
    /// Page type
    type_: PageType = .data_page,
    /// Uncompressed size (bytes)
    uncompressed_page_size: i32 = 0,
    /// Compressed size (bytes)
    compressed_page_size: i32 = 0,
    /// CRC checksum (optional)
    crc: ?i32 = null,
    /// Data page header (for DATA_PAGE type)
    data_page_header: ?DataPageHeader = null,
    /// Dictionary page header (for DICTIONARY_PAGE type)
    dictionary_page_header: ?DictionaryPageHeader = null,
    /// Data page v2 header
    data_page_header_v2: ?DataPageHeaderV2 = null,

    pub fn decode(decoder: *ThriftDecoder, allocator: std.mem.Allocator) !PageHeader {
        _ = allocator;
        var header = PageHeader{};
        decoder.resetFieldId();

        while (try decoder.readFieldHeader()) |field| {
            // Save current field context before processing nested structures
            const current_field_id = decoder.last_field_id;

            switch (field.field_id) {
                1 => header.type_ = PageType.fromI32(try decoder.readI32()),
                2 => header.uncompressed_page_size = try decoder.readI32(),
                3 => header.compressed_page_size = try decoder.readI32(),
                4 => header.crc = try decoder.readI32(),
                5 => header.data_page_header = try DataPageHeader.decode(decoder),
                7 => header.dictionary_page_header = try DictionaryPageHeader.decode(decoder),
                8 => header.data_page_header_v2 = try DataPageHeaderV2.decode(decoder),
                else => try decoder.skipField(field.field_type),
            }

            // Restore field context after nested structures
            decoder.last_field_id = current_field_id;
        }

        return header;
    }
};

/// Data page header (v1)
pub const DataPageHeader = struct {
    /// Number of values in this page
    num_values: i32 = 0,
    /// Encoding for data
    encoding: Encoding = .plain,
    /// Encoding for definition levels
    definition_level_encoding: Encoding = .rle,
    /// Encoding for repetition levels
    repetition_level_encoding: Encoding = .rle,

    pub fn decode(decoder: *ThriftDecoder) !DataPageHeader {
        var header = DataPageHeader{};
        decoder.resetFieldId();

        while (try decoder.readFieldHeader()) |field| {
            switch (field.field_id) {
                1 => header.num_values = try decoder.readI32(),
                2 => header.encoding = Encoding.fromI32(try decoder.readI32()),
                3 => header.definition_level_encoding = Encoding.fromI32(try decoder.readI32()),
                4 => header.repetition_level_encoding = Encoding.fromI32(try decoder.readI32()),
                else => try decoder.skipField(field.field_type),
            }
        }

        return header;
    }
};

/// Dictionary page header
pub const DictionaryPageHeader = struct {
    /// Number of values in dictionary
    num_values: i32 = 0,
    /// Encoding for dictionary values
    encoding: Encoding = .plain,
    /// Is sorted
    is_sorted: ?bool = null,

    pub fn decode(decoder: *ThriftDecoder) !DictionaryPageHeader {
        var header = DictionaryPageHeader{};
        decoder.resetFieldId();

        while (try decoder.readFieldHeader()) |field| {
            switch (field.field_id) {
                1 => header.num_values = try decoder.readI32(),
                2 => header.encoding = Encoding.fromI32(try decoder.readI32()),
                3 => header.is_sorted = ThriftDecoder.readBoolFromType(field.field_type),
                else => try decoder.skipField(field.field_type),
            }
        }

        return header;
    }
};

/// Data page header v2
pub const DataPageHeaderV2 = struct {
    /// Number of values
    num_values: i32 = 0,
    /// Number of nulls
    num_nulls: i32 = 0,
    /// Number of rows in this page
    num_rows: i32 = 0,
    /// Encoding for data
    encoding: Encoding = .plain,
    /// Compressed size of definition levels
    definition_levels_byte_length: i32 = 0,
    /// Compressed size of repetition levels
    repetition_levels_byte_length: i32 = 0,
    /// Is compressed
    is_compressed: ?bool = null,

    pub fn decode(decoder: *ThriftDecoder) !DataPageHeaderV2 {
        var header = DataPageHeaderV2{};
        decoder.resetFieldId();

        while (try decoder.readFieldHeader()) |field| {
            switch (field.field_id) {
                1 => header.num_values = try decoder.readI32(),
                2 => header.num_nulls = try decoder.readI32(),
                3 => header.num_rows = try decoder.readI32(),
                4 => header.encoding = Encoding.fromI32(try decoder.readI32()),
                5 => header.definition_levels_byte_length = try decoder.readI32(),
                6 => header.repetition_levels_byte_length = try decoder.readI32(),
                7 => header.is_compressed = ThriftDecoder.readBoolFromType(field.field_type),
                else => try decoder.skipField(field.field_type),
            }
        }

        return header;
    }
};

// ============================================================================
// Compile-time assertions
// ============================================================================
//
// These assertions verify:
// 1. Enum backing types match Parquet Thrift specification (all i32)
// 2. Struct sizes are documented for ABI stability
//
// If these fail after a change, verify the modification is intentional.

comptime {
    // All Parquet enums use i32 backing per Thrift specification
    const enum_size = @sizeOf(i32);
    if (@sizeOf(Type) != enum_size) @compileError("Type enum size mismatch - expected i32");
    if (@sizeOf(ConvertedType) != enum_size) @compileError("ConvertedType enum size mismatch - expected i32");
    if (@sizeOf(FieldRepetitionType) != enum_size) @compileError("FieldRepetitionType enum size mismatch - expected i32");
    if (@sizeOf(Encoding) != enum_size) @compileError("Encoding enum size mismatch - expected i32");
    if (@sizeOf(CompressionCodec) != enum_size) @compileError("CompressionCodec enum size mismatch - expected i32");
    if (@sizeOf(PageType) != enum_size) @compileError("PageType enum size mismatch - expected i32");

    // Alignment assertions for key structs
    if (@alignOf(DataPageHeader) < @alignOf(i32)) @compileError("DataPageHeader alignment too small");
    if (@alignOf(DictionaryPageHeader) < @alignOf(i32)) @compileError("DictionaryPageHeader alignment too small");
    if (@alignOf(DataPageHeaderV2) < @alignOf(i32)) @compileError("DataPageHeaderV2 alignment too small");
}
