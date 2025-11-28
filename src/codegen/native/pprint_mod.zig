/// Python pprint module - Pretty-print data structures
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate pprint.pprint(object, stream=None, indent=1, width=80, depth=None, ...) -> None
pub fn genPprint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    try self.emit("std.debug.print(\"{any}\\n\", .{");
    try self.genExpr(args[0]);
    try self.emit("})");
}

/// Generate pprint.pformat(object, indent=1, width=80, depth=None, ...) -> str
pub fn genPformat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }
    try self.emit("pformat_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var buf: [4096]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("break :pformat_blk std.fmt.bufPrint(&buf, \"{any}\", .{");
    try self.genExpr(args[0]);
    try self.emit("}) catch \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate pprint.pp(object, *args, sort_dicts=False, **kwargs) -> None
pub fn genPp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genPprint(self, args);
}

/// Generate pprint.isreadable(object) -> bool
pub fn genIsreadable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate pprint.isrecursive(object) -> bool
pub fn genIsrecursive(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate pprint.saferepr(object) -> str
pub fn genSaferepr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genPformat(self, args);
}

/// Generate pprint.PrettyPrinter class
pub fn genPrettyPrinter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("indent: i64 = 1,\n");
    try self.emitIndent();
    try self.emit("width: i64 = 80,\n");
    try self.emitIndent();
    try self.emit("depth: ?i64 = null,\n");
    try self.emitIndent();
    try self.emit("compact: bool = false,\n");
    try self.emitIndent();
    try self.emit("sort_dicts: bool = true,\n");
    try self.emitIndent();
    try self.emit("underscore_numbers: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn pprint(self: @This(), object: anytype) void { _ = self; std.debug.print(\"{any}\\n\", .{object}); }\n");
    try self.emitIndent();
    try self.emit("pub fn pformat(self: @This(), object: anytype) []const u8 { _ = self; _ = object; return \"\"; }\n");
    try self.emitIndent();
    try self.emit("pub fn isreadable(self: @This(), object: anytype) bool { _ = self; _ = object; return true; }\n");
    try self.emitIndent();
    try self.emit("pub fn isrecursive(self: @This(), object: anytype) bool { _ = self; _ = object; return false; }\n");
    try self.emitIndent();
    try self.emit("pub fn format(self: @This(), object: anytype) []const u8 { _ = self; _ = object; return \"\"; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}
