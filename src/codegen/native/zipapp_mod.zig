/// Python zipapp module - Manage executable Python zip archives
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "create_archive", genCreateArchive },
    .{ "get_interpreter", genGetInterpreter },
});

/// Generate zipapp.create_archive(source, target=None, interpreter=None, main=None, filter=None, compressed=False)
pub fn genCreateArchive(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const source = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = source; break :blk {}; }");
    } else {
        try self.emit("{}");
    }
}

/// Generate zipapp.get_interpreter(archive)
pub fn genGetInterpreter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const archive = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = archive; break :blk null; }");
    } else {
        try self.emit("null");
    }
}
