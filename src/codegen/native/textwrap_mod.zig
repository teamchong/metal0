/// Python textwrap module - text wrapping and filling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "wrap", genWrap },
    .{ "fill", genFill },
    .{ "dedent", genDedent },
    .{ "indent", genIndent },
    .{ "shorten", genShorten },
    .{ "TextWrapper", genTextWrapper },
});

/// Generate textwrap.wrap(text, width=70) -> list of lines
pub fn genWrap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Use scope-aware allocator name
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    try self.emit("textwrap_wrap_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _text = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _width: usize = ");
    if (args.len > 1) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("70");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _lines = std.ArrayList([]const u8){};\n");
    try self.emitIndent();
    try self.emit("var _start: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (_start < _text.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _end = @min(_start + _width, _text.len);\n");
    try self.emitIndent();
    try self.emitFmt("_lines.append({s}, _text[_start.._end]) catch continue;\n", .{alloc_name});
    try self.emitIndent();
    try self.emit("_start = _end;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :textwrap_wrap_blk _lines.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate textwrap.fill(text, width=70) -> single string with newlines
pub fn genFill(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Use scope-aware allocator name
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    try self.emit("textwrap_fill_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _text = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _width: usize = ");
    if (args.len > 1) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("70");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(u8){};\n");
    try self.emitIndent();
    try self.emit("var _start: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (_start < _text.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _end = @min(_start + _width, _text.len);\n");
    try self.emitIndent();
    try self.emitFmt("if (_start > 0) _result.append({s}, '\\n') catch continue;\n", .{alloc_name});
    try self.emitIndent();
    try self.emitFmt("_result.appendSlice({s}, _text[_start.._end]) catch continue;\n", .{alloc_name});
    try self.emitIndent();
    try self.emit("_start = _end;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :textwrap_fill_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate textwrap.dedent(text) -> text with common leading whitespace removed
pub fn genDedent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Use scope-aware allocator name
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    try self.emit("textwrap_dedent_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _text = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    // Simple dedent: find min leading spaces and strip that many from each line
    try self.emit("var _min_indent: usize = std.math.maxInt(usize);\n");
    try self.emitIndent();
    try self.emit("var _lines_iter = std.mem.splitSequence(u8, _text, \"\\n\");\n");
    try self.emitIndent();
    try self.emit("while (_lines_iter.next()) |line| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (line.len == 0) continue;\n");
    try self.emitIndent();
    try self.emit("var _spaces: usize = 0;\n");
    try self.emitIndent();
    try self.emit("for (line) |c| { if (c == ' ') _spaces += 1 else break; }\n");
    try self.emitIndent();
    try self.emit("if (_spaces < _min_indent) _min_indent = _spaces;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (_min_indent == std.math.maxInt(usize)) _min_indent = 0;\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(u8){};\n");
    try self.emitIndent();
    try self.emit("var _lines_iter2 = std.mem.splitSequence(u8, _text, \"\\n\");\n");
    try self.emitIndent();
    try self.emit("var _first = true;\n");
    try self.emitIndent();
    try self.emit("while (_lines_iter2.next()) |line| {\n");
    self.indent();
    try self.emitIndent();
    try self.emitFmt("if (!_first) _result.append({s}, '\\n') catch continue;\n", .{alloc_name});
    try self.emitIndent();
    try self.emit("_first = false;\n");
    try self.emitIndent();
    try self.emitFmt("if (line.len > _min_indent) _result.appendSlice({s}, line[_min_indent..]) catch continue;\n", .{alloc_name});
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :textwrap_dedent_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate textwrap.indent(text, prefix) -> text with prefix added to each line
pub fn genIndent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    // Use scope-aware allocator name
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    try self.emit("textwrap_indent_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _text = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _prefix = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(u8){};\n");
    try self.emitIndent();
    try self.emit("var _lines_iter = std.mem.splitSequence(u8, _text, \"\\n\");\n");
    try self.emitIndent();
    try self.emit("var _first = true;\n");
    try self.emitIndent();
    try self.emit("while (_lines_iter.next()) |line| {\n");
    self.indent();
    try self.emitIndent();
    try self.emitFmt("if (!_first) _result.append({s}, '\\n') catch continue;\n", .{alloc_name});
    try self.emitIndent();
    try self.emit("_first = false;\n");
    try self.emitIndent();
    try self.emitFmt("_result.appendSlice({s}, _prefix) catch continue;\n", .{alloc_name});
    try self.emitIndent();
    try self.emitFmt("_result.appendSlice({s}, line) catch continue;\n", .{alloc_name});
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :textwrap_indent_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate textwrap.shorten(text, width, **kwargs) -> shortened text with ellipsis
pub fn genShorten(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("textwrap_shorten_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _text = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _width: usize = @intCast(");
    try self.genExpr(args[1]);
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("if (_text.len <= _width) break :textwrap_shorten_blk _text;\n");
    try self.emitIndent();
    try self.emit("if (_width <= 3) break :textwrap_shorten_blk \"...\";\n");
    try self.emitIndent();
    try self.emit("var _result = __global_allocator.alloc(u8, _width) catch break :textwrap_shorten_blk _text;\n");
    try self.emitIndent();
    try self.emit("@memcpy(_result[0.._width-3], _text[0.._width-3]);\n");
    try self.emitIndent();
    try self.emit("@memcpy(_result[_width-3..], \"...\");\n");
    try self.emitIndent();
    try self.emit("break :textwrap_shorten_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate textwrap.TextWrapper(...) -> TextWrapper object
pub fn genTextWrapper(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("width: usize = 70,\n");
    try self.emitIndent();
    try self.emit("initial_indent: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("subsequent_indent: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("pub fn wrap(__self: *@This(), text: []const u8) [][]const u8 { _ = text; return &.{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn fill(__self: *@This(), text: []const u8) []const u8 { return text; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}
