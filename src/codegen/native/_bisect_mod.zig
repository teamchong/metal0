/// Python _bisect module - C accelerator for bisect (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "bisect_left", genBisectLeft },
    .{ "bisect_right", genBisectRight },
    .{ "bisect", genBisectRight },
    .{ "insort_left", genInsort },
    .{ "insort_right", genInsort },
    .{ "insort", genInsort },
});

fn genBisectLeft(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
        return;
    }
    const b = try self.getBuilder();
    const label = try b.emitInlineBlockStart("bsl");
    try self.emit("const arr = ");
    try self.genExpr(args[0]);
    try self.emit("; const x = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) {{ const mid = (lo + hi) / 2; if (arr[mid] < x) {{ lo = mid + 1; }} else {{ hi = mid; }} }} break :{s} @as(i64, @intCast(lo)); ", .{label});
    try b.emitInlineBlockEnd();
}

fn genBisectRight(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
        return;
    }
    const b = try self.getBuilder();
    const label = try b.emitInlineBlockStart("bsr");
    try self.emit("const arr = ");
    try self.genExpr(args[0]);
    try self.emit("; const x = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) {{ const mid = (lo + hi) / 2; if (x < arr[mid]) {{ hi = mid; }} else {{ lo = mid + 1; }} }} break :{s} @as(i64, @intCast(lo)); ", .{label});
    try b.emitInlineBlockEnd();
}

fn genInsort(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}
