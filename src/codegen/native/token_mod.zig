/// Python token module - Token constants and utilities
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ENDMARKER", genEndmarker },
    .{ "NAME", genName },
    .{ "NUMBER", genNumber },
    .{ "STRING", genString },
    .{ "NEWLINE", genNewline },
    .{ "INDENT", genIndent },
    .{ "DEDENT", genDedent },
    .{ "OP", genOp },
    .{ "ERRORTOKEN", genErrortoken },
    .{ "COMMENT", genComment },
    .{ "NL", genNL },
    .{ "ENCODING", genEncoding },
    .{ "N_TOKENS", genNTokens },
    .{ "NT_OFFSET", genNtOffset },
    .{ "tok_name", genTokName },
    .{ "EXACT_TOKEN_TYPES", genExactTokenTypes },
    .{ "ISTERMINAL", genIsterminal },
    .{ "ISNONTERMINAL", genIsnonterminal },
    .{ "ISEOF", genIseof },
});

fn genEndmarker(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genName(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genNumber(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genString(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 3)"), builder_mod.EmitConfig.forExpression());
}

fn genNewline(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 4)"), builder_mod.EmitConfig.forExpression());
}

fn genIndent(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 5)"), builder_mod.EmitConfig.forExpression());
}

fn genDedent(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 6)"), builder_mod.EmitConfig.forExpression());
}

fn genOp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 54)"), builder_mod.EmitConfig.forExpression());
}

fn genErrortoken(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 59)"), builder_mod.EmitConfig.forExpression());
}

fn genComment(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 60)"), builder_mod.EmitConfig.forExpression());
}

fn genNL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 61)"), builder_mod.EmitConfig.forExpression());
}

fn genEncoding(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 62)"), builder_mod.EmitConfig.forExpression());
}

fn genNTokens(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 63)"), builder_mod.EmitConfig.forExpression());
}

fn genNtOffset(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 256)"), builder_mod.EmitConfig.forExpression());
}

fn genTokName(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("hashmap_helper.AutoHashMap(i32, []const u8).init(__global_allocator)"), builder_mod.EmitConfig.forExpression());
}

fn genExactTokenTypes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("hashmap_helper.StringHashMap(i32).init(__global_allocator)"), builder_mod.EmitConfig.forExpression());
}

fn genIsterminal(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("isterminal");
        try self.emit("const x = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} x < 256; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
    }
}

fn genIsnonterminal(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("isnonterminal");
        try self.emit("const x = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} x >= 256; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
    }
}

fn genIseof(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("iseof");
        try self.emit("const x = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} x == 0; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
    }
}
