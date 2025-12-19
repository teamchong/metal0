/// Python zipfile module - ZIP archive handling
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");

const zipInfoStruct = "struct { filename: []const u8, compress_size: i64 = 0, file_size: i64 = 0, compress_type: i64 = 0, date_time: struct { year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64 } = .{ .year = 1980, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0 } }{ .filename = ";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ZipFile", genZipFile },
    .{ "is_zipfile", genIsZipfile },
    .{ "ZipInfo", h.wrap(zipInfoStruct, " }", "struct { filename: []const u8 = \"\", compress_size: i64 = 0, file_size: i64 = 0 }{}") },
    .{ "ZIP_STORED", h.I64(0) }, .{ "ZIP_DEFLATED", h.I64(8) },
    .{ "ZIP_BZIP2", h.I64(12) }, .{ "ZIP_LZMA", h.I64(14) },
    .{ "BadZipFile", h.c("\"BadZipFile\"") }, .{ "LargeZipFile", h.c("\"LargeZipFile\"") },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genZipFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 2) {
        try b.write("undefined");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("zf", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b2 = try c.getBuilder();
            try b2.write("const _path = ");
            const output1 = b2.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b3 = try c.getBuilder();
                try b3.write("; const _mode: []const u8 = ");
                const output2 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; _ = _mode; break :{s} struct {{ path: []const u8, files: std.ArrayList([]const u8), pub fn init(p: []const u8) @This() {{ return @This(){{ .path = p, .files = .{{}} }}; }} pub fn namelist(__self: *@This()) [][]const u8 {{ return __self.files.items; }} pub fn read(__self: *@This(), name: []const u8) []const u8 {{ _ = __self; _ = name; return \"\"; }} pub fn write(__self: *@This(), name: []const u8, data: []const u8) void {{ _ = data; __self.files.append(__global_allocator, name) catch unreachable; }} pub fn writestr(__self: *@This(), name: []const u8, data: []const u8) void {{ __self.write(name, data); }} pub fn extractall(__self: *@This(), path: ?[]const u8) void {{ _ = __self; _ = path; }} pub fn extract(__self: *@This(), member: []const u8, path: ?[]const u8) []const u8 {{ _ = __self; _ = path; return member; }} pub fn close(__self: *@This()) void {{ _ = __self; }} pub fn __enter__(__self: *@This()) *@This() {{ return __self; }} pub fn __exit__(__self: *@This(), _: anytype) void {{ __self.close(); }} }}.init(_path)", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

fn genIsZipfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.write("false");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("izf", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b2 = try c.getBuilder();
            try b2.write("const _path = ");
            const output1 = b2.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; const file = std.fs.cwd().openFile(_path, .{{}}) catch break :{s} false; defer file.close(); var buf: [4]u8 = undefined; _ = file.read(&buf) catch break :{s} false; break :{s} std.mem.eql(u8, buf[0..4], \"PK\\x03\\x04\")", .{ label, label, label });
                const output2 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}
