/// Python shlex module - Simple lexical analysis (shell tokenizer)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "split", genConst("&[_][]const u8{}") }, .{ "join", genConst("\"\"") },
    .{ "shlex", genConst(".{ .instream = @as(?*anyopaque, null), .infile = \"\", .posix = true, .eof = \"\", .commenters = \"#\", .wordchars = \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_\", .whitespace = \" \\t\\r\\n\", .whitespace_split = false, .quotes = \"'\\\"\" }") },
    .{ "quote", genQuote },
});

fn genQuote(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const s = "); try self.genExpr(args[0]); try self.emit("; break :blk s; }"); } else { try self.emit("\"''\""); }
}
