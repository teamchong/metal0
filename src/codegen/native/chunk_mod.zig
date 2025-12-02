/// Python chunk module - Read IFF chunked data
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Chunk", genChunk }, .{ "getname", h.c("\"\"") }, .{ "getsize", h.I64(0) },
    .{ "close", h.c("{}") }, .{ "isatty", h.c("false") }, .{ "seek", h.c("{}") },
    .{ "tell", h.I64(0) }, .{ "read", h.c("\"\"") }, .{ "skip", h.c("{}") },
});

fn genChunk(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const file = "); try self.genExpr(args[0]); try self.emit("; _ = file; break :blk .{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{0} ** 4, .chunksize = 0, .size_read = 0 }; }"); }
    else try self.emit(".{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{0} ** 4, .chunksize = 0, .size_read = 0 }");
}
