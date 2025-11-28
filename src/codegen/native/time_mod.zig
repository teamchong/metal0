/// Python time module - time-related functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate time.time() -> float (seconds since epoch)
pub fn genTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, @floatFromInt(std.time.timestamp()))");
}

/// Generate time.time_ns() -> int (nanoseconds since epoch)
pub fn genTimeNs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, @intCast(std.time.nanoTimestamp()))");
}

/// Generate time.sleep(seconds) -> None
pub fn genSleep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("std.time.sleep(@as(u64, @intFromFloat(");
    try self.genExpr(args[0]);
    try self.emit(" * 1_000_000_000)))");
}

/// Generate time.perf_counter() -> float (high-resolution timer)
pub fn genPerfCounter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("perf_counter_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _t = std.time.nanoTimestamp();\n");
    try self.emitIndent();
    try self.emit("break :perf_counter_blk @as(f64, @floatFromInt(_t)) / 1_000_000_000.0;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate time.perf_counter_ns() -> int (high-resolution timer in nanoseconds)
pub fn genPerfCounterNs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, @intCast(std.time.nanoTimestamp()))");
}

/// Generate time.monotonic() -> float (monotonic clock)
pub fn genMonotonic(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("monotonic_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _t = std.time.nanoTimestamp();\n");
    try self.emitIndent();
    try self.emit("break :monotonic_blk @as(f64, @floatFromInt(_t)) / 1_000_000_000.0;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate time.monotonic_ns() -> int
pub fn genMonotonicNs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, @intCast(std.time.nanoTimestamp()))");
}

/// Generate time.process_time() -> float (CPU time for current process)
pub fn genProcessTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Use monotonic time as approximation
    try self.emit("@as(f64, @floatFromInt(std.time.nanoTimestamp())) / 1_000_000_000.0");
}

/// Generate time.process_time_ns() -> int
pub fn genProcessTimeNs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, @intCast(std.time.nanoTimestamp()))");
}

/// Generate time.ctime(secs=None) -> string
pub fn genCtime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Return a fixed format for now
    try self.emit("\"Thu Jan  1 00:00:00 1970\"");
}

/// Generate time.gmtime(secs=None) -> struct_time
pub fn genGmtime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("gmtime_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _ts: i64 = @intCast(std.time.timestamp());\n");
    try self.emitIndent();
    try self.emit("const _epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(_ts) };\n");
    try self.emitIndent();
    try self.emit("const _day = _epoch.getEpochDay();\n");
    try self.emitIndent();
    try self.emit("const _year_day = _day.calculateYearDay();\n");
    try self.emitIndent();
    try self.emit("const _day_seconds = _epoch.getDaySeconds();\n");
    try self.emitIndent();
    try self.emit("break :gmtime_blk .{\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".tm_year = _year_day.year,\n");
    try self.emitIndent();
    try self.emit(".tm_mon = @as(i32, @intFromEnum(_year_day.month)),\n");
    try self.emitIndent();
    try self.emit(".tm_mday = _day.calculateYearDay().day_of_month,\n");
    try self.emitIndent();
    try self.emit(".tm_hour = _day_seconds.getHoursIntoDay(),\n");
    try self.emitIndent();
    try self.emit(".tm_min = _day_seconds.getMinutesIntoHour(),\n");
    try self.emitIndent();
    try self.emit(".tm_sec = _day_seconds.getSecondsIntoMinute(),\n");
    try self.emitIndent();
    try self.emit(".tm_wday = @as(i32, @intFromEnum(_day.dayOfWeek())),\n");
    try self.emitIndent();
    try self.emit(".tm_yday = _year_day.getDayOfYear(),\n");
    try self.emitIndent();
    try self.emit(".tm_isdst = 0,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate time.localtime(secs=None) -> struct_time
pub fn genLocaltime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // For now, same as gmtime
    try genGmtime(self, args);
}

/// Generate time.mktime(t) -> float
pub fn genMktime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, @floatFromInt(std.time.timestamp()))");
}

/// Generate time.strftime(format, t=None) -> string
pub fn genStrftime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    // Placeholder - return the format string
    try self.genExpr(args[0]);
}

/// Generate time.strptime(string, format) -> struct_time
pub fn genStrptime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Placeholder - return a default struct_time
    try self.emit(".{ .tm_year = 1970, .tm_mon = 1, .tm_mday = 1, .tm_hour = 0, .tm_min = 0, .tm_sec = 0, .tm_wday = 0, .tm_yday = 0, .tm_isdst = 0 }");
}

/// Generate time.get_clock_info(name) -> clock_info
pub fn genGetClockInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .implementation = \"std.time\", .monotonic = true, .adjustable = false, .resolution = 1e-9 }");
}
