/// Python types module - Standard type objects
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "FunctionType", h.c("\"function\"") }, .{ "LambdaType", h.c("\"function\"") },
    .{ "GeneratorType", h.c("\"generator\"") }, .{ "CoroutineType", h.c("\"coroutine\"") },
    .{ "AsyncGeneratorType", h.c("\"async_generator\"") }, .{ "CodeType", h.c("\"code\"") }, .{ "CellType", h.c("\"cell\"") },
    .{ "MethodType", h.c("\"method\"") }, .{ "BuiltinFunctionType", h.c("\"builtin_function_or_method\"") },
    .{ "BuiltinMethodType", h.c("\"builtin_function_or_method\"") }, .{ "ModuleType", h.c("\"module\"") },
    .{ "TracebackType", h.c("\"traceback\"") }, .{ "FrameType", h.c("\"frame\"") },
    .{ "GetSetDescriptorType", h.c("\"getset_descriptor\"") }, .{ "MemberDescriptorType", h.c("\"member_descriptor\"") },
    .{ "NoneType", h.c("\"NoneType\"") }, .{ "NotImplementedType", h.c("\"NotImplementedType\"") },
    .{ "EllipsisType", h.c("\"ellipsis\"") }, .{ "UnionType", h.c("\"UnionType\"") }, .{ "GenericAlias", h.c("\"GenericAlias\"") },
    .{ "new_class", h.c("\"class\"") }, .{ "WrapperDescriptorType", h.c("\"wrapper_descriptor\"") },
    .{ "MethodWrapperType", h.c("\"method-wrapper\"") }, .{ "ClassMethodDescriptorType", h.c("\"classmethod_descriptor\"") },
    .{ "MethodDescriptorType", h.c("\"method_descriptor\"") }, .{ "CapsuleType", h.c("\"PyCapsule\"") },
    .{ "MappingProxyType", genMappingProxyType }, .{ "SimpleNamespace", h.c("struct { attrs: hashmap_helper.StringHashMap([]const u8) = .{}, pub fn get(__self: *@This(), name: []const u8) ?[]const u8 { return __self.attrs.get(name); } pub fn set(__self: *@This(), name: []const u8, value: []const u8) void { __self.attrs.put(name, value) catch {}; } pub fn __repr__(__self: *@This()) []const u8 { _ = __self; return \"namespace()\"; } }{}") },
    .{ "DynamicClassAttribute", h.c("struct { fget: ?*anyopaque = null }{}") },
    .{ "resolve_bases", genResolveBases }, .{ "prepare_class", h.c("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)") },
    .{ "get_original_bases", h.c("&[_][]const u8{}") }, .{ "coroutine", genCoroutine },
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
