/// Python curses module - Terminal handling for character-cell displays
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "initscr", genInitscr },
    .{ "endwin", genEndwin },
    .{ "newwin", genNewwin },
    .{ "newpad", genNewpad },
    .{ "cbreak", genCbreak },
    .{ "nocbreak", genNocbreak },
    .{ "echo", genEcho },
    .{ "noecho", genNoecho },
    .{ "raw", genRaw },
    .{ "noraw", genNoraw },
    .{ "start_color", genStart_color },
    .{ "has_colors", genHas_colors },
    .{ "can_change_color", genCan_change_color },
    .{ "init_pair", genInit_pair },
    .{ "init_color", genInit_color },
    .{ "color_pair", genColor_pair },
    .{ "pair_number", genPair_number },
    .{ "getch", genGetch },
    .{ "getkey", genGetkey },
    .{ "ungetch", genUngetch },
    .{ "getstr", genGetstr },
    .{ "addch", genAddch },
    .{ "addstr", genAddstr },
    .{ "addnstr", genAddnstr },
    .{ "mvaddch", genMvaddch },
    .{ "mvaddstr", genMvaddstr },
    .{ "move", genMove },
    .{ "refresh", genRefresh },
    .{ "clear", genClear },
    .{ "erase", genErase },
    .{ "clrtoeol", genClrtoeol },
    .{ "clrtobot", genClrtobot },
    .{ "curs_set", genCurs_set },
    .{ "getmaxyx", genGetmaxyx },
    .{ "getyx", genGetyx },
    .{ "LINES", genLINES },
    .{ "COLS", genCOLS },
    .{ "attron", genAttron },
    .{ "attroff", genAttroff },
    .{ "attrset", genAttrset },
    .{ "COLOR_BLACK", genCOLOR_BLACK },
    .{ "COLOR_RED", genCOLOR_RED },
    .{ "COLOR_GREEN", genCOLOR_GREEN },
    .{ "COLOR_YELLOW", genCOLOR_YELLOW },
    .{ "COLOR_BLUE", genCOLOR_BLUE },
    .{ "COLOR_MAGENTA", genCOLOR_MAGENTA },
    .{ "COLOR_CYAN", genCOLOR_CYAN },
    .{ "COLOR_WHITE", genCOLOR_WHITE },
    .{ "A_NORMAL", genA_NORMAL },
    .{ "A_STANDOUT", genA_STANDOUT },
    .{ "A_UNDERLINE", genA_UNDERLINE },
    .{ "A_REVERSE", genA_REVERSE },
    .{ "A_BLINK", genA_BLINK },
    .{ "A_DIM", genA_DIM },
    .{ "A_BOLD", genA_BOLD },
    .{ "A_PROTECT", genA_PROTECT },
    .{ "A_INVIS", genA_INVIS },
    .{ "A_ALTCHARSET", genA_ALTCHARSET },
    .{ "KEY_UP", genKEY_UP },
    .{ "KEY_DOWN", genKEY_DOWN },
    .{ "KEY_LEFT", genKEY_LEFT },
    .{ "KEY_RIGHT", genKEY_RIGHT },
    .{ "KEY_HOME", genKEY_HOME },
    .{ "KEY_END", genKEY_END },
    .{ "KEY_NPAGE", genKEY_NPAGE },
    .{ "KEY_PPAGE", genKEY_PPAGE },
    .{ "KEY_BACKSPACE", genKEY_BACKSPACE },
    .{ "KEY_DC", genKEY_DC },
    .{ "KEY_IC", genKEY_IC },
    .{ "KEY_ENTER", genKEY_ENTER },
    .{ "KEY_F1", genKEY_F1 },
    .{ "KEY_F2", genKEY_F2 },
    .{ "KEY_F3", genKEY_F3 },
    .{ "KEY_F4", genKEY_F4 },
    .{ "KEY_F5", genKEY_F5 },
    .{ "KEY_F6", genKEY_F6 },
    .{ "KEY_F7", genKEY_F7 },
    .{ "KEY_F8", genKEY_F8 },
    .{ "KEY_F9", genKEY_F9 },
    .{ "KEY_F10", genKEY_F10 },
    .{ "KEY_F11", genKEY_F11 },
    .{ "KEY_F12", genKEY_F12 },
    .{ "beep", genBeep },
    .{ "flash", genFlash },
    .{ "napms", genNapms },
    .{ "wrapper", genWrapper },
    .{ "use_default_colors", genUse_default_colors },
    .{ "keypad", genKeypad },
    .{ "nodelay", genNodelay },
    .{ "halfdelay", genHalfdelay },
    .{ "timeout", genTimeout },
});

// ============================================================================
// Window creation and management
// ============================================================================

/// Generate curses.initscr() - initialize curses and return stdscr
pub fn genInitscr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate curses.endwin() - de-initialize curses
pub fn genEndwin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.newwin(nlines, ncols, begin_y, begin_x)
pub fn genNewwin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate curses.newpad(nlines, ncols)
pub fn genNewpad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

// ============================================================================
// Terminal modes
// ============================================================================

/// Generate curses.cbreak() - enter cbreak mode
pub fn genCbreak(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.nocbreak() - leave cbreak mode
pub fn genNocbreak(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.echo() - turn on echoing
pub fn genEcho(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.noecho() - turn off echoing
pub fn genNoecho(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.raw() - enter raw mode
pub fn genRaw(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.noraw() - leave raw mode
pub fn genNoraw(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// ============================================================================
// Color support
// ============================================================================

/// Generate curses.start_color() - initialize color support
pub fn genStart_color(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.has_colors() - check if terminal supports colors
pub fn genHas_colors(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate curses.can_change_color() - check if colors can be changed
pub fn genCan_change_color(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate curses.init_pair(pair_number, fg, bg)
pub fn genInit_pair(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.init_color(color_number, r, g, b)
pub fn genInit_color(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.color_pair(pair_number) - return attribute for color pair
pub fn genColor_pair(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("(@as(i32, ");
        try self.genExpr(args[0]);
        try self.emit(") << 8)");
    } else {
        try self.emit("@as(i32, 0)");
    }
}

/// Generate curses.pair_number(attr) - return pair number from attribute
pub fn genPair_number(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((@as(i32, ");
        try self.genExpr(args[0]);
        try self.emit(") >> 8) & 0xFF)");
    } else {
        try self.emit("@as(i32, 0)");
    }
}

// ============================================================================
// Input functions
// ============================================================================

/// Generate curses.getch() - read a character
pub fn genGetch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -1)");
}

/// Generate curses.getkey() - read a key name
pub fn genGetkey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate curses.ungetch(ch) - push character back
pub fn genUngetch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.getstr() - read a string
pub fn genGetstr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

// ============================================================================
// Output functions
// ============================================================================

/// Generate curses.addch(ch) - add character
pub fn genAddch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.addstr(str) - add string
pub fn genAddstr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.addnstr(str, n) - add string with limit
pub fn genAddnstr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.mvaddch(y, x, ch) - move and add character
pub fn genMvaddch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.mvaddstr(y, x, str) - move and add string
pub fn genMvaddstr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// ============================================================================
// Cursor and screen control
// ============================================================================

/// Generate curses.move(y, x) - move cursor
pub fn genMove(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.refresh() - refresh screen
pub fn genRefresh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.clear() - clear screen
pub fn genClear(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.erase() - erase screen
pub fn genErase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.clrtoeol() - clear to end of line
pub fn genClrtoeol(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.clrtobot() - clear to bottom of screen
pub fn genClrtobot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.curs_set(visibility) - set cursor visibility
pub fn genCurs_set(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

// ============================================================================
// Window size
// ============================================================================

/// Generate curses.getmaxyx(win) - get window dimensions
pub fn genGetmaxyx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, 24), @as(i32, 80) }");
}

/// Generate curses.getyx(win) - get cursor position
pub fn genGetyx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, 0), @as(i32, 0) }");
}

/// Generate curses.LINES - screen height
pub fn genLINES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 24)");
}

/// Generate curses.COLS - screen width
pub fn genCOLS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 80)");
}

// ============================================================================
// Attributes
// ============================================================================

/// Generate curses.attron(attr) - turn on attributes
pub fn genAttron(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.attroff(attr) - turn off attributes
pub fn genAttroff(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.attrset(attr) - set attributes
pub fn genAttrset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// ============================================================================
// Color constants
// ============================================================================

pub fn genCOLOR_BLACK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genCOLOR_RED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genCOLOR_GREEN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genCOLOR_YELLOW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genCOLOR_BLUE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genCOLOR_MAGENTA(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genCOLOR_CYAN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

pub fn genCOLOR_WHITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 7)");
}

// ============================================================================
// Attribute constants
// ============================================================================

pub fn genA_NORMAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genA_STANDOUT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x10000)");
}

pub fn genA_UNDERLINE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x20000)");
}

pub fn genA_REVERSE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x40000)");
}

pub fn genA_BLINK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x80000)");
}

pub fn genA_DIM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x100000)");
}

pub fn genA_BOLD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x200000)");
}

pub fn genA_PROTECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x400000)");
}

pub fn genA_INVIS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x800000)");
}

pub fn genA_ALTCHARSET(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x1000000)");
}

// ============================================================================
// Key constants
// ============================================================================

pub fn genKEY_UP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 259)");
}

pub fn genKEY_DOWN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 258)");
}

pub fn genKEY_LEFT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 260)");
}

pub fn genKEY_RIGHT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 261)");
}

pub fn genKEY_HOME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 262)");
}

pub fn genKEY_END(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 360)");
}

pub fn genKEY_NPAGE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 338)");
}

pub fn genKEY_PPAGE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 339)");
}

pub fn genKEY_BACKSPACE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 263)");
}

pub fn genKEY_DC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 330)");
}

pub fn genKEY_IC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 331)");
}

pub fn genKEY_ENTER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 343)");
}

pub fn genKEY_F1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 265)");
}

pub fn genKEY_F2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 266)");
}

pub fn genKEY_F3(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 267)");
}

pub fn genKEY_F4(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 268)");
}

pub fn genKEY_F5(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 269)");
}

pub fn genKEY_F6(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 270)");
}

pub fn genKEY_F7(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 271)");
}

pub fn genKEY_F8(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 272)");
}

pub fn genKEY_F9(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 273)");
}

pub fn genKEY_F10(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 274)");
}

pub fn genKEY_F11(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 275)");
}

pub fn genKEY_F12(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 276)");
}

// ============================================================================
// Misc functions
// ============================================================================

/// Generate curses.beep() - audible bell
pub fn genBeep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.flash() - visual bell
pub fn genFlash(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.napms(ms) - sleep for milliseconds
pub fn genNapms(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.wrapper(func) - initialize curses and call func
pub fn genWrapper(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.use_default_colors() - use terminal default colors
pub fn genUse_default_colors(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.keypad(win, flag) - enable keypad mode
pub fn genKeypad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.nodelay(win, flag) - non-blocking input mode
pub fn genNodelay(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.halfdelay(tenths) - half-delay mode
pub fn genHalfdelay(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate curses.timeout(delay) - set blocking timeout
pub fn genTimeout(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}
