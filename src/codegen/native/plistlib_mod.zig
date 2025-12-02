/// Python plistlib module - Apple plist file handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "load", genConst(".{}") }, .{ "loads", genConst(".{}") }, .{ "dump", genConst("{}") }, .{ "dumps", genConst("\"\"") },
    .{ "UID", genUID }, .{ "FMT_XML", genConst("@as(i32, 1)") }, .{ "FMT_BINARY", genConst("@as(i32, 2)") },
    .{ "Dict", genConst(".{}") }, .{ "Data", genData }, .{ "InvalidFileException", genConst("error.InvalidFileException") },
    .{ "readPlist", genConst(".{}") }, .{ "writePlist", genConst("{}") }, .{ "readPlistFromBytes", genConst(".{}") }, .{ "writePlistToBytes", genConst("\"\"") },
});

fn genUID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const data = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .data = data }; }"); }
    else try self.emit(".{ .data = @as(i64, 0) }");
}

fn genData(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
