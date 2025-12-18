/// Python types module - Standard type objects
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
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
    .{ "NoneType", genNoneType },
    .{ "NotImplementedType", genNotImplementedType },
    .{ "EllipsisType", genEllipsisType },
    .{ "UnionType", genUnionType },
    .{ "GenericAlias", genGenericAlias },
    .{ "new_class", genNewClass },
    .{ "WrapperDescriptorType", genWrapperDescriptorType },
    .{ "MethodWrapperType", genMethodWrapperType },
    .{ "ClassMethodDescriptorType", genClassMethodDescriptorType },
    .{ "MethodDescriptorType", genMethodDescriptorType },
    .{ "CapsuleType", genCapsuleType },
    .{ "MappingProxyType", genMappingProxyType },
    .{ "SimpleNamespace", genSimpleNamespace },
    .{ "DynamicClassAttribute", genDynamicClassAttribute },
    .{ "resolve_bases", genResolveBases },
    .{ "prepare_class", genPrepareClass },
    .{ "get_original_bases", genGetOriginalBases },
    .{ "coroutine", genCoroutine },
});

fn genFunctionType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("function"), builder_mod.EmitConfig.forExpression());
}

fn genLambdaType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("function"), builder_mod.EmitConfig.forExpression());
}

fn genGeneratorType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("generator"), builder_mod.EmitConfig.forExpression());
}

fn genCoroutineType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("coroutine"), builder_mod.EmitConfig.forExpression());
}

fn genAsyncGeneratorType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("async_generator"), builder_mod.EmitConfig.forExpression());
}

fn genCodeType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("code"), builder_mod.EmitConfig.forExpression());
}

fn genCellType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("cell"), builder_mod.EmitConfig.forExpression());
}

fn genMethodType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("method"), builder_mod.EmitConfig.forExpression());
}

fn genBuiltinFunctionType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("builtin_function_or_method"), builder_mod.EmitConfig.forExpression());
}

fn genBuiltinMethodType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("builtin_function_or_method"), builder_mod.EmitConfig.forExpression());
}

fn genModuleType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("module"), builder_mod.EmitConfig.forExpression());
}

fn genTracebackType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("traceback"), builder_mod.EmitConfig.forExpression());
}

fn genFrameType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("frame"), builder_mod.EmitConfig.forExpression());
}

fn genGetSetDescriptorType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("getset_descriptor"), builder_mod.EmitConfig.forExpression());
}

fn genMemberDescriptorType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("member_descriptor"), builder_mod.EmitConfig.forExpression());
}

fn genNoneType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("NoneType"), builder_mod.EmitConfig.forExpression());
}

fn genNotImplementedType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("NotImplementedType"), builder_mod.EmitConfig.forExpression());
}

fn genEllipsisType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ellipsis"), builder_mod.EmitConfig.forExpression());
}

fn genUnionType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("UnionType"), builder_mod.EmitConfig.forExpression());
}

fn genGenericAlias(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("GenericAlias"), builder_mod.EmitConfig.forExpression());
}

fn genNewClass(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("class"), builder_mod.EmitConfig.forExpression());
}

fn genWrapperDescriptorType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("wrapper_descriptor"), builder_mod.EmitConfig.forExpression());
}

fn genMethodWrapperType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("method-wrapper"), builder_mod.EmitConfig.forExpression());
}

fn genClassMethodDescriptorType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("classmethod_descriptor"), builder_mod.EmitConfig.forExpression());
}

fn genMethodDescriptorType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("method_descriptor"), builder_mod.EmitConfig.forExpression());
}

fn genCapsuleType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("PyCapsule"), builder_mod.EmitConfig.forExpression());
}

fn genMappingProxyType(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("struct { data: hashmap_helper.StringHashMap([]const u8) = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genSimpleNamespace(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { attrs: hashmap_helper.StringHashMap([]const u8) = .{}, pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.attrs.get(name); } pub fn set(__self: *@This(), name: []const u8, value: []const u8) void { __self.attrs.put(name, value) catch unreachable; } pub fn __repr__(__self: *@This()) []const u8 { _ = __self; return \"namespace()\"; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genDynamicClassAttribute(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { fget: ?*anyopaque = null }{}"), builder_mod.EmitConfig.forExpression());
}

fn genResolveBases(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPrepareClass(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)"), builder_mod.EmitConfig.forExpression());
}

fn genGetOriginalBases(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genCoroutine(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
    }
}
