/// Python tempfile module - temporary file operations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "mktemp", genMktemp },
    .{ "mkdtemp", genMkdtemp },
    .{ "mkstemp", genMkstemp },
    .{ "gettempdir", genGettempdir },
    .{ "gettempprefix", genGettempprefix },
    .{ "NamedTemporaryFile", genNamedTemporaryFile },
    .{ "TemporaryFile", genTemporaryFile },
    .{ "SpooledTemporaryFile", genSpooledTemporaryFile },
    .{ "TemporaryDirectory", genTemporaryDirectory },
});

/// Generate tempfile.mktemp(suffix='', prefix='tmp', dir=None) -> temp filename
pub fn genMktemp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("mktemp_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("var _buf: [64]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :mktemp_blk \"/tmp/tmpXXXXXXXX\";\n");
    try self.emitIndent();
    try self.emit("break :mktemp_blk _name;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate tempfile.mkdtemp(suffix='', prefix='tmp', dir=None) -> temp dirname
pub fn genMkdtemp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("mkdtemp_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("var _buf: [64]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :mkdtemp_blk \"/tmp/tmpXXXXXXXX\";\n");
    try self.emitIndent();
    try self.emit("std.fs.makeDirAbsolute(_name) catch {};\n");
    try self.emitIndent();
    try self.emit("break :mkdtemp_blk _name;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate tempfile.gettempdir() -> temp directory path
pub fn genGettempdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"/tmp\"");
}

/// Generate tempfile.gettempprefix() -> temp file prefix
pub fn genGettempprefix(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"tmp\"");
}

/// Generate tempfile.NamedTemporaryFile(...) -> file object
pub fn genNamedTemporaryFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("named_tempfile_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("var _buf: [64]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :named_tempfile_blk struct { name: []const u8, file: ?std.fs.File }{ .name = \"\", .file = null };\n");
    try self.emitIndent();
    try self.emit("const _file = std.fs.createFileAbsolute(_name, .{}) catch break :named_tempfile_blk struct { name: []const u8, file: ?std.fs.File }{ .name = _name, .file = null };\n");
    try self.emitIndent();
    try self.emit("break :named_tempfile_blk struct { name: []const u8, file: ?std.fs.File }{ .name = _name, .file = _file };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate tempfile.TemporaryFile(...) -> file object (deleted on close)
pub fn genTemporaryFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Same as NamedTemporaryFile for now
    try genNamedTemporaryFile(self, args);
}

/// Generate tempfile.SpooledTemporaryFile(...) -> file object (in memory)
pub fn genSpooledTemporaryFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Return a StringIO-like in-memory buffer
    try self.emit("spooled_tempfile_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _buf: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("break :spooled_tempfile_blk struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("buffer: std.ArrayList(u8),\n");
    try self.emitIndent();
    try self.emit("pos: usize = 0,\n");
    try self.emitIndent();
    try self.emit("pub fn write(__self: *@This(), data: []const u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("__self.buffer.appendSlice(__global_allocator, data) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn read(__self: *@This()) []const u8 { return __self.buffer.items; }\n");
    try self.emitIndent();
    try self.emit("pub fn seek(__self: *@This(), pos: usize) void { __self.pos = pos; }\n");
    try self.emitIndent();
    try self.emit("pub fn tell(__self: *@This()) usize { return __self.pos; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { __self.buffer.deinit(__global_allocator); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .buffer = _buf };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate tempfile.TemporaryDirectory(...) -> context manager
pub fn genTemporaryDirectory(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("temp_dir_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("var _buf: [64]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmpdir{x:0>8}\", .{_rand.int(u32)}) catch break :temp_dir_blk struct { name: []const u8 }{ .name = \"\" };\n");
    try self.emitIndent();
    try self.emit("std.fs.makeDirAbsolute(_name) catch {};\n");
    try self.emitIndent();
    try self.emit("break :temp_dir_blk struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: []const u8,\n");
    try self.emitIndent();
    try self.emit("pub fn cleanup(__self: *@This()) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("std.fs.deleteTreeAbsolute(__self.name) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(__self: *@This()) []const u8 { return __self.name; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(__self: *@This(), _: anytype) void { __self.cleanup(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .name = _name };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate tempfile.mkstemp(suffix='', prefix='tmp', dir=None) -> (fd, name)
pub fn genMkstemp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("mkstemp_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("var _buf: [64]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :mkstemp_blk .{ @as(i64, -1), \"\" };\n");
    try self.emitIndent();
    try self.emit("const _file = std.fs.createFileAbsolute(_name, .{}) catch break :mkstemp_blk .{ @as(i64, -1), _name };\n");
    try self.emitIndent();
    try self.emit("break :mkstemp_blk .{ @as(i64, @intCast(_file.handle)), _name };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
