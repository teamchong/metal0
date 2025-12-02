/// Python idlelib module - IDLE development environment
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "idle", h.c("{}") }, .{ "py_shell", h.c(".{}") }, .{ "editor_window", h.c(".{}") },
    .{ "file_list", h.c(".{}") }, .{ "output_window", h.c(".{}") }, .{ "color_delegator", h.c(".{}") },
    .{ "undo_delegator", h.c(".{}") }, .{ "percolator", h.c(".{}") }, .{ "auto_complete", h.c(".{}") },
    .{ "auto_expand", h.c(".{}") }, .{ "call_tips", h.c(".{}") }, .{ "debugger", h.c(".{}") },
    .{ "stack_viewer", h.c(".{}") }, .{ "object_browser", h.c(".{}") }, .{ "path_browser", h.c(".{}") },
    .{ "class_browser", h.c(".{}") }, .{ "module_browser", h.c(".{}") }, .{ "search_dialog", h.c(".{}") },
    .{ "search_dialog_base", h.c(".{}") }, .{ "search_engine", h.c(".{}") }, .{ "replace_dialog", h.c(".{}") },
    .{ "grep_dialog", h.c(".{}") }, .{ "bindings", h.c(".{}") }, .{ "config_handler", h.c(".{}") },
    .{ "config_dialog", h.c(".{}") }, .{ "i_o_binding", h.c(".{}") }, .{ "multi_call", h.c(".{}") },
    .{ "widget_redirector", h.c(".{}") }, .{ "delegator", h.c(".{}") }, .{ "rpc", h.c(".{}") },
    .{ "run", h.c(".{}") }, .{ "remote_debugger", h.c(".{}") }, .{ "remote_object_browser", h.c(".{}") },
    .{ "tool_tip", h.c(".{}") }, .{ "tree_widget", h.c(".{}") }, .{ "zoom_height", h.c(".{}") },
});
