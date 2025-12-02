/// Python _heapq module - C accelerator for heapq (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "heappush", genPush }, .{ "heappop", genPop }, .{ "heapify", genUnit }, .{ "heapreplace", genReplace },
    .{ "heappushpop", genPushPop }, .{ "nlargest", genNlargest }, .{ "nsmallest", genNlargest },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }

fn genPush(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { var heap = "); try self.genExpr(args[0]); try self.emit("; heap.append(__global_allocator, "); try self.genExpr(args[1]); try self.emit(") catch {}; break :blk {}; }"); } else { try self.emit("{}"); }
}

fn genPop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { var heap = "); try self.genExpr(args[0]); try self.emit("; if (heap.items.len > 0) { const item = heap.items[0]; heap.items[0] = heap.items[heap.items.len - 1]; heap.items.len -= 1; break :blk item; } else { break :blk null; } }"); } else { try self.emit("null"); }
}

fn genReplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { var heap = "); try self.genExpr(args[0]); try self.emit("; const old = heap.items[0]; heap.items[0] = "); try self.genExpr(args[1]); try self.emit("; break :blk old; }"); } else { try self.emit("null"); }
}

fn genPushPop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const item = "); try self.genExpr(args[1]); try self.emit("; var heap = "); try self.genExpr(args[0]); try self.emit("; if (heap.items.len > 0 and heap.items[0] < item) { const old = heap.items[0]; heap.items[0] = item; break :blk old; } break :blk item; }"); } else { try self.emit("null"); }
}

fn genNlargest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const n = @as(usize, @intCast("); try self.genExpr(args[0]); try self.emit(")); const items = "); try self.genExpr(args[1]); try self.emit("; var result: std.ArrayList(@TypeOf(items[0])) = .{}; for (items[0..@min(n, items.len)]) |item| { result.append(__global_allocator, item) catch {}; } break :blk result.items; }"); } else { try self.emit("&[_]@TypeOf(0){}"); }
}
