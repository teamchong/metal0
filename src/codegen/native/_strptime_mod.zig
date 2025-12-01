/// Python _strptime module - Internal strptime implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "_strptime_time", genStrptimeTime },
    .{ "_strptime_datetime", genStrptimeDatetime },
    .{ "TimeRE", genTimeRE },
    .{ "LocaleTime", genLocaleTime },
    .{ "_cache_lock", genCacheLock },
    .{ "_TimeRE_cache", genTimeRECache },
    .{ "_CACHE_MAX_SIZE", genCacheMaxSize },
    .{ "_regex_cache", genRegexCache },
    .{ "_getlang", genGetlang },
    .{ "_calc_julian_from_U_or_W", genCalcJulianFromUOrW },
    .{ "_calc_julian_from_V", genCalcJulianFromV },
});

/// Generate _strptime._strptime_time(data_string, format="%a %b %d %H:%M:%S %Y")
pub fn genStrptimeTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .tm_year = 0, .tm_mon = 1, .tm_mday = 1, .tm_hour = 0, .tm_min = 0, .tm_sec = 0, .tm_wday = 0, .tm_yday = 1, .tm_isdst = -1 }");
}

/// Generate _strptime._strptime_datetime(cls, data_string, format="%a %b %d %H:%M:%S %Y")
pub fn genStrptimeDatetime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .year = 1900, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }");
}

/// Generate _strptime.TimeRE class
pub fn genTimeRE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _strptime.LocaleTime class
pub fn genLocaleTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .lang = \"en_US\", .LC_time = null }");
}

/// Generate _strptime._cache_lock constant
pub fn genCacheLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _strptime._TimeRE_cache constant
pub fn genTimeRECache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _strptime._CACHE_MAX_SIZE constant
pub fn genCacheMaxSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 5)");
}

/// Generate _strptime._regex_cache dict
pub fn genRegexCache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _strptime._getlang()
pub fn genGetlang(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"en_US\", \"UTF-8\" }");
}

/// Generate _strptime._calc_julian_from_U_or_W(year, week_of_year, day_of_week, week_starts_Mon)
pub fn genCalcJulianFromUOrW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate _strptime._calc_julian_from_V(iso_year, iso_week, iso_weekday)
pub fn genCalcJulianFromV(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}
