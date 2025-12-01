/// Python shlex module - Simple lexical analysis (shell tokenizer)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "split", genSplit },
    .{ "join", genJoin },
    .{ "quote", genQuote },
    .{ "shlex", genShlex },
});

/// Generate shlex.split(s, comments=False, posix=True)
pub fn genSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Return empty list for now - actual implementation would tokenize shell command
    try self.emit("&[_][]const u8{}");
}

/// Generate shlex.join(split_command)
pub fn genJoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate shlex.quote(s) - shell-escape a string
pub fn genQuote(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // For now just wrap in single quotes - proper impl would escape
        try self.emit("blk: { const s = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk s; }");
    } else {
        try self.emit("\"''\"");
    }
}

/// Generate shlex.shlex class constructor
pub fn genShlex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .instream = @as(?*anyopaque, null), .infile = \"\", .posix = true, .eof = \"\", .commenters = \"#\", .wordchars = \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_\", .whitespace = \" \\t\\r\\n\", .whitespace_split = false, .quotes = \"'\\\"\" }");
}
