/// Python warnings module - Warning control
const std = @import("std");
const h = @import("mod_helper.zig");

const warn = h.debugPrint("Warning: ", "{s}", "{}");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "warn", warn }, .{ "warn_explicit", warn }, .{ "showwarning", warn },
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
