/// Python webbrowser module - Convenient web browser controller
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate webbrowser.open(url, new=0, autoraise=True)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const url = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = url; break :blk true; }");
    } else {
        try self.emit("false");
    }
}

/// Generate webbrowser.open_new(url)
pub fn genOpenNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const url = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = url; break :blk true; }");
    } else {
        try self.emit("false");
    }
}

/// Generate webbrowser.open_new_tab(url)
pub fn genOpenNewTab(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const url = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = url; break :blk true; }");
    } else {
        try self.emit("false");
    }
}

/// Generate webbrowser.get(using=None)
pub fn genGet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"default\", .basename = \"default\" }");
}

/// Generate webbrowser.register(name, constructor, instance=None, *, preferred=False)
pub fn genRegister(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate webbrowser.Error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.WebBrowserError");
}

/// Generate webbrowser.BaseBrowser class
pub fn genBaseBrowser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"base\", .basename = null }");
}

/// Generate webbrowser.GenericBrowser class
pub fn genGenericBrowser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"generic\", .basename = null, .args = &[_][]const u8{} }");
}

/// Generate webbrowser.BackgroundBrowser class
pub fn genBackgroundBrowser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"background\", .basename = null }");
}

/// Generate webbrowser.UnixBrowser class
pub fn genUnixBrowser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"unix\", .basename = null, .remote_args = &[_][]const u8{}, .remote_action = null, .remote_action_newwin = null, .remote_action_newtab = null, .background = false, .redirect_stdout = true }");
}

/// Generate webbrowser.Mozilla class
pub fn genMozilla(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"mozilla\" }");
}

/// Generate webbrowser.Netscape class
pub fn genNetscape(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"netscape\" }");
}

/// Generate webbrowser.Galeon class
pub fn genGaleon(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"galeon\" }");
}

/// Generate webbrowser.Chrome class
pub fn genChrome(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"chrome\" }");
}

/// Generate webbrowser.Chromium class
pub fn genChromium(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"chromium\" }");
}

/// Generate webbrowser.Opera class
pub fn genOpera(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"opera\" }");
}

/// Generate webbrowser.Elinks class
pub fn genElinks(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"elinks\" }");
}

/// Generate webbrowser.Konqueror class
pub fn genKonqueror(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"konqueror\" }");
}

/// Generate webbrowser.Grail class
pub fn genGrail(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"grail\" }");
}

/// Generate webbrowser.MacOSX class
pub fn genMacOSX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"macosx\" }");
}

/// Generate webbrowser.MacOSXOSAScript class
pub fn genMacOSXOSAScript(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"macosx-osascript\" }");
}

/// Generate webbrowser.WindowsDefault class
pub fn genWindowsDefault(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"windows-default\" }");
}
