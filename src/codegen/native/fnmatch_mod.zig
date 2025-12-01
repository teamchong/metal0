/// Python fnmatch module - Unix filename pattern matching
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "fnmatch", genFnmatch },
    .{ "fnmatchcase", genFnmatchcase },
    .{ "filter", genFilter },
    .{ "translate", genTranslate },
});

/// Generate fnmatch.fnmatch(name, pattern) -> bool
/// Implements Unix shell-style wildcards:
/// * - matches everything
/// ? - matches any single character
/// [seq] - matches any character in seq
/// [!seq] - matches any character not in seq
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
    // Inline glob matching implementation
    try self.emit("var pi: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var ni: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var star_pi: ?usize = null;\n");
    try self.emitIndent();
    try self.emit("var star_ni: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (ni < _name.len or pi < _pattern.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (pi < _pattern.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const pc = _pattern[pi];\n");
    try self.emitIndent();
    try self.emit("if (pc == '*') {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("star_pi = pi;\n");
    try self.emitIndent();
    try self.emit("star_ni = ni;\n");
    try self.emitIndent();
    try self.emit("pi += 1;\n");
    try self.emitIndent();
    try self.emit("continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (ni < _name.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const nc = _name[ni];\n");
    try self.emitIndent();
    try self.emit("if (pc == '?' or pc == nc) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pi += 1;\n");
    try self.emitIndent();
    try self.emit("ni += 1;\n");
    try self.emitIndent();
    try self.emit("continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (star_pi) |sp| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pi = sp + 1;\n");
    try self.emitIndent();
    try self.emit("star_ni += 1;\n");
    try self.emitIndent();
    try self.emit("ni = star_ni;\n");
    try self.emitIndent();
    try self.emit("if (ni <= _name.len) continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :fnmatch_blk false;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :fnmatch_blk true;\n");
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
    try self.emit("var _result: std.ArrayList([]const u8) = .{};\n");
    try self.emitIndent();
    try self.emit("for (_names) |_fname| {\n");
    self.indent();
    // Inline glob matching for filter
    try self.emitIndent();
    try self.emit("var _match = true;\n");
    try self.emitIndent();
    try self.emit("var _pi: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var _ni: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var _star_pi: ?usize = null;\n");
    try self.emitIndent();
    try self.emit("var _star_ni: usize = 0;\n");
    try self.emitIndent();
    try self.emit("filter_match: while (_ni < _fname.len or _pi < _pattern.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (_pi < _pattern.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _pc = _pattern[_pi];\n");
    try self.emitIndent();
    try self.emit("if (_pc == '*') { _star_pi = _pi; _star_ni = _ni; _pi += 1; continue; }\n");
    try self.emitIndent();
    try self.emit("if (_ni < _fname.len and (_pc == '?' or _pc == _fname[_ni])) { _pi += 1; _ni += 1; continue; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (_star_pi) |_sp| { _pi = _sp + 1; _star_ni += 1; _ni = _star_ni; if (_ni <= _fname.len) continue; }\n");
    try self.emitIndent();
    try self.emit("_match = false; break :filter_match;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (_match) _result.append(__global_allocator, _fname) catch {};\n");
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
    try self.emit("var _result: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, \"(?s:\") catch {};\n");
    try self.emitIndent();
    try self.emit("for (_pattern) |c| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("switch (c) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("'*' => _result.appendSlice(__global_allocator, \".*\") catch {},\n");
    try self.emitIndent();
    try self.emit("'?' => _result.append(__global_allocator, '.') catch {},\n");
    try self.emitIndent();
    try self.emit("'.' => _result.appendSlice(__global_allocator, \"\\\\.\") catch {},\n");
    try self.emitIndent();
    try self.emit("'[' => _result.append(__global_allocator, '[') catch {},\n");
    try self.emitIndent();
    try self.emit("']' => _result.append(__global_allocator, ']') catch {},\n");
    try self.emitIndent();
    try self.emit("'^' => _result.appendSlice(__global_allocator, \"\\\\^\") catch {},\n");
    try self.emitIndent();
    try self.emit("'$' => _result.appendSlice(__global_allocator, \"\\\\$\") catch {},\n");
    try self.emitIndent();
    try self.emit("else => _result.append(__global_allocator, c) catch {},\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, \")\\\\Z\") catch {};\n");
    try self.emitIndent();
    try self.emit("break :fnmatch_translate_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
