/// Python abc module - Abstract Base Classes
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ABC", h.c("struct { _is_abc: bool = true }{}") }, .{ "ABCMeta", h.c("\"ABCMeta\"") },
    .{ "abstractmethod", genAbstractmethod }, .{ "abstractclassmethod", genAbstractmethod },
    .{ "abstractstaticmethod", genAbstractmethod }, .{ "abstractproperty", genAbstractmethod },
    .{ "get_cache_token", h.I64(0) }, .{ "update_abstractmethods", genUpdate },
});

fn genAbstractmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("struct { _is_abstract: bool = true }{}");
}

fn genUpdate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("void{}");
}
