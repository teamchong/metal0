/// Python gzip module - GZIP compression
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compress", genCompress }, .{ "decompress", genDecompress },
    .{ "open", genOpen }, .{ "GzipFile", genOpen }, .{ "BadGzipFile", h.c("\"BadGzipFile\"") },
});

fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try runtime.gzip.compress(__global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

fn genDecompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try runtime.gzip.decompress(__global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("gzip_open_blk: { const _path = ");
    try self.genExpr(args[0]);
    try self.emit("; const _mode: []const u8 = ");
    if (args.len > 1) try self.genExpr(args[1]) else try self.emit("\"rb\"");
    try self.emit("; _ = _mode; break :gzip_open_blk struct { path: []const u8, buffer: std.ArrayList(u8), pub fn init(p: []const u8) @This() { return @This(){ .path = p, .buffer = .{} }; } pub fn read(__self: *@This()) []const u8 { const file = std.fs.cwd().openFile(__self.path, .{}) catch return \"\"; defer file.close(); const content = file.readToEndAlloc(__global_allocator, 10 * 1024 * 1024) catch return \"\"; return content; } pub fn write(__self: *@This(), data: []const u8) i64 { __self.buffer.appendSlice(__global_allocator, data) catch {}; return @intCast(data.len); } pub fn close(__self: *@This()) void { if (__self.buffer.items.len > 0) { const file = std.fs.cwd().createFile(__self.path, .{}) catch return; defer file.close(); _ = file.write(__self.buffer.items) catch {}; } } pub fn __enter__(__self: *@This()) *@This() { return __self; } pub fn __exit__(__self: *@This(), _: anytype) void { __self.close(); } }.init(_path); }");
}
