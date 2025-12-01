/// Python types module - Standard type objects
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "FunctionType", genFunctionType },
    .{ "LambdaType", genLambdaType },
    .{ "GeneratorType", genGeneratorType },
    .{ "CoroutineType", genCoroutineType },
    .{ "AsyncGeneratorType", genAsyncGeneratorType },
    .{ "CodeType", genCodeType },
    .{ "CellType", genCellType },
    .{ "MethodType", genMethodType },
    .{ "BuiltinFunctionType", genBuiltinFunctionType },
    .{ "BuiltinMethodType", genBuiltinMethodType },
    .{ "ModuleType", genModuleType },
    .{ "TracebackType", genTracebackType },
    .{ "FrameType", genFrameType },
    .{ "GetSetDescriptorType", genGetSetDescriptorType },
    .{ "MemberDescriptorType", genMemberDescriptorType },
    .{ "MappingProxyType", genMappingProxyType },
    .{ "SimpleNamespace", genSimpleNamespace },
    .{ "DynamicClassAttribute", genDynamicClassAttribute },
    .{ "NoneType", genNoneType },
    .{ "NotImplementedType", genNotImplementedType },
    .{ "EllipsisType", genEllipsisType },
    .{ "UnionType", genUnionType },
    .{ "GenericAlias", genGenericAlias },
    .{ "new_class", genNewClass },
    .{ "resolve_bases", genResolveBases },
    .{ "prepare_class", genPrepareClass },
    .{ "get_original_bases", genGetOriginalBases },
    .{ "coroutine", genCoroutine },
    .{ "WrapperDescriptorType", genWrapperDescriptorType },
    .{ "MethodWrapperType", genMethodWrapperType },
    .{ "ClassMethodDescriptorType", genClassMethodDescriptorType },
    .{ "MethodDescriptorType", genMethodDescriptorType },
    .{ "CapsuleType", genCapsuleType },
});

/// Generate types.FunctionType constant
pub fn genFunctionType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"function\"");
}

/// Generate types.LambdaType constant
pub fn genLambdaType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"function\"");
}

/// Generate types.GeneratorType constant
pub fn genGeneratorType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"generator\"");
}

/// Generate types.CoroutineType constant
pub fn genCoroutineType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"coroutine\"");
}

/// Generate types.AsyncGeneratorType constant
pub fn genAsyncGeneratorType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"async_generator\"");
}

/// Generate types.CodeType constant
pub fn genCodeType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"code\"");
}

/// Generate types.CellType constant
pub fn genCellType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"cell\"");
}

/// Generate types.MethodType constant
pub fn genMethodType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"method\"");
}

/// Generate types.BuiltinFunctionType constant
pub fn genBuiltinFunctionType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"builtin_function_or_method\"");
}

/// Generate types.BuiltinMethodType constant
pub fn genBuiltinMethodType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"builtin_function_or_method\"");
}

/// Generate types.ModuleType constant
pub fn genModuleType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"module\"");
}

/// Generate types.TracebackType constant
pub fn genTracebackType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"traceback\"");
}

/// Generate types.FrameType constant
pub fn genFrameType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"frame\"");
}

/// Generate types.GetSetDescriptorType constant
pub fn genGetSetDescriptorType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"getset_descriptor\"");
}

/// Generate types.MemberDescriptorType constant
pub fn genMemberDescriptorType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"member_descriptor\"");
}

/// Generate types.MappingProxyType(mapping) -> mapping proxy
pub fn genMappingProxyType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("struct { data: hashmap_helper.StringHashMap([]const u8) = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }{}");
        return;
    }
    // Return the mapping as-is (simplified)
    try self.genExpr(args[0]);
}

/// Generate types.SimpleNamespace(**kwargs) -> simple namespace
pub fn genSimpleNamespace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("attrs: hashmap_helper.StringHashMap([]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn get(self: *@This(), name: []const u8) ?[]const u8 { return self.attrs.get(name); }\n");
    try self.emitIndent();
    try self.emit("pub fn set(self: *@This(), name: []const u8, value: []const u8) void { self.attrs.put(name, value) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn __repr__(self: *@This()) []const u8 { _ = self; return \"namespace()\"; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate types.DynamicClassAttribute
pub fn genDynamicClassAttribute(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { fget: ?*anyopaque = null }{}");
}

/// Generate types.NoneType constant
pub fn genNoneType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"NoneType\"");
}

/// Generate types.NotImplementedType constant
pub fn genNotImplementedType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"NotImplementedType\"");
}

/// Generate types.EllipsisType constant
pub fn genEllipsisType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ellipsis\"");
}

/// Generate types.UnionType constant
pub fn genUnionType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"UnionType\"");
}

/// Generate types.GenericAlias constant
pub fn genGenericAlias(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"GenericAlias\"");
}

/// Generate types.new_class(name, bases, kwds, exec_body) -> class
pub fn genNewClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"class\"");
        return;
    }
    try self.emit("\"class\"");
}

/// Generate types.resolve_bases(bases) -> resolved bases
pub fn genResolveBases(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("&[_][]const u8{}");
        return;
    }
    try self.genExpr(args[0]);
}

/// Generate types.prepare_class(name, bases, kwds) -> class dict
pub fn genPrepareClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)");
}

/// Generate types.get_original_bases(cls) -> bases
pub fn genGetOriginalBases(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate types.coroutine(func) -> coroutine wrapper
pub fn genCoroutine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(?*anyopaque, null)");
        return;
    }
    try self.genExpr(args[0]);
}

/// Generate types.WrapperDescriptorType constant
pub fn genWrapperDescriptorType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"wrapper_descriptor\"");
}

/// Generate types.MethodWrapperType constant
pub fn genMethodWrapperType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"method-wrapper\"");
}

/// Generate types.ClassMethodDescriptorType constant
pub fn genClassMethodDescriptorType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"classmethod_descriptor\"");
}

/// Generate types.MethodDescriptorType constant
pub fn genMethodDescriptorType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"method_descriptor\"");
}

/// Generate types.CapsuleType constant
pub fn genCapsuleType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"PyCapsule\"");
}
