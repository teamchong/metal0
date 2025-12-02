/// Python warnings module - Warning control
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "warn", genWarn }, .{ "warn_explicit", genWarn }, .{ "showwarning", genWarn },
    .{ "formatwarning", genFormatwarning }, .{ "filterwarnings", genConst("{}") }, .{ "simplefilter", genConst("{}") },
    .{ "resetwarnings", genConst("{}") }, .{ "catch_warnings", genConst("struct { record: bool = false, log: std.ArrayList([]const u8) = .{}, pub fn __enter__(__self: *@This()) *@This() { return __self; } pub fn __exit__(__self: *@This(), _: anytype) void { _ = __self; } }{}") },
    .{ "Warning", genConst("\"Warning\"") }, .{ "UserWarning", genConst("\"UserWarning\"") }, .{ "DeprecationWarning", genConst("\"DeprecationWarning\"") },
    .{ "PendingDeprecationWarning", genConst("\"PendingDeprecationWarning\"") }, .{ "SyntaxWarning", genConst("\"SyntaxWarning\"") },
    .{ "RuntimeWarning", genConst("\"RuntimeWarning\"") }, .{ "FutureWarning", genConst("\"FutureWarning\"") },
    .{ "ImportWarning", genConst("\"ImportWarning\"") }, .{ "UnicodeWarning", genConst("\"UnicodeWarning\"") },
    .{ "BytesWarning", genConst("\"BytesWarning\"") }, .{ "ResourceWarning", genConst("\"ResourceWarning\"") },
    .{ "filters", genConst("&[_][]const u8{}") }, .{ "_filters_mutated", genConst("{}") },
    .{ "WarningMessage", genConst("struct { _WARNING_DETAILS: []const []const u8 = &[_][]const u8{\"message\", \"category\", \"filename\", \"lineno\", \"file\", \"line\", \"source\"} }{}") },
});

fn genWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("{}"); return; }
    try self.emit("std.debug.print(\"Warning: {s}\\n\", .{"); try self.genExpr(args[0]); try self.emit("})");
}

fn genFormatwarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
