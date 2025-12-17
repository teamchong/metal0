/// Python glob module - Unix style pathname pattern expansion
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "glob", genGlob }, .{ "iglob", genGlob }, .{ "escape", genEscape }, .{ "has_magic", genHasMagic },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genGlob(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("&[_][]const u8{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_glob: {{ const _pattern = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; var _results: std.ArrayList([]const u8) = .{{}}; const _dir_path = std.fs.path.dirname(_pattern) orelse \".\"; const _file_pattern = std.fs.path.basename(_pattern); var _dir = std.fs.cwd().openDir(_dir_path, .{{ .iterate = true }}) catch break :__m{d}_glob _results.items; defer _dir.close(); var _iter = _dir.iterate(); while (_iter.next() catch null) |entry| {{ var _gmatch = true; var _gpi: usize = 0; var _gni: usize = 0; var _gstar_pi: ?usize = null; var _gstar_ni: usize = 0; __m{d}_gml: while (_gni < entry.name.len or _gpi < _file_pattern.len) {{ if (_gpi < _file_pattern.len) {{ const _gpc = _file_pattern[_gpi]; if (_gpc == '*') {{ _gstar_pi = _gpi; _gstar_ni = _gni; _gpi += 1; continue; }} if (_gni < entry.name.len and (_gpc == '?' or _gpc == entry.name[_gni])) {{ _gpi += 1; _gni += 1; continue; }} }} if (_gstar_pi) |_gsp| {{ _gpi = _gsp + 1; _gstar_ni += 1; _gni = _gstar_ni; if (_gni <= entry.name.len) continue; }} _gmatch = false; break :__m{d}_gml; }} if (_gmatch) {{ const _full = std.fmt.allocPrint(__global_allocator, \"", .{ id, id, id });
    // Handle the inner {{s}}/{{s}} format in two parts to avoid fmt parsing issues
    try self.emit("{s}/{s}");
    try self.emitFmt("\", .{{_dir_path, entry.name}}) catch continue; _results.append(__global_allocator, _full) catch continue; }} }} break :__m{d}_glob _results.items; }})", .{id});
}

fn genEscape(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_esc: {{ const _path = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; var _result: std.ArrayList(u8) = .{{}}; for (_path) |c| {{ if (c == '*' or c == '?' or c == '[') {{ _result.append(__global_allocator, '[') catch continue; _result.append(__global_allocator, c) catch continue; _result.append(__global_allocator, ']') catch continue; }} else {{ _result.append(__global_allocator, c) catch continue; }} }} break :__m{d}_esc _result.items; }})", .{id});
}

fn genHasMagic(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("false"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_hm: {{ const _s = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; for (_s) |c| {{ if (c == '*' or c == '?' or c == '[') break :__m{d}_hm true; }} break :__m{d}_hm false; }})", .{ id, id });
}
