/// Python _zoneinfo module - Internal zoneinfo support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genUTC(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"UTC\""); }
fn genDefaultZone(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .key = \"UTC\" }"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "zone_info", genZoneInfo }, .{ "from_file", genDefaultZone }, .{ "no_cache", genZoneInfo }, .{ "clear_cache", genUnit },
    .{ "key", genUTC }, .{ "utcoffset", genNull }, .{ "tzname", genUTC }, .{ "dst", genNull },
    .{ "t_z_p_a_t_h", genTZPATH }, .{ "reset_tzpath", genUnit }, .{ "available_timezones", genAvailableTimezones },
    .{ "zone_info_not_found_error", genZoneInfoNotFoundError }, .{ "invalid_t_z_path_warning", genInvalidTZPathWarning },
});

fn genZoneInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("blk: { const key = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .key = key }; }"); } else try genDefaultZone(self, args); }
fn genTZPATH(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"/usr/share/zoneinfo\", \"/usr/lib/zoneinfo\", \"/usr/share/lib/zoneinfo\", \"/etc/zoneinfo\" }"); }
fn genAvailableTimezones(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"UTC\", \"GMT\" }"); }
fn genZoneInfoNotFoundError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ZoneInfoNotFoundError"); }
fn genInvalidTZPathWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.InvalidTZPathWarning"); }
