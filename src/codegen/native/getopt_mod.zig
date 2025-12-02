/// Python getopt module - C-style parser for command line options
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getopt", genGetopt }, .{ "gnu_getopt", genGetopt }, .{ "GetoptError", h.err("GetoptError") }, .{ "error", h.err("GetoptError") },
});

fn genGetopt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const argv = "); try self.genExpr(args[0]); try self.emit("; const shortopts = "); try self.genExpr(args[1]); try self.emit("; _ = shortopts; var opts: std.ArrayList(struct { []const u8, []const u8 }) = .{}; var remaining: std.ArrayList([]const u8) = .{}; for (argv) |arg| { remaining.append(__global_allocator, arg) catch {}; } break :blk .{ opts.items, remaining.items }; }"); } else { try self.emit(".{ &[_]struct { []const u8, []const u8 }{}, &[_][]const u8{} }"); }
}
