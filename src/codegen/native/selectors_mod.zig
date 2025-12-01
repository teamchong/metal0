/// Python selectors module - High-level I/O multiplexing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "DefaultSelector", genDefaultSelector },
    .{ "SelectSelector", genSelectSelector },
    .{ "PollSelector", genPollSelector },
    .{ "EpollSelector", genEpollSelector },
    .{ "KqueueSelector", genKqueueSelector },
    .{ "DevpollSelector", genDevpollSelector },
    .{ "EVENT_READ", genEVENT_READ },
    .{ "EVENT_WRITE", genEVENT_WRITE },
});

/// Generate selectors.DefaultSelector class
pub fn genDefaultSelector(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate selectors.SelectSelector class
pub fn genSelectSelector(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate selectors.PollSelector class
pub fn genPollSelector(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate selectors.EpollSelector class
pub fn genEpollSelector(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate selectors.DevpollSelector class
pub fn genDevpollSelector(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate selectors.KqueueSelector class
pub fn genKqueueSelector(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate selectors.BaseSelector class
pub fn genBaseSelector(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate selectors.SelectorKey named tuple
pub fn genSelectorKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .fileobj = @as(?*anyopaque, null), .fd = @as(i32, -1), .events = @as(i32, 0), .data = @as(?*anyopaque, null) }");
}

// ============================================================================
// Event constants
// ============================================================================

pub fn genEVENT_READ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genEVENT_WRITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}
