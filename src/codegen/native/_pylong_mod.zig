/// Python _pylong module - Pure Python long integer implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "log10_base256", genLog10Base256 }, .{ "spread", genSpread },
    .{ "int_to_decimal_string", genIntToDecimalString }, .{ "int_from_string", genIntFromString },
    .{ "dec_str_to_int_inner", genDecStrToIntInner }, .{ "compute_powers", genComputePowers },
});

fn genLog10Base256(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 0.4150374992788438)"); }
fn genSpread(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "(struct { data: std.AutoHashMap(i64, i64) = .{}, pub fn copy(self: @This()) @This() { return __self; } pub fn clear(__self: *@This()) void { __self.data.clearRetainingCapacity(); } pub fn clearRetainingCapacity(__self: *@This()) void { __self.data.clearRetainingCapacity(); } pub fn update(__self: *@This(), other: @This()) void { _ = other; } pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() { _ = allocator; return __self; } pub fn contains(self: @This(), key: i64) bool { return __self.data.contains(key); } }{})"); }

fn genIntToDecimalString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"0\""); return; }
    try self.emit("(blk: { const n = "); try self.genExpr(args[0]);
    try self.emit("; if (@TypeOf(n) == runtime.BigInt) { break :blk n.toString(__global_allocator); } else { break :blk try std.fmt.allocPrint(__global_allocator, \"{d}\", .{n}); } })");
}

fn genIntFromString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(i64, 0)"); return; }
    try self.emit("(blk: { const s = "); try self.genExpr(args[0]); try self.emit("; const base: u8 = ");
    if (args.len > 1) { try self.emit("@intCast("); try self.genExpr(args[1]); try self.emit(")"); } else { try self.emit("10"); }
    try self.emit("; break :blk runtime.builtins.parseInt(s, base) catch 0; })");
}

fn genDecStrToIntInner(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(i64, 0)"); return; }
    try self.emit("(blk: { const s = "); try self.genExpr(args[0]); try self.emit("; const guard: u8 = ");
    if (args.len > 1) { try self.emit("@intCast("); try self.genExpr(args[1]); try self.emit(")"); } else { try self.emit("8"); }
    try self.emit("; _ = guard; const max_len: usize = @intFromFloat(@as(f64, @floatFromInt(@as(u64, 1) << 47)) / 0.4150374992788438); if (s.len > max_len) { return error.ValueError; } break :blk runtime.builtins.parseInt(s, 10) catch 0; })");
}

fn genComputePowers(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) { try self.emit("(runtime.pylong.computePowers(__global_allocator, 0, 2, 0, false))"); return; }
    try self.emit("(runtime.pylong.computePowers(__global_allocator, @intCast("); try self.genExpr(args[0]);
    try self.emit("), @intCast("); try self.genExpr(args[1]); try self.emit("), @intCast("); try self.genExpr(args[2]); try self.emit("), ");
    if (args.len > 3) { try self.genExpr(args[3]); } else { try self.emit("false"); }
    try self.emit("))");
}
