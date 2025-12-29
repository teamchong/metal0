/// Python _sre module - Internal SRE support (C accelerator for regex)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compile", genCompile },
    .{ "c_o_d_e_s_i_z_e", genCodesize },
    .{ "m_a_g_i_c", genMagic },
    .{ "getlower", genGetlower },
    .{ "getcodesize", genGetcodesizeFunc },
    .{ "match", genMatch },
    .{ "fullmatch", genFullmatch },
    .{ "search", genSearch },
    .{ "findall", genFindall },
    .{ "finditer", genFinditer },
    .{ "sub", genSub },
    .{ "subn", genSubn },
    .{ "split", genSplit },
    .{ "group", genGroup },
    .{ "groups", genGroups },
    .{ "groupdict", genGroupdict },
    .{ "start", genStart },
    .{ "end", genEnd },
    .{ "span", genSpan },
    .{ "expand", genExpand },
});

const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;
const ZigValue = builder_mod.ZigValue;

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

fn genCodesize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 4)");
}

fn genMagic(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 20171005)");
}

fn genGetlower(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(i32, 0)");
    }
}

fn genGetcodesizeFunc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 4)");
}

fn genMatch(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("null");
}

fn genFullmatch(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("null");
}

fn genSearch(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("null");
}

fn genFindall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("&[_][]const u8{}");
}

fn genFinditer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("&[_]@TypeOf(null){}");
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

fn genSplit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("&[_][]const u8{}");
}

fn genGroup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("\"\"");
}

fn genGroups(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{}");
}

fn genGroupdict(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{}");
}

fn genStart(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i64, 0)");
}

fn genEnd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i64, 0)");
}

fn genSpan(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{ @as(i64, 0), @as(i64, 0) }");
}

fn genExpand(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("\"\"");
}
