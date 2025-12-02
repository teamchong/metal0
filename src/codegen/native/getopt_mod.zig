/// Python getopt module - C-style parser for command line options
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getopt", genGetopt }, .{ "gnu_getopt", genGetopt }, .{ "GetoptError", genError }, .{ "error", genError },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.GetoptError"); }
fn genGetopt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const argv = "); try self.genExpr(args[0]); try self.emit("; const shortopts = "); try self.genExpr(args[1]); try self.emit("; _ = shortopts; var opts: std.ArrayList(struct { []const u8, []const u8 }) = .{}; var remaining: std.ArrayList([]const u8) = .{}; for (argv) |arg| { remaining.append(__global_allocator, arg) catch {}; } break :blk .{ opts.items, remaining.items }; }"); } else { try self.emit(".{ &[_]struct { []const u8, []const u8 }{}, &[_][]const u8{} }"); }
}
