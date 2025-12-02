/// Python _pickle module - C accelerator for pickle (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "dumps", genDumps }, .{ "dump", genConst("{}") }, .{ "loads", genLoads }, .{ "load", genConst("null") },
    .{ "Pickler", genConst(".{ .protocol = 4 }") }, .{ "Unpickler", genConst(".{}") }, .{ "HIGHEST_PROTOCOL", genConst("@as(i32, 5)") }, .{ "DEFAULT_PROTOCOL", genConst("@as(i32, 4)") },
    .{ "PickleError", genConst("error.PickleError") }, .{ "PicklingError", genConst("error.PicklingError") }, .{ "UnpicklingError", genConst("error.UnpicklingError") },
});

fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const obj = "); try self.genExpr(args[0]); try self.emit("; _ = obj; break :blk \"\"; }"); } else { try self.emit("\"\""); }
}

fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const data = "); try self.genExpr(args[0]); try self.emit("; _ = data; break :blk null; }"); } else { try self.emit("null"); }
}
