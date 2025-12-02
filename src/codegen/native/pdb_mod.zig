/// Python pdb module - Python debugger
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Pdb", genPdb }, .{ "run", genUnit }, .{ "runeval", genNullPtr }, .{ "runcall", genNullPtr },
    .{ "set_trace", genUnit }, .{ "post_mortem", genUnit }, .{ "pm", genUnit }, .{ "help", genUnit },
    .{ "Breakpoint", genBreakpoint },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNullPtr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genPdb(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .skip = @as(?[]const []const u8, null), .nosigint = false }"); }
fn genBreakpoint(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .file = \"\", .line = @as(i32, 0), .temporary = false, .cond = @as(?[]const u8, null), .funcname = @as(?[]const u8, null), .enabled = true, .ignore = @as(i32, 0), .hits = @as(i32, 0), .number = @as(i32, 0) }"); }
