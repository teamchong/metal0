/// Python sre_compile module - Internal support module for sre
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compile", genCompile }, .{ "isstring", genConst("true") }, .{ "MAXCODE", genConst("@as(u32, 65535)") }, .{ "MAXGROUPS", genConst("@as(u32, 100)") },
    .{ "_code", genConst("&[_]u32{}") }, .{ "_compile", genConst("{}") }, .{ "_compile_charset", genConst("{}") },
    .{ "_optimize_charset", genConst("&[_]@TypeOf(.{}){}") }, .{ "_generate_overlap_table", genConst("&[_]i32{}") }, .{ "_compile_info", genConst("{}") },
    .{ "SRE_FLAG_TEMPLATE", genConst("@as(u32, 1)") }, .{ "SRE_FLAG_IGNORECASE", genConst("@as(u32, 2)") }, .{ "SRE_FLAG_LOCALE", genConst("@as(u32, 4)") },
    .{ "SRE_FLAG_MULTILINE", genConst("@as(u32, 8)") }, .{ "SRE_FLAG_DOTALL", genConst("@as(u32, 16)") }, .{ "SRE_FLAG_UNICODE", genConst("@as(u32, 32)") },
    .{ "SRE_FLAG_VERBOSE", genConst("@as(u32, 64)") }, .{ "SRE_FLAG_DEBUG", genConst("@as(u32, 128)") }, .{ "SRE_FLAG_ASCII", genConst("@as(u32, 256)") },
});

fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const pattern = "); try self.genExpr(args[0]); try self.emit("; _ = pattern; break :blk .{ .pattern = \"\", .flags = 0, .code = &[_]u32{}, .groups = 0 }; }"); }
    else { try self.emit(".{ .pattern = \"\", .flags = 0, .code = &[_]u32{}, .groups = 0 }"); }
}
