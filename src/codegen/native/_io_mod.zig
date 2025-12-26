/// Python _io module - Core I/O implementation (underlying io module)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "FileIO", genFileIO },
    .{ "BytesIO", genBytesIO },
    .{ "StringIO", genStringIO },
    .{ "BufferedReader", genBuffered },
    .{ "BufferedWriter", genBuffered },
    .{ "BufferedRandom", genBuffered },
    .{ "BufferedRWPair", genBufferedRWPair },
    .{ "TextIOWrapper", genTextIO },
    .{ "IncrementalNewlineDecoder", genIncrementalNewlineDecoder },
    .{ "open", genFileIO },
    .{ "open_code", genOpenCode },
    .{ "text_encoding", genTextEncoding },
    .{ "IOBase", genIOBase },
    .{ "RawIOBase", genRawIOBase },
    .{ "BufferedIOBase", genBufferedIOBase },
    .{ "TextIOBase", genTextIOBase },
    .{ "DEFAULT_BUFFER_SIZE", genDefaultBufferSize },
    .{ "UnsupportedOperation", genUnsupportedOperation },
    .{ "BlockingIOError", genBlockingIOError },
});

fn genFileIO(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("@as(?std.fs.File, null)"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("fio", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const __path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; break :{s} std.fs.cwd().openFile(__path, .{{}}) catch null; ", .{label});
        }
    }.emit);
}

fn genBytesIO(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .buffer = .{}, .pos = 0 }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("bio", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const __init = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; var __bio: std.ArrayList(u8) = .{{}}; __bio.appendSlice(__global_allocator, __init) catch unreachable; break :{s} .{{ .buffer = __bio, .pos = 0 }}; ", .{label});
        }
    }.emit);
}

fn genStringIO(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .buffer = .{}, .pos = 0 }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("sio", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const __init = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; var __sio: std.ArrayList(u8) = .{{}}; __sio.appendSlice(__global_allocator, __init) catch unreachable; break :{s} .{{ .buffer = __sio, .pos = 0 }}; ", .{label});
        }
    }.emit);
}

fn genBuffered(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.withInlineBlock("buf", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; break :{s} .{{ .raw = __v, .buffer_size = 8192 }}; ", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .raw = null, .buffer_size = 8192 }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genTextIO(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.withInlineBlock("tio", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; break :{s} .{{ .buffer = __v, .encoding = \"utf-8\" }}; ", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .buffer = null, .encoding = \"utf-8\" }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genBufferedRWPair(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 2) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .reader = null, .writer = null, .buffer_size = 8192 }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("rwp", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const __r = ");
            try c.genExpr(a[0]);
            try c.emit("; const __w = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; break :{s} .{{ .reader = __r, .writer = __w, .buffer_size = 8192 }}; ", .{label});
        }
    }.emit);
}

fn genOpenCode(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("@as(?std.fs.File, null)"), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("oc", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const __path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; break :{s} std.fs.cwd().openFile(__path, .{{ .mode = .read_only }}) catch null; ", .{label});
        }
    }.emit);
}

fn genIncrementalNewlineDecoder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .translate = true }"), builder_mod.EmitConfig.forExpression());
}

fn genTextEncoding(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string("utf-8"), builder_mod.EmitConfig.forExpression());
    }
}

fn genIOBase(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genRawIOBase(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genBufferedIOBase(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genTextIOBase(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genDefaultBufferSize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 8192)"), builder_mod.EmitConfig.forExpression());
}

fn genUnsupportedOperation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.UnsupportedOperation"), builder_mod.EmitConfig.forExpression());
}

fn genBlockingIOError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.BlockingIOError"), builder_mod.EmitConfig.forExpression());
}
