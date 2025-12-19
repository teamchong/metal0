/// Python html module - HTML entity encoding/decoding
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

/// Generates html.escape(s) - escapes HTML special characters
fn genEscape(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.write("\"\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    try self.withInlineBlock("escape", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b2 = try c.getBuilder();
            try b2.write("const _s = ");
            const output1 = b2.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; var _result: std.ArrayList(u8) = .{{}}; for (_s) |ch| {{ switch (ch) {{ '&' => _result.appendSlice(__global_allocator, \"&amp;\") catch unreachable, '<' => _result.appendSlice(__global_allocator, \"&lt;\") catch unreachable, '>' => _result.appendSlice(__global_allocator, \"&gt;\") catch unreachable, '\"' => _result.appendSlice(__global_allocator, \"&quot;\") catch unreachable, '\\'' => _result.appendSlice(__global_allocator, \"&#x27;\") catch unreachable, else => _result.append(__global_allocator, ch) catch unreachable, }} }} break :{s} _result.items", .{label});
                const output2 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

/// Generates html.unescape(s) - unescapes HTML entities
fn genUnescape(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.write("\"\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    try self.withInlineBlock("unescape", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b2 = try c.getBuilder();
            try b2.write("const _s = ");
            const output1 = b2.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; var _result: std.ArrayList(u8) = .{{}}; var _i: usize = 0; while (_i < _s.len) {{ if (_s[_i] == '&') {{ if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&lt;\")) {{ _result.append(__global_allocator, '<') catch unreachable; _i += 4; continue; }} if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&gt;\")) {{ _result.append(__global_allocator, '>') catch unreachable; _i += 4; continue; }} if (_i + 5 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 5], \"&amp;\")) {{ _result.append(__global_allocator, '&') catch unreachable; _i += 5; continue; }} if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&quot;\")) {{ _result.append(__global_allocator, '\"') catch unreachable; _i += 6; continue; }} if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&#x27;\")) {{ _result.append(__global_allocator, '\\'') catch unreachable; _i += 6; continue; }} if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&apos;\")) {{ _result.append(__global_allocator, '\\'') catch unreachable; _i += 6; continue; }} }} _result.append(__global_allocator, _s[_i]) catch unreachable; _i += 1; }} break :{s} _result.items", .{label});
                const output2 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "escape", genEscape },
    .{ "unescape", genUnescape },
});
