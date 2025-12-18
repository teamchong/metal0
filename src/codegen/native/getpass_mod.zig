/// Python getpass module - Portable password input
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getpass", genGetpass },
    .{ "getuser", genGetuser },
    .{ "GetPassWarning", genGetPassWarning },
});

/// getpass(prompt) - Read password from stdin without echoing
fn genGetpass(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
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
fn genGetuser(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("getuser_{d}: {{ const user = if (comptime @import(\"builtin\").os.tag == .windows) \"unknown\" else (std.posix.getenv(\"USER\") orelse std.posix.getenv(\"LOGNAME\") orelse \"unknown\"); break :getuser_{d} user; }}", .{ id, id });
}

fn genGetPassWarning(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("GetPassWarning"), builder_mod.EmitConfig.forExpression());
}
