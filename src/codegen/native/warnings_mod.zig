/// Python warnings module - Warning control
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "warn", genWarn }, .{ "warn_explicit", genWarn }, .{ "showwarning", genWarn },
    .{ "formatwarning", h.pass("\"\"") }, .{ "filterwarnings", h.c("{}") }, .{ "simplefilter", h.c("{}") },
    .{ "resetwarnings", h.c("{}") }, .{ "catch_warnings", h.c("struct { record: bool = false, log: std.ArrayList([]const u8) = .{}, pub fn __enter__(__self: *@This()) *@This() { return __self; } pub fn __exit__(__self: *@This(), _: anytype) void { _ = __self; } }{}") },
    .{ "Warning", h.c("\"Warning\"") }, .{ "UserWarning", h.c("\"UserWarning\"") }, .{ "DeprecationWarning", h.c("\"DeprecationWarning\"") },
    .{ "PendingDeprecationWarning", h.c("\"PendingDeprecationWarning\"") }, .{ "SyntaxWarning", h.c("\"SyntaxWarning\"") },
    .{ "RuntimeWarning", h.c("\"RuntimeWarning\"") }, .{ "FutureWarning", h.c("\"FutureWarning\"") },
    .{ "ImportWarning", h.c("\"ImportWarning\"") }, .{ "UnicodeWarning", h.c("\"UnicodeWarning\"") },
    .{ "BytesWarning", h.c("\"BytesWarning\"") }, .{ "ResourceWarning", h.c("\"ResourceWarning\"") },
    .{ "filters", h.c("&[_][]const u8{}") }, .{ "_filters_mutated", h.c("{}") },
    .{ "WarningMessage", h.c("struct { _WARNING_DETAILS: []const []const u8 = &[_][]const u8{\"message\", \"category\", \"filename\", \"lineno\", \"file\", \"line\", \"source\"} }{}") },
});

fn genWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("{}"); return; }
    try self.emit("std.debug.print(\"Warning: {s}\\n\", .{"); try self.genExpr(args[0]); try self.emit("})");
}
