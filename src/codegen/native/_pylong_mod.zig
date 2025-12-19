/// Python _pylong module - Pure Python long integer implementation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "log10_base256", genLog10Base256 },
    .{ "spread", genSpread },
    .{ "int_to_decimal_string", genIntToDecimalString },
    .{ "int_from_string", genIntFromString },
    .{ "dec_str_to_int_inner", genDecStrToIntInner },
    .{ "compute_powers", genComputePowers },
});

fn genLog10Base256(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "@as(f64, 0.4150374992788438)");
}

fn genSpread(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "(struct { data: std.AutoHashMap(i64, i64) = .{}, pub fn copy(self: @This()) @This() { return self; } pub fn clear(self: *@This()) void { self.data.clearRetainingCapacity(); } pub fn clearRetainingCapacity(self: *@This()) void { self.data.clearRetainingCapacity(); } pub fn update(self: *@This(), other: @This()) void { _ = other; } pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() { _ = allocator; return self; } pub fn contains(self: @This(), key: i64) bool { return self.data.contains(key); } }{})");
}

fn genIntToDecimalString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "\"0\"");
        return;
    }
    const id = self.nextNameId();
    try emitFmtConst(self, "(__pylong_itds_{d}: {{ const __n_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try emitFmtConst(self, "; if (@TypeOf(__n_{d}) == runtime.BigInt) {{ break :__pylong_itds_{d} __n_{d}.toString(__global_allocator); }} else {{ break :__pylong_itds_{d} try std.fmt.allocPrint(__global_allocator, \"{{d}}\", .{{__n_{d}}}); }} }})", .{ id, id, id, id, id });
}

fn genIntFromString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "@as(i64, 0)");
        return;
    }
    const id = self.nextNameId();
    try emitFmtConst(self, "(__pylong_ifs_{d}: {{ const __s_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try emitFmtConst(self, "; const __base_{d}: u8 = ", .{id});
    if (args.len > 1) {
        try emitConst(self, "@intCast(");
        try self.genExpr(args[1]);
        try emitConst(self, ")");
    } else {
        try emitConst(self, "10");
    }
    try emitFmtConst(self, "; break :__pylong_ifs_{d} runtime.builtins.parseInt(__s_{d}, __base_{d}) catch 0; }})", .{ id, id, id });
}

fn genDecStrToIntInner(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "@as(i64, 0)");
        return;
    }
    const id = self.nextNameId();
    try emitFmtConst(self, "(__pylong_dsi_{d}: {{ const __s_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try emitFmtConst(self, "; const __guard_{d}: u8 = ", .{id});
    if (args.len > 1) {
        try emitConst(self, "@intCast(");
        try self.genExpr(args[1]);
        try emitConst(self, ")");
    } else {
        try emitConst(self, "8");
    }
    try emitFmtConst(self, "; _ = __guard_{d}; const __max_len_{d}: usize = @intFromFloat(@as(f64, @floatFromInt(@as(u64, 1) << 47)) / 0.4150374992788438); if (__s_{d}.len > __max_len_{d}) {{ return error.ValueError; }} break :__pylong_dsi_{d} runtime.builtins.parseInt(__s_{d}, 10) catch 0; }})", .{ id, id, id, id, id, id });
}

fn genComputePowers(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) {
        try emitConst(self, "(runtime.pylong.computePowers(__global_allocator, 0, 2, 0, false))");
        return;
    }
    try emitConst(self, "(runtime.pylong.computePowers(__global_allocator, @intCast(");
    try self.genExpr(args[0]);
    try emitConst(self, "), @intCast(");
    try self.genExpr(args[1]);
    try emitConst(self, "), @intCast(");
    try self.genExpr(args[2]);
    try emitConst(self, "), ");
    if (args.len > 3) {
        try self.genExpr(args[3]);
    } else {
        try emitConst(self, "false");
    }
    try emitConst(self, "))");
}
