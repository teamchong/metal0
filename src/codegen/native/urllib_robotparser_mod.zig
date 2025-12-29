/// Python urllib.robotparser module - robots.txt parser
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "RobotFileParser", genRobotFileParser },
});

const ZigBuilder = builder_mod.ZigBuilder;
const ZigValue = builder_mod.ZigValue;

fn genRobotFileParser(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        // With argument: .{ .url = __v, .last_checked = @as(i64, 0) }
        const url_val = try self.captureExpr(args[0]);
        try b.withLabeledBlock("__rfp", struct {
            fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: ZigValue) !void {
                try bld.emitConstWithValue("__url", "", ctx, "");
                try scope.breakWithRaw(".{ .url = __url, .last_checked = @as(i64, 0) }");
            }
        }.emit, url_val);
    } else {
        // Without argument: default struct
        try b.emitRaw(".{ .url = \"\", .last_checked = @as(i64, 0) }");
    }
    try self.flushBuilder();
}
