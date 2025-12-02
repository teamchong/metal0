/// Python _typing module - Internal typing support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "_idfunc", genIdfunc }, .{ "TypeVar", genTypeVar }, .{ "ParamSpec", genName }, .{ "TypeVarTuple", genName },
    .{ "ParamSpecArgs", genOrigin }, .{ "ParamSpecKwargs", genOrigin }, .{ "Generic", genEmpty },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genName(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .__name__ = \"\" }"); }
fn genOrigin(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .__origin__ = null }"); }
fn genTypeVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .__name__ = \"\", .__bound__ = null, .__constraints__ = &[_]type{}, .__covariant__ = false, .__contravariant__ = false }"); }
fn genIdfunc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("null"); } }
