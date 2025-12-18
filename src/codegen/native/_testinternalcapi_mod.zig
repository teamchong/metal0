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
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_ts: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_ts @as(i64, 0); }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeFromSecondsObject(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_tso: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_tso @as(i64, 0); }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsTimeval(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_ttv: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_ttv .{{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }}; }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsTimespec(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_tts: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_tts .{{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }}; }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsTivevalClamp(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_ttvc: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_ttvc .{{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }}; }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsTimespecClamp(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_ttsc: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_ttsc .{{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }}; }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsMilliseconds(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_tms: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_tms @as(i64, 0); }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeAsMicroseconds(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_tus: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_tus @as(i64, 0); }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeObjectToTimeT(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_ott: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_ott @as(i64, 0); }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeObjectToTimeval(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_otv: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_otv .{{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }}; }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPyTimeObjectToTimespec(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_ots: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_ots .{{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }}; }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
    }
}
