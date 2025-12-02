/// Python xml module - XML processing
const std = @import("std");
const h = @import("mod_helper.zig");

const element_tree_struct = "struct { root: ?*Element = null, pub fn getroot(s: *@This()) ?*Element { return s.root; } pub fn write(s: *@This(), f: []const u8) void { _ = s; _ = f; } }{}";
const parseBody = "; const f = std.fs.cwd().openFile(_src, .{}) catch break :blk " ++ element_tree_struct ++ "; defer f.close(); _ = f.readToEndAlloc(__global_allocator, 10*1024*1024) catch {}; break :blk " ++ element_tree_struct ++ "; }";
const tostringBody = "; var r: std.ArrayList(u8) = .{}; r.appendSlice(__global_allocator, \"<\") catch {}; r.appendSlice(__global_allocator, e.tag) catch {}; r.appendSlice(__global_allocator, \">\") catch {}; r.appendSlice(__global_allocator, e.text) catch {}; r.appendSlice(__global_allocator, \"</\") catch {}; r.appendSlice(__global_allocator, e.tag) catch {}; r.appendSlice(__global_allocator, \">\") catch {}; break :blk r.items; }";
const subElementBody = "; var c = Element{ .tag = t }; p.children.append(__global_allocator, &c) catch {}; break :blk c; }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "parse", h.wrap("blk: { const _src = ", parseBody, element_tree_struct) },
    .{ "fromstring", h.discard("Element{}") },
    .{ "tostring", h.wrap("blk: { const e = ", tostringBody, "\"\"") },
    .{ "Element", h.wrap("Element{ .tag = ", " }", "Element{}") },
    .{ "SubElement", h.wrap2("blk: { var p = ", "; const t = ", subElementBody, "Element{}") },
    .{ "ElementTree", h.c(element_tree_struct) },
    .{ "Comment", h.c("Element{ .tag = \"!--\" }") }, .{ "ProcessingInstruction", h.c("Element{ .tag = \"?\" }") },
    .{ "QName", h.wrap("struct { text: []const u8 }{ .text = ", " }", "struct { text: []const u8 = \"\" }{}") },
    .{ "indent", h.c("{}") }, .{ "dump", h.c("{}") }, .{ "iselement", h.c("true") },
});
