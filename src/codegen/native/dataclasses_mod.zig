/// Python dataclasses module - Data class decorators and functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate @dataclasses.dataclass decorator
pub fn genDataclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Decorator returns the class as-is (transformation is compile-time)
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("struct { _is_dataclass: bool = true }{}");
    }
}

/// Generate dataclasses.field(*, default=MISSING, default_factory=MISSING, ...) -> Field
pub fn genField(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("default: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("default_factory: ?*anyopaque = null,\n");
    try self.emitIndent();
    try self.emit("repr: bool = true,\n");
    try self.emitIndent();
    try self.emit("hash: ?bool = null,\n");
    try self.emitIndent();
    try self.emit("init: bool = true,\n");
    try self.emitIndent();
    try self.emit("compare: bool = true,\n");
    try self.emitIndent();
    try self.emit("metadata: ?hashmap_helper.StringHashMap([]const u8) = null,\n");
    try self.emitIndent();
    try self.emit("kw_only: bool = false,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate dataclasses.Field class
pub fn genFieldClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genField(self, args);
}

/// Generate dataclasses.fields(class_or_instance) -> tuple of Field objects
pub fn genFields(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { name: []const u8, type_: []const u8 }{}");
}

/// Generate dataclasses.asdict(instance, *, dict_factory=dict) -> dict
pub fn genAsdict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hashmap_helper.StringHashMap([]const u8).init(allocator)");
}

/// Generate dataclasses.astuple(instance, *, tuple_factory=tuple) -> tuple
pub fn genAstuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate dataclasses.make_dataclass(cls_name, fields, ...) -> class
pub fn genMakeDataclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { _is_dataclass: bool = true }");
}

/// Generate dataclasses.replace(instance, **changes) -> instance
pub fn genReplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("void{}");
    }
}

/// Generate dataclasses.is_dataclass(class_or_instance) -> bool
pub fn genIsDataclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate dataclasses.MISSING sentinel value
pub fn genMISSING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { _missing: bool = true }{}");
}

/// Generate dataclasses.KW_ONLY sentinel
pub fn genKW_ONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { _kw_only: bool = true }{}");
}

/// Generate dataclasses.FrozenInstanceError exception
pub fn genFrozenInstanceError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"FrozenInstanceError\"");
}
