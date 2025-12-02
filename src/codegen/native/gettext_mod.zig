/// Python gettext module - Internationalization services
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "gettext", h.pass("\"\"") }, .{ "ngettext", h.passN(0, "\"\"") }, .{ "pgettext", h.passN(1, "\"\"") },
    .{ "npgettext", h.passN(1, "\"\"") }, .{ "dgettext", h.passN(1, "\"\"") }, .{ "dngettext", h.passN(1, "\"\"") },
    .{ "bindtextdomain", h.passN(1, "null") }, .{ "textdomain", h.pass("\"messages\"") }, .{ "install", h.c("{}") },
    .{ "translation", h.c(".{ .gettext = struct { fn f(msg: []const u8) []const u8 { return msg; } }.f, .ngettext = struct { fn f(s: []const u8, p: []const u8, n: i64) []const u8 { return if (n == 1) s else p; } }.f, .info = struct { fn f() []const u8 { return \"\"; } }.f, .charset = struct { fn f() []const u8 { return \"UTF-8\"; } }.f }") },
    .{ "find", h.c("null") },
    .{ "GNUTranslations", h.c(".{ .gettext = struct { fn f(msg: []const u8) []const u8 { return msg; } }.f }") },
    .{ "NullTranslations", h.c(".{ .gettext = struct { fn f(msg: []const u8) []const u8 { return msg; } }.f }") },
});
