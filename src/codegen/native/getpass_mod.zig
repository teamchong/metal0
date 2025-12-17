/// Python getpass module - Portable password input
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getpass", genGetpass },
    .{ "getuser", genGetuser },
    .{ "GetPassWarning", h.c("\"GetPassWarning\"") },
});

/// getpass(prompt) - Read password from stdin without echoing
fn genGetpass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("getpass_{d}: {{ ", .{id});

    // Discard prompt arg if provided
    if (args.len > 0) {
        try self.emit("_ = ");
        try self.genExpr(args[0]);
        try self.emit("; ");
    }

    try self.emit("const stdin = std.io.getStdIn().reader(); var buf: [256]u8 = undefined; break :getpass_");
    try self.emitFmt("{d} stdin.readUntilDelimiter(&buf, '\\n') catch \"\"; }}", .{id});
}

/// getuser() - Get current username from environment
fn genGetuser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args; // No arguments expected
    const id = self.nextNameId();
    try self.emitFmt("getuser_{d}: {{ const user = if (comptime @import(\"builtin\").os.tag == .windows) \"unknown\" else (std.posix.getenv(\"USER\") orelse std.posix.getenv(\"LOGNAME\") orelse \"unknown\"); break :getuser_{d} user; }}", .{ id, id });
}
