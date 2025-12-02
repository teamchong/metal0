/// Python curses module - Terminal handling for character-cell displays
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Window/screen
    .{ "initscr", h.c("@as(?*anyopaque, null)") }, .{ "endwin", h.c("{}") }, .{ "newwin", h.c("@as(?*anyopaque, null)") }, .{ "newpad", h.c("@as(?*anyopaque, null)") },
    // Modes
    .{ "cbreak", h.c("{}") }, .{ "nocbreak", h.c("{}") }, .{ "echo", h.c("{}") }, .{ "noecho", h.c("{}") }, .{ "raw", h.c("{}") }, .{ "noraw", h.c("{}") },
    // Colors
    .{ "start_color", h.c("{}") }, .{ "has_colors", h.c("true") }, .{ "can_change_color", h.c("true") },
    .{ "init_pair", h.c("{}") }, .{ "init_color", h.c("{}") }, .{ "color_pair", genColorPair }, .{ "pair_number", genPairNumber },
    // Input
    .{ "getch", h.I32(-1) }, .{ "getkey", h.c("\"\"") }, .{ "ungetch", h.c("{}") }, .{ "getstr", h.c("\"\"") },
    // Output
    .{ "addch", h.c("{}") }, .{ "addstr", h.c("{}") }, .{ "addnstr", h.c("{}") }, .{ "mvaddch", h.c("{}") }, .{ "mvaddstr", h.c("{}") },
    // Cursor/screen
    .{ "move", h.c("{}") }, .{ "refresh", h.c("{}") }, .{ "clear", h.c("{}") }, .{ "erase", h.c("{}") },
    .{ "clrtoeol", h.c("{}") }, .{ "clrtobot", h.c("{}") }, .{ "curs_set", h.I32(0) },
    // Size
    .{ "getmaxyx", h.c(".{ @as(i32, 24), @as(i32, 80) }") }, .{ "getyx", h.c(".{ @as(i32, 0), @as(i32, 0) }") }, .{ "LINES", h.I32(24) }, .{ "COLS", h.I32(80) },
    // Attributes
    .{ "attron", h.c("{}") }, .{ "attroff", h.c("{}") }, .{ "attrset", h.c("{}") },
    // Color constants (0-7)
    .{ "COLOR_BLACK", h.I32(0) }, .{ "COLOR_RED", h.I32(1) }, .{ "COLOR_GREEN", h.I32(2) }, .{ "COLOR_YELLOW", h.I32(3) },
    .{ "COLOR_BLUE", h.I32(4) }, .{ "COLOR_MAGENTA", h.I32(5) }, .{ "COLOR_CYAN", h.I32(6) }, .{ "COLOR_WHITE", h.I32(7) },
    // Attr constants
    .{ "A_NORMAL", h.I32(0) }, .{ "A_STANDOUT", h.I32(0x10000) }, .{ "A_UNDERLINE", h.I32(0x20000) },
    .{ "A_REVERSE", h.I32(0x40000) }, .{ "A_BLINK", h.I32(0x80000) }, .{ "A_DIM", h.I32(0x100000) },
    .{ "A_BOLD", h.I32(0x200000) }, .{ "A_PROTECT", h.I32(0x400000) }, .{ "A_INVIS", h.I32(0x800000) }, .{ "A_ALTCHARSET", h.I32(0x1000000) },
    // Keys
    .{ "KEY_UP", h.I32(259) }, .{ "KEY_DOWN", h.I32(258) }, .{ "KEY_LEFT", h.I32(260) }, .{ "KEY_RIGHT", h.I32(261) },
    .{ "KEY_HOME", h.I32(262) }, .{ "KEY_END", h.I32(360) }, .{ "KEY_NPAGE", h.I32(338) }, .{ "KEY_PPAGE", h.I32(339) },
    .{ "KEY_BACKSPACE", h.I32(263) }, .{ "KEY_DC", h.I32(330) }, .{ "KEY_IC", h.I32(331) }, .{ "KEY_ENTER", h.I32(343) },
    .{ "KEY_F1", h.I32(265) }, .{ "KEY_F2", h.I32(266) }, .{ "KEY_F3", h.I32(267) }, .{ "KEY_F4", h.I32(268) },
    .{ "KEY_F5", h.I32(269) }, .{ "KEY_F6", h.I32(270) }, .{ "KEY_F7", h.I32(271) }, .{ "KEY_F8", h.I32(272) },
    .{ "KEY_F9", h.I32(273) }, .{ "KEY_F10", h.I32(274) }, .{ "KEY_F11", h.I32(275) }, .{ "KEY_F12", h.I32(276) },
    // Misc
    .{ "beep", h.c("{}") }, .{ "flash", h.c("{}") }, .{ "napms", h.c("{}") }, .{ "wrapper", h.c("{}") },
    .{ "use_default_colors", h.c("{}") }, .{ "keypad", h.c("{}") }, .{ "nodelay", h.c("{}") }, .{ "halfdelay", h.c("{}") }, .{ "timeout", h.c("{}") },
});

fn genColorPair(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("(@as(i32, "); try self.genExpr(args[0]); try self.emit(") << 8)"); } else try self.emit("@as(i32, 0)"); }
fn genPairNumber(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("((@as(i32, "); try self.genExpr(args[0]); try self.emit(") >> 8) & 0xFF)"); } else try self.emit("@as(i32, 0)"); }
