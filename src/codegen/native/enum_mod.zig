/// Python enum module - Enumerations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genI64_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 1)"); }
fn genI64_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 2)"); }
fn genI64_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 3)"); }
fn genI64_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 4)"); }
fn genI64_5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 5)"); }
fn genI64_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 6)"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct {}{}"); }
fn genEnumType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"EnumType\""); }
fn genEnum(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { name: []const u8, value: i64, pub fn __str__(__self: @This()) []const u8 { return __self.name; } pub fn __repr__(__self: @This()) []const u8 { return __self.name; } }{ .name = \"\", .value = 0 }"); }
fn genStrEnum(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { name: []const u8, value: []const u8, pub fn __str__(__self: @This()) []const u8 { return __self.value; } pub fn __repr__(__self: @This()) []const u8 { return __self.name; } }{ .name = \"\", .value = \"\" }"); }
fn genFlag(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { name: []const u8, value: i64, pub fn __or__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value | other.value }; } pub fn __and__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value & other.value }; } pub fn __xor__(__self: @This(), other: @This()) @This() { return @This(){ .name = __self.name, .value = __self.value ^ other.value }; } pub fn __invert__(__self: @This()) @This() { return @This(){ .name = __self.name, .value = ~__self.value }; } }{ .name = \"\", .value = 0 }"); }
fn genProperty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("struct { fget: ?*anyopaque = null }{}"); } }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Enum", genEnum }, .{ "IntEnum", genEnum }, .{ "StrEnum", genStrEnum },
    .{ "Flag", genFlag }, .{ "IntFlag", genFlag }, .{ "FlagBoundary", genEnum },
    .{ "auto", genI64_0 }, .{ "unique", genDecorator }, .{ "verify", genDecorator },
    .{ "member", genDecorator }, .{ "nonmember", genDecorator }, .{ "global_enum", genDecorator },
    .{ "EJECT", genI64_1 }, .{ "KEEP", genI64_2 }, .{ "STRICT", genI64_3 },
    .{ "CONFORM", genI64_4 }, .{ "CONTINUOUS", genI64_5 }, .{ "NAMED_FLAGS", genI64_6 },
    .{ "EnumType", genEnumType }, .{ "EnumCheck", genEmpty }, .{ "property", genProperty },
});

fn genDecorator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("struct {}{}"); }
}
