/// Python _curses_panel module - Internal curses panel support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "new_panel", genConst(".{ .window = null }") }, .{ "bottom_panel", genConst("null") }, .{ "top_panel", genConst("null") }, .{ "update_panels", genConst("{}") },
    .{ "above", genConst("null") }, .{ "below", genConst("null") }, .{ "bottom", genConst("{}") }, .{ "hidden", genConst("false") },
    .{ "hide", genConst("{}") }, .{ "move", genConst("{}") }, .{ "replace", genConst("{}") }, .{ "set_userptr", genConst("{}") },
    .{ "show", genConst("{}") }, .{ "top", genConst("{}") }, .{ "userptr", genConst("null") }, .{ "window", genConst("null") },
    .{ "error", genConst("error.PanelError") },
});
