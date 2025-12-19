/// Python _testinternalcapi module - Internal CPython testing API
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

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

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genGetConfigs(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, ".{}");
}

fn genGetRecursionDepth(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "@as(i64, 1000)");
}

fn genSizeofTimeT(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const builtin = @import("builtin");
    // time_t size varies by platform: 32-bit on 32-bit systems, 64-bit elsewhere
    const size_expr = if (builtin.os.tag == .windows)
        "@as(i64, 8)" // Windows: always 64-bit time_t
    else if (builtin.cpu.arch == .x86 or builtin.cpu.arch == .arm)
        "@as(i64, 4)" // 32-bit Unix: 32-bit time_t
    else
        "@as(i64, 8)"; // 64-bit Unix: 64-bit time_t
    try emitConst(self, size_expr);
}

fn genPyTimeFromSeconds(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("ts", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; _ = __v; break :{s} @as(i64, 0)", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, "@as(i64, 0)");
    }
}

fn genPyTimeFromSecondsObject(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("tso", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; _ = __v; break :{s} @as(i64, 0)", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, "@as(i64, 0)");
    }
}

fn genPyTimeAsTimeval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("ttv", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }}", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, ".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }");
    }
}

fn genPyTimeAsTimespec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("tts", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }}", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, ".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }");
    }
}

fn genPyTimeAsTivevalClamp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("ttvc", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }}", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, ".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }");
    }
}

fn genPyTimeAsTimespecClamp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("ttsc", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }}", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, ".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }");
    }
}

fn genPyTimeAsMilliseconds(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("tms", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; _ = __v; break :{s} @as(i64, 0)", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, "@as(i64, 0)");
    }
}

fn genPyTimeAsMicroseconds(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("tus", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; _ = __v; break :{s} @as(i64, 0)", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, "@as(i64, 0)");
    }
}

fn genPyTimeObjectToTimeT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("ott", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; _ = __v; break :{s} @as(i64, 0)", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, "@as(i64, 0)");
    }
}

fn genPyTimeObjectToTimeval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("otv", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }}", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, ".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }");
    }
}

fn genPyTimeObjectToTimespec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("ots", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; _ = __v; break :{s} .{{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }}", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, ".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }");
    }
}
