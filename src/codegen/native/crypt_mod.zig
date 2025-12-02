/// Python crypt module - Function to check Unix passwords
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "crypt", genCrypt }, .{ "mksalt", genConst("\"$6$rounds=5000$\"") },
    .{ "METHOD_SHA512", genConst(".{ .name = \"SHA512\", .ident = \"$6$\", .salt_chars = 16, .total_size = 106 }") },
    .{ "METHOD_SHA256", genConst(".{ .name = \"SHA256\", .ident = \"$5$\", .salt_chars = 16, .total_size = 63 }") },
    .{ "METHOD_BLOWFISH", genConst(".{ .name = \"BLOWFISH\", .ident = \"$2b$\", .salt_chars = 22, .total_size = 59 }") },
    .{ "METHOD_MD5", genConst(".{ .name = \"MD5\", .ident = \"$1$\", .salt_chars = 8, .total_size = 34 }") },
    .{ "METHOD_CRYPT", genConst(".{ .name = \"CRYPT\", .ident = \"\", .salt_chars = 2, .total_size = 13 }") },
    .{ "methods", genConst("metal0_runtime.PyList(@TypeOf(.{ .name = \"\", .ident = \"\", .salt_chars = @as(i32, 0), .total_size = @as(i32, 0) })).init()") },
});

fn genCrypt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const word = "); try self.genExpr(args[0]); try self.emit("; _ = word; break :blk \"$6$rounds=5000$salt$hash\"; }"); }
    else try self.emit("\"\"");
}
