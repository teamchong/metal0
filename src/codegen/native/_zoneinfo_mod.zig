/// Python _zoneinfo module - Internal zoneinfo support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "zone_info", genZoneInfo }, .{ "from_file", genConst(".{ .key = \"UTC\" }") }, .{ "no_cache", genZoneInfo }, .{ "clear_cache", genConst("{}") },
    .{ "key", genConst("\"UTC\"") }, .{ "utcoffset", genConst("null") }, .{ "tzname", genConst("\"UTC\"") }, .{ "dst", genConst("null") },
    .{ "t_z_p_a_t_h", genConst("&[_][]const u8{ \"/usr/share/zoneinfo\", \"/usr/lib/zoneinfo\", \"/usr/share/lib/zoneinfo\", \"/etc/zoneinfo\" }") },
    .{ "reset_tzpath", genConst("{}") }, .{ "available_timezones", genConst("&[_][]const u8{ \"UTC\", \"GMT\" }") },
    .{ "zone_info_not_found_error", genConst("error.ZoneInfoNotFoundError") }, .{ "invalid_t_z_path_warning", genConst("error.InvalidTZPathWarning") },
});

fn genZoneInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const key = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .key = key }; }"); }
    else try self.emit(".{ .key = \"UTC\" }");
}
