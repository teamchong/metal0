/// Python tempfile module - temporary file operations
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output - uses h.NativeCodegen from mod_helper
fn emitConst(self: *h.NativeCodegen, val: []const u8) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *h.NativeCodegen, comptime fmt: []const u8, args: anytype) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}



pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "mktemp", genMktemp },
    .{ "mkdtemp", genMkdtemp },
    .{ "mkstemp", genMkstemp },
    .{ "gettempdir", h.c("\"/tmp\"") }, .{ "gettempprefix", h.c("\"tmp\"") },
    .{ "NamedTemporaryFile", genNamedTempFile },
    .{ "TemporaryFile", genNamedTempFile },
    .{ "SpooledTemporaryFile", genSpooledTempFile },
    .{ "TemporaryDirectory", genTempDir },
});

const prng_init = "var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _buf: [64]u8 = undefined; ";

fn genMktemp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("mkt", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
            try emitConst(c, prng_init ++ "const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp");
            try emitConst(c, "{x:0>8}");
            try emitFmtConst(c, "\", .{{_rand.int(u32)}}) catch break :{s} \"/tmp/tmpXXXXXXXX\"; break :{s} _name; ", .{ label, label });
        }
    }.emit);
}

fn genMkdtemp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("mkd", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
            try emitConst(c, prng_init ++ "const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp");
            try emitConst(c, "{x:0>8}");
            try emitFmtConst(c, "\", .{{_rand.int(u32)}}) catch break :{s} \"/tmp/tmpXXXXXXXX\"; std.fs.makeDirAbsolute(_name) catch unreachable; break :{s} _name; ", .{ label, label });
        }
    }.emit);
}

fn genMkstemp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("mks", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
            try emitConst(c, prng_init ++ "const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp");
            try emitConst(c, "{x:0>8}");
            try emitFmtConst(c, "\", .{{_rand.int(u32)}}) catch break :{s} .{{ @as(i64, -1), \"\" }}; const _file = std.fs.createFileAbsolute(_name, .{{}}) catch break :{s} .{{ @as(i64, -1), _name }}; break :{s} .{{ if (comptime @import(\"builtin\").os.tag == .windows) @as(i64, @intFromPtr(_file.handle)) else @as(i64, @intCast(_file.handle)), _name }}; ", .{ label, label, label });
        }
    }.emit);
}

fn genNamedTempFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("ntf", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
            try emitConst(c, prng_init ++ "const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmp");
            try emitConst(c, "{x:0>8}");
            try emitFmtConst(c, "\", .{{_rand.int(u32)}}) catch break :{s} struct {{ name: []const u8, file: ?std.fs.File }}{{ .name = \"\", .file = null }}; const _file = std.fs.createFileAbsolute(_name, .{{}}) catch break :{s} struct {{ name: []const u8, file: ?std.fs.File }}{{ .name = _name, .file = null }}; break :{s} struct {{ name: []const u8, file: ?std.fs.File }}{{ .name = _name, .file = _file }}; ", .{ label, label, label });
        }
    }.emit);
}

fn genSpooledTempFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("stf", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
            try emitFmtConst(c, "var _buf2: std.ArrayList(u8) = .{{}}; break :{s} struct {{ buffer: std.ArrayList(u8), pos: usize = 0, pub fn write(__self: *@This(), data: []const u8) void {{ __self.buffer.appendSlice(__global_allocator, data) catch unreachable; }} pub fn read(__self: *@This()) []const u8 {{ return __self.buffer.items; }} pub fn seek(__self: *@This(), pos: usize) void {{ __self.pos = pos; }} pub fn tell(__self: *@This()) usize {{ return __self.pos; }} pub fn close(__self: *@This()) void {{ __self.buffer.deinit(__global_allocator); }} }}{{ .buffer = _buf2 }}; ", .{label});
        }
    }.emit);
}

fn genTempDir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("td", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
            try emitConst(c, prng_init ++ "const _name = std.fmt.bufPrint(&_buf, \"/tmp/tmpdir");
            try emitConst(c, "{x:0>8}");
            try emitFmtConst(c, "\", .{{_rand.int(u32)}}) catch break :{s} struct {{ name: []const u8 }}{{ .name = \"\" }}; std.fs.makeDirAbsolute(_name) catch unreachable; break :{s} struct {{ name: []const u8, pub fn cleanup(__self: *@This()) void {{ std.fs.deleteTreeAbsolute(__self.name) catch unreachable; }} pub fn __enter__(__self: *@This()) []const u8 {{ return __self.name; }} pub fn __exit__(__self: *@This(), _: anytype) void {{ __self.cleanup(); }} }}{{ .name = _name }}; ", .{ label, label });
        }
    }.emit);
}
