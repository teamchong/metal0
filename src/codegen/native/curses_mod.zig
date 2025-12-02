/// Python curses module - Terminal handling for character-cell displays
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    // Window/screen
    .{ "initscr", genConst("@as(?*anyopaque, null)") }, .{ "endwin", genConst("{}") }, .{ "newwin", genConst("@as(?*anyopaque, null)") }, .{ "newpad", genConst("@as(?*anyopaque, null)") },
    // Modes
    .{ "cbreak", genConst("{}") }, .{ "nocbreak", genConst("{}") }, .{ "echo", genConst("{}") }, .{ "noecho", genConst("{}") }, .{ "raw", genConst("{}") }, .{ "noraw", genConst("{}") },
    // Colors
    .{ "start_color", genConst("{}") }, .{ "has_colors", genConst("true") }, .{ "can_change_color", genConst("true") },
    .{ "init_pair", genConst("{}") }, .{ "init_color", genConst("{}") }, .{ "color_pair", genColorPair }, .{ "pair_number", genPairNumber },
    // Input
    .{ "getch", genConst("@as(i32, -1)") }, .{ "getkey", genConst("\"\"") }, .{ "ungetch", genConst("{}") }, .{ "getstr", genConst("\"\"") },
    // Output
    .{ "addch", genConst("{}") }, .{ "addstr", genConst("{}") }, .{ "addnstr", genConst("{}") }, .{ "mvaddch", genConst("{}") }, .{ "mvaddstr", genConst("{}") },
    // Cursor/screen
    .{ "move", genConst("{}") }, .{ "refresh", genConst("{}") }, .{ "clear", genConst("{}") }, .{ "erase", genConst("{}") },
    .{ "clrtoeol", genConst("{}") }, .{ "clrtobot", genConst("{}") }, .{ "curs_set", genConst("@as(i32, 0)") },
    // Size
    .{ "getmaxyx", genConst(".{ @as(i32, 24), @as(i32, 80) }") }, .{ "getyx", genConst(".{ @as(i32, 0), @as(i32, 0) }") }, .{ "LINES", genConst("@as(i32, 24)") }, .{ "COLS", genConst("@as(i32, 80)") },
    // Attributes
    .{ "attron", genConst("{}") }, .{ "attroff", genConst("{}") }, .{ "attrset", genConst("{}") },
    // Color constants (0-7)
    .{ "COLOR_BLACK", genConst("@as(i32, 0)") }, .{ "COLOR_RED", genConst("@as(i32, 1)") }, .{ "COLOR_GREEN", genConst("@as(i32, 2)") }, .{ "COLOR_YELLOW", genConst("@as(i32, 3)") },
    .{ "COLOR_BLUE", genConst("@as(i32, 4)") }, .{ "COLOR_MAGENTA", genConst("@as(i32, 5)") }, .{ "COLOR_CYAN", genConst("@as(i32, 6)") }, .{ "COLOR_WHITE", genConst("@as(i32, 7)") },
    // Attr constants
    .{ "A_NORMAL", genConst("@as(i32, 0)") }, .{ "A_STANDOUT", genConst("@as(i32, 0x10000)") }, .{ "A_UNDERLINE", genConst("@as(i32, 0x20000)") },
    .{ "A_REVERSE", genConst("@as(i32, 0x40000)") }, .{ "A_BLINK", genConst("@as(i32, 0x80000)") }, .{ "A_DIM", genConst("@as(i32, 0x100000)") },
    .{ "A_BOLD", genConst("@as(i32, 0x200000)") }, .{ "A_PROTECT", genConst("@as(i32, 0x400000)") }, .{ "A_INVIS", genConst("@as(i32, 0x800000)") }, .{ "A_ALTCHARSET", genConst("@as(i32, 0x1000000)") },
    // Keys
    .{ "KEY_UP", genConst("@as(i32, 259)") }, .{ "KEY_DOWN", genConst("@as(i32, 258)") }, .{ "KEY_LEFT", genConst("@as(i32, 260)") }, .{ "KEY_RIGHT", genConst("@as(i32, 261)") },
    .{ "KEY_HOME", genConst("@as(i32, 262)") }, .{ "KEY_END", genConst("@as(i32, 360)") }, .{ "KEY_NPAGE", genConst("@as(i32, 338)") }, .{ "KEY_PPAGE", genConst("@as(i32, 339)") },
    .{ "KEY_BACKSPACE", genConst("@as(i32, 263)") }, .{ "KEY_DC", genConst("@as(i32, 330)") }, .{ "KEY_IC", genConst("@as(i32, 331)") }, .{ "KEY_ENTER", genConst("@as(i32, 343)") },
    .{ "KEY_F1", genConst("@as(i32, 265)") }, .{ "KEY_F2", genConst("@as(i32, 266)") }, .{ "KEY_F3", genConst("@as(i32, 267)") }, .{ "KEY_F4", genConst("@as(i32, 268)") },
    .{ "KEY_F5", genConst("@as(i32, 269)") }, .{ "KEY_F6", genConst("@as(i32, 270)") }, .{ "KEY_F7", genConst("@as(i32, 271)") }, .{ "KEY_F8", genConst("@as(i32, 272)") },
    .{ "KEY_F9", genConst("@as(i32, 273)") }, .{ "KEY_F10", genConst("@as(i32, 274)") }, .{ "KEY_F11", genConst("@as(i32, 275)") }, .{ "KEY_F12", genConst("@as(i32, 276)") },
    // Misc
    .{ "beep", genConst("{}") }, .{ "flash", genConst("{}") }, .{ "napms", genConst("{}") }, .{ "wrapper", genConst("{}") },
    .{ "use_default_colors", genConst("{}") }, .{ "keypad", genConst("{}") }, .{ "nodelay", genConst("{}") }, .{ "halfdelay", genConst("{}") }, .{ "timeout", genConst("{}") },
});

fn genColorPair(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("(@as(i32, "); try self.genExpr(args[0]); try self.emit(") << 8)"); } else try self.emit("@as(i32, 0)"); }
fn genPairNumber(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("((@as(i32, "); try self.genExpr(args[0]); try self.emit(") >> 8) & 0xFF)"); } else try self.emit("@as(i32, 0)"); }
