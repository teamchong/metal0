/// Python unittest.mock module - Mock object library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

const mock_full = ".{ .return_value = @as(?*anyopaque, null), .side_effect = @as(?*anyopaque, null), .called = false, .call_count = @as(i64, 0), .call_args = @as(?*anyopaque, null), .call_args_list = &[_]*anyopaque{}, .method_calls = &[_]*anyopaque{}, .mock_calls = &[_]*anyopaque{} }";
const mock_async = ".{ .return_value = @as(?*anyopaque, null), .side_effect = @as(?*anyopaque, null), .called = false, .call_count = @as(i64, 0) }";

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Mock", genConst(mock_full) }, .{ "MagicMock", genConst(mock_full) }, .{ "AsyncMock", genConst(mock_async) },
    .{ "NonCallableMock", genConst(".{ .return_value = @as(?*anyopaque, null) }") }, .{ "NonCallableMagicMock", genConst(".{ .return_value = @as(?*anyopaque, null) }") },
    .{ "patch", genConst("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator") },
    .{ "patch.object", genConst("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator") },
    .{ "patch.dict", genConst("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator") },
    .{ "patch.multiple", genConst("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator") },
    .{ "create_autospec", genConst(".{ .return_value = @as(?*anyopaque, null) }") },
    .{ "call", genConst(".{ .args = &[_]*anyopaque{}, .kwargs = @as(?*anyopaque, null) }") },
    .{ "ANY", genConst(".{}") }, .{ "FILTER_DIR", genConst("true") }, .{ "sentinel", genConst(".{}") },
    .{ "DEFAULT", genConst(".{}") }, .{ "seal", genConst("{}") }, .{ "PropertyMock", genConst(".{ .return_value = @as(?*anyopaque, null) }") },
});
