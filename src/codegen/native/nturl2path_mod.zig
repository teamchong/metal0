/// Python nturl2path module - Convert NT URLs to pathnames
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "url2pathname", genUrl2pathname },
    .{ "pathname2url", genPathname2url },
});

/// Generate nturl2path.url2pathname(url) - Convert URL to NT pathname
pub fn genUrl2pathname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

/// Generate nturl2path.pathname2url(pathname) - Convert NT pathname to URL
pub fn genPathname2url(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
