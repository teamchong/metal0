/// Python readline module - GNU readline interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse_and_bind", genUnit }, .{ "read_init_file", genUnit }, .{ "insert_text", genUnit },
    .{ "redisplay", genUnit }, .{ "read_history_file", genUnit }, .{ "write_history_file", genUnit },
    .{ "append_history_file", genUnit }, .{ "set_history_length", genUnit }, .{ "clear_history", genUnit },
    .{ "remove_history_item", genUnit }, .{ "replace_history_item", genUnit }, .{ "add_history", genUnit },
    .{ "set_auto_history", genUnit }, .{ "set_startup_hook", genUnit }, .{ "set_pre_input_hook", genUnit },
    .{ "set_completer", genUnit }, .{ "set_completer_delims", genUnit }, .{ "set_completion_display_matches_hook", genUnit },
    .{ "get_line_buffer", genEmptyStr }, .{ "get_history_length", genI32Neg1 },
    .{ "get_current_history_length", genI32_0 }, .{ "get_completion_type", genI32_0 },
    .{ "get_begidx", genI32_0 }, .{ "get_endidx", genI32_0 },
    .{ "get_history_item", genNullStr }, .{ "get_completer", genNullPtr },
    .{ "get_completer_delims", genDelims },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32Neg1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, -1)"); }
fn genNullStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?[]const u8, null)"); }
fn genNullPtr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genDelims(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\" \\t\\n`~!@#$%^&*()-=+[{]}\\\\|;:'\\\",<>/?\""); }
