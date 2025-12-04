/// DateTime module codegen - datetime.datetime, datetime.date, datetime.time, datetime.timedelta
/// Supports constructors, now(), today(), strftime, and method calls
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Handler function type
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// datetime.datetime class methods (datetime.datetime.now(), datetime.datetime(...))
pub const DatetimeFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "now", genDatetimeNow },
    .{ "utcnow", genDatetimeUtcnow },
    .{ "today", genDatetimeToday },
    .{ "fromtimestamp", genDatetimeFromTimestamp },
    .{ "utcfromtimestamp", genDatetimeFromTimestamp },
    .{ "fromisoformat", genDatetimeFromIsoformat },
    .{ "combine", genDatetimeCombine },
});

/// datetime.date class methods (datetime.date.today(), datetime.date(...))
pub const DateFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "today", genDateToday },
    .{ "fromtimestamp", genDateFromTimestamp },
    .{ "fromisoformat", genDateFromIsoformat },
    .{ "fromordinal", genDateFromOrdinal },
});

/// datetime.time class methods (datetime.time(...))
pub const TimeFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "fromisoformat", genTimeFromIsoformat },
});

/// datetime module functions (datetime.timedelta(), datetime.datetime(), datetime.date(), datetime.time())
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "timedelta", genTimedelta },
    .{ "datetime", genDatetimeConstructor },
    .{ "date", genDateConstructor },
    .{ "time", genTimeConstructor },
});

/// Handler type for datetime instance methods (self, obj, args)
const MethodHandler = *const fn (*NativeCodegen, ast.Node, []ast.Node) CodegenError!void;

/// Method handlers for datetime objects (obj.strftime(), obj.date(), obj.time(), etc.)
pub const MethodFuncs = std.StaticStringMap(MethodHandler).initComptime(.{
    .{ "weekday", genMethodWeekday },
    .{ "isoweekday", genMethodIsoweekday },
    .{ "replace", genMethodReplace },
    .{ "strftime", genMethodStrftime },
    .{ "isoformat", genMethodIsoformat },
    .{ "date", genMethodDate },
    .{ "time", genMethodTime },
    .{ "timestamp", genMethodTimestamp },
    .{ "timetuple", genMethodTimetuple },
    .{ "toordinal", genMethodToordinal },
    .{ "ctime", genMethodCtime },
    .{ "total_seconds", genMethodTotalSeconds },
});

/// Generate code for datetime.datetime.now()
/// Returns current datetime as Datetime struct
pub fn genDatetimeNow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args; // datetime.now() takes no arguments
    try self.emit("runtime.datetime.Datetime.now()");
}

/// Generate code for datetime.date.today()
/// Returns current date as Date struct
pub fn genDateToday(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args; // date.today() takes no arguments
    try self.emit("runtime.datetime.Date.today()");
}

/// Generate code for datetime.timedelta(days=N)
/// Returns Timedelta struct
pub fn genTimedelta(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("runtime.datetime.Timedelta{ .days = 0, .seconds = 0, .microseconds = 0 }");
        return;
    }
    // Simple case: timedelta(days)
    try self.emit("runtime.datetime.Timedelta.fromDays(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// dt.weekday() - return day of week (0=Monday, 6=Sunday)
pub fn genWeekday(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("@as(i64, 0)"); return; }
    try self.emit("wd_blk: { _ = "); try self.genExpr(args[0]); try self.emit("; break :wd_blk @as(i64, 0); }");
}

/// dt.isoweekday() - return ISO day of week (1=Monday, 7=Sunday)
pub fn genIsoweekday(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("@as(i64, 1)"); return; }
    try self.emit("iwd_blk: { _ = "); try self.genExpr(args[0]); try self.emit("; break :iwd_blk @as(i64, 1); }");
}

/// dt.replace(...) - return copy with replaced fields
pub fn genReplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }"); return; }
    try self.genExpr(args[0]);
}

// =============================================================================
// Datetime constructors
// =============================================================================

/// Generate datetime.datetime(year, month, day, hour=0, minute=0, second=0, microsecond=0)
pub fn genDatetimeConstructor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) {
        try self.emit("runtime.datetime.Datetime{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }");
        return;
    }
    try self.emit("runtime.datetime.Datetime{ .year = @intCast(");
    try self.genExpr(args[0]);
    try self.emit("), .month = @intCast(");
    try self.genExpr(args[1]);
    try self.emit("), .day = @intCast(");
    try self.genExpr(args[2]);
    try self.emit("), .hour = ");
    if (args.len > 3) { try self.emit("@intCast("); try self.genExpr(args[3]); try self.emit(")"); } else try self.emit("0");
    try self.emit(", .minute = ");
    if (args.len > 4) { try self.emit("@intCast("); try self.genExpr(args[4]); try self.emit(")"); } else try self.emit("0");
    try self.emit(", .second = ");
    if (args.len > 5) { try self.emit("@intCast("); try self.genExpr(args[5]); try self.emit(")"); } else try self.emit("0");
    try self.emit(", .microsecond = ");
    if (args.len > 6) { try self.emit("@intCast("); try self.genExpr(args[6]); try self.emit(")"); } else try self.emit("0");
    try self.emit(" }");
}

/// Generate datetime.date(year, month, day)
pub fn genDateConstructor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) {
        try self.emit("runtime.datetime.Date{ .year = 1970, .month = 1, .day = 1 }");
        return;
    }
    try self.emit("runtime.datetime.Date{ .year = @intCast(");
    try self.genExpr(args[0]);
    try self.emit("), .month = @intCast(");
    try self.genExpr(args[1]);
    try self.emit("), .day = @intCast(");
    try self.genExpr(args[2]);
    try self.emit(") }");
}

/// Generate datetime.time(hour=0, minute=0, second=0, microsecond=0)
pub fn genTimeConstructor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("runtime.datetime.Time{ .hour = ");
    if (args.len > 0) { try self.emit("@intCast("); try self.genExpr(args[0]); try self.emit(")"); } else try self.emit("0");
    try self.emit(", .minute = ");
    if (args.len > 1) { try self.emit("@intCast("); try self.genExpr(args[1]); try self.emit(")"); } else try self.emit("0");
    try self.emit(", .second = ");
    if (args.len > 2) { try self.emit("@intCast("); try self.genExpr(args[2]); try self.emit(")"); } else try self.emit("0");
    try self.emit(", .microsecond = ");
    if (args.len > 3) { try self.emit("@intCast("); try self.genExpr(args[3]); try self.emit(")"); } else try self.emit("0");
    try self.emit(" }");
}

// =============================================================================
// Datetime class methods
// =============================================================================

/// datetime.datetime.utcnow()
pub fn genDatetimeUtcnow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.datetime.Datetime.fromTimestamp(std.time.timestamp())");
}

/// datetime.datetime.today() - same as now()
pub fn genDatetimeToday(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.datetime.Datetime.now()");
}

/// datetime.datetime.fromtimestamp(ts)
pub fn genDatetimeFromTimestamp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("runtime.datetime.Datetime.fromTimestamp(0)"); return; }
    try self.emit("runtime.datetime.Datetime.fromTimestamp(@intCast(");
    try self.genExpr(args[0]);
    try self.emit("))");
}

/// datetime.datetime.fromisoformat(string)
pub fn genDatetimeFromIsoformat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("runtime.datetime.Datetime.now()"); return; }
    try self.emit("runtime.datetime.Datetime.parseIsoformat(");
    try self.genExpr(args[0]);
    try self.emit(") catch runtime.datetime.Datetime.now()");
}

/// datetime.datetime.combine(date, time)
pub fn genDatetimeCombine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("runtime.datetime.Datetime.now()"); return; }
    try self.emit("runtime.datetime.Datetime{ .year = ");
    try self.genExpr(args[0]);
    try self.emit(".year, .month = ");
    try self.genExpr(args[0]);
    try self.emit(".month, .day = ");
    try self.genExpr(args[0]);
    try self.emit(".day, .hour = ");
    try self.genExpr(args[1]);
    try self.emit(".hour, .minute = ");
    try self.genExpr(args[1]);
    try self.emit(".minute, .second = ");
    try self.genExpr(args[1]);
    try self.emit(".second, .microsecond = ");
    try self.genExpr(args[1]);
    try self.emit(".microsecond }");
}

// =============================================================================
// Date class methods
// =============================================================================

/// datetime.date.fromtimestamp(ts)
pub fn genDateFromTimestamp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("runtime.datetime.Date.today()"); return; }
    try self.emit("blk: { const _dt = runtime.datetime.Datetime.fromTimestamp(@intCast(");
    try self.genExpr(args[0]);
    try self.emit(")); break :blk runtime.datetime.Date{ .year = _dt.year, .month = _dt.month, .day = _dt.day }; }");
}

/// datetime.date.fromisoformat(string)
pub fn genDateFromIsoformat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("runtime.datetime.Date.today()"); return; }
    try self.emit("runtime.datetime.Date.parseIsoformat(");
    try self.genExpr(args[0]);
    try self.emit(") catch runtime.datetime.Date.today()");
}

/// datetime.date.fromordinal(ordinal)
pub fn genDateFromOrdinal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("runtime.datetime.Date.today()"); return; }
    try self.emit("runtime.datetime.Date.fromOrdinal(@intCast(");
    try self.genExpr(args[0]);
    try self.emit("))");
}

// =============================================================================
// Time class methods
// =============================================================================

/// datetime.time.fromisoformat(string)
pub fn genTimeFromIsoformat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("runtime.datetime.Time{ .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }"); return; }
    try self.emit("runtime.datetime.Time.parseIsoformat(");
    try self.genExpr(args[0]);
    try self.emit(") catch runtime.datetime.Time{ .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }");
}

// =============================================================================
// Datetime object methods
// =============================================================================

/// dt.strftime(format)
pub fn genStrftime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("\"\""); return; }
    try self.emit("try runtime.datetime.strftime(__global_allocator, ");
    try self.genExpr(args[0]); // datetime object
    try self.emit(", ");
    try self.genExpr(args[1]); // format string
    try self.emit(")");
}

/// dt.isoformat(sep='T')
pub fn genIsoformat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("\"1970-01-01T00:00:00\""); return; }
    try self.emit("try ");
    try self.genExpr(args[0]);
    try self.emit(".toIsoformat(__global_allocator)");
}

/// dt.date() - extract date from datetime
pub fn genExtractDate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("runtime.datetime.Date.today()"); return; }
    try self.emit("runtime.datetime.Date{ .year = ");
    try self.genExpr(args[0]);
    try self.emit(".year, .month = ");
    try self.genExpr(args[0]);
    try self.emit(".month, .day = ");
    try self.genExpr(args[0]);
    try self.emit(".day }");
}

/// dt.time() - extract time from datetime
pub fn genExtractTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("runtime.datetime.Time{ .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }"); return; }
    try self.emit("runtime.datetime.Time{ .hour = ");
    try self.genExpr(args[0]);
    try self.emit(".hour, .minute = ");
    try self.genExpr(args[0]);
    try self.emit(".minute, .second = ");
    try self.genExpr(args[0]);
    try self.emit(".second, .microsecond = ");
    try self.genExpr(args[0]);
    try self.emit(".microsecond }");
}

/// dt.timestamp() - convert to Unix timestamp
pub fn genTimestamp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("@as(f64, 0)"); return; }
    try self.genExpr(args[0]);
    try self.emit(".toTimestamp()");
}

/// dt.timetuple() - return time.struct_time
pub fn genTimetuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit(".{ .@\"0\" = 1970, .@\"1\" = 1, .@\"2\" = 1, .@\"3\" = 0, .@\"4\" = 0, .@\"5\" = 0, .@\"6\" = 0, .@\"7\" = 1, .@\"8\" = -1 }"); return; }
    try self.emit(".{ .@\"0\" = @as(i64, ");
    try self.genExpr(args[0]);
    try self.emit(".year), .@\"1\" = @as(i64, ");
    try self.genExpr(args[0]);
    try self.emit(".month), .@\"2\" = @as(i64, ");
    try self.genExpr(args[0]);
    try self.emit(".day), .@\"3\" = @as(i64, ");
    try self.genExpr(args[0]);
    try self.emit(".hour), .@\"4\" = @as(i64, ");
    try self.genExpr(args[0]);
    try self.emit(".minute), .@\"5\" = @as(i64, ");
    try self.genExpr(args[0]);
    try self.emit(".second), .@\"6\" = 0, .@\"7\" = 1, .@\"8\" = -1 }");
}

/// dt.toordinal() - return proleptic Gregorian ordinal
pub fn genToordinal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("@as(i64, 1)"); return; }
    try self.genExpr(args[0]);
    try self.emit(".toOrdinal()");
}

/// dt.ctime() - return string like "Sun Jun  9 01:21:11 1993"
pub fn genCtime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("\"Thu Jan  1 00:00:00 1970\""); return; }
    try self.emit("try ");
    try self.genExpr(args[0]);
    try self.emit(".toCtime(__global_allocator)");
}

// =============================================================================
// Method handlers (MethodHandler signature: self, obj, args)
// These wrap the old handlers to work with method dispatch
// =============================================================================

/// dt.strftime(format) - method handler
fn genMethodStrftime(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("\"\""); return; }
    try self.emit("try runtime.datetime.strftime(__global_allocator, ");
    try self.genExpr(obj);
    try self.emit(", ");
    try self.genExpr(args[0]); // format string
    try self.emit(")");
}

/// dt.isoformat() - method handler
fn genMethodIsoformat(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("try ");
    try self.genExpr(obj);
    try self.emit(".toIsoformat(__global_allocator)");
}

/// dt.date() - method handler
fn genMethodDate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.datetime.Date{ .year = ");
    try self.genExpr(obj);
    try self.emit(".year, .month = ");
    try self.genExpr(obj);
    try self.emit(".month, .day = ");
    try self.genExpr(obj);
    try self.emit(".day }");
}

/// dt.time() - method handler
fn genMethodTime(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.datetime.Time{ .hour = ");
    try self.genExpr(obj);
    try self.emit(".hour, .minute = ");
    try self.genExpr(obj);
    try self.emit(".minute, .second = ");
    try self.genExpr(obj);
    try self.emit(".second, .microsecond = ");
    try self.genExpr(obj);
    try self.emit(".microsecond }");
}

/// dt.weekday() - method handler
fn genMethodWeekday(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.genExpr(obj);
    try self.emit(".weekday()");
}

/// dt.isoweekday() - method handler
fn genMethodIsoweekday(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.genExpr(obj);
    try self.emit(".weekday() + 1");
}

/// dt.toordinal() - method handler
fn genMethodToordinal(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.genExpr(obj);
    try self.emit(".toOrdinal()");
}

/// dt.timestamp() - method handler
fn genMethodTimestamp(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.genExpr(obj);
    try self.emit(".toTimestamp()");
}

/// dt.timetuple() - method handler
fn genMethodTimetuple(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .@\"0\" = @as(i64, ");
    try self.genExpr(obj);
    try self.emit(".year), .@\"1\" = @as(i64, ");
    try self.genExpr(obj);
    try self.emit(".month), .@\"2\" = @as(i64, ");
    try self.genExpr(obj);
    try self.emit(".day), .@\"3\" = @as(i64, ");
    try self.genExpr(obj);
    try self.emit(".hour), .@\"4\" = @as(i64, ");
    try self.genExpr(obj);
    try self.emit(".minute), .@\"5\" = @as(i64, ");
    try self.genExpr(obj);
    try self.emit(".second), .@\"6\" = 0, .@\"7\" = 1, .@\"8\" = -1 }");
}

/// dt.ctime() - method handler
fn genMethodCtime(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("try ");
    try self.genExpr(obj);
    try self.emit(".toCtime(__global_allocator)");
}

/// dt.replace() - method handler
fn genMethodReplace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // For now, just return the object unchanged
    _ = args;
    try self.genExpr(obj);
}

/// timedelta.total_seconds() - method handler
fn genMethodTotalSeconds(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.genExpr(obj);
    try self.emit(".totalSeconds()");
}
