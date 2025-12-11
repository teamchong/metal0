//\! Utility functions for dataclasses
//\!
//\! Provides helper functions for working with dataclass instances:
//\! - getFields: Extract field information
//\! - asdict: Convert to dictionary-like structure
//\! - replace: Create modified copy with updated fields
//\! - copy: Shallow copy
//\! - isDataclass: Type checking

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

/// Get the tuple type for a struct's fields
pub fn AsTupleType(comptime T: type) type {
    const fields = @typeInfo(T).@"struct".fields;
    var types: [fields.len]type = undefined;
    for (fields, 0..) |fld, i| {
        types[i] = fld.type;
    }
    return std.meta.Tuple(&types);
}

/// Convert a dataclass instance to tuple of field values
pub fn astuple(comptime T: type, self: anytype) AsTupleType(T) {
    var result: AsTupleType(T) = undefined;
    const struct_fields = @typeInfo(T).@"struct".fields;
    inline for (struct_fields, 0..) |fld, i| {
        result[i] = @field(self.data, fld.name);
    }
    return result;
}

/// Get all fields of a dataclass
pub fn getFields(comptime T: type) []const std.builtin.Type.StructField {
    const type_info = @typeInfo(T);
    if (type_info == .@"struct") {
        return type_info.@"struct".fields;
    }
    return &[_]std.builtin.Type.StructField{};
}

/// Check if a type is a dataclass
pub fn isDataclass(comptime T: type) bool {
    const type_info = @typeInfo(T);
    if (type_info \!= .@"struct") return false;

    // Check if it has the characteristic dataclass methods
    return @hasDecl(T, "data") or @hasDecl(T, "repr") or @hasDecl(T, "eql");
}

/// Convert a dataclass instance to a dict-like struct
pub fn asdict(comptime T: type, instance: T, allocator: std.mem.Allocator) \!hashmap_helper.StringHashMap([]const u8) {
    var result = hashmap_helper.StringHashMap([]const u8).init(allocator);
    errdefer result.deinit();

    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields) |fld| {
        const value = @field(instance, fld.name);
        var buf: [64]u8 = undefined;
        const str = try formatValue(&buf, value);
        try result.put(fld.name, try allocator.dupe(u8, str));
    }

    return result;
}

/// Format a value for dictionary representation
fn formatValue(buf: []u8, value: anytype) \![]const u8 {
    const VT = @TypeOf(value);
    const vt_info = @typeInfo(VT);

    return switch (vt_info) {
        .int, .comptime_int => std.fmt.bufPrint(buf, "{d}", .{value}) catch "<int>",
        .float, .comptime_float => std.fmt.bufPrint(buf, "{d}", .{value}) catch "<float>",
        .bool => if (value) "True" else "False",
        .pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                return value;
            }
            return "<pointer>";
        },
        else => "<...>",
    };
}

/// Create a new dataclass with some fields replaced
pub fn replace(comptime T: type, instance: T, updates: anytype) T {
    var result = instance;
    const update_info = @typeInfo(@TypeOf(updates));

    if (update_info == .@"struct") {
        inline for (update_info.@"struct".fields) |fld| {
            if (@hasField(T, fld.name)) {
                @field(result, fld.name) = @field(updates, fld.name);
            }
        }
    }

    return result;
}

/// Create a shallow copy of a dataclass instance
pub fn copy(comptime T: type, instance: T) T {
    return instance;
}
