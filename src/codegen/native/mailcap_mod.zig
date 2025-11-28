/// Python mailcap module - Mailcap file handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate mailcap.findmatch(caps, MIMEtype, key='view', filename="/dev/null", plist=[])
pub fn genFindmatch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?@TypeOf(.{ \"\", .{} }), null)");
}

/// Generate mailcap.getcaps()
pub fn genGetcaps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate mailcap.listmailcapfiles()
pub fn genListmailcapfiles(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate mailcap.readmailcapfile(fp)
pub fn genReadmailcapfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate mailcap.lookup(caps, MIMEtype, key=None)
pub fn genLookup(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_].{ []const u8, .{} }{}");
}

/// Generate mailcap.subst(field, MIMEtype, filename, plist=[])
pub fn genSubst(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}
