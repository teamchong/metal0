//! CPython source: Lib/configparser.py
//!
//! Default converters for getint, getfloat, getboolean.

const std = @import("std");

/// Default converters for getint, getfloat, getboolean
pub const Converters = struct {
    pub fn int(value: []const u8) !i64 {
        return std.fmt.parseInt(i64, value, 10);
    }

    pub fn float(value: []const u8) !f64 {
        return std.fmt.parseFloat(f64, value);
    }

    pub fn boolean(value: []const u8) !bool {
        const lower = std.ascii.lowerString(@constCast(value), value);
        _ = lower;

        if (std.mem.eql(u8, value, "true") or
            std.mem.eql(u8, value, "yes") or
            std.mem.eql(u8, value, "on") or
            std.mem.eql(u8, value, "1"))
        {
            return true;
        }

        if (std.mem.eql(u8, value, "false") or
            std.mem.eql(u8, value, "no") or
            std.mem.eql(u8, value, "off") or
            std.mem.eql(u8, value, "0"))
        {
            return false;
        }

        return error.InvalidBoolean;
    }
};
