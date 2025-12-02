/// Python glob module - Unix style pathname pattern expansion
const std = @import("std");
const h = @import("mod_helper.zig");

const genGlob = h.wrap("blk: { const _pattern = ", "; var _results: std.ArrayList([]const u8) = .{}; const _dir_path = std.fs.path.dirname(_pattern) orelse \".\"; const _file_pattern = std.fs.path.basename(_pattern); var _dir = std.fs.cwd().openDir(_dir_path, .{ .iterate = true }) catch break :blk _results.items; defer _dir.close(); var _iter = _dir.iterate(); while (_iter.next() catch null) |entry| { var _gmatch = true; var _gpi: usize = 0; var _gni: usize = 0; var _gstar_pi: ?usize = null; var _gstar_ni: usize = 0; glob_match_loop: while (_gni < entry.name.len or _gpi < _file_pattern.len) { if (_gpi < _file_pattern.len) { const _gpc = _file_pattern[_gpi]; if (_gpc == '*') { _gstar_pi = _gpi; _gstar_ni = _gni; _gpi += 1; continue; } if (_gni < entry.name.len and (_gpc == '?' or _gpc == entry.name[_gni])) { _gpi += 1; _gni += 1; continue; } } if (_gstar_pi) |_gsp| { _gpi = _gsp + 1; _gstar_ni += 1; _gni = _gstar_ni; if (_gni <= entry.name.len) continue; } _gmatch = false; break :glob_match_loop; } if (_gmatch) { const _full = std.fmt.allocPrint(__global_allocator, \"{s}/{s}\", .{_dir_path, entry.name}) catch continue; _results.append(__global_allocator, _full) catch continue; } } break :blk _results.items; }", "&[_][]const u8{}");
const genEscape = h.wrap("blk: { const _path = ", "; var _result: std.ArrayList(u8) = .{}; for (_path) |c| { if (c == '*' or c == '?' or c == '[') { _result.append(__global_allocator, '[') catch continue; _result.append(__global_allocator, c) catch continue; _result.append(__global_allocator, ']') catch continue; } else { _result.append(__global_allocator, c) catch continue; } } break :blk _result.items; }", "\"\"");
const genHasMagic = h.wrap("blk: { const _s = ", "; for (_s) |c| { if (c == '*' or c == '?' or c == '[') break :blk true; } break :blk false; }", "false");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "glob", genGlob }, .{ "iglob", genGlob }, .{ "escape", genEscape }, .{ "has_magic", genHasMagic },
});
