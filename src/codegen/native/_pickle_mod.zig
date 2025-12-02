/// Python _pickle module - C accelerator for pickle (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "dumps", genDumps }, .{ "dump", genUnit }, .{ "loads", genLoads }, .{ "load", genNull },
    .{ "Pickler", genPickler }, .{ "Unpickler", genEmpty }, .{ "HIGHEST_PROTOCOL", genI32_5 }, .{ "DEFAULT_PROTOCOL", genI32_4 },
    .{ "PickleError", genPickleErr }, .{ "PicklingError", genPicklingErr }, .{ "UnpicklingError", genUnpicklingErr },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 5)"); }
fn genPickler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .protocol = 4 }"); }
fn genPickleErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.PickleError"); }
fn genPicklingErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.PicklingError"); }
fn genUnpicklingErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.UnpicklingError"); }

fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const obj = "); try self.genExpr(args[0]); try self.emit("; _ = obj; break :blk \"\"; }"); } else { try self.emit("\"\""); }
}

fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const data = "); try self.genExpr(args[0]); try self.emit("; _ = data; break :blk null; }"); } else { try self.emit("null"); }
}
