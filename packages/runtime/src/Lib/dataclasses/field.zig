//! Field descriptor and configuration
//!
//! Provides the Field generic type for defining dataclass fields with
//! custom configuration (defaults, factories, repr, comparison, etc.)

const std = @import("std");

/// Field configuration for a dataclass field
pub fn Field(comptime T: type) type {
    return struct {
        const Self = @This();

        name: []const u8,
        field_type: type = T,
        default: ?T = null,
        default_factory: ?*const fn () T = null,
        init: bool = true,
        repr: bool = true,
        hash: ?bool = null,
        compare: bool = true,
        metadata: ?*const anyopaque = null,
        kw_only: bool = false,

        pub fn init(name: []const u8) Self {
            return .{ .name = name };
        }

        pub fn withDefault(self: Self, default: T) Self {
            var new = self;
            new.default = default;
            return new;
        }

        pub fn withDefaultFactory(self: Self, factory: *const fn () T) Self {
            var new = self;
            new.default_factory = factory;
            return new;
        }

        pub fn withInit(self: Self, val: bool) Self {
            var new = self;
            new.init = val;
            return new;
        }

        pub fn withRepr(self: Self, val: bool) Self {
            var new = self;
            new.repr = val;
            return new;
        }

        pub fn withCompare(self: Self, val: bool) Self {
            var new = self;
            new.compare = val;
            return new;
        }

        pub fn withKwOnly(self: Self, val: bool) Self {
            var new = self;
            new.kw_only = val;
            return new;
        }
    };
}

/// Create a field with custom configuration
pub fn field(comptime T: type, name: []const u8) Field(T) {
    return Field(T).init(name);
}
