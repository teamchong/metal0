/// Python _heapq module - C accelerator for heapq (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "heappush", genHeappush },
    .{ "heappop", genHeappop },
    .{ "heapify", genHeapify },
    .{ "heapreplace", genHeapreplace },
    .{ "heappushpop", genHeappushpop },
    .{ "nlargest", genNlargest },
    .{ "nsmallest", genNsmallest },
});

fn genHeappush(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_hpush: {{ const __v0 = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; const __v1 = ");
        try self.genExpr(args[1]);
        try self.emit("; __v0.append(__global_allocator, __v1) catch unreachable; break :__m");
        try self.emitFmt("{d}_hpush {{}}; }}", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genHeappop(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_hpop: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; if (__v.items.len > 0) { const _item = __v.items[0]; __v.items[0] = __v.items[__v.items.len - 1]; __v.items.len -= 1; break :__m");
        try self.emitFmt("{d}_hpop _item; }} break :__m{d}_hpop null; }}", .{ id, id });
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genHeapify(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genHeapreplace(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_hrep: {{ const __v0 = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; const __v1 = ");
        try self.genExpr(args[1]);
        try self.emit("; const _old = __v0.items[0]; __v0.items[0] = __v1; break :__m");
        try self.emitFmt("{d}_hrep _old; }}", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genHeappushpop(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_hpp: {{ const __v0 = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; const __v1 = ");
        try self.genExpr(args[1]);
        try self.emit("; if (__v1.items.len > 0 and __v1.items[0] < __v0) { const _old = __v1.items[0]; __v1.items[0] = __v0; break :__m");
        try self.emitFmt("{d}_hpp _old; }} break :__m{d}_hpp __v0; }}", .{ id, id });
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genNlargest(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_nlrg: {{ const __v0 = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; const __v1 = ");
        try self.genExpr(args[1]);
        try self.emit("; const _n = @as(usize, @intCast(__v0)); var _result: std.ArrayList(@TypeOf(__v1[0])) = .{}; for (__v1[0..@min(_n, __v1.len)]) |_item| { _result.append(__global_allocator, _item) catch unreachable; } break :__m");
        try self.emitFmt("{d}_nlrg _result.items; }}", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(0){}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genNsmallest(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_nsm: {{ const __v0 = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; const __v1 = ");
        try self.genExpr(args[1]);
        try self.emit("; const _n = @as(usize, @intCast(__v0)); var _result: std.ArrayList(@TypeOf(__v1[0])) = .{}; for (__v1[0..@min(_n, __v1.len)]) |_item| { _result.append(__global_allocator, _item) catch unreachable; } break :__m");
        try self.emitFmt("{d}_nsm _result.items; }}", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(0){}"), builder_mod.EmitConfig.forExpression());
    }
}
