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
    const label = try self.emitInlineBlockStart("gub");
    const b = try self.getBuilder();
    try b.write("const home = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\");");
    try b.writeFmt("break :{s} std.fmt.allocPrint(__global_allocator, \"{{s}}/.local\", .{{home}}) catch \"\"; ", .{label});
    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
    try self.emitInlineBlockEnd();
}

fn genGetusersitepackages(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const label = try self.emitInlineBlockStart("gusp");
    const b = try self.getBuilder();
    try b.write("const home = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\");");
    try b.writeFmt("break :{s} std.fmt.allocPrint(__global_allocator, \"{{s}}/.local/lib/python3/site-packages\", .{{home}}) catch \"\"; ", .{label});
    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
    try self.emitInlineBlockEnd();
}
