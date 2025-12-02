/// Python webbrowser module - Convenient web browser controller
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

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

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const url = "); try self.genExpr(args[0]); try self.emit("; _ = url; break :blk true; }"); } else { try self.emit("false"); }
}
