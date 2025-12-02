/// Python _curses_panel module - Internal curses panel support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "new_panel", genNewPanel }, .{ "bottom_panel", genNull }, .{ "top_panel", genNull }, .{ "update_panels", genUnit },
    .{ "above", genNull }, .{ "below", genNull }, .{ "bottom", genUnit }, .{ "hidden", genFalse },
    .{ "hide", genUnit }, .{ "move", genUnit }, .{ "replace", genUnit }, .{ "set_userptr", genUnit },
    .{ "show", genUnit }, .{ "top", genUnit }, .{ "userptr", genNull }, .{ "window", genNull },
    .{ "error", genErr },
});

fn genNewPanel(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .window = null }"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.PanelError"); }
