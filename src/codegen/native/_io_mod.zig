/// Python _io module - Core I/O implementation (underlying io module)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

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
    const id = self.nextNameId();
    try self.emitFmt("(__io_fio_{d}: {{ const __path_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; break :__io_fio_{d} std.fs.cwd().openFile(__path_{d}, .{{}}) catch null; }})", .{ id, id });
}

fn genBytesIO(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .buffer = .{}, .pos = 0 }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__io_bio_{d}: {{ const __init_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; var __bio_{d}: std.ArrayList(u8) = .{{}}; __bio_{d}.appendSlice(__global_allocator, __init_{d}) catch unreachable; break :__io_bio_{d} .{{ .buffer = __bio_{d}, .pos = 0 }}; }})", .{ id, id, id, id, id });
}

fn genStringIO(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .buffer = .{}, .pos = 0 }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__io_sio_{d}: {{ const __init_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; var __sio_{d}: std.ArrayList(u8) = .{{}}; __sio_{d}.appendSlice(__global_allocator, __init_{d}) catch unreachable; break :__io_sio_{d} .{{ .buffer = __sio_{d}, .pos = 0 }}; }})", .{ id, id, id, id, id });
}

fn genBuffered(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_buf: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; break :__m");
        try self.emitFmt("{d}_buf .{{ .raw = __v, .buffer_size = 8192 }}; }}", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .raw = null, .buffer_size = 8192 }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genTextIO(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_tio: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; break :__m");
        try self.emitFmt("{d}_tio .{{ .buffer = __v, .encoding = \"utf-8\" }}; }}", .{id});
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
    const id = self.nextNameId();
    try self.emitFmt("(__io_rwp_{d}: {{ const __r_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; const __w_{d} = ", .{id});
    try self.genExpr(args[1]);
    try self.emitFmt("; break :__io_rwp_{d} .{{ .reader = __r_{d}, .writer = __w_{d}, .buffer_size = 8192 }}; }})", .{ id, id, id });
}

fn genOpenCode(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw("@as(?std.fs.File, null)"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__io_oc_{d}: {{ const __path_{d} = ", .{ id, id });
    try self.genExpr(args[0]);
    try self.emitFmt("; break :__io_oc_{d} std.fs.cwd().openFile(__path_{d}, .{{ .mode = .read_only }}) catch null; }})", .{ id, id });
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
