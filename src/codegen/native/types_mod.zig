/// Python types module - Standard type objects
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "FunctionType", genFunction }, .{ "LambdaType", genFunction },
    .{ "GeneratorType", genGenerator }, .{ "CoroutineType", genCoroutine_ },
    .{ "AsyncGeneratorType", genAsyncGen }, .{ "CodeType", genCode }, .{ "CellType", genCell },
    .{ "MethodType", genMethod }, .{ "BuiltinFunctionType", genBuiltin }, .{ "BuiltinMethodType", genBuiltin },
    .{ "ModuleType", genModule }, .{ "TracebackType", genTraceback }, .{ "FrameType", genFrame },
    .{ "GetSetDescriptorType", genGetsetDesc }, .{ "MemberDescriptorType", genMemberDesc },
    .{ "MappingProxyType", genMappingProxyType }, .{ "SimpleNamespace", genSimpleNamespace },
    .{ "DynamicClassAttribute", genDynamicClassAttribute },
    .{ "NoneType", genNoneType }, .{ "NotImplementedType", genNotImplementedType },
    .{ "EllipsisType", genEllipsis }, .{ "UnionType", genUnion }, .{ "GenericAlias", genGenericAlias },
    .{ "new_class", genNewClass }, .{ "resolve_bases", genResolveBases },
    .{ "prepare_class", genPrepareClass }, .{ "get_original_bases", genGetOriginalBases },
    .{ "coroutine", genCoroutine }, .{ "WrapperDescriptorType", genWrapperDesc },
    .{ "MethodWrapperType", genMethodWrapper }, .{ "ClassMethodDescriptorType", genClassMethodDesc },
    .{ "MethodDescriptorType", genMethodDesc }, .{ "CapsuleType", genCapsule },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }

// Type name constants
fn genFunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"function\""); }
fn genGenerator(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"generator\""); }
fn genCoroutine_(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"coroutine\""); }
fn genAsyncGen(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"async_generator\""); }
fn genCode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"code\""); }
fn genCell(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"cell\""); }
fn genMethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"method\""); }
fn genBuiltin(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"builtin_function_or_method\""); }
fn genModule(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"module\""); }
fn genTraceback(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"traceback\""); }
fn genFrame(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"frame\""); }
fn genGetsetDesc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"getset_descriptor\""); }
fn genMemberDesc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"member_descriptor\""); }
fn genNoneType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"NoneType\""); }
fn genNotImplementedType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"NotImplementedType\""); }
fn genEllipsis(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ellipsis\""); }
fn genUnion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"UnionType\""); }
fn genGenericAlias(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"GenericAlias\""); }
fn genWrapperDesc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"wrapper_descriptor\""); }
fn genMethodWrapper(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"method-wrapper\""); }
fn genClassMethodDesc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"classmethod_descriptor\""); }
fn genMethodDesc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"method_descriptor\""); }
fn genCapsule(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"PyCapsule\""); }
fn genNewClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"class\""); }
fn genGetOriginalBases(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genPrepareClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "hashmap_helper.StringHashMap([]const u8).init(__global_allocator)"); }
fn genDynamicClassAttribute(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { fget: ?*anyopaque = null }{}"); }

// Types with logic
fn genMappingProxyType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) try self.emit("struct { data: hashmap_helper.StringHashMap([]const u8) = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }{}")
    else try self.genExpr(args[0]);
}

fn genSimpleNamespace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { attrs: hashmap_helper.StringHashMap([]const u8) = .{}, pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.attrs.get(name); } pub fn set(__self: *@This(), name: []const u8, value: []const u8) void { __self.attrs.put(name, value) catch {}; } pub fn __repr__(__self: *@This()) []const u8 { _ = __self; return \"namespace()\"; } }{}");
}

fn genResolveBases(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) try self.emit("&[_][]const u8{}") else try self.genExpr(args[0]);
}

fn genCoroutine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) try self.emit("@as(?*anyopaque, null)") else try self.genExpr(args[0]);
}
