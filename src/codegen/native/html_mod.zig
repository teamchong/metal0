/// Python html module - HTML entity encoding/decoding
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "escape", genEscape },
    .{ "unescape", genUnescape },
});

/// Generate html.escape(s, quote=True) -> escaped string
pub fn genEscape(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("html_escape_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _s = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("for (_s) |c| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("switch (c) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("'&' => _result.appendSlice(__global_allocator, \"&amp;\") catch {},\n");
    try self.emitIndent();
    try self.emit("'<' => _result.appendSlice(__global_allocator, \"&lt;\") catch {},\n");
    try self.emitIndent();
    try self.emit("'>' => _result.appendSlice(__global_allocator, \"&gt;\") catch {},\n");
    try self.emitIndent();
    try self.emit("'\"' => _result.appendSlice(__global_allocator, \"&quot;\") catch {},\n");
    try self.emitIndent();
    try self.emit("'\\'' => _result.appendSlice(__global_allocator, \"&#x27;\") catch {},\n");
    try self.emitIndent();
    try self.emit("else => _result.append(__global_allocator, c) catch {},\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :html_escape_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate html.unescape(s) -> unescaped string
pub fn genUnescape(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("html_unescape_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _s = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("var _i: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (_i < _s.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (_s[_i] == '&') {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&lt;\")) { _result.append(__global_allocator, '<') catch {}; _i += 4; continue; }\n");
    try self.emitIndent();
    try self.emit("if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&gt;\")) { _result.append(__global_allocator, '>') catch {}; _i += 4; continue; }\n");
    try self.emitIndent();
    try self.emit("if (_i + 5 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 5], \"&amp;\")) { _result.append(__global_allocator, '&') catch {}; _i += 5; continue; }\n");
    try self.emitIndent();
    try self.emit("if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&quot;\")) { _result.append(__global_allocator, '\"') catch {}; _i += 6; continue; }\n");
    try self.emitIndent();
    try self.emit("if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&#x27;\")) { _result.append(__global_allocator, '\\'') catch {}; _i += 6; continue; }\n");
    try self.emitIndent();
    try self.emit("if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&apos;\")) { _result.append(__global_allocator, '\\'') catch {}; _i += 6; continue; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, _s[_i]) catch {};\n");
    try self.emitIndent();
    try self.emit("_i += 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :html_unescape_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
