/// Python glob module - Unix style pathname pattern expansion
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "glob", genGlob },
    .{ "iglob", genIglob },
    .{ "escape", genEscape },
    .{ "has_magic", genHasMagic },
});

/// Generate glob.glob(pattern, *, root_dir=None, recursive=False) -> list of paths
pub fn genGlob(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("glob_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _pattern = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _results: std.ArrayList([]const u8) = .{};\n");
    try self.emitIndent();
    // Simple glob: split pattern and match files
    try self.emit("const _dir_path = std.fs.path.dirname(_pattern) orelse \".\";\n");
    try self.emitIndent();
    try self.emit("const _file_pattern = std.fs.path.basename(_pattern);\n");
    try self.emitIndent();
    try self.emit("var _dir = std.fs.cwd().openDir(_dir_path, .{ .iterate = true }) catch break :glob_blk _results.items;\n");
    try self.emitIndent();
    try self.emit("defer _dir.close();\n");
    try self.emitIndent();
    try self.emit("var _iter = _dir.iterate();\n");
    try self.emitIndent();
    try self.emit("while (_iter.next() catch null) |entry| {\n");
    self.indent();
    // Inline glob matching
    try self.emitIndent();
    try self.emit("var _gmatch = true;\n");
    try self.emitIndent();
    try self.emit("var _gpi: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var _gni: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var _gstar_pi: ?usize = null;\n");
    try self.emitIndent();
    try self.emit("var _gstar_ni: usize = 0;\n");
    try self.emitIndent();
    try self.emit("glob_match_loop: while (_gni < entry.name.len or _gpi < _file_pattern.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (_gpi < _file_pattern.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _gpc = _file_pattern[_gpi];\n");
    try self.emitIndent();
    try self.emit("if (_gpc == '*') { _gstar_pi = _gpi; _gstar_ni = _gni; _gpi += 1; continue; }\n");
    try self.emitIndent();
    try self.emit("if (_gni < entry.name.len and (_gpc == '?' or _gpc == entry.name[_gni])) { _gpi += 1; _gni += 1; continue; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (_gstar_pi) |_gsp| { _gpi = _gsp + 1; _gstar_ni += 1; _gni = _gstar_ni; if (_gni <= entry.name.len) continue; }\n");
    try self.emitIndent();
    try self.emit("_gmatch = false; break :glob_match_loop;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (_gmatch) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _full = std.fmt.allocPrint(__global_allocator, \"{s}/{s}\", .{_dir_path, entry.name}) catch continue;\n");
    try self.emitIndent();
    try self.emit("_results.append(__global_allocator, _full) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :glob_blk _results.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate glob.iglob(pattern, *, root_dir=None, recursive=False) -> iterator
pub fn genIglob(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // For simplicity, same as glob (returns list, not iterator)
    try genGlob(self, args);
}

/// Generate glob.escape(pathname) -> escaped string
pub fn genEscape(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("glob_escape_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("for (_path) |c| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (c == '*' or c == '?' or c == '[') {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, '[') catch continue;\n");
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, c) catch continue;\n");
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, ']') catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, c) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :glob_escape_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate glob.has_magic(s) -> bool
pub fn genHasMagic(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("glob_hasmagic_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _s = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("for (_s) |c| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (c == '*' or c == '?' or c == '[') break :glob_hasmagic_blk true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :glob_hasmagic_blk false;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
