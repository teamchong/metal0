/// Python quopri module - Quoted-Printable encoding/decoding
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "encode", genUnit }, .{ "decode", genUnit }, .{ "encodestring", genString }, .{ "decodestring", genString },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genString(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); } }
