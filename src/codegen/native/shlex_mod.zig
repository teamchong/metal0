/// Python shlex module - Simple lexical analysis (shell tokenizer)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "split", h.c("&[_][]const u8{}") }, .{ "join", h.c("\"\"") },
    .{ "shlex", h.c(".{ .instream = @as(?*anyopaque, null), .infile = \"\", .posix = true, .eof = \"\", .commenters = \"#\", .wordchars = \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_\", .whitespace = \" \\t\\r\\n\", .whitespace_split = false, .quotes = \"'\\\"\" }") },
    .{ "quote", genQuote },
});

fn genQuote(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const s = "); try self.genExpr(args[0]); try self.emit("; break :blk s; }"); } else { try self.emit("\"''\""); }
}
