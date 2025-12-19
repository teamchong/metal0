/// Python crypt module - Function to check Unix passwords
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output - uses h.NativeCodegen from mod_helper
fn emitConst(self: *h.NativeCodegen, val: []const u8) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *h.NativeCodegen, comptime fmt: []const u8, args: anytype) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}



pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "crypt", genCrypt },
    .{ "mksalt", genMksalt },
    .{ "METHOD_SHA512", genMethodSha512 },
    .{ "METHOD_SHA256", genMethodSha256 },
    .{ "METHOD_BLOWFISH", genMethodBlowfish },
    .{ "METHOD_MD5", genMethodMd5 },
    .{ "METHOD_CRYPT", genMethodCrypt },
    .{ "methods", genMethods },
});

fn genCrypt(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.withInlineBlock("crypt", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitConst(c, "; _ = __v;");
                try emitFmtConst(c, " break :{s} \"$6$rounds=5000$salt$hash\"", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genMksalt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("$6$rounds=5000$"), builder_mod.EmitConfig.forExpression());
}

fn genMethodSha512(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"SHA512\", .ident = \"$6$\", .salt_chars = 16, .total_size = 106 }"), builder_mod.EmitConfig.forExpression());
}

fn genMethodSha256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"SHA256\", .ident = \"$5$\", .salt_chars = 16, .total_size = 63 }"), builder_mod.EmitConfig.forExpression());
}

fn genMethodBlowfish(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"BLOWFISH\", .ident = \"$2b$\", .salt_chars = 22, .total_size = 59 }"), builder_mod.EmitConfig.forExpression());
}

fn genMethodMd5(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"MD5\", .ident = \"$1$\", .salt_chars = 8, .total_size = 34 }"), builder_mod.EmitConfig.forExpression());
}

fn genMethodCrypt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"CRYPT\", .ident = \"\", .salt_chars = 2, .total_size = 13 }"), builder_mod.EmitConfig.forExpression());
}

fn genMethods(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("runtime.NativeList.init()"), builder_mod.EmitConfig.forExpression());
}
