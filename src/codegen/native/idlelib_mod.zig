/// Python idlelib module - IDLE development environment
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "idle", genConst("{}") }, .{ "py_shell", genConst(".{}") }, .{ "editor_window", genConst(".{}") },
    .{ "file_list", genConst(".{}") }, .{ "output_window", genConst(".{}") }, .{ "color_delegator", genConst(".{}") },
    .{ "undo_delegator", genConst(".{}") }, .{ "percolator", genConst(".{}") }, .{ "auto_complete", genConst(".{}") },
    .{ "auto_expand", genConst(".{}") }, .{ "call_tips", genConst(".{}") }, .{ "debugger", genConst(".{}") },
    .{ "stack_viewer", genConst(".{}") }, .{ "object_browser", genConst(".{}") }, .{ "path_browser", genConst(".{}") },
    .{ "class_browser", genConst(".{}") }, .{ "module_browser", genConst(".{}") }, .{ "search_dialog", genConst(".{}") },
    .{ "search_dialog_base", genConst(".{}") }, .{ "search_engine", genConst(".{}") }, .{ "replace_dialog", genConst(".{}") },
    .{ "grep_dialog", genConst(".{}") }, .{ "bindings", genConst(".{}") }, .{ "config_handler", genConst(".{}") },
    .{ "config_dialog", genConst(".{}") }, .{ "i_o_binding", genConst(".{}") }, .{ "multi_call", genConst(".{}") },
    .{ "widget_redirector", genConst(".{}") }, .{ "delegator", genConst(".{}") }, .{ "rpc", genConst(".{}") },
    .{ "run", genConst(".{}") }, .{ "remote_debugger", genConst(".{}") }, .{ "remote_object_browser", genConst(".{}") },
    .{ "tool_tip", genConst(".{}") }, .{ "tree_widget", genConst(".{}") }, .{ "zoom_height", genConst(".{}") },
});
