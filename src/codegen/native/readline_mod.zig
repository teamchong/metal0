/// Python readline module - GNU readline interface
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "parse_and_bind", h.c("{}") }, .{ "read_init_file", h.c("{}") }, .{ "insert_text", h.c("{}") },
    .{ "redisplay", h.c("{}") }, .{ "read_history_file", h.c("{}") }, .{ "write_history_file", h.c("{}") },
    .{ "append_history_file", h.c("{}") }, .{ "set_history_length", h.c("{}") }, .{ "clear_history", h.c("{}") },
    .{ "remove_history_item", h.c("{}") }, .{ "replace_history_item", h.c("{}") }, .{ "add_history", h.c("{}") },
    .{ "set_auto_history", h.c("{}") }, .{ "set_startup_hook", h.c("{}") }, .{ "set_pre_input_hook", h.c("{}") },
    .{ "set_completer", h.c("{}") }, .{ "set_completer_delims", h.c("{}") }, .{ "set_completion_display_matches_hook", h.c("{}") },
    .{ "get_line_buffer", h.c("\"\"") }, .{ "get_history_length", h.I32(-1) },
    .{ "get_current_history_length", h.I32(0) }, .{ "get_completion_type", h.I32(0) },
    .{ "get_begidx", h.I32(0) }, .{ "get_endidx", h.I32(0) },
    .{ "get_history_item", h.c("@as(?[]const u8, null)") }, .{ "get_completer", h.c("@as(?*anyopaque, null)") },
    .{ "get_completer_delims", h.c("\" \\t\\n`~!@#$%^&*()-=+[{]}\\\\|;:'\\\",<>/?\"") },
});
