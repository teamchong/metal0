/// Python graphlib module - Topological sorting algorithms
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "TopologicalSorter", genTopologicalSorter },
    .{ "CycleError", genCycleError },
});

fn genTopologicalSorter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { nodes: std.ArrayList([]const u8) = .{}, edges: hashmap_helper.StringHashMap(std.ArrayList([]const u8)) = .{}, prepared: bool = false, pub fn add(__self: *@This(), node: []const u8, predecessors: anytype) void { __self.nodes.append(__global_allocator, node) catch unreachable; _ = predecessors; } pub fn prepare(__self: *@This()) void { __self.prepared = true; } pub fn is_active(__self: *@This()) bool { return __self.nodes.items.len > 0; } pub fn get_ready(__self: *@This()) [][]const u8 { if (!__self.prepared) __self.prepare(); return __self.nodes.items; } pub fn done(__self: *@This(), nodes: anytype) void { _ = nodes; } pub fn static_order(__self: *@This()) [][]const u8 { __self.prepare(); return __self.nodes.items; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genCycleError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("CycleError"), builder_mod.EmitConfig.forExpression());
}
