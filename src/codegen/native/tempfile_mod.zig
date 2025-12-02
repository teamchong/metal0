/// Python tempfile module - temporary file operations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genGettempdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"/tmp\""); }
fn genGettempprefix(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"tmp\""); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "mktemp", genMktemp }, .{ "mkdtemp", genMkdtemp }, .{ "mkstemp", genMkstemp },
    .{ "gettempdir", genGettempdir }, .{ "gettempprefix", genGettempprefix },
    .{ "NamedTemporaryFile", genNamedTemporaryFile }, .{ "TemporaryFile", genNamedTemporaryFile },
    .{ "SpooledTemporaryFile", genSpooledTemporaryFile }, .{ "TemporaryDirectory", genTemporaryDirectory },
});

fn genMktemp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :blk \"/tmp/tmpXXXXXXXX\"; break :blk _name; }");
}

fn genMkdtemp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :blk \"/tmp/tmpXXXXXXXX\"; std.fs.makeDirAbsolute(_name) catch {}; break :blk _name; }");
}

fn genMkstemp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :blk .{ @as(i64, -1), \"\" }; const _file = std.fs.createFileAbsolute(_name, .{}) catch break :blk .{ @as(i64, -1), _name }; break :blk .{ @as(i64, @intCast(_file.handle)), _name }; }");
}

fn genNamedTemporaryFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :blk struct { name: []const u8, file: ?std.fs.File }{ .name = \"\", .file = null }; const _file = std.fs.createFileAbsolute(_name, .{}) catch break :blk struct { name: []const u8, file: ?std.fs.File }{ .name = _name, .file = null }; break :blk struct { name: []const u8, file: ?std.fs.File }{ .name = _name, .file = _file }; }");
}

fn genSpooledTemporaryFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { var _buf: std.ArrayList(u8) = .{}; break :blk struct { buffer: std.ArrayList(u8), pos: usize = 0, pub fn write(__self: *@This(), data: []const u8) void { __self.buffer.appendSlice(__global_allocator, data) catch {}; } pub fn read(__self: *@This()) []const u8 { return __self.buffer.items; } pub fn seek(__self: *@This(), pos: usize) void { __self.pos = pos; } pub fn tell(__self: *@This()) usize { return __self.pos; } pub fn close(__self: *@This()) void { __self.buffer.deinit(__global_allocator); } }{ .buffer = _buf }; }");
}

fn genTemporaryDirectory(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmpdir{x:0>8}\", .{_rand.int(u32)}) catch break :blk struct { name: []const u8 }{ .name = \"\" }; std.fs.makeDirAbsolute(_name) catch {}; break :blk struct { name: []const u8, pub fn cleanup(__self: *@This()) void { std.fs.deleteTreeAbsolute(__self.name) catch {}; } pub fn __enter__(__self: *@This()) []const u8 { return __self.name; } pub fn __exit__(__self: *@This(), _: anytype) void { __self.cleanup(); } }{ .name = _name }; }");
}
