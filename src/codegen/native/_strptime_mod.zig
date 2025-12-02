/// Python _strptime module - Internal strptime implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "_strptime_time", genStrptimeTime }, .{ "_strptime_datetime", genStrptimeDatetime },
    .{ "TimeRE", genEmpty }, .{ "LocaleTime", genLocaleTime },
    .{ "_cache_lock", genEmpty }, .{ "_TimeRE_cache", genEmpty }, .{ "_CACHE_MAX_SIZE", genCacheMaxSize },
    .{ "_regex_cache", genEmpty }, .{ "_getlang", genGetlang },
    .{ "_calc_julian_from_U_or_W", genI32_1 }, .{ "_calc_julian_from_V", genI32_1 },
});

fn genStrptimeTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .tm_year = 0, .tm_mon = 1, .tm_mday = 1, .tm_hour = 0, .tm_min = 0, .tm_sec = 0, .tm_wday = 0, .tm_yday = 1, .tm_isdst = -1 }"); }
fn genStrptimeDatetime(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .year = 1900, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }"); }
fn genLocaleTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .lang = \"en_US\", .LC_time = null }"); }
fn genCacheMaxSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 5)"); }
fn genGetlang(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"en_US\", \"UTF-8\" }"); }
