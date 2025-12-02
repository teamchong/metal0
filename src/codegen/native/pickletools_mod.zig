/// Python pickletools module - Tools for working with pickle data streams
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "dis", genConst("{}") }, .{ "genops", genConst("&[_]@TypeOf(.{}){}") }, .{ "optimize", genOptimize },
    .{ "OpcodeInfo", genConst(".{ .name = \"\", .code = \"\", .arg = null, .stack_before = &[_][]const u8{}, .stack_after = &[_][]const u8{}, .proto = 0, .doc = \"\" }") },
    .{ "opcodes", genConst("&[_]@TypeOf(.{}){}") },
    .{ "bytes_types", genConst("&[_]type{ []const u8 }") },
    .{ "UP_TO_NEWLINE", genConst("@as(i32, -1)") }, .{ "TAKEN_FROM_ARGUMENT1", genConst("@as(i32, -2)") },
    .{ "TAKEN_FROM_ARGUMENT4", genConst("@as(i32, -3)") }, .{ "TAKEN_FROM_ARGUMENT4U", genConst("@as(i32, -4)") }, .{ "TAKEN_FROM_ARGUMENT8U", genConst("@as(i32, -5)") },
});

fn genOptimize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\""); }
