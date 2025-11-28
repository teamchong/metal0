/// Python _zoneinfo module - Internal zoneinfo support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _zoneinfo.ZoneInfo(key)
pub fn genZoneInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const key = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .key = key }; }");
    } else {
        try self.emit(".{ .key = \"UTC\" }");
    }
}

/// Generate _zoneinfo.ZoneInfo.from_file(fobj, key=None)
pub fn genFromFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .key = \"UTC\" }");
}

/// Generate _zoneinfo.ZoneInfo.no_cache(key)
pub fn genNoCache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const key = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .key = key }; }");
    } else {
        try self.emit(".{ .key = \"UTC\" }");
    }
}

/// Generate _zoneinfo.ZoneInfo.clear_cache(*, only_keys=None)
pub fn genClearCache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ZoneInfo.key property
pub fn genKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"UTC\"");
}

/// Generate ZoneInfo.utcoffset(dt)
pub fn genUtcoffset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate ZoneInfo.tzname(dt)
pub fn genTzname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"UTC\"");
}

/// Generate ZoneInfo.dst(dt)
pub fn genDst(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _zoneinfo.TZPATH constant
pub fn genTZPATH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"/usr/share/zoneinfo\", \"/usr/lib/zoneinfo\", \"/usr/share/lib/zoneinfo\", \"/etc/zoneinfo\" }");
}

/// Generate _zoneinfo.reset_tzpath(to=None)
pub fn genResetTzpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _zoneinfo.available_timezones()
pub fn genAvailableTimezones(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"UTC\", \"GMT\" }");
}

/// Generate _zoneinfo.ZoneInfoNotFoundError exception
pub fn genZoneInfoNotFoundError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ZoneInfoNotFoundError");
}

/// Generate _zoneinfo.InvalidTZPathWarning exception
pub fn genInvalidTZPathWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.InvalidTZPathWarning");
}
