/// Python _curses module - Internal curses support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "initscr", genConst(".{ .lines = 24, .cols = 80 }") }, .{ "endwin", genConst("{}") }, .{ "newwin", genConst(".{ .lines = 24, .cols = 80, .y = 0, .x = 0 }") }, .{ "newpad", genConst(".{ .lines = 24, .cols = 80 }") },
    .{ "start_color", genConst("{}") }, .{ "init_pair", genConst("{}") }, .{ "color_pair", genConst("@as(i32, 0)") },
    .{ "cbreak", genConst("{}") }, .{ "nocbreak", genConst("{}") }, .{ "echo", genConst("{}") }, .{ "noecho", genConst("{}") },
    .{ "raw", genConst("{}") }, .{ "noraw", genConst("{}") }, .{ "curs_set", genConst("@as(i32, 1)") },
    .{ "has_colors", genConst("true") }, .{ "can_change_color", genConst("true") },
    .{ "COLORS", genConst("@as(i32, 256)") }, .{ "COLOR_PAIRS", genConst("@as(i32, 256)") }, .{ "LINES", genConst("@as(i32, 24)") }, .{ "COLS", genConst("@as(i32, 80)") },
    .{ "error", genConst("error.CursesError") },
});
