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
    const b = try self.getBuilder();
    try b.writeFmt("getpass_{d}: {{ ", .{id});

    // Discard prompt arg if provided
    if (args.len > 0) {
        try b.write("_ = ");
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.write("; ");
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
    } else {
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
    }

    {
        const b2 = try self.getBuilder();
        try b2.write("const stdin = std.io.getStdIn().reader(); var buf: [256]u8 = undefined; break :getpass_");
        try b2.writeFmt("{d} stdin.readUntilDelimiter(&buf, '\\n') catch \"\"; }}", .{id});
        const output = b2.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// getuser() - Get current username from environment
fn genGetuser(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const id = self.nextNameId();
    const b = try self.getBuilder();
    try b.writeFmt("getuser_{d}: {{ const user = if (comptime @import(\"builtin\").os.tag == .windows) \"unknown\" else (std.posix.getenv(\"USER\") orelse std.posix.getenv(\"LOGNAME\") orelse \"unknown\"); break :getuser_{d} user; }}", .{ id, id });
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genGetPassWarning(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("\"GetPassWarning\"");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
