/// Python time module - time-related functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "time", genConst("@as(f64, @floatFromInt(std.time.timestamp()))") },
    .{ "time_ns", genConst("@as(i64, @intCast(std.time.nanoTimestamp()))") },
    .{ "sleep", genSleep },
    .{ "perf_counter", genConst("blk: { const _t = std.time.nanoTimestamp(); break :blk @as(f64, @floatFromInt(_t)) / 1_000_000_000.0; }") },
    .{ "perf_counter_ns", genConst("@as(i64, @intCast(std.time.nanoTimestamp()))") },
    .{ "monotonic", genConst("blk: { const _t = std.time.nanoTimestamp(); break :blk @as(f64, @floatFromInt(_t)) / 1_000_000_000.0; }") },
    .{ "monotonic_ns", genConst("@as(i64, @intCast(std.time.nanoTimestamp()))") },
    .{ "process_time", genConst("@as(f64, @floatFromInt(std.time.nanoTimestamp())) / 1_000_000_000.0") },
    .{ "process_time_ns", genConst("@as(i64, @intCast(std.time.nanoTimestamp()))") },
    .{ "ctime", genConst("\"Thu Jan  1 00:00:00 1970\"") },
    .{ "gmtime", genGmtime }, .{ "localtime", genGmtime },
    .{ "mktime", genConst("@as(f64, @floatFromInt(std.time.timestamp()))") },
    .{ "strftime", genStrftime },
    .{ "strptime", genConst(".{ .tm_year = 1970, .tm_mon = 1, .tm_mday = 1, .tm_hour = 0, .tm_min = 0, .tm_sec = 0, .tm_wday = 0, .tm_yday = 0, .tm_isdst = 0 }") },
    .{ "get_clock_info", genConst(".{ .implementation = \"std.time\", .monotonic = true, .adjustable = false, .resolution = 1e-9 }") },
});

fn genSleep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const is_class_instance = (arg_type == .class_instance) or (args[0] == .call and args[0].call.func.* == .name and std.ascii.isUpper(args[0].call.func.name.id[0]));
    try self.emit("std.Thread.sleep(@as(u64, @intFromFloat(");
    if (is_class_instance) { try self.emit("(runtime.floatBuiltinCall("); try self.genExpr(args[0]); try self.emit(", .{}) catch 0.0)"); } else { try self.genExpr(args[0]); }
    try self.emit(" * 1_000_000_000)))");
}

fn genGmtime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { const _ts: i64 = @intCast(std.time.timestamp()); const _epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(_ts) }; const _day = _epoch.getEpochDay(); const _year_day = _day.calculateYearDay(); const _day_seconds = _epoch.getDaySeconds(); break :blk .{ .tm_year = _year_day.year, .tm_mon = @as(i32, @intFromEnum(_year_day.month)), .tm_mday = _day.calculateYearDay().day_of_month, .tm_hour = _day_seconds.getHoursIntoDay(), .tm_min = _day_seconds.getMinutesIntoHour(), .tm_sec = _day_seconds.getSecondsIntoMinute(), .tm_wday = @as(i32, @intFromEnum(_day.dayOfWeek())), .tm_yday = _year_day.getDayOfYear(), .tm_isdst = 0 }; }");
}

fn genStrftime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.genExpr(args[0]);
}
