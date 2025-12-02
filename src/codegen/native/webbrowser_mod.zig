/// Python webbrowser module - Convenient web browser controller
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen }, .{ "open_new", genOpen }, .{ "open_new_tab", genOpen },
    .{ "get", genConst(".{ .name = \"default\", .basename = \"default\" }") },
    .{ "register", genConst("{}") }, .{ "Error", genConst("error.WebBrowserError") },
    .{ "BaseBrowser", genConst(".{ .name = \"base\", .basename = null }") },
    .{ "GenericBrowser", genConst(".{ .name = \"generic\", .basename = null, .args = &[_][]const u8{} }") },
    .{ "BackgroundBrowser", genConst(".{ .name = \"background\", .basename = null }") },
    .{ "UnixBrowser", genConst(".{ .name = \"unix\", .basename = null, .remote_args = &[_][]const u8{}, .remote_action = null, .remote_action_newwin = null, .remote_action_newtab = null, .background = false, .redirect_stdout = true }") },
    .{ "Mozilla", genConst(".{ .name = \"mozilla\" }") }, .{ "Netscape", genConst(".{ .name = \"netscape\" }") },
    .{ "Galeon", genConst(".{ .name = \"galeon\" }") }, .{ "Chrome", genConst(".{ .name = \"chrome\" }") },
    .{ "Chromium", genConst(".{ .name = \"chromium\" }") }, .{ "Opera", genConst(".{ .name = \"opera\" }") },
    .{ "Elinks", genConst(".{ .name = \"elinks\" }") }, .{ "Konqueror", genConst(".{ .name = \"konqueror\" }") },
    .{ "Grail", genConst(".{ .name = \"grail\" }") }, .{ "MacOSX", genConst(".{ .name = \"macosx\" }") },
    .{ "MacOSXOSAScript", genConst(".{ .name = \"macosx-osascript\" }") },
    .{ "WindowsDefault", genConst(".{ .name = \"windows-default\" }") },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const url = "); try self.genExpr(args[0]); try self.emit("; _ = url; break :blk true; }"); } else { try self.emit("false"); }
}
