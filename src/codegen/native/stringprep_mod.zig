/// Python stringprep module - Internet string preparation (RFC 3454)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "in_table_a1", genConst("false") }, .{ "in_table_b1", genConst("false") },
    .{ "map_table_b2", genMapTable }, .{ "map_table_b3", genMapTable },
    .{ "in_table_c11", genConst("false") }, .{ "in_table_c12", genConst("false") }, .{ "in_table_c11_c12", genConst("false") },
    .{ "in_table_c21", genConst("false") }, .{ "in_table_c22", genConst("false") }, .{ "in_table_c21_c22", genConst("false") },
    .{ "in_table_c3", genConst("false") }, .{ "in_table_c4", genConst("false") }, .{ "in_table_c5", genConst("false") },
    .{ "in_table_c6", genConst("false") }, .{ "in_table_c7", genConst("false") }, .{ "in_table_c8", genConst("false") },
    .{ "in_table_c9", genConst("false") }, .{ "in_table_d1", genConst("false") }, .{ "in_table_d2", genConst("false") },
});

fn genMapTable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
