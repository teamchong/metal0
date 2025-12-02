/// Python zipfile module - ZIP archive handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genI64_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 8)"); }
fn genI64_12(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 12)"); }
fn genI64_14(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 14)"); }
fn genBadZip(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"BadZipFile\""); }
fn genLargeZip(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"LargeZipFile\""); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ZipFile", genZipFile }, .{ "is_zipfile", genIsZipfile }, .{ "ZipInfo", genZipInfo },
    .{ "ZIP_STORED", genI64_0 }, .{ "ZIP_DEFLATED", genI64_8 }, .{ "ZIP_BZIP2", genI64_12 }, .{ "ZIP_LZMA", genI64_14 },
    .{ "BadZipFile", genBadZip }, .{ "LargeZipFile", genLargeZip },
});

fn genZipFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _path = "); try self.genExpr(args[0]); try self.emit("; const _mode: []const u8 = ");
    if (args.len > 1) { try self.genExpr(args[1]); } else { try self.emit("\"r\""); }
    try self.emit("; _ = _mode; break :blk struct { path: []const u8, files: std.ArrayList([]const u8), pub fn init(p: []const u8) @This() { return @This(){ .path = p, .files = .{} }; } pub fn namelist(__self: *@This()) [][]const u8 { return __self.files.items; } pub fn read(__self: *@This(), name: []const u8) []const u8 { _ = __self; _ = name; return \"\"; } pub fn write(__self: *@This(), name: []const u8, data: []const u8) void { _ = data; __self.files.append(__global_allocator, name) catch {}; } pub fn writestr(__self: *@This(), name: []const u8, data: []const u8) void { __self.write(name, data); } pub fn extractall(__self: *@This(), path: ?[]const u8) void { _ = __self; _ = path; } pub fn extract(__self: *@This(), member: []const u8, path: ?[]const u8) []const u8 { _ = __self; _ = path; return member; } pub fn close(__self: *@This()) void { _ = __self; } pub fn __enter__(__self: *@This()) *@This() { return __self; } pub fn __exit__(__self: *@This(), _: anytype) void { __self.close(); } }.init(_path); }");
}

fn genIsZipfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _path = "); try self.genExpr(args[0]); try self.emit("; const file = std.fs.cwd().openFile(_path, .{}) catch break :blk false; defer file.close(); var buf: [4]u8 = undefined; _ = file.read(&buf) catch break :blk false; break :blk std.mem.eql(u8, buf[0..4], \"PK\\x03\\x04\"); }");
}

fn genZipInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("struct { filename: []const u8 = \"\", compress_size: i64 = 0, file_size: i64 = 0 }{}"); return; }
    try self.emit("struct { filename: []const u8, compress_size: i64 = 0, file_size: i64 = 0, compress_type: i64 = 0, date_time: struct { year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64 } = .{ .year = 1980, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0 } }{ .filename = ");
    try self.genExpr(args[0]);
    try self.emit(" }");
}
