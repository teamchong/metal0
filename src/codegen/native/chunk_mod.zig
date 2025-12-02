/// Python chunk module - Read IFF chunked data
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Chunk", genChunk }, .{ "getname", genEmptyStr }, .{ "getsize", genI64_0 },
    .{ "close", genUnit }, .{ "isatty", genFalse }, .{ "seek", genUnit },
    .{ "tell", genI64_0 }, .{ "read", genEmptyStr }, .{ "skip", genUnit },
});

fn genChunk(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const file = "); try self.genExpr(args[0]); try self.emit("; _ = file; break :blk .{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{0} ** 4, .chunksize = 0, .size_read = 0 }; }"); }
    else try self.emit(".{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{0} ** 4, .chunksize = 0, .size_read = 0 }");
}
