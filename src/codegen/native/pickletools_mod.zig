/// Python pickletools module - Tools for working with pickle data streams
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dis", h.c("{}") }, .{ "genops", h.c("&[_]@TypeOf(.{}){}") }, .{ "optimize", genOptimize },
    .{ "OpcodeInfo", h.c(".{ .name = \"\", .code = \"\", .arg = null, .stack_before = &[_][]const u8{}, .stack_after = &[_][]const u8{}, .proto = 0, .doc = \"\" }") },
    .{ "opcodes", h.c("&[_]@TypeOf(.{}){}") },
    .{ "bytes_types", h.c("&[_]type{ []const u8 }") },
    .{ "UP_TO_NEWLINE", h.I32(-1) }, .{ "TAKEN_FROM_ARGUMENT1", h.I32(-2) },
    .{ "TAKEN_FROM_ARGUMENT4", h.I32(-3) }, .{ "TAKEN_FROM_ARGUMENT4U", h.I32(-4) }, .{ "TAKEN_FROM_ARGUMENT8U", h.I32(-5) },
});

fn genOptimize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\""); }
