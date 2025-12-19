/// Python dbm module - Interfaces to Unix databases
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen },
    .{ "error", genError },
    .{ "whichdb", genWhichdb },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // With argument: .{ .path = __v, .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }
        try emitConst(self, ".{ .path = ");
        try self.genExpr(args[0]);
        try emitConst(self, ", .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }");
    } else {
        // Without argument: default struct
        try emitConst(self, ".{ .path = \"\", .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }");
    }
}

fn genError(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "error.DbmError");
}

fn genWhichdb(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "@as(?[]const u8, \"dbm.dumb\")");
}
