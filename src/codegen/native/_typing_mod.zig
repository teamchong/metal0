/// Python _typing module - Internal typing support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "_idfunc", genIdfunc },
    .{ "TypeVar", h.c(".{ .__name__ = \"\", .__bound__ = null, .__constraints__ = &[_]type{}, .__covariant__ = false, .__contravariant__ = false }") },
    .{ "ParamSpec", h.c(".{ .__name__ = \"\" }") }, .{ "TypeVarTuple", h.c(".{ .__name__ = \"\" }") },
    .{ "ParamSpecArgs", h.c(".{ .__origin__ = null }") }, .{ "ParamSpecKwargs", h.c(".{ .__origin__ = null }") },
    .{ "Generic", h.c(".{}") },
});

fn genIdfunc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("null"); }
}
