/// Python _frozen_importlib module - Frozen import machinery
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "module_spec", genModuleSpec }, .{ "builtin_importer", h.c(".{}") }, .{ "frozen_importer", h.c(".{}") },
    .{ "init_module_attrs", h.c("{}") }, .{ "call_with_frames_removed", h.c("null") }, .{ "find_and_load", h.c("null") },
    .{ "find_and_load_unlocked", h.c("null") }, .{ "gcd_import", h.c("null") }, .{ "handle_fromlist", h.c("null") },
    .{ "lock_unlock_module", h.c(".{}") }, .{ "import", h.c("null") },
});

fn genModuleSpec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .name = name, .loader = null, .origin = null, .submodule_search_locations = null }; }"); } else try self.emit(".{ .name = \"\", .loader = null, .origin = null, .submodule_search_locations = null }");
}
