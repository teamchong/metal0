/// pylifecycle locale handling
const std = @import("std");
const builtin = @import("builtin");

/// Initialize locale settings
pub fn initLocale() void {
    // Set locale from environment - in Zig we rely on system defaults
}

/// Coerce legacy C locale to UTF-8
pub fn coerceLegacyLocale(warn: bool) bool {
    _ = warn;
    if (builtin.os.tag == .windows) {
        return false;
    }

    const lc_ctype = std.posix.getenv("LC_CTYPE");
    const lc_all = std.posix.getenv("LC_ALL");
    const lang = std.posix.getenv("LANG");

    const is_c_locale = blk: {
        if (lc_all) |v| {
            if (std.mem.eql(u8, v, "C") or std.mem.eql(u8, v, "POSIX")) break :blk true;
        }
        if (lc_ctype) |v| {
            if (std.mem.eql(u8, v, "C") or std.mem.eql(u8, v, "POSIX")) break :blk true;
        }
        if (lang) |v| {
            if (std.mem.eql(u8, v, "C") or std.mem.eql(u8, v, "POSIX")) break :blk true;
        }
        break :blk false;
    };

    if (is_c_locale) {
        return true;
    }

    return false;
}

/// Check if current locale is legacy C locale
pub fn isLegacyLocaleDetected(warn: bool) bool {
    _ = warn;
    if (builtin.os.tag == .windows) {
        return false;
    }

    const lc_all = std.posix.getenv("LC_ALL");
    const lc_ctype = std.posix.getenv("LC_CTYPE");
    const lang = std.posix.getenv("LANG");

    if (lc_all) |v| {
        if (std.mem.eql(u8, v, "C") or std.mem.eql(u8, v, "POSIX")) return true;
    }
    if (lc_ctype) |v| {
        if (std.mem.eql(u8, v, "C") or std.mem.eql(u8, v, "POSIX")) return true;
    }
    if (lang) |v| {
        if (std.mem.eql(u8, v, "C") or std.mem.eql(u8, v, "POSIX")) return true;
        if (v.len == 0 and lc_ctype == null) return true;
    }

    if (lc_all == null and lc_ctype == null and lang == null) {
        return false;
    }

    return false;
}
