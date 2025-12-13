/// Python time module - time-related functions
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;
const type_traits = @import("../../analysis/traits/type_traits.zig");

const nano_ts = h.c("@as(i64, @intCast(std.time.nanoTimestamp()))");

fn genNsToSec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Use scoped label to avoid conflicts with nested blocks
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;
    try self.emitFmt("time_{d}: {{ const _t = std.time.nanoTimestamp(); break :time_{d} @as(f64, @floatFromInt(_t)) / 1_000_000_000.0; }}", .{ label_id, label_id });
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "time", genNsToSec }, // Use nanoTimestamp for sub-second precision
    .{ "time_ns", nano_ts }, .{ "sleep", genSleep },
    .{ "perf_counter", genNsToSec }, .{ "perf_counter_ns", nano_ts },
    .{ "monotonic", genNsToSec }, .{ "monotonic_ns", nano_ts },
    .{ "process_time", genNsToSec }, .{ "process_time_ns", nano_ts },
    .{ "ctime", h.c("\"Thu Jan  1 00:00:00 1970\"") },
    .{ "gmtime", genGmtime }, .{ "localtime", genGmtime },
    .{ "mktime", h.stub("@as(f64, @floatFromInt(std.time.timestamp()))") },
    .{ "strftime", h.pass("\"\"") },
    .{ "strptime", h.c(".{ .tm_year = 1970, .tm_mon = 1, .tm_mday = 1, .tm_hour = 0, .tm_min = 0, .tm_sec = 0, .tm_wday = 0, .tm_yday = 0, .tm_isdst = 0 }") },
    .{ "get_clock_info", h.c(".{ .implementation = \"std.time\", .monotonic = true, .adjustable = false, .resolution = 1e-9 }") },
});

fn genSleep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const is_class_instance = type_traits.isClassInstance(arg_type) or (args[0] == .call and args[0].call.func.* == .name and std.ascii.isUpper(args[0].call.func.name.id[0]));
    if (is_class_instance) {
        // When inside try body (assertRaises), wrap in block that returns error union
        // so expectError can catch the error. Otherwise, silently convert to 0.0 on error.
        if (self.inside_try_body) {
            // Generate: __sleep_blk: { const _v = runtime.floatBuiltinCall(...) catch |e| break :__sleep_blk @as(anyerror!void, e); std.Thread.sleep(...); break :__sleep_blk @as(anyerror!void, {}); }
            try self.emit("__sleep_blk: { const __sleep_v = runtime.floatBuiltinCall(");
            try self.genExpr(args[0]);
            try self.emit(", .{}) catch |e| break :__sleep_blk @as(anyerror!void, e); std.Thread.sleep(@as(u64, @intFromFloat(__sleep_v * 1_000_000_000))); break :__sleep_blk @as(anyerror!void, {}); }");
        } else {
            try self.emit("std.Thread.sleep(@as(u64, @intFromFloat((runtime.floatBuiltinCall(");
            try self.genExpr(args[0]);
            try self.emit(", .{}) catch 0.0) * 1_000_000_000)))");
        }
    } else {
        try self.emit("std.Thread.sleep(@as(u64, @intFromFloat(");
        try self.genExpr(args[0]);
        try self.emit(" * 1_000_000_000)))");
    }
}

fn genGmtime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Use scoped label to avoid conflicts with nested blocks
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;
    try self.emitFmt("gmtime_{d}: {{ const _ts: i64 = ", .{label_id});
    if (args.len > 0) {
        try self.emit("@intFromFloat(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("@intCast(std.time.timestamp())");
    }
    try self.emit("; const _epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(_ts) }; const _day = _epoch.getEpochDay(); const _year_day = _day.calculateYearDay(); const _day_seconds = _epoch.getDaySeconds(); ");
    try self.emitFmt("break :gmtime_{d} .{{ .tm_year = _year_day.year, .tm_mon = @as(i32, @intFromEnum(_year_day.month)), .tm_mday = _day.calculateYearDay().day_of_month, .tm_hour = _day_seconds.getHoursIntoDay(), .tm_min = _day_seconds.getMinutesIntoHour(), .tm_sec = _day_seconds.getSecondsIntoMinute(), .tm_wday = @as(i32, @intFromEnum(_day.dayOfWeek())), .tm_yday = _year_day.getDayOfYear(), .tm_isdst = 0 }}; }}", .{label_id});
}
