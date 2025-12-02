/// Python idlelib module - IDLE development environment
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "idle", genUnit }, .{ "py_shell", genEmpty }, .{ "editor_window", genEmpty }, .{ "file_list", genEmpty },
    .{ "output_window", genEmpty }, .{ "color_delegator", genEmpty }, .{ "undo_delegator", genEmpty },
    .{ "percolator", genEmpty }, .{ "auto_complete", genEmpty }, .{ "auto_expand", genEmpty },
    .{ "call_tips", genEmpty }, .{ "debugger", genEmpty }, .{ "stack_viewer", genEmpty },
    .{ "object_browser", genEmpty }, .{ "path_browser", genEmpty }, .{ "class_browser", genEmpty },
    .{ "module_browser", genEmpty }, .{ "search_dialog", genEmpty }, .{ "search_dialog_base", genEmpty },
    .{ "search_engine", genEmpty }, .{ "replace_dialog", genEmpty }, .{ "grep_dialog", genEmpty },
    .{ "bindings", genEmpty }, .{ "config_handler", genEmpty }, .{ "config_dialog", genEmpty },
    .{ "i_o_binding", genEmpty }, .{ "multi_call", genEmpty }, .{ "widget_redirector", genEmpty },
    .{ "delegator", genEmpty }, .{ "rpc", genEmpty }, .{ "run", genEmpty },
    .{ "remote_debugger", genEmpty }, .{ "remote_object_browser", genEmpty },
    .{ "tool_tip", genEmpty }, .{ "tree_widget", genEmpty }, .{ "zoom_height", genEmpty },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
