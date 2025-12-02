/// Python _strptime module - Internal strptime implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "_strptime_time", genConst(".{ .tm_year = 0, .tm_mon = 1, .tm_mday = 1, .tm_hour = 0, .tm_min = 0, .tm_sec = 0, .tm_wday = 0, .tm_yday = 1, .tm_isdst = -1 }") },
    .{ "_strptime_datetime", genConst(".{ .year = 1900, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }") },
    .{ "TimeRE", genConst(".{}") }, .{ "LocaleTime", genConst(".{ .lang = \"en_US\", .LC_time = null }") },
    .{ "_cache_lock", genConst(".{}") }, .{ "_TimeRE_cache", genConst(".{}") }, .{ "_CACHE_MAX_SIZE", genConst("@as(u32, 5)") },
    .{ "_regex_cache", genConst(".{}") }, .{ "_getlang", genConst(".{ \"en_US\", \"UTF-8\" }") },
    .{ "_calc_julian_from_U_or_W", genConst("@as(i32, 1)") }, .{ "_calc_julian_from_V", genConst("@as(i32, 1)") },
});
