/// Python time module - time-related functions
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

const ns_to_sec = h.c("blk: { const _t = std.time.nanoTimestamp(); break :blk @as(f64, @floatFromInt(_t)) / 1_000_000_000.0; }");
const nano_ts = h.c("@as(i64, @intCast(std.time.nanoTimestamp()))");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "time", h.c("@as(f64, @floatFromInt(std.time.timestamp()))") },
    .{ "time_ns", nano_ts }, .{ "sleep", genSleep },
    .{ "perf_counter", ns_to_sec }, .{ "perf_counter_ns", nano_ts },
    .{ "monotonic", ns_to_sec }, .{ "monotonic_ns", nano_ts },
    .{ "process_time", ns_to_sec }, .{ "process_time_ns", nano_ts },
    .{ "ctime", h.c("\"Thu Jan  1 00:00:00 1970\"") },
    .{ "gmtime", genGmtime }, .{ "localtime", genGmtime },
    .{ "mktime", h.stub("@as(f64, @floatFromInt(std.time.timestamp()))") },
    .{ "strftime", h.pass("\"\"") },
    .{ "strptime", h.c(".{ .tm_year = 1970, .tm_mon = 1, .tm_mday = 1, .tm_hour = 0, .tm_min = 0, .tm_sec = 0, .tm_wday = 0, .tm_yday = 0, .tm_isdst = 0 }") },
    .{ "get_clock_info", h.c(".{ .implementation = \"std.time\", .monotonic = true, .adjustable = false, .resolution = 1e-9 }") },
});

fn genSleep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const is_class_instance = (arg_type == .class_instance) or (args[0] == .call and args[0].call.func.* == .name and std.ascii.isUpper(args[0].call.func.name.id[0]));
    try self.emit("std.Thread.sleep(@as(u64, @intFromFloat(");
    if (is_class_instance) { try self.emit("(runtime.floatBuiltinCall("); try self.genExpr(args[0]); try self.emit(", .{}) catch 0.0)"); } else { try self.genExpr(args[0]); }
    try self.emit(" * 1_000_000_000)))");
}

/// Generate gmtime(secs) or gmtime() - convert seconds to struct_time
fn genGmtime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("blk: { const _ts: i64 = ");
    if (args.len > 0) {
        // Use provided timestamp
        try self.emit("@intFromFloat(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        // No arg - use current time
        try self.emit("@intCast(std.time.timestamp())");
    }
    try self.emit("; const _epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(_ts) }; ");
    try self.emit("const _day = _epoch.getEpochDay(); const _year_day = _day.calculateYearDay(); ");
    try self.emit("const _day_seconds = _epoch.getDaySeconds(); ");
    try self.emit("break :blk .{ .tm_year = _year_day.year, .tm_mon = @as(i32, @intFromEnum(_year_day.month)), ");
    try self.emit(".tm_mday = _day.calculateYearDay().day_of_month, .tm_hour = _day_seconds.getHoursIntoDay(), ");
    try self.emit(".tm_min = _day_seconds.getMinutesIntoHour(), .tm_sec = _day_seconds.getSecondsIntoMinute(), ");
    try self.emit(".tm_wday = @as(i32, @intFromEnum(_day.dayOfWeek())), .tm_yday = _year_day.getDayOfYear(), .tm_isdst = 0 }; }");
}
