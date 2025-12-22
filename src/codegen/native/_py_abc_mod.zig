/// Python _py_abc module - Pure Python ABC implementation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "a_b_c_meta", genAbcMeta },
    .{ "get_cache_token", genGetCacheToken },
});

fn genAbcMeta(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ ._abc_registry = .{}, ._abc_cache = .{}, ._abc_negative_cache = .{} }"), builder_mod.EmitConfig.forExpression());
}

fn genGetCacheToken(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    // If no args, this is a reference (_py_abc.get_cache_token passed as value), not a call
    // Return UnsupportedSyntax to let the fallback emit &_py_abc.get_cache_token
    if (args.len == 0) return error.UnsupportedSyntax;
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}
