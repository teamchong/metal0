/// Python _bisect module - C accelerator for bisect (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
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
        try self.emit("0");
        return;
    }
    try self.withInlineBlock("bsl", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const arr = ");
            try c.genExpr(a[0]);
            try c.emit("; const x = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) {{ const mid = (lo + hi) / 2; if (arr[mid] < x) {{ lo = mid + 1; }} else {{ hi = mid; }} }} break :{s} @as(i64, @intCast(lo))", .{label});
        }
    }.emit);
}

fn genBisectRight(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("0");
        return;
    }
    try self.withInlineBlock("bsr", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const arr = ");
            try c.genExpr(a[0]);
            try c.emit("; const x = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) {{ const mid = (lo + hi) / 2; if (x < arr[mid]) {{ hi = mid; }} else {{ lo = mid + 1; }} }} break :{s} @as(i64, @intCast(lo))", .{label});
        }
    }.emit);
}

fn genInsort(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("{}");
}
