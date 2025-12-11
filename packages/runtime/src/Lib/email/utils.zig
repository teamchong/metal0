//! Email utility functions
//!
//! Provides utility functions for email address parsing, formatting, and date handling.

const std = @import("std");

/// Parse an email address
pub fn parseaddr(address: []const u8) struct { name: []const u8, email: []const u8 } {
    // Simple parsing: "Name <email>" or just "email"
    if (std.mem.indexOf(u8, address, "<")) |lt_pos| {
        if (std.mem.indexOf(u8, address, ">")) |gt_pos| {
            const name = std.mem.trim(u8, address[0..lt_pos], " \t\"");
            const email = address[lt_pos + 1 .. gt_pos];
            return .{ .name = name, .email = email };
        }
    }
    return .{ .name = "", .email = std.mem.trim(u8, address, " \t") };
}

/// Format an email address
pub fn formataddr(allocator: std.mem.Allocator, name: []const u8, email: []const u8) ![]u8 {
    if (name.len == 0) {
        return allocator.dupe(u8, email);
    }

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Check if name needs quoting
    var needs_quote = false;
    for (name) |c| {
        if (c == '"' or c == ',' or c == '<' or c == '>') {
            needs_quote = true;
            break;
        }
    }

    if (needs_quote) {
        try result.append('"');
        for (name) |c| {
            if (c == '"' or c == '\\') {
                try result.append('\\');
            }
            try result.append(c);
        }
        try result.append('"');
    } else {
        try result.appendSlice(name);
    }

    try result.appendSlice(" <");
    try result.appendSlice(email);
    try result.append('>');

    return result.toOwnedSlice();
}

/// Get a list of addresses from a header
pub fn getaddresses(allocator: std.mem.Allocator, fieldvalues: []const []const u8) ![]struct { name: []const u8, email: []const u8 } {
    var result = std.ArrayList(struct { name: []const u8, email: []const u8 }).init(allocator);
    errdefer result.deinit();

    for (fieldvalues) |value| {
        var parts = std.mem.splitScalar(u8, value, ',');
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (trimmed.len > 0) {
                try result.append(parseaddr(trimmed));
            }
        }
    }

    return result.toOwnedSlice();
}

// Day names for RFC 2822
const day_names = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
const month_names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

/// Format a date for email (RFC 2822 format)
/// Example: "Thu, 01 Jan 1970 00:00:00 +0000"
pub fn formatdate(localtime: bool, usegmt: bool) []const u8 {
    _ = localtime;

    const timestamp = std.time.timestamp();
    const epoch_secs: u64 = @intCast(timestamp);
    const epoch_day = std.time.epoch.EpochDay{ .day = @intCast(epoch_secs / std.time.s_per_day) };
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const day_seconds = @mod(epoch_secs, std.time.s_per_day);
    const hour: u8 = @intCast(day_seconds / 3600);
    const minute: u8 = @intCast(@mod(day_seconds, 3600) / 60);
    const second: u8 = @intCast(@mod(day_seconds, 60));

    const weekday = @mod(@as(i32, @intCast(epoch_day.day)) + 3, 7); // Jan 1, 1970 was Thursday (3)
    const day_name = day_names[@intCast(weekday)];
    const month_name = month_names[month_day.month.numeric() - 1];

    const tz = if (usegmt) "GMT" else "+0000";

    // Use static buffer for the formatted date
    const Static = struct {
        var buf: [64]u8 = undefined;
    };
    const result = std.fmt.bufPrint(&Static.buf, "{s}, {d:0>2} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} {s}", .{
        day_name,
        month_day.day_of_month,
        month_name,
        year_day.year,
        hour,
        minute,
        second,
        tz,
    }) catch return "Thu, 01 Jan 1970 00:00:00 +0000";

    return result;
}

/// Parse a date from email (RFC 2822 format)
pub fn parsedate(date: []const u8) ?struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
} {
    // Skip day name if present (e.g., "Thu, ")
    var input = date;
    if (std.mem.indexOf(u8, input, ", ")) |comma_idx| {
        input = input[comma_idx + 2 ..];
    }

    // Parse: "01 Jan 1970 00:00:00 +0000"
    var iter = std.mem.tokenizeAny(u8, input, " :");

    const day_str = iter.next() orelse return null;
    const month_str = iter.next() orelse return null;
    const year_str = iter.next() orelse return null;
    const hour_str = iter.next() orelse return null;
    const minute_str = iter.next() orelse return null;
    const second_str = iter.next() orelse return null;

    const day = std.fmt.parseInt(u8, day_str, 10) catch return null;
    const year = std.fmt.parseInt(i32, year_str, 10) catch return null;
    const hour = std.fmt.parseInt(u8, hour_str, 10) catch return null;
    const minute = std.fmt.parseInt(u8, minute_str, 10) catch return null;
    const second = std.fmt.parseInt(u8, second_str, 10) catch return null;

    // Parse month name
    var month: u8 = 0;
    for (month_names, 1..) |name, i| {
        if (std.ascii.eqlIgnoreCase(month_str, name)) {
            month = @intCast(i);
            break;
        }
    }
    if (month == 0) return null;

    return .{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

/// Parse date to datetime (alias for parsedate)
pub fn parsedate_to_datetime(date: []const u8) ?struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
} {
    return parsedate(date);
}

/// Create a unique message ID
pub fn makeMessageId(allocator: std.mem.Allocator, domain: ?[]const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.append('<');

    // Generate random part
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = rng.random();
    var buf: [16]u8 = undefined;
    for (&buf) |*b| {
        b.* = random.int(u8);
    }

    const hex = "0123456789abcdef";
    for (buf) |b| {
        try result.append(hex[b >> 4]);
        try result.append(hex[b & 0x0F]);
    }

    try result.append('@');
    try result.appendSlice(domain orelse "localhost");
    try result.append('>');

    return result.toOwnedSlice();
}

/// Quote a string for use in headers
pub fn quoteString(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.append('"');
    for (str) |c| {
        if (c == '"' or c == '\\') {
            try result.append('\\');
        }
        try result.append(c);
    }
    try result.append('"');

    return result.toOwnedSlice();
}

/// Make message ID (snake_case alias)
pub fn make_msgid(allocator: std.mem.Allocator, domain: ?[]const u8) ![]u8 {
    return makeMessageId(allocator, domain);
}
