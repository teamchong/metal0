/// Python graphlib module - Topological sorting algorithms
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "TopologicalSorter", genTopologicalSorter },
    .{ "CycleError", genCycleError },
});

/// Generate graphlib.TopologicalSorter(graph=None)
pub fn genTopologicalSorter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("nodes: std.ArrayList([]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("edges: hashmap_helper.StringHashMap(std.ArrayList([]const u8)) = .{},\n");
    try self.emitIndent();
    try self.emit("prepared: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn add(self: *@This(), node: []const u8, predecessors: anytype) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.nodes.append(__global_allocator, node) catch {};\n");
    try self.emitIndent();
    try self.emit("_ = predecessors;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn prepare(self: *@This()) void { self.prepared = true; }\n");
    try self.emitIndent();
    try self.emit("pub fn is_active(self: *@This()) bool { return self.nodes.items.len > 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn get_ready(self: *@This()) [][]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (!self.prepared) self.prepare();\n");
    try self.emitIndent();
    try self.emit("return self.nodes.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn done(self: *@This(), nodes: anytype) void { _ = self; _ = nodes; }\n");
    try self.emitIndent();
    try self.emit("pub fn static_order(self: *@This()) [][]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.prepare();\n");
    try self.emitIndent();
    try self.emit("return self.nodes.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate graphlib.CycleError exception
pub fn genCycleError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"CycleError\"");
}
