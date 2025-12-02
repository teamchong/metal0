/// Python readline module - GNU readline interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse_and_bind", genConst("{}") }, .{ "read_init_file", genConst("{}") }, .{ "insert_text", genConst("{}") },
    .{ "redisplay", genConst("{}") }, .{ "read_history_file", genConst("{}") }, .{ "write_history_file", genConst("{}") },
    .{ "append_history_file", genConst("{}") }, .{ "set_history_length", genConst("{}") }, .{ "clear_history", genConst("{}") },
    .{ "remove_history_item", genConst("{}") }, .{ "replace_history_item", genConst("{}") }, .{ "add_history", genConst("{}") },
    .{ "set_auto_history", genConst("{}") }, .{ "set_startup_hook", genConst("{}") }, .{ "set_pre_input_hook", genConst("{}") },
    .{ "set_completer", genConst("{}") }, .{ "set_completer_delims", genConst("{}") }, .{ "set_completion_display_matches_hook", genConst("{}") },
    .{ "get_line_buffer", genConst("\"\"") }, .{ "get_history_length", genConst("@as(i32, -1)") },
    .{ "get_current_history_length", genConst("@as(i32, 0)") }, .{ "get_completion_type", genConst("@as(i32, 0)") },
    .{ "get_begidx", genConst("@as(i32, 0)") }, .{ "get_endidx", genConst("@as(i32, 0)") },
    .{ "get_history_item", genConst("@as(?[]const u8, null)") }, .{ "get_completer", genConst("@as(?*anyopaque, null)") },
    .{ "get_completer_delims", genConst("\" \\t\\n`~!@#$%^&*()-=+[{]}\\\\|;:'\\\",<>/?\"") },
});
