/// Python traceback module - Print or retrieve a stack traceback
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

/// Frame struct type for extract_tb/extract_stack return
const FrameStruct = "&[_]struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 }{}";
const WalkStruct = "&[_]struct { frame: ?*anyopaque, lineno: i64 }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "print_tb", genPrintTb },
    .{ "print_exception", genPrintException },
    .{ "print_exc", genPrintExc },
    .{ "print_last", genPrintLast },
    .{ "print_stack", genPrintStack },
    .{ "clear_frames", genClearFrames },
    .{ "extract_tb", genExtractTb },
    .{ "extract_stack", genExtractStack },
    .{ "walk_tb", genWalkTb },
    .{ "walk_stack", genWalkStack },
    .{ "format_list", genFormatList },
    .{ "format_exception_only", genFormatExceptionOnly },
    .{ "format_exception", genFormatException },
    .{ "format_tb", genFormatTb },
    .{ "format_stack", genFormatStack },
    .{ "format_exc", genFormatExc },
    .{ "TracebackException", genTracebackException },
    .{ "StackSummary", genStackSummary },
    .{ "FrameSummary", genFrameSummary },
});

fn genPrintTb(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("ptb");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} {{{{}}}}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPrintException(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("pex");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} {{{{}}}}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPrintExc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrintLast(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrintStack(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genClearFrames(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("cf");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} {{{{}}}}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genExtractTb(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("etb");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} ", .{label});
        try self.emit(FrameStruct);
        try self.emit("; ");
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(FrameStruct), builder_mod.EmitConfig.forExpression());
    }
}

fn genExtractStack(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(FrameStruct), builder_mod.EmitConfig.forExpression());
}

fn genWalkTb(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("wtb");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} ", .{label});
        try self.emit(WalkStruct);
        try self.emit("; ");
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(WalkStruct), builder_mod.EmitConfig.forExpression());
    }
}

fn genWalkStack(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(WalkStruct), builder_mod.EmitConfig.forExpression());
}

fn genFormatList(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("fl");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} &[_][]const u8{{{{}}}}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genFormatExceptionOnly(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("feo");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} &[_][]const u8{{{{}}}}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genFormatException(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("fe");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} &[_][]const u8{{{{}}}}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genFormatTb(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("ftb");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = __v; break :{s} &[_][]const u8{{{{}}}}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genFormatStack(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genFormatExc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genTracebackException(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { exc_type: []const u8 = \"\", exc_value: []const u8 = \"\", stack: []struct { filename: []const u8, lineno: i64, name: []const u8 } = &.{}, cause: ?*@This() = null, context: ?*@This() = null, pub fn format(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn format_exception_only(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn from_exception(exc: anytype) @This() { _ = exc; return @This(){}; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genStackSummary(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { frames: []struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 } = &.{}, pub fn extract(tb: anytype) @This() { _ = tb; return @This(){}; } pub fn from_list(frames: anytype) @This() { _ = frames; return @This(){}; } pub fn format(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genFrameSummary(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { filename: []const u8 = \"\", lineno: i64 = 0, name: []const u8 = \"\", line: []const u8 = \"\", locals: ?hashmap_helper.StringHashMap([]const u8) = null }{}"), builder_mod.EmitConfig.forExpression());
}
