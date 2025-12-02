/// Python unittest.mock module - Mock object library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genPassDecorator(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator"); }
fn genReturnNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .return_value = @as(?*anyopaque, null) }"); }

const mock_full = ".{ .return_value = @as(?*anyopaque, null), .side_effect = @as(?*anyopaque, null), .called = false, .call_count = @as(i64, 0), .call_args = @as(?*anyopaque, null), .call_args_list = &[_]*anyopaque{}, .method_calls = &[_]*anyopaque{}, .mock_calls = &[_]*anyopaque{} }";
const mock_async = ".{ .return_value = @as(?*anyopaque, null), .side_effect = @as(?*anyopaque, null), .called = false, .call_count = @as(i64, 0) }";
fn genMock(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, mock_full); }
fn genAsyncMock(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, mock_async); }
fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .args = &[_]*anyopaque{}, .kwargs = @as(?*anyopaque, null) }"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Mock", genMock }, .{ "MagicMock", genMock }, .{ "AsyncMock", genAsyncMock },
    .{ "NonCallableMock", genReturnNull }, .{ "NonCallableMagicMock", genReturnNull },
    .{ "patch", genPassDecorator }, .{ "patch.object", genPassDecorator },
    .{ "patch.dict", genPassDecorator }, .{ "patch.multiple", genPassDecorator },
    .{ "create_autospec", genReturnNull }, .{ "call", genCall },
    .{ "ANY", genEmpty }, .{ "FILTER_DIR", genTrue }, .{ "sentinel", genEmpty },
    .{ "DEFAULT", genEmpty }, .{ "seal", genUnit }, .{ "PropertyMock", genReturnNull },
});
