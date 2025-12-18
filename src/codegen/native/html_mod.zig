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

    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_escape: {{ const _s = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; var _result: std.ArrayList(u8) = .{{}}; for (_s) |c| {{ switch (c) {{ '&' => _result.appendSlice(__global_allocator, \"&amp;\") catch unreachable, '<' => _result.appendSlice(__global_allocator, \"&lt;\") catch unreachable, '>' => _result.appendSlice(__global_allocator, \"&gt;\") catch unreachable, '\"' => _result.appendSlice(__global_allocator, \"&quot;\") catch unreachable, '\\'' => _result.appendSlice(__global_allocator, \"&#x27;\") catch unreachable, else => _result.append(__global_allocator, c) catch unreachable, }} }} break :__m{d}_escape _result.items; }})", .{id});
}

/// Generates html.unescape(s) - unescapes HTML entities
fn genUnescape(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }

    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_unescape: {{ const _s = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; var _result: std.ArrayList(u8) = .{{}}; var _i: usize = 0; while (_i < _s.len) {{ if (_s[_i] == '&') {{ if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&lt;\")) {{ _result.append(__global_allocator, '<') catch unreachable; _i += 4; continue; }} if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&gt;\")) {{ _result.append(__global_allocator, '>') catch unreachable; _i += 4; continue; }} if (_i + 5 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 5], \"&amp;\")) {{ _result.append(__global_allocator, '&') catch unreachable; _i += 5; continue; }} if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&quot;\")) {{ _result.append(__global_allocator, '\"') catch unreachable; _i += 6; continue; }} if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&#x27;\")) {{ _result.append(__global_allocator, '\\'') catch unreachable; _i += 6; continue; }} if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&apos;\")) {{ _result.append(__global_allocator, '\\'') catch unreachable; _i += 6; continue; }} }} _result.append(__global_allocator, _s[_i]) catch unreachable; _i += 1; }} break :__m{d}_unescape _result.items; }})", .{id});
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "escape", genEscape },
    .{ "unescape", genUnescape },
});
