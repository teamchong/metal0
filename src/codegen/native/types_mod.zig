/// Python types module - Standard type objects
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "FunctionType", genConst("\"function\"") }, .{ "LambdaType", genConst("\"function\"") },
    .{ "GeneratorType", genConst("\"generator\"") }, .{ "CoroutineType", genConst("\"coroutine\"") },
    .{ "AsyncGeneratorType", genConst("\"async_generator\"") }, .{ "CodeType", genConst("\"code\"") }, .{ "CellType", genConst("\"cell\"") },
    .{ "MethodType", genConst("\"method\"") }, .{ "BuiltinFunctionType", genConst("\"builtin_function_or_method\"") },
    .{ "BuiltinMethodType", genConst("\"builtin_function_or_method\"") }, .{ "ModuleType", genConst("\"module\"") },
    .{ "TracebackType", genConst("\"traceback\"") }, .{ "FrameType", genConst("\"frame\"") },
    .{ "GetSetDescriptorType", genConst("\"getset_descriptor\"") }, .{ "MemberDescriptorType", genConst("\"member_descriptor\"") },
    .{ "NoneType", genConst("\"NoneType\"") }, .{ "NotImplementedType", genConst("\"NotImplementedType\"") },
    .{ "EllipsisType", genConst("\"ellipsis\"") }, .{ "UnionType", genConst("\"UnionType\"") }, .{ "GenericAlias", genConst("\"GenericAlias\"") },
    .{ "new_class", genConst("\"class\"") }, .{ "WrapperDescriptorType", genConst("\"wrapper_descriptor\"") },
    .{ "MethodWrapperType", genConst("\"method-wrapper\"") }, .{ "ClassMethodDescriptorType", genConst("\"classmethod_descriptor\"") },
    .{ "MethodDescriptorType", genConst("\"method_descriptor\"") }, .{ "CapsuleType", genConst("\"PyCapsule\"") },
    .{ "MappingProxyType", genMappingProxyType }, .{ "SimpleNamespace", genConst("struct { attrs: hashmap_helper.StringHashMap([]const u8) = .{}, pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.attrs.get(name); } pub fn set(__self: *@This(), name: []const u8, value: []const u8) void { __self.attrs.put(name, value) catch {}; } pub fn __repr__(__self: *@This()) []const u8 { _ = __self; return \"namespace()\"; } }{}") },
    .{ "DynamicClassAttribute", genConst("struct { fget: ?*anyopaque = null }{}") },
    .{ "resolve_bases", genResolveBases }, .{ "prepare_class", genConst("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)") },
    .{ "get_original_bases", genConst("&[_][]const u8{}") }, .{ "coroutine", genCoroutine },
});

fn genMappingProxyType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) try self.emit("struct { data: hashmap_helper.StringHashMap([]const u8) = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }{}")
    else try self.genExpr(args[0]);
}

fn genResolveBases(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) try self.emit("&[_][]const u8{}") else try self.genExpr(args[0]);
}

fn genCoroutine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) try self.emit("@as(?*anyopaque, null)") else try self.genExpr(args[0]);
}
