/// Python tomllib module - Parse TOML files (Python 3.11+)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "load", genLoad }, .{ "loads", genLoads }, .{ "TOMLDecodeError", genConst("error.TOMLDecodeError") },
});

fn genLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const fp = "); try self.genExpr(args[0]); try self.emit("; _ = fp; break :blk .{}; }"); } else { try self.emit(".{}"); }
}

fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const s = "); try self.genExpr(args[0]); try self.emit("; _ = s; break :blk .{}; }"); } else { try self.emit(".{}"); }
}
