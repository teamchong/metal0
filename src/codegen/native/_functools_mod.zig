/// Python _functools module - C accelerator for functools (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "reduce", genReduce },
    .{ "cmp_to_key", genCmpToKey },
});

fn genReduce(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        const label = try b.emitInlineBlockStart("red");
        try self.emit("const __v0 = ");
        try self.genExpr(args[0]);
        try self.emit("; const __v1 = ");
        try self.genExpr(args[1]);
        try self.emitFmt("; _ = __v1; break :{s} __v0; ", .{label});
        try b.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genCmpToKey(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try b.emitInlineBlockStart("ctk");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} .{{ .cmp = __v }}; ", .{label});
        try b.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
    }
}
