/// Python zoneinfo module - IANA time zone support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ZoneInfo", genZoneInfo }, .{ "available_timezones", genConst("&[_][]const u8{ \"UTC\", \"America/New_York\", \"America/Los_Angeles\", \"America/Chicago\", \"Europe/London\", \"Europe/Paris\", \"Europe/Berlin\", \"Asia/Tokyo\", \"Asia/Shanghai\", \"Asia/Singapore\", \"Australia/Sydney\", \"Pacific/Auckland\" }") },
    .{ "reset_tzpath", genConst("{}") }, .{ "TZPATH", genConst("&[_][]const u8{ \"/usr/share/zoneinfo\", \"/usr/lib/zoneinfo\", \"/usr/share/lib/zoneinfo\", \"/etc/zoneinfo\" }") },
    .{ "key", genConst("\"UTC\"") }, .{ "utcoffset", genConst(".{ .days = 0, .seconds = 0, .microseconds = 0 }") },
    .{ "tzname", genConst("\"UTC\"") }, .{ "dst", genConst(".{ .days = 0, .seconds = 0, .microseconds = 0 }") },
    .{ "fromutc", genFromutc }, .{ "no_cache", genZoneInfo }, .{ "clear_cache", genConst("{}") },
    .{ "ZoneInfoNotFoundError", genConst("error.ZoneInfoNotFoundError") }, .{ "InvalidTZPathWarning", genConst("error.InvalidTZPathWarning") },
});

fn genZoneInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit(".{ .key = "); try self.genExpr(args[0]); try self.emit(" }"); }
    else try self.emit(".{ .key = \"UTC\" }");
}
fn genFromutc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0])
    else try self.emit(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }");
}
