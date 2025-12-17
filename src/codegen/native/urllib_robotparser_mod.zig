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
    if (args.len > 0) {
        // With argument: .{ .url = __v, .last_checked = @as(i64, 0) }
        try self.emit(".{ .url = ");
        try self.genExpr(args[0]);
        try self.emit(", .last_checked = @as(i64, 0) }");
    } else {
        // Without argument: default struct
        const b = try self.getBuilder();
        try b.emitValue(builder_mod.ZigValue.raw(".{ .url = \"\", .last_checked = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}
