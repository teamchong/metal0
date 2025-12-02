/// Python _frozen_importlib module - Frozen import machinery
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "module_spec", genModuleSpec }, .{ "builtin_importer", genConst(".{}") }, .{ "frozen_importer", genConst(".{}") },
    .{ "init_module_attrs", genConst("{}") }, .{ "call_with_frames_removed", genConst("null") }, .{ "find_and_load", genConst("null") },
    .{ "find_and_load_unlocked", genConst("null") }, .{ "gcd_import", genConst("null") }, .{ "handle_fromlist", genConst("null") },
    .{ "lock_unlock_module", genConst(".{}") }, .{ "import", genConst("null") },
});

fn genModuleSpec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .name = name, .loader = null, .origin = null, .submodule_search_locations = null }; }"); } else try self.emit(".{ .name = \"\", .loader = null, .origin = null, .submodule_search_locations = null }");
}
