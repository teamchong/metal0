/// Python _bisect module - C accelerator for bisect (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "bisect_left", genBisectLeft }, .{ "bisect_right", genBisectRight }, .{ "bisect", genBisectRight },
    .{ "insort_left", genConst("{}") }, .{ "insort_right", genConst("{}") }, .{ "insort", genConst("{}") },
});

fn genBisectLeft(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const arr = "); try self.genExpr(args[0]); try self.emit("; const x = "); try self.genExpr(args[1]); try self.emit("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) { const mid = (lo + hi) / 2; if (arr[mid] < x) { lo = mid + 1; } else { hi = mid; } } break :blk @as(i64, @intCast(lo)); }"); } else try self.emit("@as(i64, 0)");
}
fn genBisectRight(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const arr = "); try self.genExpr(args[0]); try self.emit("; const x = "); try self.genExpr(args[1]); try self.emit("; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) { const mid = (lo + hi) / 2; if (x < arr[mid]) { hi = mid; } else { lo = mid + 1; } } break :blk @as(i64, @intCast(lo)); }"); } else try self.emit("@as(i64, 0)");
}
