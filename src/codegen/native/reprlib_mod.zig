/// Python reprlib module - Alternate repr() implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Repr", genRepr }, .{ "repr", genReprFunc }, .{ "recursive_repr", genRecursiveRepr },
});

fn genRepr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .maxlevel = 6, .maxtuple = 6, .maxlist = 6, .maxarray = 5, .maxdict = 4, .maxset = 6, .maxfrozenset = 6, .maxdeque = 6, .maxstring = 30, .maxlong = 40, .maxother = 30, .fillvalue = \"...\" }"); }
fn genRecursiveRepr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*const fn(anytype) anytype, null)"); }

fn genReprFunc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const obj = "); try self.genExpr(args[0]); try self.emit("; break :blk std.fmt.allocPrint(metal0_allocator, \"{any}\", .{obj}) catch \"<repr error>\"; }"); } else try self.emit("\"\"");
}
