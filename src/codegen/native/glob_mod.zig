/// Python glob module - Unix style pathname pattern expansion
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output - uses h.NativeCodegen from mod_helper
fn emitConst(self: *h.NativeCodegen, val: []const u8) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *h.NativeCodegen, comptime fmt: []const u8, args: anytype) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}



pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "glob", genGlob },
    .{ "iglob", genGlob },
    .{ "escape", genEscape },
    .{ "has_magic", genHasMagic },
});

fn genGlob(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("glob", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const inner_id = (try c.getBuilder()).getNextId();
            try emitConst(c, "const _pattern = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; var _results: std.ArrayList([]const u8) = .{{}}; const _dir_path = std.fs.path.dirname(_pattern) orelse \".\"; const _file_pattern = std.fs.path.basename(_pattern); var _dir = std.fs.cwd().openDir(_dir_path, .{{ .iterate = true }}) catch break :{s} _results.items; defer _dir.close(); var _iter = _dir.iterate(); while (_iter.next() catch null) |entry| {{ var _gmatch = true; var _gpi: usize = 0; var _gni: usize = 0; var _gstar_pi: ?usize = null; var _gstar_ni: usize = 0; __gml{d}: while (_gni < entry.name.len or _gpi < _file_pattern.len) {{ if (_gpi < _file_pattern.len) {{ const _gpc = _file_pattern[_gpi]; if (_gpc == '*') {{ _gstar_pi = _gpi; _gstar_ni = _gni; _gpi += 1; continue; }} if (_gni < entry.name.len and (_gpc == '?' or _gpc == entry.name[_gni])) {{ _gpi += 1; _gni += 1; continue; }} }} if (_gstar_pi) |_gsp| {{ _gpi = _gsp + 1; _gstar_ni += 1; _gni = _gstar_ni; if (_gni <= entry.name.len) continue; }} _gmatch = false; break :__gml{d}; }} if (_gmatch) {{ const _full = std.fmt.allocPrint(__global_allocator, \"", .{ label, inner_id, inner_id });
            // Handle the inner {s}/{s} format in two parts to avoid fmt parsing issues
            try emitConst(c, "{s}/{s}");
            try emitFmtConst(c, "\", .{{_dir_path, entry.name}}) catch continue; _results.append(__global_allocator, _full) catch continue; }} }} break :{s} _results.items; ", .{label});
        }
    }.emit);
}

fn genEscape(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("esc", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const _path = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; var _result: std.ArrayList(u8) = .{{}}; for (_path) |c| {{ if (c == '*' or c == '?' or c == '[') {{ _result.append(__global_allocator, '[') catch continue; _result.append(__global_allocator, c) catch continue; _result.append(__global_allocator, ']') catch continue; }} else {{ _result.append(__global_allocator, c) catch continue; }} }} break :{s} _result.items; ", .{label});
        }
    }.emit);
}

fn genHasMagic(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("hm", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const _s = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; for (_s) |c| {{ if (c == '*' or c == '?' or c == '[') break :{s} true; }} break :{s} false; ", .{ label, label });
        }
    }.emit);
}
