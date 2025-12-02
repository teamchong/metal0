/// Python html module - HTML entity encoding/decoding
const std = @import("std");
const h = @import("mod_helper.zig");

const genEscape = h.wrap("html_escape_blk: { const _s = ", "; var _result: std.ArrayList(u8) = .{}; for (_s) |c| { switch (c) { '&' => _result.appendSlice(__global_allocator, \"&amp;\") catch {}, '<' => _result.appendSlice(__global_allocator, \"&lt;\") catch {}, '>' => _result.appendSlice(__global_allocator, \"&gt;\") catch {}, '\"' => _result.appendSlice(__global_allocator, \"&quot;\") catch {}, '\\'' => _result.appendSlice(__global_allocator, \"&#x27;\") catch {}, else => _result.append(__global_allocator, c) catch {}, } } break :html_escape_blk _result.items; }", "\"\"");
const genUnescape = h.wrap("html_unescape_blk: { const _s = ", "; var _result: std.ArrayList(u8) = .{}; var _i: usize = 0; while (_i < _s.len) { if (_s[_i] == '&') { if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&lt;\")) { _result.append(__global_allocator, '<') catch {}; _i += 4; continue; } if (_i + 4 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 4], \"&gt;\")) { _result.append(__global_allocator, '>') catch {}; _i += 4; continue; } if (_i + 5 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 5], \"&amp;\")) { _result.append(__global_allocator, '&') catch {}; _i += 5; continue; } if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&quot;\")) { _result.append(__global_allocator, '\"') catch {}; _i += 6; continue; } if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&#x27;\")) { _result.append(__global_allocator, '\\'') catch {}; _i += 6; continue; } if (_i + 6 <= _s.len and std.mem.eql(u8, _s[_i .. _i + 6], \"&apos;\")) { _result.append(__global_allocator, '\\'') catch {}; _i += 6; continue; } } _result.append(__global_allocator, _s[_i]) catch {}; _i += 1; } break :html_unescape_blk _result.items; }", "\"\"");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "escape", genEscape }, .{ "unescape", genUnescape },
});
