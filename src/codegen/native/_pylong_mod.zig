/// Python _pylong module - Pure Python long integer implementation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "log10_base256", genLog10Base256 },
    .{ "spread", genSpread },
    .{ "int_to_decimal_string", genIntToDecimalString },
    .{ "int_from_string", genIntFromString },
    .{ "dec_str_to_int_inner", genDecStrToIntInner },
    .{ "compute_powers", genComputePowers },
});

fn genLog10Base256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(f64, 0.4150374992788438)"), builder_mod.EmitConfig.forExpression());
}

fn genSpread(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("(struct { data: std.AutoHashMap(i64, i64) = .{}, pub fn copy(self: @This()) @This() { return self; } pub fn clear(self: *@This()) void { self.data.clearRetainingCapacity(); } pub fn clearRetainingCapacity(self: *@This()) void { self.data.clearRetainingCapacity(); } pub fn update(self: *@This(), other: @This()) void { _ = other; } pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() { _ = allocator; return self; } pub fn contains(self: @This(), key: i64) bool { return self.data.contains(key); } }{})"), builder_mod.EmitConfig.forExpression());
}

fn genIntToDecimalString(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.string("0"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__pylong_itds_{d}: {{ const __n_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emit("; if (@TypeOf(__n_");
    try self.emitFmt("{d}) == runtime.BigInt) {{ break :__pylong_itds_{d} __n_{d}.toString(__global_allocator); }} else {{ break :__pylong_itds_{d} try std.fmt.allocPrint(__global_allocator, \"{{d}}\", .{{__n_{d}}}); }} }})", .{ id, id, id, id, id });
}

fn genIntFromString(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__pylong_ifs_{d}: {{ const __s_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; const __base_{d}: u8 = ", .{id});
    if (args.len > 1) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("10");
    }
    try self.emitFmt("; break :__pylong_ifs_{d} runtime.builtins.parseInt(__s_{d}, __base_{d}) catch 0; }})", .{ id, id, id });
}

fn genDecStrToIntInner(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__pylong_dsi_{d}: {{ const __s_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; const __guard_{d}: u8 = ", .{id});
    if (args.len > 1) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("8");
    }
    try self.emitFmt("; _ = __guard_{d}; const __max_len_{d}: usize = @intFromFloat(@as(f64, @floatFromInt(@as(u64, 1) << 47)) / 0.4150374992788438); if (__s_{d}.len > __max_len_{d}) {{ return error.ValueError; }} break :__pylong_dsi_{d} runtime.builtins.parseInt(__s_{d}, 10) catch 0; }})", .{ id, id, id, id, id, id });
}

fn genComputePowers(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len < 3) {
        try self.emit("(runtime.pylong.computePowers(__global_allocator, 0, 2, 0, false))");
        return;
    }
    try self.emit("(runtime.pylong.computePowers(__global_allocator, @intCast(");
    try self.genExpr(args[0]);
    try self.emit("), @intCast(");
    try self.genExpr(args[1]);
    try self.emit("), @intCast(");
    try self.genExpr(args[2]);
    try self.emit("), ");
    if (args.len > 3) {
        try self.genExpr(args[3]);
    } else {
        try self.emit("false");
    }
    try self.emit("))");
}
