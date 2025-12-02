/// Python chunk module - Read IFF chunked data
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Chunk", genChunk }, .{ "getname", genConst("\"\"") }, .{ "getsize", genConst("@as(i64, 0)") },
    .{ "close", genConst("{}") }, .{ "isatty", genConst("false") }, .{ "seek", genConst("{}") },
    .{ "tell", genConst("@as(i64, 0)") }, .{ "read", genConst("\"\"") }, .{ "skip", genConst("{}") },
});

fn genChunk(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const file = "); try self.genExpr(args[0]); try self.emit("; _ = file; break :blk .{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{0} ** 4, .chunksize = 0, .size_read = 0 }; }"); }
    else try self.emit(".{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{0} ** 4, .chunksize = 0, .size_read = 0 }");
}
