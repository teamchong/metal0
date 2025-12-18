/// Python unittest.mock module - Mock object library
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

const mock_full = ".{ .return_value = @as(?*anyopaque, null), .side_effect = @as(?*anyopaque, null), .called = false, .call_count = @as(i64, 0), .call_args = @as(?*anyopaque, null), .call_args_list = &[_]*anyopaque{}, .method_calls = &[_]*anyopaque{}, .mock_calls = &[_]*anyopaque{} }";
const mock_async = ".{ .return_value = @as(?*anyopaque, null), .side_effect = @as(?*anyopaque, null), .called = false, .call_count = @as(i64, 0) }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Mock", genMock },
    .{ "MagicMock", genMock },
    .{ "AsyncMock", genAsyncMock },
    .{ "NonCallableMock", genNonCallableMock },
    .{ "NonCallableMagicMock", genNonCallableMock },
    .{ "patch", genPatch },
    .{ "patch.object", genPatch },
    .{ "patch.dict", genPatch },
    .{ "patch.multiple", genPatch },
    .{ "create_autospec", genNonCallableMock },
    .{ "call", genCall },
    .{ "ANY", genAny },
    .{ "FILTER_DIR", genFilterDir },
    .{ "sentinel", genAny },
    .{ "DEFAULT", genAny },
    .{ "seal", genSeal },
    .{ "PropertyMock", genNonCallableMock },
});

fn genMock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(mock_full), builder_mod.EmitConfig.forExpression());
}

fn genAsyncMock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(mock_async), builder_mod.EmitConfig.forExpression());
}

fn genNonCallableMock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .return_value = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genPatch(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator"), builder_mod.EmitConfig.forExpression());
}

fn genCall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .args = &[_]*anyopaque{}, .kwargs = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genAny(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genFilterDir(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genSeal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}
