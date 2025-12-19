/// IO module codegen - StringIO, BytesIO
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const m = @import("mod_helper.zig");
const H = m.H;

// Helper for simple constant output
fn emitConst(self: *m.NativeCodegen, val: []const u8) m.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
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
        try emitConst(self, "try runtime.io.StringIO.create(__global_allocator)");
    } else {
        try emitConst(self, "try runtime.io.StringIO.createWithValue(__global_allocator, ");
        try self.genExpr(args[0]);
        try emitConst(self, ")");
    }
}

pub fn genBytesIO(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "try runtime.io.BytesIO.create(__global_allocator)");
    } else {
        try emitConst(self, "try runtime.io.BytesIO.createWithValue(__global_allocator, ");
        try self.genExpr(args[0]);
        try emitConst(self, ")");
    }
}

fn genOpen(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genOpen(self, args);
}

fn genTextIOWrapper(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "try runtime.io.StringIO.create(__global_allocator)");
    } else {
        try emitConst(self, "try runtime.io.StringIO.createWithValue(__global_allocator, ");
        try self.genExpr(args[0]);
        try emitConst(self, ")");
    }
}

fn genFileIO(self: *m.NativeCodegen, args: []ast.Node) m.CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "try runtime.io.BytesIO.create(__global_allocator)");
    } else {
        try emitConst(self, "try runtime.io.openFile(__global_allocator, ");
        try self.genExpr(args[0]);
        if (args.len > 1) {
            try emitConst(self, ", ");
            try self.genExpr(args[1]);
        } else try emitConst(self, ", \"rb\"");
        try emitConst(self, ")");
    }
}
