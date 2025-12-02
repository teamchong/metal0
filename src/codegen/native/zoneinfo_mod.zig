/// Python zoneinfo module - IANA time zone support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genUTC(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"UTC\""); }
fn genTimedelta(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .days = 0, .seconds = 0, .microseconds = 0 }"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ZoneInfo", genZoneInfo }, .{ "available_timezones", genAvailableTimezones }, .{ "reset_tzpath", genUnit }, .{ "TZPATH", genTZPATH },
    .{ "key", genUTC }, .{ "utcoffset", genTimedelta }, .{ "tzname", genUTC }, .{ "dst", genTimedelta },
    .{ "fromutc", genFromutc }, .{ "no_cache", genZoneInfo }, .{ "clear_cache", genUnit },
    .{ "ZoneInfoNotFoundError", genZoneInfoNotFoundError }, .{ "InvalidTZPathWarning", genInvalidTZPathWarning },
});

fn genZoneInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit(".{ .key = "); try self.genExpr(args[0]); try self.emit(" }"); } else try self.emit(".{ .key = \"UTC\" }"); }
fn genAvailableTimezones(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"UTC\", \"America/New_York\", \"America/Los_Angeles\", \"America/Chicago\", \"Europe/London\", \"Europe/Paris\", \"Europe/Berlin\", \"Asia/Tokyo\", \"Asia/Shanghai\", \"Asia/Singapore\", \"Australia/Sydney\", \"Pacific/Auckland\" }"); }
fn genTZPATH(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"/usr/share/zoneinfo\", \"/usr/lib/zoneinfo\", \"/usr/share/lib/zoneinfo\", \"/etc/zoneinfo\" }"); }
fn genFromutc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }"); }
fn genZoneInfoNotFoundError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ZoneInfoNotFoundError"); }
fn genInvalidTZPathWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.InvalidTZPathWarning"); }
