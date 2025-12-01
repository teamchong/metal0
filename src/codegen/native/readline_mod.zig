/// Python readline module - GNU readline interface
const std = @import("std");
const ast = @import("ast");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse_and_bind", genParse_and_bind },
    .{ "read_init_file", genRead_init_file },
    .{ "get_line_buffer", genGet_line_buffer },
    .{ "insert_text", genInsert_text },
    .{ "redisplay", genRedisplay },
    .{ "read_history_file", genRead_history_file },
    .{ "write_history_file", genWrite_history_file },
    .{ "append_history_file", genAppend_history_file },
    .{ "get_history_length", genGet_history_length },
    .{ "set_history_length", genSet_history_length },
    .{ "clear_history", genClear_history },
    .{ "get_current_history_length", genGet_current_history_length },
    .{ "get_history_item", genGet_history_item },
    .{ "remove_history_item", genRemove_history_item },
    .{ "replace_history_item", genReplace_history_item },
    .{ "add_history", genAdd_history },
    .{ "set_auto_history", genSet_auto_history },
    .{ "set_startup_hook", genSet_startup_hook },
    .{ "set_pre_input_hook", genSet_pre_input_hook },
    .{ "set_completer", genSet_completer },
    .{ "get_completer", genGet_completer },
    .{ "get_completion_type", genGet_completion_type },
    .{ "get_begidx", genGet_begidx },
    .{ "get_endidx", genGet_endidx },
    .{ "set_completer_delims", genSet_completer_delims },
    .{ "get_completer_delims", genGet_completer_delims },
    .{ "set_completion_display_matches_hook", genSet_completion_display_matches_hook },
});
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate readline.parse_and_bind(string)
pub fn genParse_and_bind(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.read_init_file(filename=None)
pub fn genRead_init_file(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.get_line_buffer()
pub fn genGet_line_buffer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate readline.insert_text(string)
pub fn genInsert_text(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.redisplay()
pub fn genRedisplay(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.read_history_file(filename=None)
pub fn genRead_history_file(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.write_history_file(filename=None)
pub fn genWrite_history_file(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.append_history_file(nelements, filename=None)
pub fn genAppend_history_file(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.get_history_length()
pub fn genGet_history_length(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -1)");
}

/// Generate readline.set_history_length(length)
pub fn genSet_history_length(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.clear_history()
pub fn genClear_history(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.get_current_history_length()
pub fn genGet_current_history_length(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate readline.get_history_item(index)
pub fn genGet_history_item(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[]const u8, null)");
}

/// Generate readline.remove_history_item(pos)
pub fn genRemove_history_item(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.replace_history_item(pos, line)
pub fn genReplace_history_item(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.add_history(line)
pub fn genAdd_history(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.set_auto_history(enabled)
pub fn genSet_auto_history(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.set_startup_hook(function=None)
pub fn genSet_startup_hook(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.set_pre_input_hook(function=None)
pub fn genSet_pre_input_hook(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.set_completer(function=None)
pub fn genSet_completer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.get_completer()
pub fn genGet_completer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate readline.get_completion_type()
pub fn genGet_completion_type(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate readline.get_begidx()
pub fn genGet_begidx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate readline.get_endidx()
pub fn genGet_endidx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate readline.set_completer_delims(string)
pub fn genSet_completer_delims(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate readline.get_completer_delims()
pub fn genGet_completer_delims(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\" \\t\\n`~!@#$%^&*()-=+[{]}\\\\|;:'\\\",<>/?\"");
}

/// Generate readline.set_completion_display_matches_hook(function=None)
pub fn genSet_completion_display_matches_hook(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}
