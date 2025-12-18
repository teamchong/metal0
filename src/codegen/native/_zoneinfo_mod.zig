/// Python _zoneinfo module - Internal zoneinfo support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "zone_info", genZoneInfo },
    .{ "from_file", genFromFile },
    .{ "no_cache", genZoneInfo },
    .{ "clear_cache", genClearCache },
    .{ "key", genKey },
    .{ "utcoffset", genUtcoffset },
    .{ "tzname", genTzname },
    .{ "dst", genDst },
    .{ "t_z_p_a_t_h", genTzpath },
    .{ "reset_tzpath", genResetTzpath },
    .{ "available_timezones", genAvailableTimezones },
    .{ "zone_info_not_found_error", genZoneInfoNotFoundError },
    .{ "invalid_t_z_path_warning", genInvalidTzPathWarning },
});

fn genZoneInfo(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.withInlineBlock("zi", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; break :{s} .{{ .key = __v }}", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .key = \"UTC\" }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genFromFile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .key = \"UTC\" }"), builder_mod.EmitConfig.forExpression());
}

fn genClearCache(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("UTC"), builder_mod.EmitConfig.forExpression());
}

fn genUtcoffset(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genTzname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("UTC"), builder_mod.EmitConfig.forExpression());
}

fn genDst(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genTzpath(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"/usr/share/zoneinfo\", \"/usr/lib/zoneinfo\", \"/usr/share/lib/zoneinfo\", \"/etc/zoneinfo\" }"), builder_mod.EmitConfig.forExpression());
}

fn genResetTzpath(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genAvailableTimezones(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"UTC\", \"GMT\" }"), builder_mod.EmitConfig.forExpression());
}

fn genZoneInfoNotFoundError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.ZoneInfoNotFoundError"), builder_mod.EmitConfig.forExpression());
}

fn genInvalidTzPathWarning(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.InvalidTZPathWarning"), builder_mod.EmitConfig.forExpression());
}
