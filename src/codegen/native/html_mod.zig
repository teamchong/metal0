/// Python html module - HTML entity encoding/decoding
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "escape", genEscape }, .{ "unescape", genUnescape },
});

pub fn genEscape(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("html_escape_blk: { const _s = ");
    try self.genExpr(args[0]);
    try self.emit("; var _result: std.ArrayList(u8) = .{}; for (_s) |c| { switch (c) { '&' => _result.appendSlice(__global_allocator, \"&amp;\") catch {}, '<' => _result.appendSlice(__global_allocator, \"&lt;\") catch {}, '>' => _result.appendSlice(__global_allocator, \"&gt;\") catch {}, '\"' => _result.appendSlice(__global_allocator, \"&quot;\") catch {}, '\\'' => _result.appendSlice(__global_allocator, \"&#x27;\") catch {}, else => _result.append(__global_allocator, c) catch {}, } } break :html_escape_blk _result.items; }");
}

pub fn genUnescape(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("html_unescape_blk: { const _s = ");
    try self.genExpr(args[0]);
    try self.emit("; var _result: std.ArrayList(u8) = .{}; var _i: usize = 0; while (_i < _s.len) { if (_s[_i] == '&') { if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&lt;\")) { _result.append(__global_allocator, '<') catch {}; _i += 4; continue; } if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&gt;\")) { _result.append(__global_allocator, '>') catch {}; _i += 4; continue; } if (_i + 5 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 5], \"&amp;\")) { _result.append(__global_allocator, '&') catch {}; _i += 5; continue; } if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&quot;\")) { _result.append(__global_allocator, '\"') catch {}; _i += 6; continue; } if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&#x27;\")) { _result.append(__global_allocator, '\\'') catch {}; _i += 6; continue; } if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&apos;\")) { _result.append(__global_allocator, '\\'') catch {}; _i += 6; continue; } } _result.append(__global_allocator, _s[_i]) catch {}; _i += 1; } break :html_unescape_blk _result.items; }");
}
