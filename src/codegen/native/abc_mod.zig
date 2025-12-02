/// Python abc module - Abstract Base Classes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ABC", genConst("struct { _is_abc: bool = true }{}") }, .{ "ABCMeta", genConst("\"ABCMeta\"") },
    .{ "abstractmethod", genAbstractmethod }, .{ "abstractclassmethod", genAbstractmethod },
    .{ "abstractstaticmethod", genAbstractmethod }, .{ "abstractproperty", genAbstractmethod },
    .{ "get_cache_token", genConst("@as(i64, 0)") }, .{ "update_abstractmethods", genUpdate },
});

fn genAbstractmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("struct { _is_abstract: bool = true }{}");
}

fn genUpdate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("void{}");
}
