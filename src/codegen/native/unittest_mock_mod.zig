/// Python unittest.mock module - Mock object library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate unittest.mock.Mock class
pub fn genMock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .return_value = @as(?*anyopaque, null), .side_effect = @as(?*anyopaque, null), .called = false, .call_count = @as(i64, 0), .call_args = @as(?*anyopaque, null), .call_args_list = &[_]*anyopaque{}, .method_calls = &[_]*anyopaque{}, .mock_calls = &[_]*anyopaque{} }");
}

/// Generate unittest.mock.MagicMock class
pub fn genMagicMock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .return_value = @as(?*anyopaque, null), .side_effect = @as(?*anyopaque, null), .called = false, .call_count = @as(i64, 0), .call_args = @as(?*anyopaque, null), .call_args_list = &[_]*anyopaque{}, .method_calls = &[_]*anyopaque{}, .mock_calls = &[_]*anyopaque{} }");
}

/// Generate unittest.mock.AsyncMock class
pub fn genAsyncMock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .return_value = @as(?*anyopaque, null), .side_effect = @as(?*anyopaque, null), .called = false, .call_count = @as(i64, 0) }");
}

/// Generate unittest.mock.NonCallableMock class
pub fn genNonCallableMock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .return_value = @as(?*anyopaque, null) }");
}

/// Generate unittest.mock.NonCallableMagicMock class
pub fn genNonCallableMagicMock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .return_value = @as(?*anyopaque, null) }");
}

/// Generate unittest.mock.patch decorator
pub fn genPatch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator");
}

/// Generate unittest.mock.patch.object decorator
pub fn genPatch_object(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator");
}

/// Generate unittest.mock.patch.dict decorator
pub fn genPatch_dict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator");
}

/// Generate unittest.mock.patch.multiple decorator
pub fn genPatch_multiple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator");
}

/// Generate unittest.mock.create_autospec function
pub fn genCreate_autospec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .return_value = @as(?*anyopaque, null) }");
}

/// Generate unittest.mock.call helper
pub fn genCall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .args = &[_]*anyopaque{}, .kwargs = @as(?*anyopaque, null) }");
}

/// Generate unittest.mock.ANY sentinel
pub fn genANY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate unittest.mock.FILTER_DIR
pub fn genFILTER_DIR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate unittest.mock.sentinel
pub fn genSentinel(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate unittest.mock.DEFAULT sentinel
pub fn genDEFAULT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate unittest.mock.seal function
pub fn genSeal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate unittest.mock.PropertyMock class
pub fn genPropertyMock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .return_value = @as(?*anyopaque, null) }");
}
