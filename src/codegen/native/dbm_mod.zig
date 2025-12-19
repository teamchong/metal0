/// Python dbm module - Interfaces to Unix databases
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen },
    .{ "error", genError },
    .{ "whichdb", genWhichdb },
});

fn genOpen(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        // With argument: .{ .path = __v, .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }
        try b.write(".{ .path = ");
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.write(", .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }");
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
    } else {
        // Without argument: default struct
        try b.write(".{ .path = \"\", .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("error.DbmError");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genWhichdb(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(?[]const u8, \"dbm.dumb\")");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
