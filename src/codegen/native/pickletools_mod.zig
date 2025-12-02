/// Python pickletools module - Tools for working with pickle data streams
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyList(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{}){}"); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "dis", genUnit }, .{ "genops", genEmptyList }, .{ "optimize", genOptimize }, .{ "OpcodeInfo", genOpcodeInfo }, .{ "opcodes", genEmptyList },
    .{ "bytes_types", genBytesTypes }, .{ "UP_TO_NEWLINE", genI32(-1) }, .{ "TAKEN_FROM_ARGUMENT1", genI32(-2) },
    .{ "TAKEN_FROM_ARGUMENT4", genI32(-3) }, .{ "TAKEN_FROM_ARGUMENT4U", genI32(-4) }, .{ "TAKEN_FROM_ARGUMENT8U", genI32(-5) },
});

fn genOptimize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\""); }
fn genOpcodeInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .code = \"\", .arg = null, .stack_before = &[_][]const u8{}, .stack_after = &[_][]const u8{}, .proto = 0, .doc = \"\" }"); }
fn genBytesTypes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]type{ []const u8 }"); }
