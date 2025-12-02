/// Python fileinput module - Iterate over lines from multiple input streams
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "input", genConst(".{ .files = &[_][]const u8{}, .inplace = false, .backup = \"\", .mode = \"r\" }") },
    .{ "filename", genConst("\"\"") }, .{ "fileno", genConst("@as(i32, -1)") },
    .{ "lineno", genConst("@as(i64, 0)") }, .{ "filelineno", genConst("@as(i64, 0)") },
    .{ "isfirstline", genConst("false") }, .{ "isstdin", genConst("false") }, .{ "nextfile", genConst("{}") }, .{ "close", genConst("{}") },
    .{ "FileInput", genConst(".{ .files = &[_][]const u8{}, .inplace = false, .backup = \"\", .mode = \"r\", .encoding = null, .errors = null }") },
    .{ "hook_compressed", genConst("null") }, .{ "hook_encoded", genConst("null") },
});
