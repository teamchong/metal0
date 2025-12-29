/// IO module codegen - StringIO, BytesIO
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const m = @import("mod_helper.zig");
const H = m.H;

/// Helper: emit try runtime.io.TypeName.createWithValue(__global_allocator, expr) with bracket matching
fn emitCreateWithValue(self: *m.NativeCodegen, type_name: []const u8, expr: ast.Node) m.CodegenError!void {
    const Ctx = struct { t: []const u8, e: ast.Node };
    try self.emitCallCtx("try runtime.io", Ctx{ .t = type_name, .e = expr }, struct {
        pub fn f(s: *m.NativeCodegen, ctx: Ctx) m.CodegenError!void {
            try s.emit(".");
            try s.emit(ctx.t);
            try s.emitCallCtx(".createWithValue", ctx.e, struct {
                pub fn inner(ss: *m.NativeCodegen, e: ast.Node) m.CodegenError!void {
                    try ss.emit("__global_allocator, ");
                    try ss.genExpr(e);
                }
            }.inner);
        }
    }.f);
}

/// Helper: emit try runtime.io.openFile(__global_allocator, path, mode) with bracket matching
fn emitOpenFile(self: *m.NativeCodegen, path: ast.Node, mode: ?ast.Node) m.CodegenError!void {
    const Ctx = struct { p: ast.Node, mode_node: ?ast.Node };
    try self.emitCallCtx("try runtime.io.openFile", Ctx{ .p = path, .mode_node = mode }, struct {
        pub fn f(s: *m.NativeCodegen, ctx: Ctx) m.CodegenError!void {
            try s.emit("__global_allocator, ");
            try s.genExpr(ctx.p);
            if (ctx.mode_node) |mode_expr| {
                try s.emit(", ");
                try s.genExpr(mode_expr);
            } else {
                try s.emit(", \"rb\"");
            }
        }
    }.f);
}

pub const Funcs = std.StaticStringMap(H).initComptime(.{
    // Constructors with optional initial value
    .{ "StringIO", genStringIO },
    .{ "BytesIO", genBytesIO },
    .{ "open", genOpen },
    .{ "TextIOWrapper", genTextIOWrapper },
    .{ "FileIO", genFileIO },
    // Buffered wrappers - all return BytesIO for now
    .{ "BufferedReader", m.c("try runtime.io.BytesIO.create(__global_allocator)") },
    .{ "BufferedWriter", m.c("try runtime.io.BytesIO.create(__global_allocator)") },
    .{ "BufferedRandom", m.c("try runtime.io.BytesIO.create(__global_allocator)") },
    .{ "BufferedRWPair", m.c("try runtime.io.BytesIO.create(__global_allocator)") },
    // Base classes
    .{ "RawIOBase", m.c("try runtime.io.BytesIO.create(__global_allocator)") },
    .{ "IOBase", m.c("try runtime.io.BytesIO.create(__global_allocator)") },
    .{ "TextIOBase", m.c("try runtime.io.StringIO.create(__global_allocator)") },
    // Constants
    .{ "UnsupportedOperation", m.c("error.UnsupportedOperation") },
    .{ "DEFAULT_BUFFER_SIZE", m.I64(8192) },
    .{ "SEEK_SET", m.I64(0) },
    .{ "SEEK_CUR", m.I64(1) },
    .{ "SEEK_END", m.I64(2) },
});

pub fn genStringIO(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.StringIO.create(__global_allocator)");
    } else {
        try emitCreateWithValue(self, "StringIO", args[0]);
    }
}

pub fn genBytesIO(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
    } else {
        try emitCreateWithValue(self, "BytesIO", args[0]);
    }
}

fn genOpen(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genOpen(self, args);
}

fn genTextIOWrapper(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.StringIO.create(__global_allocator)");
    } else {
        try emitCreateWithValue(self, "StringIO", args[0]);
    }
}

fn genFileIO(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len == 0) {
        try self.emit("try runtime.io.BytesIO.create(__global_allocator)");
    } else {
        const mode = if (args.len > 1) args[1] else null;
        try emitOpenFile(self, args[0], mode);
    }
}
