/// Python _frozen_importlib module - Frozen import machinery
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "module_spec", genModuleSpec }, .{ "builtin_importer", genEmpty }, .{ "frozen_importer", genEmpty },
    .{ "init_module_attrs", genUnit }, .{ "call_with_frames_removed", genNull }, .{ "find_and_load", genNull },
    .{ "find_and_load_unlocked", genNull }, .{ "gcd_import", genNull }, .{ "handle_fromlist", genNull },
    .{ "lock_unlock_module", genEmpty }, .{ "import", genNull },
});

fn genModuleSpec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .name = name, .loader = null, .origin = null, .submodule_search_locations = null }; }"); } else try self.emit(".{ .name = \"\", .loader = null, .origin = null, .submodule_search_locations = null }");
}
