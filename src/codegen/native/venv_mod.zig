/// Python venv module - Virtual environment creation
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "EnvBuilder", h.c(".{ .system_site_packages = false, .clear = false, .symlinks = false, .upgrade = false, .with_pip = false, .prompt = @as(?[]const u8, null), .upgrade_deps = false }") },
    .{ "create", h.c("{}") },
    .{ "ENV_CFG", h.c("\"pyvenv.cfg\"") },
    .{ "BIN_NAME", h.c("\"bin\"") },
});
