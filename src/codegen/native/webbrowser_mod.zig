/// Python webbrowser module - Convenient web browser controller
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen }, .{ "open_new", genOpen }, .{ "open_new_tab", genOpen },
    .{ "get", genGet }, .{ "register", genUnit }, .{ "Error", genErr },
    .{ "BaseBrowser", genBase }, .{ "GenericBrowser", genGeneric }, .{ "BackgroundBrowser", genBg }, .{ "UnixBrowser", genUnix },
    .{ "Mozilla", genMoz }, .{ "Netscape", genNet }, .{ "Galeon", genGal }, .{ "Chrome", genChr }, .{ "Chromium", genChm },
    .{ "Opera", genOp }, .{ "Elinks", genEl }, .{ "Konqueror", genKon }, .{ "Grail", genGra },
    .{ "MacOSX", genMac }, .{ "MacOSXOSAScript", genMacOSA }, .{ "WindowsDefault", genWin },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.WebBrowserError"); }
fn genGet(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"default\", .basename = \"default\" }"); }
fn genBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"base\", .basename = null }"); }
fn genGeneric(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"generic\", .basename = null, .args = &[_][]const u8{} }"); }
fn genBg(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"background\", .basename = null }"); }
fn genUnix(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"unix\", .basename = null, .remote_args = &[_][]const u8{}, .remote_action = null, .remote_action_newwin = null, .remote_action_newtab = null, .background = false, .redirect_stdout = true }"); }
fn genMoz(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"mozilla\" }"); }
fn genNet(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"netscape\" }"); }
fn genGal(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"galeon\" }"); }
fn genChr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"chrome\" }"); }
fn genChm(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"chromium\" }"); }
fn genOp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"opera\" }"); }
fn genEl(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"elinks\" }"); }
fn genKon(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"konqueror\" }"); }
fn genGra(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"grail\" }"); }
fn genMac(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"macosx\" }"); }
fn genMacOSA(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"macosx-osascript\" }"); }
fn genWin(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"windows-default\" }"); }

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const url = "); try self.genExpr(args[0]); try self.emit("; _ = url; break :blk true; }"); } else { try self.emit("false"); }
}
