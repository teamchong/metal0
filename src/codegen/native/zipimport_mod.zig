/// Python zipimport module - Import modules from zip files
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "zipimporter", h.structField("archive", ", .prefix = \"\"", ".{ .archive = \"\", .prefix = \"\" }") },
    .{ "ZipImportError", h.err("ZipImportError") },
});
