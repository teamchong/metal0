/// Python locale module - Internationalization services
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "setlocale", h.c("\"C\"") }, .{ "getlocale", h.c(".{ @as(?[]const u8, null), @as(?[]const u8, null) }") },
    .{ "getdefaultlocale", h.c(".{ \"en_US\", \"UTF-8\" }") },
    .{ "getpreferredencoding", h.c("\"UTF-8\"") }, .{ "getencoding", h.c("\"UTF-8\"") }, .{ "normalize", h.pass("\"C\"") },
    .{ "resetlocale", h.c("{}") },
    .{ "localeconv", h.c(".{ .decimal_point = \".\", .thousands_sep = \"\", .grouping = \"\", .int_curr_symbol = \"\", .currency_symbol = \"\", .mon_decimal_point = \"\", .mon_thousands_sep = \"\", .mon_grouping = \"\", .positive_sign = \"\", .negative_sign = \"\", .int_frac_digits = 127, .frac_digits = 127, .p_cs_precedes = 127, .p_sep_by_space = 127, .n_cs_precedes = 127, .n_sep_by_space = 127, .p_sign_posn = 127, .n_sign_posn = 127 }") },
    .{ "strcoll", h.memOrder() }, .{ "strxfrm", h.pass("\"\"") },
    .{ "format_string", h.c("\"\"") }, .{ "currency", h.c("\"\"") }, .{ "str", h.c("\"\"") },
    .{ "atof", h.F64(0.0) }, .{ "atoi", h.I64(0) }, .{ "delocalize", h.pass("\"\"") }, .{ "localize", h.pass("\"\"") },
    .{ "nl_langinfo", h.c("\"\"") }, .{ "gettext", h.pass("\"\"") },
    .{ "LC_CTYPE", h.I64(0) }, .{ "LC_COLLATE", h.I64(1) }, .{ "LC_TIME", h.I64(2) },
    .{ "LC_MONETARY", h.I64(3) }, .{ "LC_NUMERIC", h.I64(4) }, .{ "LC_MESSAGES", h.I64(5) }, .{ "LC_ALL", h.I64(6) },
    .{ "Error", h.c("\"locale.Error\"") },
});
