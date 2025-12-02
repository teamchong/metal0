/// Python copy module - copy, deepcopy
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "copy", genCopy }, .{ "deepcopy", genDeepcopy }, .{ "replace", genReplace },
});

pub fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("copy_blk: { const _src = ");
    try self.genExpr(args[0]);
    try self.emit("; if (@typeInfo(@TypeOf(_src)) == .@\"struct\" and @hasField(@TypeOf(_src), \"items\")) { var _copy = @TypeOf(_src).init(__global_allocator); _copy.appendSlice(__global_allocator, _src.items) catch {}; break :copy_blk _copy; } break :copy_blk _src; }");
}

pub fn genDeepcopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("deepcopy_blk: { const _src = ");
    try self.genExpr(args[0]);
    try self.emit("; if (@TypeOf(_src) == i64 or @TypeOf(_src) == f64 or @TypeOf(_src) == bool or @TypeOf(_src) == []const u8) { break :deepcopy_blk _src; } if (@typeInfo(@TypeOf(_src)) == .@\"struct\" and @hasField(@TypeOf(_src), \"items\")) { var _copy = @TypeOf(_src).init(__global_allocator); for (_src.items) |item| { _copy.append(__global_allocator, item) catch continue; } break :deepcopy_blk _copy; } break :deepcopy_blk _src; }");
}

fn genReplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("void{}"); return; }
    try self.genExpr(args[0]);
}
