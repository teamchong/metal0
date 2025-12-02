/// Python warnings module - Warning control
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "warn", genWarn }, .{ "warn_explicit", genWarn }, .{ "showwarning", genWarn },
    .{ "formatwarning", genFormatwarning }, .{ "filterwarnings", genUnit }, .{ "simplefilter", genUnit },
    .{ "resetwarnings", genUnit }, .{ "catch_warnings", genCatchWarnings }, .{ "Warning", genWarnStr },
    .{ "UserWarning", genUserWarn }, .{ "DeprecationWarning", genDeprecWarn }, .{ "PendingDeprecationWarning", genPendDeprecWarn },
    .{ "SyntaxWarning", genSyntaxWarn }, .{ "RuntimeWarning", genRuntimeWarn }, .{ "FutureWarning", genFutureWarn },
    .{ "ImportWarning", genImportWarn }, .{ "UnicodeWarning", genUnicodeWarn }, .{ "BytesWarning", genBytesWarn },
    .{ "ResourceWarning", genResourceWarn }, .{ "filters", genEmptyStrArr }, .{ "_filters_mutated", genUnit },
    .{ "WarningMessage", genWarningMessage },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyStrArr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genWarnStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Warning\""); }
fn genUserWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"UserWarning\""); }
fn genDeprecWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"DeprecationWarning\""); }
fn genPendDeprecWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"PendingDeprecationWarning\""); }
fn genSyntaxWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"SyntaxWarning\""); }
fn genRuntimeWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"RuntimeWarning\""); }
fn genFutureWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"FutureWarning\""); }
fn genImportWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ImportWarning\""); }
fn genUnicodeWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"UnicodeWarning\""); }
fn genBytesWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"BytesWarning\""); }
fn genResourceWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ResourceWarning\""); }
fn genWarningMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { _WARNING_DETAILS: []const []const u8 = &[_][]const u8{\"message\", \"category\", \"filename\", \"lineno\", \"file\", \"line\", \"source\"} }{}"); }
fn genCatchWarnings(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { record: bool = false, log: std.ArrayList([]const u8) = .{}, pub fn __enter__(__self: *@This()) *@This() { return __self; } pub fn __exit__(__self: *@This(), _: anytype) void { _ = __self; } }{}"); }

fn genWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("{}"); return; }
    try self.emit("std.debug.print(\"Warning: {s}\\n\", .{"); try self.genExpr(args[0]); try self.emit("})");
}

fn genFormatwarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else try self.emit("\"\"");
}
