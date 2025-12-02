/// Python _curses module - Internal curses support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "initscr", genInitscr }, .{ "endwin", genUnit }, .{ "newwin", genNewwin }, .{ "newpad", genNewpad },
    .{ "start_color", genUnit }, .{ "init_pair", genUnit }, .{ "color_pair", genI32_0 },
    .{ "cbreak", genUnit }, .{ "nocbreak", genUnit }, .{ "echo", genUnit }, .{ "noecho", genUnit },
    .{ "raw", genUnit }, .{ "noraw", genUnit }, .{ "curs_set", genI32_1 },
    .{ "has_colors", genTrue }, .{ "can_change_color", genTrue },
    .{ "COLORS", genI32_256 }, .{ "COLOR_PAIRS", genI32_256 }, .{ "LINES", genI32_24 }, .{ "COLS", genI32_80 },
    .{ "error", genError },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_24(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 24)"); }
fn genI32_80(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 80)"); }
fn genI32_256(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 256)"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.CursesError"); }
fn genInitscr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .lines = 24, .cols = 80 }"); }
fn genNewwin(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .lines = 24, .cols = 80, .y = 0, .x = 0 }"); }
fn genNewpad(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .lines = 24, .cols = 80 }"); }
