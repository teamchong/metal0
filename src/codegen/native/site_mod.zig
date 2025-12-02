/// Python site module - Site-specific configuration hook
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "PREFIXES", genConst("metal0_runtime.PyList([]const u8).init()") },
    .{ "ENABLE_USER_SITE", genConst("true") }, .{ "USER_SITE", genConst("@as(?[]const u8, null)") },
    .{ "USER_BASE", genConst("@as(?[]const u8, null)") },
    .{ "main", genConst("{}") }, .{ "addsitedir", genConst("metal0_runtime.PySet([]const u8).init()") },
    .{ "getsitepackages", genConst("metal0_runtime.PyList([]const u8).init()") },
    .{ "getuserbase", genConst("blk: { const home = std.posix.getenv(\"HOME\") orelse \"\"; break :blk std.fmt.allocPrint(metal0_allocator, \"{s}/.local\", .{home}) catch \"\"; }") },
    .{ "getusersitepackages", genConst("blk: { const home = std.posix.getenv(\"HOME\") orelse \"\"; break :blk std.fmt.allocPrint(metal0_allocator, \"{s}/.local/lib/python3/site-packages\", .{home}) catch \"\"; }") },
    .{ "removeduppaths", genConst("metal0_runtime.PySet([]const u8).init()") },
});
