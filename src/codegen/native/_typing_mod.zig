/// Python _typing module - Internal typing support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _typing._idfunc(x)
pub fn genIdfunc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("null");
    }
}

/// Generate _typing.TypeVar class
pub fn genTypeVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .__name__ = \"\", .__bound__ = null, .__constraints__ = &[_]type{}, .__covariant__ = false, .__contravariant__ = false }");
}

/// Generate _typing.ParamSpec class
pub fn genParamSpec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .__name__ = \"\" }");
}

/// Generate _typing.TypeVarTuple class
pub fn genTypeVarTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .__name__ = \"\" }");
}

/// Generate _typing.ParamSpecArgs class
pub fn genParamSpecArgs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .__origin__ = null }");
}

/// Generate _typing.ParamSpecKwargs class
pub fn genParamSpecKwargs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .__origin__ = null }");
}

/// Generate _typing.Generic class
pub fn genGeneric(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}
