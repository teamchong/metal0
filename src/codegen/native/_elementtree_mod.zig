/// Python _elementtree module - Internal ElementTree support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

const elem_default = ".{ .tag = \"\", .attrib = .{}, .text = null, .tail = null }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Element", h.wrap("blk: { const tag = ", "; break :blk .{ .tag = tag, .attrib = .{}, .text = null, .tail = null }; }", elem_default) },
    .{ "SubElement", h.wrapN(1, "blk: { const tag = ", "; break :blk .{ .tag = tag, .attrib = .{}, .text = null, .tail = null }; }", elem_default) },
    .{ "TreeBuilder", h.c(".{ .element_factory = null, .data = &[_][]const u8{}, .elem = &[_]@TypeOf(.{}){}, .last = null }") },
    .{ "XMLParser", h.c(".{ .target = null, .parser = null }") }, .{ "ParseError", h.err("ParseError") },
});
