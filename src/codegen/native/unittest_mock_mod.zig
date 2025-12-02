/// Python unittest.mock module - Mock object library
const std = @import("std");
const h = @import("mod_helper.zig");

const mock_full = ".{ .return_value = @as(?*anyopaque, null), .side_effect = @as(?*anyopaque, null), .called = false, .call_count = @as(i64, 0), .call_args = @as(?*anyopaque, null), .call_args_list = &[_]*anyopaque{}, .method_calls = &[_]*anyopaque{}, .mock_calls = &[_]*anyopaque{} }";
const mock_async = ".{ .return_value = @as(?*anyopaque, null), .side_effect = @as(?*anyopaque, null), .called = false, .call_count = @as(i64, 0) }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Mock", h.c(mock_full) }, .{ "MagicMock", h.c(mock_full) }, .{ "AsyncMock", h.c(mock_async) },
    .{ "NonCallableMock", h.c(".{ .return_value = @as(?*anyopaque, null) }") }, .{ "NonCallableMagicMock", h.c(".{ .return_value = @as(?*anyopaque, null) }") },
    .{ "patch", h.c("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator") },
    .{ "patch.object", h.c("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator") },
    .{ "patch.dict", h.c("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator") },
    .{ "patch.multiple", h.c("struct { fn decorator(func: anytype) @TypeOf(func) { return func; } }.decorator") },
    .{ "create_autospec", h.c(".{ .return_value = @as(?*anyopaque, null) }") },
    .{ "call", h.c(".{ .args = &[_]*anyopaque{}, .kwargs = @as(?*anyopaque, null) }") },
    .{ "ANY", h.c(".{}") }, .{ "FILTER_DIR", h.c("true") }, .{ "sentinel", h.c(".{}") },
    .{ "DEFAULT", h.c(".{}") }, .{ "seal", h.c("{}") }, .{ "PropertyMock", h.c(".{ .return_value = @as(?*anyopaque, null) }") },
});
