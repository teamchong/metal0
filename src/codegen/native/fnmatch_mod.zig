/// Python fnmatch module - Unix filename pattern matching
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate fnmatch.fnmatch(name, pattern) -> bool
pub fn genFnmatch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("fnmatch_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _name = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _pattern = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("break :fnmatch_blk globMatch(_pattern, _name);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate fnmatch.fnmatchcase(name, pattern) -> bool (case sensitive)
pub fn genFnmatchcase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Same as fnmatch for now (Zig is case-sensitive by default)
    try genFnmatch(self, args);
}

/// Generate fnmatch.filter(names, pattern) -> list
pub fn genFilter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("fnmatch_filter_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _names = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _pattern = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList([]const u8).init(allocator);\n");
    try self.emitIndent();
    try self.emit("for (_names) |name| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (globMatch(_pattern, name)) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(allocator, name) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :fnmatch_filter_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate fnmatch.translate(pattern) -> regex pattern string
pub fn genTranslate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("fnmatch_translate_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _pattern = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(u8).init(allocator);\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(allocator, \"(?s:\") catch {};\n");
    try self.emitIndent();
    try self.emit("for (_pattern) |c| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("switch (c) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("'*' => _result.appendSlice(allocator, \".*\") catch {},\n");
    try self.emitIndent();
    try self.emit("'?' => _result.append(allocator, '.') catch {},\n");
    try self.emitIndent();
    try self.emit("'.' => _result.appendSlice(allocator, \"\\\\.\") catch {},\n");
    try self.emitIndent();
    try self.emit("'[' => _result.append(allocator, '[') catch {},\n");
    try self.emitIndent();
    try self.emit("']' => _result.append(allocator, ']') catch {},\n");
    try self.emitIndent();
    try self.emit("'^' => _result.appendSlice(allocator, \"\\\\^\") catch {},\n");
    try self.emitIndent();
    try self.emit("'$' => _result.appendSlice(allocator, \"\\\\$\") catch {},\n");
    try self.emitIndent();
    try self.emit("else => _result.append(allocator, c) catch {},\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(allocator, \")\\\\Z\") catch {};\n");
    try self.emitIndent();
    try self.emit("break :fnmatch_translate_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
