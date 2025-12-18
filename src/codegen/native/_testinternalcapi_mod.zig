/// Python _testinternalcapi module - Internal CPython testing API
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "get_configs", genGetConfigs },
    .{ "get_recursion_depth", genGetRecursionDepth },
    .{ "SIZEOF_TIME_T", genSizeofTimeT },
    .{ "_PyTime_FromSeconds", genPyTimeFromSeconds },
    .{ "_PyTime_FromSecondsObject", genPyTimeFromSecondsObject },
    .{ "_PyTime_AsTimeval", genPyTimeAsTimeval },
    .{ "_PyTime_AsTimespec", genPyTimeAsTimespec },
    .{ "_PyTime_AsTimeval_clamp", genPyTimeAsTivevalClamp },
    .{ "_PyTime_AsTimespec_clamp", genPyTimeAsTimespecClamp },
    .{ "_PyTime_AsMilliseconds", genPyTimeAsMilliseconds },
    .{ "_PyTime_AsMicroseconds", genPyTimeAsMicroseconds },
    .{ "_PyTime_ObjectToTime_t", genPyTimeObjectToTimeT },
    .{ "_PyTime_ObjectToTimeval", genPyTimeObjectToTimeval },
    .{ "_PyTime_ObjectToTimespec", genPyTimeObjectToTimespec },
});

fn genGetConfigs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetRecursionDepth(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 1000)"), builder_mod.EmitConfig.forExpression());
}

fn genSizeofTimeT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const builtin = @import("builtin");
    // time_t size varies by platform: 32-bit on 32-bit systems, 64-bit elsewhere
    const size_expr = if (builtin.os.tag == .windows)
        "@as(i64, 8)" // Windows: always 64-bit time_t
    else if (builtin.cpu.arch == .x86 or builtin.cpu.arch == .arm)
        "@as(i64, 4)" // 32-bit Unix: 32-bit time_t
    else
        "@as(i64, 8)"; // 64-bit Unix: 64-bit time_t
    try b.emitValue(builder_mod.ZigValue.raw(size_expr), builder_mod.EmitConfig.forExpression());
}

fn genPyTimeFromSeconds(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("ts");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} @as(i64, 0); ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeFromSecondsObject(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("tso");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} @as(i64, 0); ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsTimeval(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("ttv");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsTimespec(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("tts");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsTivevalClamp(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("ttvc");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsTimespecClamp(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("ttsc");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsMilliseconds(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("tms");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} @as(i64, 0); ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsMicroseconds(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("tus");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} @as(i64, 0); ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeObjectToTimeT(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("ott");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} @as(i64, 0); ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeObjectToTimeval(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("otv");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeObjectToTimespec(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("ots");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}
