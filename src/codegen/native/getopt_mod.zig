/// Python getopt module - C-style parser for command line options
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate getopt.getopt(args, shortopts, longopts=[])
pub fn genGetopt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const argv = ");
        try self.genExpr(args[0]);
        try self.emit("; const shortopts = ");
        try self.genExpr(args[1]);
        try self.emit("; _ = shortopts; var opts = std.ArrayList(struct { []const u8, []const u8 }).init(__global_allocator); var remaining = std.ArrayList([]const u8).init(__global_allocator); for (argv) |arg| { remaining.append(__global_allocator, arg) catch {}; } break :blk .{ opts.items, remaining.items }; }");
    } else {
        try self.emit(".{ &[_]struct { []const u8, []const u8 }{}, &[_][]const u8{} }");
    }
}

/// Generate getopt.gnu_getopt(args, shortopts, longopts=[])
pub fn genGnuGetopt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const argv = ");
        try self.genExpr(args[0]);
        try self.emit("; const shortopts = ");
        try self.genExpr(args[1]);
        try self.emit("; _ = shortopts; var opts = std.ArrayList(struct { []const u8, []const u8 }).init(__global_allocator); var remaining = std.ArrayList([]const u8).init(__global_allocator); for (argv) |arg| { remaining.append(__global_allocator, arg) catch {}; } break :blk .{ opts.items, remaining.items }; }");
    } else {
        try self.emit(".{ &[_]struct { []const u8, []const u8 }{}, &[_][]const u8{} }");
    }
}

/// Generate getopt.GetoptError exception
pub fn genGetoptError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.GetoptError");
}

/// Generate getopt.error (alias for GetoptError)
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.GetoptError");
}
