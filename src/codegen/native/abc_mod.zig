/// Python abc module - Abstract Base Classes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ABC", genABC }, .{ "ABCMeta", genABCMeta }, .{ "abstractmethod", genAbstractmethod },
    .{ "abstractclassmethod", genAbstractmethod }, .{ "abstractstaticmethod", genAbstractmethod },
    .{ "abstractproperty", genAbstractmethod }, .{ "get_cache_token", genI64_0 }, .{ "update_abstractmethods", genUpdate },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genABC(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { _is_abc: bool = true }{}"); }
fn genABCMeta(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ABCMeta\""); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }

fn genAbstractmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else try self.emit("struct { _is_abstract: bool = true }{}");
}

fn genUpdate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else try self.emit("void{}");
}
