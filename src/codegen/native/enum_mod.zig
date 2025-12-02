/// Python enum module - Enumerations
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Enum", h.c("struct { name: []const u8, value: i64, pub fn __str__(__self: @This()) []const u8 { return __self.name; } pub fn __repr__(__self: @This()) []const u8 { return __self.name; } }{ .name = \"\", .value = 0 }") },
    .{ "IntEnum", h.c("struct { name: []const u8, value: i64, pub fn __str__(__self: @This()) []const u8 { return __self.name; } pub fn __repr__(__self: @This()) []const u8 { return __self.name; } }{ .name = \"\", .value = 0 }") },
    .{ "StrEnum", h.c("struct { name: []const u8, value: []const u8, pub fn __str__(__self: @This()) []const u8 { return __self.value; } pub fn __repr__(__self: @This()) []const u8 { return __self.name; } }{ .name = \"\", .value = \"\" }") },
    .{ "Flag", h.c("struct { name: []const u8, value: i64, pub fn __or__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value | other.value }; } pub fn __and__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value & other.value }; } pub fn __xor__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value ^ other.value }; } pub fn __invert__(__self: @This()) @This() { return @This(){ .name = __self.name, .value = ~__self.value }; } }{ .name = \"\", .value = 0 }") },
    .{ "IntFlag", h.c("struct { name: []const u8, value: i64, pub fn __or__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value | other.value }; } pub fn __and__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value & other.value }; } pub fn __xor__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value ^ other.value }; } pub fn __invert__(__self: @This()) @This() { return @This(){ .name = __self.name, .value = ~__self.value }; } }{ .name = \"\", .value = 0 }") },
    .{ "FlagBoundary", h.c("struct { name: []const u8, value: i64, pub fn __str__(__self: @This()) []const u8 { return __self.name; } pub fn __repr__(__self: @This()) []const u8 { return __self.name; } }{ .name = \"\", .value = 0 }") },
    .{ "auto", h.I64(0) }, .{ "unique", h.pass("struct {}{}") }, .{ "verify", h.pass("struct {}{}") },
    .{ "member", h.pass("struct {}{}") }, .{ "nonmember", h.pass("struct {}{}") }, .{ "global_enum", h.pass("struct {}{}") },
    .{ "EJECT", h.I64(1) }, .{ "KEEP", h.I64(2) }, .{ "STRICT", h.I64(3) },
    .{ "CONFORM", h.I64(4) }, .{ "CONTINUOUS", h.I64(5) }, .{ "NAMED_FLAGS", h.I64(6) },
    .{ "EnumType", h.c("\"EnumType\"") }, .{ "EnumCheck", h.c("struct {}{}") }, .{ "property", h.pass("struct {}{}") },
});
