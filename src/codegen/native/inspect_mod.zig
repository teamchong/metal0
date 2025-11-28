/// Python inspect module - Runtime inspection
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate inspect.isclass(object) -> bool
pub fn genIsclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.isfunction(object) -> bool
pub fn genIsfunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.ismethod(object) -> bool
pub fn genIsmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.ismodule(object) -> bool
pub fn genIsmodule(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.isbuiltin(object) -> bool
pub fn genIsbuiltin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.isroutine(object) -> bool
pub fn genIsroutine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.isabstract(object) -> bool
pub fn genIsabstract(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.isgenerator(object) -> bool
pub fn genIsgenerator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.iscoroutine(object) -> bool
pub fn genIscoroutine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.isasyncgen(object) -> bool
pub fn genIsasyncgen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.isdatadescriptor(object) -> bool
pub fn genIsdatadescriptor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.getmembers(object, predicate=None) -> list
pub fn genGetmembers(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { name: []const u8, value: []const u8 }{}");
}

/// Generate inspect.getmodule(object) -> module
pub fn genGetmodule(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate inspect.getfile(object) -> string
pub fn genGetfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"<compiled>\"");
}

/// Generate inspect.getsourcefile(object) -> string
pub fn genGetsourcefile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[]const u8, null)");
}

/// Generate inspect.getsourcelines(object) -> (lines, lineno)
pub fn genGetsourcelines(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ &[_][]const u8{}, @as(i64, 0) }");
}

/// Generate inspect.getsource(object) -> string
pub fn genGetsource(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate inspect.getdoc(object) -> string
pub fn genGetdoc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[]const u8, null)");
}

/// Generate inspect.getcomments(object) -> string
pub fn genGetcomments(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[]const u8, null)");
}

/// Generate inspect.signature(callable) -> Signature
pub fn genSignature(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("parameters: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("return_annotation: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("pub fn bind(self: @This(), args: anytype) @This() { _ = self; _ = args; return @This(){}; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate inspect.Parameter class
pub fn genParameter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: []const u8,\n");
    try self.emitIndent();
    try self.emit("kind: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("default: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("annotation: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("pub const POSITIONAL_ONLY: i64 = 0;\n");
    try self.emitIndent();
    try self.emit("pub const POSITIONAL_OR_KEYWORD: i64 = 1;\n");
    try self.emitIndent();
    try self.emit("pub const VAR_POSITIONAL: i64 = 2;\n");
    try self.emitIndent();
    try self.emit("pub const KEYWORD_ONLY: i64 = 3;\n");
    try self.emitIndent();
    try self.emit("pub const VAR_KEYWORD: i64 = 4;\n");
    try self.emitIndent();
    try self.emit("pub const empty: ?[]const u8 = null;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{ .name = \"\" }");
}

/// Generate inspect.currentframe() -> frame
pub fn genCurrentframe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate inspect.stack(context=1) -> list of FrameInfo
pub fn genStack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { frame: ?*anyopaque, filename: []const u8, lineno: i64, function: []const u8 }{}");
}

/// Generate inspect.getargspec(func) -> ArgSpec (deprecated)
pub fn genGetargspec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .args = &[_][]const u8{}, .varargs = null, .varkw = null, .defaults = null }");
}

/// Generate inspect.getfullargspec(func) -> FullArgSpec
pub fn genGetfullargspec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("args: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("varargs: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("varkw: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("defaults: ?[][]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("kwonlyargs: [][]const u8 = &[_][]const u8{},\n");
    try self.emitIndent();
    try self.emit("kwonlydefaults: ?hashmap_helper.StringHashMap([]const u8) = null,\n");
    try self.emitIndent();
    try self.emit("annotations: hashmap_helper.StringHashMap([]const u8) = hashmap_helper.StringHashMap([]const u8).init(allocator),\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate inspect.iscoroutinefunction(object) -> bool
pub fn genIscoroutinefunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.isgeneratorfunction(object) -> bool
pub fn genIsgeneratorfunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.isasyncgenfunction(object) -> bool
pub fn genIsasyncgenfunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate inspect.getattr_static(obj, attr, default=None) -> value
pub fn genGetattrStatic(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate inspect.unwrap(func) -> wrapped function
pub fn genUnwrap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}
