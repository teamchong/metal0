/// Python shlex module - Simple lexical analysis (shell tokenizer)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "split", genSplit }, .{ "join", genJoin }, .{ "quote", genQuote }, .{ "shlex", genShlex },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genJoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genShlex(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .instream = @as(?*anyopaque, null), .infile = \"\", .posix = true, .eof = \"\", .commenters = \"#\", .wordchars = \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_\", .whitespace = \" \\t\\r\\n\", .whitespace_split = false, .quotes = \"'\\\"\" }"); }
fn genQuote(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const s = "); try self.genExpr(args[0]); try self.emit("; break :blk s; }"); } else { try self.emit("\"''\""); }
}
