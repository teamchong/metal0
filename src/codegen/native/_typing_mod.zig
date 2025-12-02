/// Python _typing module - Internal typing support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "_idfunc", genIdfunc },
    .{ "TypeVar", genConst(".{ .__name__ = \"\", .__bound__ = null, .__constraints__ = &[_]type{}, .__covariant__ = false, .__contravariant__ = false }") },
    .{ "ParamSpec", genConst(".{ .__name__ = \"\" }") }, .{ "TypeVarTuple", genConst(".{ .__name__ = \"\" }") },
    .{ "ParamSpecArgs", genConst(".{ .__origin__ = null }") }, .{ "ParamSpecKwargs", genConst(".{ .__origin__ = null }") },
    .{ "Generic", genConst(".{}") },
});

fn genIdfunc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("null"); }
}
