/// Python _curses module - Internal curses support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _curses.initscr()
pub fn genInitscr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .lines = 24, .cols = 80 }");
}

/// Generate _curses.endwin()
pub fn genEndwin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _curses.newwin(nlines, ncols, begin_y, begin_x)
pub fn genNewwin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .lines = 24, .cols = 80, .y = 0, .x = 0 }");
}

/// Generate _curses.newpad(nlines, ncols)
pub fn genNewpad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .lines = 24, .cols = 80 }");
}

/// Generate _curses.start_color()
pub fn genStartColor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _curses.init_pair(pair_number, fg, bg)
pub fn genInitPair(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _curses.color_pair(pair_number)
pub fn genColorPair(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _curses.cbreak()
pub fn genCbreak(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _curses.nocbreak()
pub fn genNocbreak(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _curses.echo()
pub fn genEcho(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _curses.noecho()
pub fn genNoecho(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _curses.raw()
pub fn genRaw(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _curses.noraw()
pub fn genNoraw(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _curses.curs_set(visibility)
pub fn genCursSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate _curses.has_colors()
pub fn genHasColors(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _curses.can_change_color()
pub fn genCanChangeColor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _curses.COLORS constant
pub fn genCOLORS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 256)");
}

/// Generate _curses.COLOR_PAIRS constant
pub fn genCOLOR_PAIRS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 256)");
}

/// Generate _curses.LINES constant
pub fn genLINES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 24)");
}

/// Generate _curses.COLS constant
pub fn genCOLS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 80)");
}

/// Generate _curses.error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.CursesError");
}
