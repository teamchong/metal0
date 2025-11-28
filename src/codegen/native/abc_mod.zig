/// Python abc module - Abstract Base Classes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate abc.ABC - Abstract Base Class base
pub fn genABC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("// Abstract Base Class marker\n");
    try self.emitIndent();
    try self.emit("_is_abc: bool = true,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate abc.ABCMeta - Metaclass for ABC
pub fn genABCMeta(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ABCMeta\"");
}

/// Generate abc.abstractmethod decorator
pub fn genAbstractmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Decorator returns the function as-is (marking is compile-time only)
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("struct { _is_abstract: bool = true }{}");
    }
}

/// Generate abc.abstractclassmethod decorator (deprecated)
pub fn genAbstractclassmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genAbstractmethod(self, args);
}

/// Generate abc.abstractstaticmethod decorator (deprecated)
pub fn genAbstractstaticmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genAbstractmethod(self, args);
}

/// Generate abc.abstractproperty decorator (deprecated)
pub fn genAbstractproperty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genAbstractmethod(self, args);
}

/// Generate abc.get_cache_token() -> int
pub fn genGetCacheToken(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate abc.update_abstractmethods(cls) -> cls
pub fn genUpdateAbstractmethods(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("void{}");
    }
}
