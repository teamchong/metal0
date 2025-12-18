/// Python keyword module - Test whether strings are Python keywords
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

const kwlist = "\"False\", \"None\", \"True\", \"and\", \"as\", \"assert\", \"async\", \"await\", \"break\", \"class\", \"continue\", \"def\", \"del\", \"elif\", \"else\", \"except\", \"finally\", \"for\", \"from\", \"global\", \"if\", \"import\", \"in\", \"is\", \"lambda\", \"nonlocal\", \"not\", \"or\", \"pass\", \"raise\", \"return\", \"try\", \"while\", \"with\", \"yield\"";
const softkwlist = "\"_\", \"case\", \"match\", \"type\"";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "iskeyword", genIskeyword },
    .{ "issoftkeyword", genIssoftkeyword },
    .{ "kwlist", genKwlist },
    .{ "softkwlist", genSoftkwlist },
});

fn genIskeyword(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
        return;
    }
    const label = try self.emitInlineBlockStart("iskw");
    try self.emit("const __search = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; const __items = [_][]const u8{{ {s} }}; for (__items) |__item| {{ if (std.mem.eql(u8, __search, __item)) break :{s} true; }} break :{s} false; ", .{ kwlist, label, label });
    try self.emitInlineBlockEnd();
}

fn genIssoftkeyword(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
        return;
    }
    const label = try self.emitInlineBlockStart("issk");
    try self.emit("const __search = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; const __items = [_][]const u8{{ {s} }}; for (__items) |__item| {{ if (std.mem.eql(u8, __search, __item)) break :{s} true; }} break :{s} false; ", .{ softkwlist, label, label });
    try self.emitInlineBlockEnd();
}

fn genKwlist(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("(try runtime.NativeList.fromStringSlice(__global_allocator, &[_][]const u8{ " ++ kwlist ++ " }))"), builder_mod.EmitConfig.forExpression());
}

fn genSoftkwlist(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("(try runtime.NativeList.fromStringSlice(__global_allocator, &[_][]const u8{ " ++ softkwlist ++ " }))"), builder_mod.EmitConfig.forExpression());
}
