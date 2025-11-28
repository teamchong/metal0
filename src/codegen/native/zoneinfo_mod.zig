/// Python zoneinfo module - IANA time zone support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate zoneinfo.ZoneInfo(key)
pub fn genZoneInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ .key = ");
        try self.genExpr(args[0]);
        try self.emit(" }");
    } else {
        try self.emit(".{ .key = \"UTC\" }");
    }
}

/// Generate zoneinfo.available_timezones()
pub fn genAvailableTimezones(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"UTC\", \"America/New_York\", \"America/Los_Angeles\", \"America/Chicago\", \"Europe/London\", \"Europe/Paris\", \"Europe/Berlin\", \"Asia/Tokyo\", \"Asia/Shanghai\", \"Asia/Singapore\", \"Australia/Sydney\", \"Pacific/Auckland\" }");
}

/// Generate zoneinfo.reset_tzpath(to=None)
pub fn genResetTzpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate zoneinfo.TZPATH
pub fn genTZPATH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"/usr/share/zoneinfo\", \"/usr/lib/zoneinfo\", \"/usr/share/lib/zoneinfo\", \"/etc/zoneinfo\" }");
}

/// Generate ZoneInfo.key property
pub fn genKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"UTC\"");
}

/// Generate ZoneInfo.utcoffset(dt)
pub fn genUtcoffset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .days = 0, .seconds = 0, .microseconds = 0 }");
}

/// Generate ZoneInfo.tzname(dt)
pub fn genTzname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"UTC\"");
}

/// Generate ZoneInfo.dst(dt)
pub fn genDst(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .days = 0, .seconds = 0, .microseconds = 0 }");
}

/// Generate ZoneInfo.fromutc(dt)
pub fn genFromutc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }");
    }
}

/// Generate ZoneInfo.no_cache(key)
pub fn genNoCache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ .key = ");
        try self.genExpr(args[0]);
        try self.emit(" }");
    } else {
        try self.emit(".{ .key = \"UTC\" }");
    }
}

/// Generate ZoneInfo.clear_cache(*, only_keys=None)
pub fn genClearCache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate zoneinfo.ZoneInfoNotFoundError
pub fn genZoneInfoNotFoundError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ZoneInfoNotFoundError");
}

/// Generate zoneinfo.InvalidTZPathWarning
pub fn genInvalidTZPathWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.InvalidTZPathWarning");
}
