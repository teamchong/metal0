/// Python gzip module - GZIP compression
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compress", h.wrap("try runtime.gzip.compress(__global_allocator, ", ")", "\"\"") },
    .{ "decompress", h.wrap("try runtime.gzip.decompress(__global_allocator, ", ")", "\"\"") },
    .{ "open", genOpen }, .{ "GzipFile", genOpen }, .{ "BadGzipFile", h.c("\"BadGzipFile\"") },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    const open_id = self.nextNameId();
    try self.emitFmt("__m{d}_gzip_open: {{ const _path = ", .{open_id});
    try self.genExpr(args[0]);
    try self.emit("; const _mode: []const u8 = ");
    if (args.len > 1) try self.genExpr(args[1]) else try self.emit("\"rb\"");
    try self.emitFmt("; _ = _mode; break :__m{d}_gzip_open struct {{ path: []const u8, buffer: std.ArrayListUnmanaged(u8), pub fn init(p: []const u8) @This() {{ return @This(){{ .path = p, .buffer = .{{}} }}; }} pub fn read(__self: *@This()) []const u8 {{ const file = std.fs.cwd().openFile(__self.path, .{{}}) catch return \"\"; defer file.close(); const content = file.readToEndAlloc(__global_allocator, 10 * 1024 * 1024) catch return \"\"; return content; }} pub fn write(__self: *@This(), data: []const u8) i64 {{ __self.buffer.appendSlice(__global_allocator, data) catch |err| @panic(\"gzip write OOM\"); return @intCast(data.len); }} pub fn close(__self: *@This()) void {{ if (__self.buffer.items.len > 0) {{ const file = std.fs.cwd().createFile(__self.path, .{{}}) catch |err| @panic(\"gzip createFile failed\"); defer file.close(); file.writeAll(__self.buffer.items) catch |err| @panic(\"gzip write failed\"); }} }} pub fn __enter__(__self: *@This()) *@This() {{ return __self; }} pub fn __exit__(__self: *@This(), _: anytype) void {{ __self.close(); }} }}.init(_path); }}", .{open_id});
}
