/// Python site module - Site-specific configuration hook
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "PREFIXES", h.c("runtime.NativeList.init()") },
    .{ "ENABLE_USER_SITE", h.c("true") }, .{ "USER_SITE", h.c("@as(?[]const u8, null)") },
    .{ "USER_BASE", h.c("@as(?[]const u8, null)") },
    .{ "main", h.c("{}") }, .{ "addsitedir", h.c("hashmap_helper.StringHashMap(void).init(__global_allocator)") },
    .{ "getsitepackages", h.c("runtime.NativeList.init()") },
    .{ "getuserbase", genGetuserbase },
    .{ "getusersitepackages", genGetusersitepackages },
    .{ "removeduppaths", h.c("hashmap_helper.StringHashMap(void).init(__global_allocator)") },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genGetuserbase(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    // Use self.emit (not builder) to write to correct output buffer
    const label = try self.emitInlineBlockStart("gub");
    try self.emit("const home = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\");");
    try self.emitFmt("break :{s} std.fmt.allocPrint(__global_allocator, \"{{s}}/.local\", .{{home}}) catch \"\"; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genGetusersitepackages(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    // Use self.emit (not builder) to write to correct output buffer
    const label = try self.emitInlineBlockStart("gusp");
    try self.emit("const home = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\");");
    try self.emitFmt("break :{s} std.fmt.allocPrint(__global_allocator, \"{{s}}/.local/lib/python3/site-packages\", .{{home}}) catch \"\"; ", .{label});
    try self.emitInlineBlockEnd();
}
