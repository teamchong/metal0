/// Python _struct module - C accelerator for struct (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "pack", genPack }, .{ "pack_into", genUnit }, .{ "unpack", genUnpack }, .{ "unpack_from", genUnpack },
    .{ "iter_unpack", genIterUnpack }, .{ "calcsize", genCalcsize }, .{ "Struct", genStruct }, .{ "error", genErr },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genIterUnpack(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{}){}"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.StructError"); }

fn genPack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const fmt = "); try self.genExpr(args[0]); try self.emit("; _ = fmt; var result: std.ArrayList(u8) = .{}; break :blk result.items; }"); } else { try self.emit("\"\""); }
}

fn genUnpack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const fmt = "); try self.genExpr(args[0]); try self.emit("; const buffer = "); try self.genExpr(args[1]); try self.emit("; _ = fmt; _ = buffer; break :blk .{}; }"); } else { try self.emit(".{}"); }
}

fn genCalcsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const fmt = "); try self.genExpr(args[0]); try self.emit("; var size: i64 = 0; for (fmt) |c| { switch (c) { 'b', 'B', 'c', '?', 's', 'p' => size += 1, 'h', 'H' => size += 2, 'i', 'I', 'l', 'L', 'f' => size += 4, 'q', 'Q', 'd' => size += 8, else => {}, } } break :blk size; }"); } else { try self.emit("@as(i64, 0)"); }
}

fn genStruct(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const fmt = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .format = fmt, .size = 0 }; }"); } else { try self.emit(".{ .format = \"\", .size = 0 }"); }
}
