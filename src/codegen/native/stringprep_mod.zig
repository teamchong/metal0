/// Python stringprep module - Internet string preparation (RFC 3454)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "in_table_a1", genFalse }, .{ "in_table_b1", genFalse },
    .{ "map_table_b2", genMapTable }, .{ "map_table_b3", genMapTable },
    .{ "in_table_c11", genFalse }, .{ "in_table_c12", genFalse }, .{ "in_table_c11_c12", genFalse },
    .{ "in_table_c21", genFalse }, .{ "in_table_c22", genFalse }, .{ "in_table_c21_c22", genFalse },
    .{ "in_table_c3", genFalse }, .{ "in_table_c4", genFalse }, .{ "in_table_c5", genFalse },
    .{ "in_table_c6", genFalse }, .{ "in_table_c7", genFalse }, .{ "in_table_c8", genFalse },
    .{ "in_table_c9", genFalse }, .{ "in_table_d1", genFalse }, .{ "in_table_d2", genFalse },
});

fn genMapTable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); }
}
