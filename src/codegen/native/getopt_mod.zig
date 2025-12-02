/// Python getopt module - C-style parser for command line options
const std = @import("std");
const h = @import("mod_helper.zig");

const genGetopt = h.wrap2("blk: { const argv = ", "; const shortopts = ", "; _ = shortopts; var opts: std.ArrayList(struct { []const u8, []const u8 }) = .{}; var remaining: std.ArrayList([]const u8) = .{}; for (argv) |arg| { remaining.append(__global_allocator, arg) catch {}; } break :blk .{ opts.items, remaining.items }; }", ".{ &[_]struct { []const u8, []const u8 }{}, &[_][]const u8{} }");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getopt", genGetopt }, .{ "gnu_getopt", genGetopt }, .{ "GetoptError", h.err("GetoptError") }, .{ "error", h.err("GetoptError") },
});
