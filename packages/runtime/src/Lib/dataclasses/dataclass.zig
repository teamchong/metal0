//\! Main dataclass type and generator
//\!
//\! Provides the Dataclass generic type that wraps a struct and
//\! automatically generates initialization, representation, equality,
//\! comparison, and hashing methods based on options.

const std = @import("std");
const types = @import("types.zig");
const repr = @import("repr.zig");
const comparison = @import("comparison.zig");
const hash_mod = @import("hash.zig");
const utilities = @import("utilities.zig");

/// Make a type into a dataclass with automatic method generation
pub fn Dataclass(comptime T: type, comptime options: types.DataclassOptions) type {
    const type_info = @typeInfo(T);

    if (type_info \!= .@"struct") {
        @compileError("Dataclass requires a struct type");
    }

    return struct {
        const Self = @This();
        const OriginalType = T;

        data: T,

        /// Generated __init__ method
        pub fn init(args: T) Self {
            return .{ .data = args };
        }

        /// Default constructor with default values
        pub fn initDefault() Self {
            var result: T = undefined;
            inline for (@typeInfo(T).@"struct".fields) |fld| {
                if (fld.default_value_ptr) |ptr| {
                    @field(result, fld.name) = @as(*const fld.type, @ptrCast(@alignCast(ptr))).*;
                }
            }
            return .{ .data = result };
        }

        /// Generated __repr__ method
        pub fn reprStr(self: Self, allocator: std.mem.Allocator) \![]u8 {
            return repr.generateRepr(T, self, options, allocator);
        }

        /// Generated __eq__ method
        pub fn eql(self: Self, other: Self) bool {
            return comparison.instancesEqual(T, self, other, options);
        }

        /// Generated __hash__ method (if hashable)
        pub fn hashValue(self: Self) u64 {
            return hash_mod.instanceHash(T, self);
        }

        /// Generated comparison methods (if order=true)
        pub fn lessThan(self: Self, other: Self) bool {
            return comparison.instanceLessThan(T, self, other, options);
        }

        pub fn lessThanOrEqual(self: Self, other: Self) bool {
            return comparison.instanceLessThanOrEqual(T, self, other, options);
        }

        pub fn greaterThan(self: Self, other: Self) bool {
            return comparison.instanceGreaterThan(T, self, other, options);
        }

        pub fn greaterThanOrEqual(self: Self, other: Self) bool {
            return comparison.instanceGreaterThanOrEqual(T, self, other, options);
        }

        /// Access fields directly
        pub fn get(self: Self, comptime field_name: []const u8) @TypeOf(@field(self.data, field_name)) {
            return @field(self.data, field_name);
        }

        /// Get the list of fields
        pub fn fields() []const std.builtin.Type.StructField {
            return @typeInfo(T).@"struct".fields;
        }

        /// Convert to tuple of field values
        pub fn astuple(self: Self) utilities.AsTupleType(T) {
            return utilities.astuple(T, self);
        }
    };
}

/// Create a dataclass with default options
pub fn dataclass(comptime T: type) type {
    return Dataclass(T, .{});
}
