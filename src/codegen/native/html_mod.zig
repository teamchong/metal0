/// Python html module - HTML entity encoding/decoding
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

/// Generates html.escape(s) - escapes HTML special characters
fn genEscape(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }

    const b = try self.getBuilder();
    const label = try b.emitInlineBlockStart("escape");
    try self.emit("const _s = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; var _result: std.ArrayList(u8) = .{{}}; for (_s) |c| {{ switch (c) {{ '&' => _result.appendSlice(__global_allocator, \"&amp;\") catch unreachable, '<' => _result.appendSlice(__global_allocator, \"&lt;\") catch unreachable, '>' => _result.appendSlice(__global_allocator, \"&gt;\") catch unreachable, '\"' => _result.appendSlice(__global_allocator, \"&quot;\") catch unreachable, '\\'' => _result.appendSlice(__global_allocator, \"&#x27;\") catch unreachable, else => _result.append(__global_allocator, c) catch unreachable, }} }} break :{s} _result.items; ", .{label});
    try b.emitInlineBlockEnd();
}

/// Generates html.unescape(s) - unescapes HTML entities
fn genUnescape(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }

    const b = try self.getBuilder();
    const label = try b.emitInlineBlockStart("unescape");
    try self.emit("const _s = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; var _result: std.ArrayList(u8) = .{{}}; var _i: usize = 0; while (_i < _s.len) {{ if (_s[_i] == '&') {{ if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&lt;\")) {{ _result.append(__global_allocator, '<') catch unreachable; _i += 4; continue; }} if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&gt;\")) {{ _result.append(__global_allocator, '>') catch unreachable; _i += 4; continue; }} if (_i + 5 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 5], \"&amp;\")) {{ _result.append(__global_allocator, '&') catch unreachable; _i += 5; continue; }} if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&quot;\")) {{ _result.append(__global_allocator, '\"') catch unreachable; _i += 6; continue; }} if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&#x27;\")) {{ _result.append(__global_allocator, '\\'') catch unreachable; _i += 6; continue; }} if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&apos;\")) {{ _result.append(__global_allocator, '\\'') catch unreachable; _i += 6; continue; }} }} _result.append(__global_allocator, _s[_i]) catch unreachable; _i += 1; }} break :{s} _result.items; ", .{label});
    try b.emitInlineBlockEnd();
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "escape", genEscape },
    .{ "unescape", genUnescape },
});
