/// Python _string module - Low-level string formatting (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _string.formatter_field_name_split(field_name)
pub fn genFormatterFieldNameSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const field = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ field, &[_][]const u8{} }; }");
    } else {
        try self.emit(".{ \"\", &[_][]const u8{} }");
    }
}

/// Generate _string.formatter_parser(format_string)
pub fn genFormatterParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const fmt = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = fmt; break :blk &[_]struct { []const u8, []const u8, []const u8, []const u8 }{}; }");
    } else {
        try self.emit("&[_]struct { []const u8, []const u8, []const u8, []const u8 }{}");
    }
}
