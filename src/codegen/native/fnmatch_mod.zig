/// Python fnmatch module - Unix filename pattern matching
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "fnmatch", genFnmatch },
    .{ "fnmatchcase", genFnmatch },
    .{ "filter", genFilter },
    .{ "translate", genTranslate },
});

fn genFnmatch(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 2) {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
        return;
    }
    const label = try self.emitInlineBlockStart("fnm");
    try self.emit("const _name = ");
    try self.genExpr(args[0]);
    try self.emit("; const _pattern = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; var pi: usize = 0; var ni: usize = 0; var star_pi: ?usize = null; var star_ni: usize = 0; while (ni < _name.len or pi < _pattern.len) {{ if (pi < _pattern.len) {{ const pc = _pattern[pi]; if (pc == '*') {{ star_pi = pi; star_ni = ni; pi += 1; continue; }} if (ni < _name.len) {{ const nc = _name[ni]; if (pc == '?' or pc == nc) {{ pi += 1; ni += 1; continue; }} }} }} if (star_pi) |sp| {{ pi = sp + 1; star_ni += 1; ni = star_ni; if (ni <= _name.len) continue; }} break :{s} false; }} break :{s} true; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genFilter(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 2) {
        try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const label = try self.emitInlineBlockStart("flt");
    const inner_label = try b.freshInlineLabel("fm");
    try self.emit("const _names = ");
    try self.genExpr(args[0]);
    try self.emit("; const _pattern = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; var _result: std.ArrayList([]const u8) = .{{}}; for (_names) |_fname| {{ var _match = true; var _pi: usize = 0; var _ni: usize = 0; var _star_pi: ?usize = null; var _star_ni: usize = 0; {s}: while (_ni < _fname.len or _pi < _pattern.len) {{ if (_pi < _pattern.len) {{ const _pc = _pattern[_pi]; if (_pc == '*') {{ _star_pi = _pi; _star_ni = _ni; _pi += 1; continue; }} if (_ni < _fname.len and (_pc == '?' or _pc == _fname[_ni])) {{ _pi += 1; _ni += 1; continue; }} }} if (_star_pi) |_sp| {{ _pi = _sp + 1; _star_ni += 1; _ni = _star_ni; if (_ni <= _fname.len) continue; }} _match = false; break :{s}; }} if (_match) _result.append(__global_allocator, _fname) catch unreachable; }} break :{s} _result.items; ", .{ inner_label, inner_label, label });
    try self.emitInlineBlockEnd();
}

fn genTranslate(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
        return;
    }
    const label = try self.emitInlineBlockStart("tr");
    try self.emit("const _pattern = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; var _result: std.ArrayList(u8) = .{{}}; _result.appendSlice(__global_allocator, \"(?s:\") catch unreachable; for (_pattern) |c| {{ switch (c) {{ '*' => _result.appendSlice(__global_allocator, \".*\") catch unreachable, '?' => _result.append(__global_allocator, '.') catch unreachable, '.' => _result.appendSlice(__global_allocator, \"\\\\.\") catch unreachable, '[' => _result.append(__global_allocator, '[') catch unreachable, ']' => _result.append(__global_allocator, ']') catch unreachable, '^' => _result.appendSlice(__global_allocator, \"\\\\^\") catch unreachable, '$' => _result.appendSlice(__global_allocator, \"\\\\$\") catch unreachable, else => _result.append(__global_allocator, c) catch unreachable }} }} _result.appendSlice(__global_allocator, \")\\\\Z\") catch unreachable; break :{s} _result.items; ", .{label});
    try self.emitInlineBlockEnd();
}
