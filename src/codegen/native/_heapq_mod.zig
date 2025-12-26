/// Python _heapq module - C accelerator for heapq (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

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
        try self.withInlineBlock("hpush", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v0 = ");
                try c.genExpr(a[0]);
                try c.emit("; const __v1 = ");
                try c.genExpr(a[1]);
                try c.emitFmt("; __v0.append(__global_allocator, __v1) catch unreachable; break :{s}; ", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genHeappop(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.withInlineBlock("hpop", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; if (__v.items.len > 0) {{ const _item = __v.items[0]; __v.items[0] = __v.items[__v.items.len - 1]; __v.items.len -= 1; break :{s} _item; }} break :{s} null; ", .{ label, label });
            }
        }.emit);
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
        try self.withInlineBlock("hrep", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v0 = ");
                try c.genExpr(a[0]);
                try c.emit("; const __v1 = ");
                try c.genExpr(a[1]);
                try c.emitFmt("; const _old = __v0.items[0]; __v0.items[0] = __v1; break :{s} _old; ", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genHeappushpop(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        try self.withInlineBlock("hpp", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v0 = ");
                try c.genExpr(a[0]);
                try c.emit("; const __v1 = ");
                try c.genExpr(a[1]);
                try c.emitFmt("; if (__v1.items.len > 0 and __v1.items[0] < __v0) {{ const _old = __v1.items[0]; __v1.items[0] = __v0; break :{s} _old; }} break :{s} __v0; ", .{ label, label });
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genNlargest(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        try self.withInlineBlock("nlrg", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v0 = ");
                try c.genExpr(a[0]);
                try c.emit("; const __v1 = ");
                try c.genExpr(a[1]);
                try c.emitFmt("; const _n = @as(usize, @intCast(__v0)); var _result: std.ArrayList(@TypeOf(__v1[0])) = .{{}}; for (__v1[0..@min(_n, __v1.len)]) |_item| {{ _result.append(__global_allocator, _item) catch unreachable; }} break :{s} _result.items; ", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(0){}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genNsmallest(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        try self.withInlineBlock("nsm", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v0 = ");
                try c.genExpr(a[0]);
                try c.emit("; const __v1 = ");
                try c.genExpr(a[1]);
                try c.emitFmt("; const _n = @as(usize, @intCast(__v0)); var _result: std.ArrayList(@TypeOf(__v1[0])) = .{{}}; for (__v1[0..@min(_n, __v1.len)]) |_item| {{ _result.append(__global_allocator, _item) catch unreachable; }} break :{s} _result.items; ", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(0){}"), builder_mod.EmitConfig.forExpression());
    }
}
