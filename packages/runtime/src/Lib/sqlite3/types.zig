//! SQLite3 type converters and adapters
//!
//! Mirrors: CPython Lib/sqlite3/dbapi2.py (adapter/converter registration)

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const hashmap_helper = @import("utils.hashmap_helper");
const errors = @import("errors.zig");

// ============================================================================
// Type Detection
// ============================================================================

pub const PARSE_DECLTYPES = 1;
pub const PARSE_COLNAMES = 2;

// ============================================================================
// Global Adapter and Converter Registries
// ============================================================================

// Global adapter and converter registries
var adapters_map: ?hashmap_helper.StringHashMap(*const anyopaque) = null;
var converters_map: ?hashmap_helper.StringHashMap(*const anyopaque) = null;

/// Register an adapter for a Python type to SQLite
pub fn registerAdapter(comptime T: type, adapter: *const fn (value: T) []const u8) void {
    if (adapters_map == null) {
        adapters_map = hashmap_helper.StringHashMap(*const anyopaque).init(allocator_helper.fast_allocator);
    }
    adapters_map.?.put(@typeName(T), @ptrCast(adapter)) catch {};
}

/// Register a converter from SQLite type to Python
pub fn registerConverter(typename: []const u8, converter: *const anyopaque) void {
    if (converters_map == null) {
        converters_map = hashmap_helper.StringHashMap(*const anyopaque).init(allocator_helper.fast_allocator);
    }
    converters_map.?.put(typename, converter) catch {};
}

// ============================================================================
// Adapters
// ============================================================================

pub const adapters = struct {
    /// Adapt a date struct to ISO format (YYYY-MM-DD)
    /// Input: struct with year, month, day fields
    pub fn adaptDate(allocator: std.mem.Allocator, date: anytype) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            date.year,
            date.month,
            date.day,
        });
    }

    /// Adapt a datetime struct to ISO format (YYYY-MM-DD HH:MM:SS)
    /// Input: struct with year, month, day, hour, minute, second fields
    pub fn adaptDatetime(allocator: std.mem.Allocator, datetime: anytype) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
            datetime.year,
            datetime.month,
            datetime.day,
            datetime.hour,
            datetime.minute,
            datetime.second,
        });
    }
};

// ============================================================================
// Converters
// ============================================================================

pub const converters = struct {
    /// Convert ISO date string to date
    pub fn convertDate(allocator: std.mem.Allocator, s: []const u8) !struct { year: i32, month: u8, day: u8 } {
        _ = allocator;
        // Parse YYYY-MM-DD
        var parts = std.mem.splitScalar(u8, s, '-');
        const year_str = parts.next() orelse return error.DataError;
        const month_str = parts.next() orelse return error.DataError;
        const day_str = parts.next() orelse return error.DataError;

        return .{
            .year = try std.fmt.parseInt(i32, year_str, 10),
            .month = try std.fmt.parseInt(u8, month_str, 10),
            .day = try std.fmt.parseInt(u8, day_str, 10),
        };
    }

    /// Convert ISO timestamp string to datetime
    pub fn convertTimestamp(allocator: std.mem.Allocator, s: []const u8) !struct {
        year: i32,
        month: u8,
        day: u8,
        hour: u8,
        minute: u8,
        second: u8,
    } {
        _ = allocator;
        // Parse YYYY-MM-DD HH:MM:SS
        var date_time = std.mem.splitScalar(u8, s, ' ');
        const date_str = date_time.next() orelse return error.DataError;
        const time_str = date_time.next() orelse return error.DataError;

        var date_parts = std.mem.splitScalar(u8, date_str, '-');
        var time_parts = std.mem.splitScalar(u8, time_str, ':');

        return .{
            .year = try std.fmt.parseInt(i32, date_parts.next() orelse return error.DataError, 10),
            .month = try std.fmt.parseInt(u8, date_parts.next() orelse return error.DataError, 10),
            .day = try std.fmt.parseInt(u8, date_parts.next() orelse return error.DataError, 10),
            .hour = try std.fmt.parseInt(u8, time_parts.next() orelse return error.DataError, 10),
            .minute = try std.fmt.parseInt(u8, time_parts.next() orelse return error.DataError, 10),
            .second = try std.fmt.parseInt(u8, time_parts.next() orelse return error.DataError, 10),
        };
    }
};

// ============================================================================
// PrepareProtocol
// ============================================================================

pub const PrepareProtocol = struct {
    /// Protocol for preparing values for SQLite
    /// Converts Zig types to SQLite-compatible string representations
    pub fn prepare(allocator: std.mem.Allocator, value: anytype) ![]u8 {
        const T = @TypeOf(value);
        return switch (@typeInfo(T)) {
            .int, .comptime_int => std.fmt.allocPrint(allocator, "{d}", .{value}),
            .float, .comptime_float => std.fmt.allocPrint(allocator, "{d}", .{value}),
            .bool => if (value) allocator.dupe(u8, "1") else allocator.dupe(u8, "0"),
            .pointer => |ptr| {
                if (ptr.size == .Slice and ptr.child == u8) {
                    // String - escape single quotes
                    var result: std.ArrayList(u8) = .{};
                    try result.append(allocator, '\'');
                    for (value) |c| {
                        if (c == '\'') try result.append(allocator, '\''); // Escape with double quote
                        try result.append(allocator, c);
                    }
                    try result.append(allocator, '\'');
                    return result.toOwnedSlice(allocator);
                }
                return error.UnsupportedType;
            },
            .optional => if (value) |v| prepare(allocator, v) else allocator.dupe(u8, "NULL"),
            else => error.UnsupportedType,
        };
    }
};
