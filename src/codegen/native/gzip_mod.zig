/// Python gzip module - GZIP compression
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compress", genCompress },
    .{ "decompress", genDecompress },
    .{ "open", genOpen },
    .{ "GzipFile", genGzipFile },
    .{ "BadGzipFile", genBadGzipFile },
});

/// Generate gzip.compress(data, compresslevel=9) -> compressed bytes
pub fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Use runtime.gzip.compress(__global_allocator, data)
    try self.emit("try runtime.gzip.compress(__global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate gzip.decompress(data) -> decompressed bytes
pub fn genDecompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Use runtime.gzip.decompress(__global_allocator, data)
    try self.emit("try runtime.gzip.decompress(__global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate gzip.open(filename, mode='rb', compresslevel=9) -> file object
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("gzip_open_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _mode: []const u8 = ");
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("\"rb\"");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _mode;\n");
    try self.emitIndent();
    try self.emit("break :gzip_open_blk struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("path: []const u8,\n");
    try self.emitIndent();
    try self.emit("buffer: std.ArrayList(u8),\n");
    try self.emitIndent();
    try self.emit("pub fn init(p: []const u8) @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return @This(){ .path = p, .buffer = .{} };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn read(__self: *@This()) []const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const file = std.fs.cwd().openFile(__self.path, .{}) catch return \"\";\n");
    try self.emitIndent();
    try self.emit("defer file.close();\n");
    try self.emitIndent();
    try self.emit("const content = file.readToEndAlloc(__global_allocator, 10 * 1024 * 1024) catch return \"\";\n");
    try self.emitIndent();
    try self.emit("return content;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn write(__self: *@This(), data: []const u8) i64 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("__self.buffer.appendSlice(__global_allocator, data) catch {};\n");
    try self.emitIndent();
    try self.emit("return @intCast(data.len);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (__self.buffer.items.len > 0) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const file = std.fs.cwd().createFile(__self.path, .{}) catch return;\n");
    try self.emitIndent();
    try self.emit("defer file.close();\n");
    try self.emitIndent();
    try self.emit("_ = file.write(__self.buffer.items) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(__self: *@This()) *@This() { return __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(__self: *@This(), _: anytype) void { __self.close(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}.init(_path);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate gzip.GzipFile(filename, mode='rb', compresslevel=9) -> GzipFile
pub fn genGzipFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genOpen(self, args);
}

/// Generate gzip.BadGzipFile exception
pub fn genBadGzipFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"BadGzipFile\"");
}
