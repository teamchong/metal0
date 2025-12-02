/// Python sre_compile module - Internal support module for sre
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genFlag(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(u32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compile", genCompile }, .{ "isstring", genTrue }, .{ "MAXCODE", genMaxcode }, .{ "MAXGROUPS", genMaxgroups },
    .{ "_code", genEmptyU32 }, .{ "_compile", genUnit }, .{ "_compile_charset", genUnit },
    .{ "_optimize_charset", genEmptyTypeList }, .{ "_generate_overlap_table", genEmptyI32 }, .{ "_compile_info", genUnit },
    .{ "SRE_FLAG_TEMPLATE", genFlag(1) }, .{ "SRE_FLAG_IGNORECASE", genFlag(2) }, .{ "SRE_FLAG_LOCALE", genFlag(4) },
    .{ "SRE_FLAG_MULTILINE", genFlag(8) }, .{ "SRE_FLAG_DOTALL", genFlag(16) }, .{ "SRE_FLAG_UNICODE", genFlag(32) },
    .{ "SRE_FLAG_VERBOSE", genFlag(64) }, .{ "SRE_FLAG_DEBUG", genFlag(128) }, .{ "SRE_FLAG_ASCII", genFlag(256) },
});

fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genMaxcode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 65535)"); }
fn genMaxgroups(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 100)"); }
fn genEmptyU32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u32{}"); }
fn genEmptyI32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]i32{}"); }
fn genEmptyTypeList(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{}){}"); }

fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const pattern = "); try self.genExpr(args[0]); try self.emit("; _ = pattern; break :blk .{ .pattern = \"\", .flags = 0, .code = &[_]u32{}, .groups = 0 }; }"); }
    else { try self.emit(".{ .pattern = \"\", .flags = 0, .code = &[_]u32{}, .groups = 0 }"); }
}
