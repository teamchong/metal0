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

    // Still use emit for complex control flow - full builder migration needs more work
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_bsl: {{ const arr = ", .{id});
    try self.genExpr(args[0]);
    try self.emit("; const x = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) {{ const mid = (lo + hi) / 2; if (arr[mid] < x) {{ lo = mid + 1; }} else {{ hi = mid; }} }} break :__m{d}_bsl @as(i64, @intCast(lo)); }})", .{id});
}

fn genBisectRight(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
        return;
    }

    // Still use emit for complex control flow - full builder migration needs more work
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_bsr: {{ const arr = ", .{id});
    try self.genExpr(args[0]);
    try self.emit("; const x = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) {{ const mid = (lo + hi) / 2; if (x < arr[mid]) {{ hi = mid; }} else {{ lo = mid + 1; }} }} break :__m{d}_bsr @as(i64, @intCast(lo)); }})", .{id});
}

fn genInsort(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}
