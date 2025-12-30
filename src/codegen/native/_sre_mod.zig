/// Python _sre module - Internal SRE support (C accelerator for regex)
/// MIGRATED TO ZIGBUILDER
/// DRY: Uses h.c(), h.I32(), h.I64() factories for simple constant generators
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;
const ZigValue = builder_mod.ZigValue;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Functions that need runtime args - keep as functions
    .{ "compile", genCompile },
    .{ "getlower", genGetlower },
    .{ "sub", genSub },
    .{ "subn", genSubn },
    // Simple i32 constants - using h.I32() factory
    .{ "c_o_d_e_s_i_z_e", h.I32(4) },
    .{ "m_a_g_i_c", h.I32(20171005) },
    .{ "getcodesize", h.I32(4) },
    // Simple i64 constants - using h.I64() factory
    .{ "start", h.I64(0) },
    .{ "end", h.I64(0) },
    // Simple constant returns - using h.c() factory
    .{ "match", h.c("null") },
    .{ "fullmatch", h.c("null") },
    .{ "search", h.c("null") },
    .{ "findall", h.c("&[_][]const u8{}") },
    .{ "finditer", h.c("&[_]@TypeOf(null){}") },
    .{ "split", h.c("&[_][]const u8{}") },
    .{ "group", h.c("\"\"") },
    .{ "groups", h.c(".{}") },
    .{ "groupdict", h.c(".{}") },
    .{ "span", h.c(".{ @as(i64, 0), @as(i64, 0) }") },
    .{ "expand", h.c("\"\"") },
});

// Functions that need runtime args
fn genCompile(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        const pattern_val = try self.captureExpr(args[0]);
        const b = try self.getBuilder();
        try b.withLabeledBlock("__sre", struct {
            fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: ZigValue) !void {
                try bld.emitConstWithValue("__v", "", ctx, "");
                try scope.breakWithRaw(".{ .pattern = __v, .flags = 0, .groups = 0 }");
            }
        }.emit, pattern_val);
        try self.flushBuilder();
    } else {
        try self.emit(".{ .pattern = \"\", .flags = 0, .groups = 0 }");
    }
}

fn genGetlower(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(i32, 0)");
    }
}

fn genSub(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("\"\"");
    }
}

fn genSubn(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 1) {
        const repl_val = try self.captureExpr(args[1]);
        const b = try self.getBuilder();
        try b.withLabeledBlock("__subn", struct {
            fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: ZigValue) !void {
                try bld.emitConstWithValue("__repl", "", ctx, "");
                try scope.breakWithRaw(".{ __repl, @as(i64, 0) }");
            }
        }.emit, repl_val);
        try self.flushBuilder();
    } else {
        try self.emit(".{ \"\", @as(i64, 0) }");
    }
}
