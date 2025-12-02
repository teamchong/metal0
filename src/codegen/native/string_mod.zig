/// Python string module - string constants and utilities
const std = @import("std");
const h = @import("mod_helper.zig");

// Public exports for use in builtins.zig
pub const genAsciiLowercase = h.c("\"abcdefghijklmnopqrstuvwxyz\"");
pub const genAsciiUppercase = h.c("\"ABCDEFGHIJKLMNOPQRSTUVWXYZ\"");
pub const genAsciiLetters = h.c("\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\"");
pub const genDigits = h.c("\"0123456789\"");
pub const genPunctuation = h.c("\"!\\\"#$%&'()*+,-./:;<=>?@[\\\\]^_`{|}~\"");

const capwordsBody = "; var _result: std.ArrayList(u8) = .{}; var _cap_next = true; for (_s) |c| { if (c == ' ') { _result.append(__global_allocator, ' ') catch continue; _cap_next = true; } else if (_cap_next and c >= 'a' and c <= 'z') { _result.append(__global_allocator, c - 32) catch continue; _cap_next = false; } else { _result.append(__global_allocator, c) catch continue; _cap_next = false; } } break :capwords_blk _result.items; }";
const tmpl = "struct { template: []const u8, pub fn substitute(__self: @This(), _: anytype) []const u8 { return __self.template; } pub fn safe_substitute(__self: @This(), _: anytype) []const u8 { return __self.template; } }";

pub const genCapwords = h.wrap("capwords_blk: { const _s = ", capwordsBody, "\"\"");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ascii_lowercase", genAsciiLowercase }, .{ "ascii_uppercase", genAsciiUppercase },
    .{ "ascii_letters", genAsciiLetters }, .{ "digits", genDigits },
    .{ "hexdigits", h.c("\"0123456789abcdefABCDEF\"") }, .{ "octdigits", h.c("\"01234567\"") },
    .{ "punctuation", genPunctuation }, .{ "whitespace", h.c("\" \\t\\n\\r\\x0b\\x0c\"") },
    .{ "printable", h.c("\"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!\\\"#$%&'()*+,-./:;<=>?@[\\\\]^_`{|}~ \\t\\n\\r\\x0b\\x0c\"") },
    .{ "capwords", genCapwords },
    .{ "Formatter", h.c("struct { format: []const u8 = \"\", pub fn vformat(self: @This(), s: []const u8, _: anytype, _: anytype) []const u8 { return s; } }{}") },
    .{ "Template", h.wrap(tmpl ++ "{ .template = ", " }", tmpl ++ "{ .template = \"\" }") },
});
