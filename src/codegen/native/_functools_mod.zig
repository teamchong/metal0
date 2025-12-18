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
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_red: {{ const __v0 = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; const __v1 = ");
        try self.genExpr(args[1]);
        try self.emit("; _ = __v1; break :__m");
        try self.emitFmt("{d}_red __v0; }}", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genCmpToKey(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_ctk: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; break :__m");
        try self.emitFmt("{d}_ctk .{{ .cmp = __v }}; }}", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
    }
}
