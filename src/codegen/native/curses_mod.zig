/// Python curses module - Terminal handling for character-cell displays
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    // Window/screen
    .{ "initscr", genNull }, .{ "endwin", genUnit }, .{ "newwin", genNull }, .{ "newpad", genNull },
    // Modes
    .{ "cbreak", genUnit }, .{ "nocbreak", genUnit }, .{ "echo", genUnit }, .{ "noecho", genUnit }, .{ "raw", genUnit }, .{ "noraw", genUnit },
    // Colors
    .{ "start_color", genUnit }, .{ "has_colors", genTrue }, .{ "can_change_color", genTrue },
    .{ "init_pair", genUnit }, .{ "init_color", genUnit }, .{ "color_pair", genColorPair }, .{ "pair_number", genPairNumber },
    // Input
    .{ "getch", genI32(-1) }, .{ "getkey", genEmptyStr }, .{ "ungetch", genUnit }, .{ "getstr", genEmptyStr },
    // Output
    .{ "addch", genUnit }, .{ "addstr", genUnit }, .{ "addnstr", genUnit }, .{ "mvaddch", genUnit }, .{ "mvaddstr", genUnit },
    // Cursor/screen
    .{ "move", genUnit }, .{ "refresh", genUnit }, .{ "clear", genUnit }, .{ "erase", genUnit },
    .{ "clrtoeol", genUnit }, .{ "clrtobot", genUnit }, .{ "curs_set", genI32(0) },
    // Size
    .{ "getmaxyx", genMaxyx }, .{ "getyx", genYx00 }, .{ "LINES", genI32(24) }, .{ "COLS", genI32(80) },
    // Attributes
    .{ "attron", genUnit }, .{ "attroff", genUnit }, .{ "attrset", genUnit },
    // Color constants (0-7)
    .{ "COLOR_BLACK", genI32(0) }, .{ "COLOR_RED", genI32(1) }, .{ "COLOR_GREEN", genI32(2) }, .{ "COLOR_YELLOW", genI32(3) },
    .{ "COLOR_BLUE", genI32(4) }, .{ "COLOR_MAGENTA", genI32(5) }, .{ "COLOR_CYAN", genI32(6) }, .{ "COLOR_WHITE", genI32(7) },
    // Attr constants
    .{ "A_NORMAL", genI32(0) }, .{ "A_STANDOUT", genI32(0x10000) }, .{ "A_UNDERLINE", genI32(0x20000) },
    .{ "A_REVERSE", genI32(0x40000) }, .{ "A_BLINK", genI32(0x80000) }, .{ "A_DIM", genI32(0x100000) },
    .{ "A_BOLD", genI32(0x200000) }, .{ "A_PROTECT", genI32(0x400000) }, .{ "A_INVIS", genI32(0x800000) }, .{ "A_ALTCHARSET", genI32(0x1000000) },
    // Keys
    .{ "KEY_UP", genI32(259) }, .{ "KEY_DOWN", genI32(258) }, .{ "KEY_LEFT", genI32(260) }, .{ "KEY_RIGHT", genI32(261) },
    .{ "KEY_HOME", genI32(262) }, .{ "KEY_END", genI32(360) }, .{ "KEY_NPAGE", genI32(338) }, .{ "KEY_PPAGE", genI32(339) },
    .{ "KEY_BACKSPACE", genI32(263) }, .{ "KEY_DC", genI32(330) }, .{ "KEY_IC", genI32(331) }, .{ "KEY_ENTER", genI32(343) },
    .{ "KEY_F1", genI32(265) }, .{ "KEY_F2", genI32(266) }, .{ "KEY_F3", genI32(267) }, .{ "KEY_F4", genI32(268) },
    .{ "KEY_F5", genI32(269) }, .{ "KEY_F6", genI32(270) }, .{ "KEY_F7", genI32(271) }, .{ "KEY_F8", genI32(272) },
    .{ "KEY_F9", genI32(273) }, .{ "KEY_F10", genI32(274) }, .{ "KEY_F11", genI32(275) }, .{ "KEY_F12", genI32(276) },
    // Misc
    .{ "beep", genUnit }, .{ "flash", genUnit }, .{ "napms", genUnit }, .{ "wrapper", genUnit },
    .{ "use_default_colors", genUnit }, .{ "keypad", genUnit }, .{ "nodelay", genUnit }, .{ "halfdelay", genUnit }, .{ "timeout", genUnit },
});

fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genMaxyx(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 24), @as(i32, 80) }"); }
fn genYx00(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 0), @as(i32, 0) }"); }
fn genColorPair(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("(@as(i32, "); try self.genExpr(args[0]); try self.emit(") << 8)"); } else try self.emit("@as(i32, 0)"); }
fn genPairNumber(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("((@as(i32, "); try self.genExpr(args[0]); try self.emit(") >> 8) & 0xFF)"); } else try self.emit("@as(i32, 0)"); }
