//! Lance schema protobuf parser.
//!
//! Based on Lance file.proto:
//! https://github.com/lance-format/lance/blob/main/protos/file.proto

const std = @import("std");
const decoder = @import("decoder.zig");

const ProtoDecoder = decoder.ProtoDecoder;
const DecodeError = decoder.DecodeError;

/// Field type enum
pub const FieldType = enum {
    parent,
    repeated,
    leaf,
    unknown,

    pub fn fromInt(value: u64) FieldType {
        return switch (value) {
            0 => .parent,
            1 => .repeated,
            2 => .leaf,
            else => .unknown,
        };
    }
};

/// A field (column) in the schema.
pub const Field = struct {
    name: []const u8,
    id: i32,
    parent_id: i32,
    field_type: FieldType,
    logical_type: []const u8,
    nullable: bool,

    /// Check if this is a top-level (root) field.
    pub fn isTopLevel(self: Field) bool {
        return self.parent_id == -1;
    }
};

/// Lance file schema.
pub const Schema = struct {
    fields: []Field,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Parse schema from protobuf bytes.
    /// Lance v2 wraps the schema in an outer message:
    ///   OuterWrapper { field 1: Schema { repeated Field fields = 1; } }
    /// This function handles both the wrapper and direct schema formats.
    pub fn parse(allocator: std.mem.Allocator, data: []const u8) DecodeError!Self {
        var proto = ProtoDecoder.init(data);

        var fields = std.ArrayListUnmanaged(Field){};
        errdefer {
            for (fields.items) |field| {
                allocator.free(field.name);
                allocator.free(field.logical_type);
            }
            fields.deinit(allocator);
        }

        while (proto.hasMore()) {
            const header = try proto.readFieldHeader();

            switch (header.field_num) {
                1 => {
                    // Field 1 is always wire_type 2 (length-delimited) in both cases:
                    // - Direct: repeated Field (each Field is a nested message)
                    // - Wrapper: Schema wrapper containing nested Schema bytes
                    //
                    // To distinguish: check if the content starts with field 1 wire_type 2.
                    // In the wrapper case, the inner bytes also start with 0a (field 1, bytes).
                    // In direct Field case, the inner bytes start with field definitions
                    // like 08 (field 1 varint for type) or 12 (field 2 string for name).
                    const field_bytes = try proto.readBytes();

                    if (field_bytes.len > 0) {
                        const first_byte = field_bytes[0];
                        const inner_field_num = first_byte >> 3;
                        const inner_wire_type = first_byte & 0x7;

                        // If inner message starts with field 1, wire_type 2 (bytes),
                        // it's the wrapper format containing nested Field messages
                        if (inner_field_num == 1 and inner_wire_type == 2) {
                            // Wrapper format: parse the inner bytes as Schema
                            try parseSchemaFields(allocator, field_bytes, &fields);
                        } else {
                            // Direct Field format: parse this as a single Field
                            const field = try parseField(allocator, field_bytes);
                            fields.append(allocator, field) catch return DecodeError.OutOfMemory;
                        }
                    }
                },
                else => {
                    try proto.skipField(header.wire_type);
                },
            }
        }

        return Self{
            .fields = fields.toOwnedSlice(allocator) catch return DecodeError.OutOfMemory,
            .allocator = allocator,
        };
    }

    /// Parse schema fields from nested bytes (handles wrapper format).
    fn parseSchemaFields(allocator: std.mem.Allocator, data: []const u8, fields: *std.ArrayListUnmanaged(Field)) DecodeError!void {
        var proto = ProtoDecoder.init(data);

        while (proto.hasMore()) {
            const header = try proto.readFieldHeader();

            switch (header.field_num) {
                1 => { // repeated Field message
                    const field_bytes = try proto.readBytes();
                    const field = try parseField(allocator, field_bytes);
                    fields.append(allocator, field) catch return DecodeError.OutOfMemory;
                },
                else => {
                    try proto.skipField(header.wire_type);
                },
            }
        }
    }

    pub fn deinit(self: *Self) void {
        for (self.fields) |field| {
            // Always free (we always allocate, even for empty strings)
            self.allocator.free(field.name);
            self.allocator.free(field.logical_type);
        }
        self.allocator.free(self.fields);
    }

    /// Get number of top-level columns.
    pub fn columnCount(self: Self) usize {
        var count: usize = 0;
        for (self.fields) |field| {
            if (field.isTopLevel()) count += 1;
        }
        return count;
    }

    /// Get top-level column names.
    pub fn columnNames(self: Self, allocator: std.mem.Allocator) ![][]const u8 {
        var names = std.ArrayListUnmanaged([]const u8){};
        errdefer names.deinit(allocator);

        for (self.fields) |field| {
            if (field.isTopLevel()) {
                names.append(allocator, field.name) catch return error.OutOfMemory;
            }
        }

        return names.toOwnedSlice(allocator) catch return error.OutOfMemory;
    }

    /// Find field by name.
    pub fn findField(self: Self, name: []const u8) ?Field {
        for (self.fields) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                return field;
            }
        }
        return null;
    }

    /// Get field index by name.
    pub fn fieldIndex(self: Self, name: []const u8) ?usize {
        for (self.fields, 0..) |field, i| {
            if (std.mem.eql(u8, field.name, name)) {
                return i;
            }
        }
        return null;
    }

    /// Get the physical column ID for a field by name.
    /// Returns the field's id (physical column index) which can be used with column metadata.
    pub fn physicalColumnId(self: Self, name: []const u8) ?u32 {
        for (self.fields) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                // field.id is i32 but physical column IDs should be non-negative
                if (field.id >= 0) {
                    return @intCast(field.id);
                }
                return null;
            }
        }
        return null;
    }
};

/// Parse a single Field from protobuf bytes.
fn parseField(allocator: std.mem.Allocator, data: []const u8) DecodeError!Field {
    var proto = ProtoDecoder.init(data);

    var name: ?[]const u8 = null;
    var id: i32 = 0;
    var parent_id: i32 = -1;
    var field_type: FieldType = .leaf;
    var logical_type: ?[]const u8 = null;
    var nullable: bool = false;

    errdefer {
        if (name) |n| allocator.free(n);
        if (logical_type) |lt| allocator.free(lt);
    }

    while (proto.hasMore()) {
        const header = try proto.readFieldHeader();

        switch (header.field_num) {
            1 => { // type (enum)
                field_type = FieldType.fromInt(try proto.readVarint());
            },
            2 => { // name (string)
                const bytes = try proto.readBytes();
                // Free previous allocation if field appears multiple times
                if (name) |n| allocator.free(n);
                name = allocator.dupe(u8, bytes) catch return DecodeError.OutOfMemory;
            },
            3 => { // id (int32)
                const val = try proto.readVarint();
                id = @bitCast(@as(u32, @truncate(val)));
            },
            4 => { // parent_id (int32) - can be -1 for root fields
                const val = try proto.readVarint();
                parent_id = @bitCast(@as(u32, @truncate(val)));
            },
            5 => { // logical_type (string)
                const bytes = try proto.readBytes();
                // Free previous allocation if field appears multiple times
                if (logical_type) |lt| allocator.free(lt);
                logical_type = allocator.dupe(u8, bytes) catch return DecodeError.OutOfMemory;
            },
            6 => { // nullable (bool)
                nullable = try proto.readVarint() != 0;
            },
            else => {
                try proto.skipField(header.wire_type);
            },
        }
    }

    // Always allocate strings (even empty) for consistent cleanup
    const final_name = name orelse (allocator.alloc(u8, 0) catch return DecodeError.OutOfMemory);
    const final_logical_type = logical_type orelse (allocator.alloc(u8, 0) catch return DecodeError.OutOfMemory);

    return Field{
        .name = final_name,
        .id = id,
        .parent_id = parent_id,
        .field_type = field_type,
        .logical_type = final_logical_type,
        .nullable = nullable,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "parse empty schema" {
    const allocator = std.testing.allocator;
    var schema = try Schema.parse(allocator, &[_]u8{});
    defer schema.deinit();

    try std.testing.expectEqual(@as(usize, 0), schema.fields.len);
}

test "parse lancedb schema" {
    // Schema bytes from a lancedb-created file with columns: id (int64), name (string)
    const schema_bytes = [_]u8{
        0x0a, 0x4f, 0x0a, 0x23, 0x12, 0x02, 0x69, 0x64, 0x20, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0x01, 0x2a, 0x05, 0x69, 0x6e, 0x74, 0x36, 0x34, 0x30, 0x01, 0x38, 0x01, 0x5a, 0x07,
        0x64, 0x65, 0x66, 0x61, 0x75, 0x6c, 0x74, 0x0a, 0x28, 0x12, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x18,
        0x01, 0x20, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0x2a, 0x06, 0x73, 0x74,
        0x72, 0x69, 0x6e, 0x67, 0x30, 0x01, 0x38, 0x02, 0x5a, 0x07, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6c,
        0x74, 0x10, 0x03,
    };

    const allocator = std.testing.allocator;
    var schema = try Schema.parse(allocator, &schema_bytes);
    defer schema.deinit();

    // Debug: print all fields
    std.debug.print("\nParsed {d} fields:\n", .{schema.fields.len});
    for (schema.fields, 0..) |field, i| {
        std.debug.print("  Field {d}: name=\"{s}\" id={d} parent_id={d} type={s} logical_type=\"{s}\"\n", .{
            i,
            field.name,
            field.id,
            field.parent_id,
            @tagName(field.field_type),
            field.logical_type,
        });
    }

    // Should have 2 fields
    try std.testing.expectEqual(@as(usize, 2), schema.fields.len);

    // First field: id (int64)
    try std.testing.expectEqualStrings("id", schema.fields[0].name);
    try std.testing.expectEqualStrings("int64", schema.fields[0].logical_type);
    try std.testing.expectEqual(@as(i32, -1), schema.fields[0].parent_id);

    // Second field: name (string)
    try std.testing.expectEqualStrings("name", schema.fields[1].name);
    try std.testing.expectEqualStrings("string", schema.fields[1].logical_type);
    try std.testing.expectEqual(@as(i32, -1), schema.fields[1].parent_id);

    // Column names should return both
    const names = try schema.columnNames(allocator);
    defer allocator.free(names);
    try std.testing.expectEqual(@as(usize, 2), names.len);
    try std.testing.expectEqualStrings("id", names[0]);
    try std.testing.expectEqualStrings("name", names[1]);
}
