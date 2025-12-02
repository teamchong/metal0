/// Python pyclbr module - Python class browser support
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "readmodule", genReadmod }, .{ "readmodule_ex", genReadmod },
    .{ "Class", h.c(".{ .module = \"\", .name = \"\", .super = &[_]@TypeOf(.{}){}, .methods = .{}, .file = \"\", .lineno = 0, .end_lineno = null, .parent = null, .children = .{} }") },
    .{ "Function", h.c(".{ .module = \"\", .name = \"\", .file = \"\", .lineno = 0, .end_lineno = null, .parent = null, .children = .{}, .is_async = false }") },
});

fn genReadmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const modname = "); try self.genExpr(args[0]); try self.emit("; _ = modname; break :blk .{}; }"); } else { try self.emit(".{}"); }
}
