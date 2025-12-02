/// Python enum module - Enumerations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Enum", genConst("struct { name: []const u8, value: i64, pub fn __str__(__self: @This()) []const u8 { return __self.name; } pub fn __repr__(__self: @This()) []const u8 { return __self.name; } }{ .name = \"\", .value = 0 }") },
    .{ "IntEnum", genConst("struct { name: []const u8, value: i64, pub fn __str__(__self: @This()) []const u8 { return __self.name; } pub fn __repr__(__self: @This()) []const u8 { return __self.name; } }{ .name = \"\", .value = 0 }") },
    .{ "StrEnum", genConst("struct { name: []const u8, value: []const u8, pub fn __str__(__self: @This()) []const u8 { return __self.value; } pub fn __repr__(__self: @This()) []const u8 { return __self.name; } }{ .name = \"\", .value = \"\" }") },
    .{ "Flag", genConst("struct { name: []const u8, value: i64, pub fn __or__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value | other.value }; } pub fn __and__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value & other.value }; } pub fn __xor__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value ^ other.value }; } pub fn __invert__(__self: @This()) @This() { return @This(){ .name = __self.name, .value = ~__self.value }; } }{ .name = \"\", .value = 0 }") },
    .{ "IntFlag", genConst("struct { name: []const u8, value: i64, pub fn __or__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value | other.value }; } pub fn __and__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value & other.value }; } pub fn __xor__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value ^ other.value }; } pub fn __invert__(__self: @This()) @This() { return @This(){ .name = __self.name, .value = ~__self.value }; } }{ .name = \"\", .value = 0 }") },
    .{ "FlagBoundary", genConst("struct { name: []const u8, value: i64, pub fn __str__(__self: @This()) []const u8 { return __self.name; } pub fn __repr__(__self: @This()) []const u8 { return __self.name; } }{ .name = \"\", .value = 0 }") },
    .{ "auto", genConst("@as(i64, 0)") }, .{ "unique", genDecorator }, .{ "verify", genDecorator },
    .{ "member", genDecorator }, .{ "nonmember", genDecorator }, .{ "global_enum", genDecorator },
    .{ "EJECT", genConst("@as(i64, 1)") }, .{ "KEEP", genConst("@as(i64, 2)") }, .{ "STRICT", genConst("@as(i64, 3)") },
    .{ "CONFORM", genConst("@as(i64, 4)") }, .{ "CONTINUOUS", genConst("@as(i64, 5)") }, .{ "NAMED_FLAGS", genConst("@as(i64, 6)") },
    .{ "EnumType", genConst("\"EnumType\"") }, .{ "EnumCheck", genConst("struct {}{}") }, .{ "property", genDecorator },
});

fn genDecorator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("struct {}{}"); }
}
