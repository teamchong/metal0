/// Python urllib.robotparser module - robots.txt parser
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "RobotFileParser", genRobotFileParser },
});

fn genRobotFileParser(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        // With argument: .{ .url = __v, .last_checked = @as(i64, 0) }
        try b.write(".{ .url = ");
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.write(", .last_checked = @as(i64, 0) }");
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
    } else {
        // Without argument: default struct
        try b.write(".{ .url = \"\", .last_checked = @as(i64, 0) }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}
