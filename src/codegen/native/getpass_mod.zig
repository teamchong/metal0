/// Python getpass module - Portable password input
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getpass", genGetpass },
    .{ "getuser", genGetuser },
    .{ "GetPassWarning", genGetPassWarning },
});

/// getpass(prompt) - Read password from stdin without echoing
fn genGetpass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try emitFmtConst(self, "getpass_{d}: {{ ", .{id});

    // Discard prompt arg if provided
    if (args.len > 0) {
        try emitConst(self, "_ = ");
        try self.genExpr(args[0]);
        try emitConst(self, "; ");
    }

    try emitFmtConst(self, "const stdin = std.io.getStdIn().reader(); var buf: [256]u8 = undefined; break :getpass_{d} stdin.readUntilDelimiter(&buf, '\\n') catch \"\"; }}", .{id});
}

/// getuser() - Get current username from environment
fn genGetuser(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try emitFmtConst(self, "getuser_{d}: {{ const user = if (comptime @import(\"builtin\").os.tag == .windows) \"unknown\" else (std.posix.getenv(\"USER\") orelse std.posix.getenv(\"LOGNAME\") orelse \"unknown\"); break :getuser_{d} user; }}", .{ id, id });
}

fn genGetPassWarning(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "\"GetPassWarning\"");
}
