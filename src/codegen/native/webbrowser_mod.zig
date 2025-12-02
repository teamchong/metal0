/// Python webbrowser module - Convenient web browser controller
const std = @import("std");
const h = @import("mod_helper.zig");

const genOpen = h.wrap("blk: { const url = ", "; _ = url; break :blk true; }", "false");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen }, .{ "open_new", genOpen }, .{ "open_new_tab", genOpen },
    .{ "get", h.c(".{ .name = \"default\", .basename = \"default\" }") },
    .{ "register", h.c("{}") }, .{ "Error", h.err("WebBrowserError") },
    .{ "BaseBrowser", h.c(".{ .name = \"base\", .basename = null }") },
    .{ "GenericBrowser", h.c(".{ .name = \"generic\", .basename = null, .args = &[_][]const u8{} }") },
    .{ "BackgroundBrowser", h.c(".{ .name = \"background\", .basename = null }") },
    .{ "UnixBrowser", h.c(".{ .name = \"unix\", .basename = null, .remote_args = &[_][]const u8{}, .remote_action = null, .remote_action_newwin = null, .remote_action_newtab = null, .background = false, .redirect_stdout = true }") },
    .{ "Mozilla", h.c(".{ .name = \"mozilla\" }") }, .{ "Netscape", h.c(".{ .name = \"netscape\" }") },
    .{ "Galeon", h.c(".{ .name = \"galeon\" }") }, .{ "Chrome", h.c(".{ .name = \"chrome\" }") },
    .{ "Chromium", h.c(".{ .name = \"chromium\" }") }, .{ "Opera", h.c(".{ .name = \"opera\" }") },
    .{ "Elinks", h.c(".{ .name = \"elinks\" }") }, .{ "Konqueror", h.c(".{ .name = \"konqueror\" }") },
    .{ "Grail", h.c(".{ .name = \"grail\" }") }, .{ "MacOSX", h.c(".{ .name = \"macosx\" }") },
    .{ "MacOSXOSAScript", h.c(".{ .name = \"macosx-osascript\" }") },
    .{ "WindowsDefault", h.c(".{ .name = \"windows-default\" }") },
});
