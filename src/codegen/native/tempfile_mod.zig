/// Python tempfile module - temporary file operations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "mktemp", genConst("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :blk \"/tmp/tmpXXXXXXXX\"; break :blk _name; }") },
    .{ "mkdtemp", genConst("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :blk \"/tmp/tmpXXXXXXXX\"; std.fs.makeDirAbsolute(_name) catch {}; break :blk _name; }") },
    .{ "mkstemp", genConst("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :blk .{ @as(i64, -1), \"\" }; const _file = std.fs.createFileAbsolute(_name, .{}) catch break :blk .{ @as(i64, -1), _name }; break :blk .{ @as(i64, @intCast(_file.handle)), _name }; }") },
    .{ "gettempdir", genConst("\"/tmp\"") }, .{ "gettempprefix", genConst("\"tmp\"") },
    .{ "NamedTemporaryFile", genConst("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :blk struct { name: []const u8, file: ?std.fs.File }{ .name = \"\", .file = null }; const _file = std.fs.createFileAbsolute(_name, .{}) catch break :blk struct { name: []const u8, file: ?std.fs.File }{ .name = _name, .file = null }; break :blk struct { name: []const u8, file: ?std.fs.File }{ .name = _name, .file = _file }; }") },
    .{ "TemporaryFile", genConst("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp{x:0>8}\", .{_rand.int(u32)}) catch break :blk struct { name: []const u8, file: ?std.fs.File }{ .name = \"\", .file = null }; const _file = std.fs.createFileAbsolute(_name, .{}) catch break :blk struct { name: []const u8, file: ?std.fs.File }{ .name = _name, .file = null }; break :blk struct { name: []const u8, file: ?std.fs.File }{ .name = _name, .file = _file }; }") },
    .{ "SpooledTemporaryFile", genConst("blk: { var _buf: std.ArrayList(u8) = .{}; break :blk struct { buffer: std.ArrayList(u8), pos: usize = 0, pub fn write(__self: *@This(), data: []const u8) void { __self.buffer.appendSlice(__global_allocator, data) catch {}; } pub fn read(__self: *@This()) []const u8 { return __self.buffer.items; } pub fn seek(__self: *@This(), pos: usize) void { __self.pos = pos; } pub fn tell(__self: *@This()) usize { return __self.pos; } pub fn close(__self: *@This()) void { __self.buffer.deinit(__global_allocator); } }{ .buffer = _buf }; }") },
    .{ "TemporaryDirectory", genConst("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmpdir{x:0>8}\", .{_rand.int(u32)}) catch break :blk struct { name: []const u8 }{ .name = \"\" }; std.fs.makeDirAbsolute(_name) catch {}; break :blk struct { name: []const u8, pub fn cleanup(__self: *@This()) void { std.fs.deleteTreeAbsolute(__self.name) catch {}; } pub fn __enter__(__self: *@This()) []const u8 { return __self.name; } pub fn __exit__(__self: *@This(), _: anytype) void { __self.cleanup(); } }{ .name = _name }; }") },
});
