/// Python zipfile module - ZIP archive handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate zipfile.ZipFile(file, mode='r') -> ZipFile object
pub fn genZipFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("zipfile_open_blk: {\n");
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
        try self.emit("\"r\"");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _mode;\n");
    try self.emitIndent();
    try self.emit("break :zipfile_open_blk struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("path: []const u8,\n");
    try self.emitIndent();
    try self.emit("files: std.ArrayList([]const u8),\n");
    try self.emitIndent();
    try self.emit("pub fn init(p: []const u8) @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return @This(){ .path = p, .files = std.ArrayList([]const u8).init(allocator) };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn namelist(self: *@This()) [][]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return self.files.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn read(self: *@This(), name: []const u8) []const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self;\n");
    try self.emitIndent();
    try self.emit("_ = name;\n");
    try self.emitIndent();
    try self.emit("return \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn write(self: *@This(), name: []const u8, data: []const u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = data;\n");
    try self.emitIndent();
    try self.emit("self.files.append(allocator, name) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn writestr(self: *@This(), name: []const u8, data: []const u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.write(name, data);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn extractall(self: *@This(), path: ?[]const u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self;\n");
    try self.emitIndent();
    try self.emit("_ = path;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn extract(self: *@This(), member: []const u8, path: ?[]const u8) []const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self;\n");
    try self.emitIndent();
    try self.emit("_ = path;\n");
    try self.emitIndent();
    try self.emit("return member;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(self: *@This()) *@This() { return self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(self: *@This(), _: anytype) void { self.close(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}.init(_path);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate zipfile.is_zipfile(filename) -> bool
pub fn genIsZipfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("is_zipfile_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const file = std.fs.cwd().openFile(_path, .{}) catch break :is_zipfile_blk false;\n");
    try self.emitIndent();
    try self.emit("defer file.close();\n");
    try self.emitIndent();
    try self.emit("var buf: [4]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("_ = file.read(&buf) catch break :is_zipfile_blk false;\n");
    try self.emitIndent();
    try self.emit("break :is_zipfile_blk std.mem.eql(u8, buf[0..4], \"PK\\x03\\x04\");\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate zipfile.ZIP_STORED constant
pub fn genZIP_STORED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate zipfile.ZIP_DEFLATED constant
pub fn genZIP_DEFLATED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 8)");
}

/// Generate zipfile.ZIP_BZIP2 constant
pub fn genZIP_BZIP2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 12)");
}

/// Generate zipfile.ZIP_LZMA constant
pub fn genZIP_LZMA(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 14)");
}

/// Generate zipfile.BadZipFile exception (returns error string)
pub fn genBadZipFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"BadZipFile\"");
}

/// Generate zipfile.LargeZipFile exception
pub fn genLargeZipFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"LargeZipFile\"");
}

/// Generate zipfile.ZipInfo(filename) -> ZipInfo object
pub fn genZipInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("struct { filename: []const u8 = \"\", compress_size: i64 = 0, file_size: i64 = 0 }{}");
        return;
    }

    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("filename: []const u8,\n");
    try self.emitIndent();
    try self.emit("compress_size: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("file_size: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("compress_type: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("date_time: struct { year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64 } = .{ .year = 1980, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0 },\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .filename = ");
    try self.genExpr(args[0]);
    try self.emit(" }");
}
