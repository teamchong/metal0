/// Python _codecs module - C accelerator for codecs (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _codecs.encode(obj, encoding='utf-8', errors='strict')
pub fn genEncode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate _codecs.decode(obj, encoding='utf-8', errors='strict')
pub fn genDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate _codecs.register(search_function)
pub fn genRegister(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _codecs.lookup(encoding)
pub fn genLookup(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null }");
}

/// Generate _codecs.register_error(name, handler)
pub fn genRegisterError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _codecs.lookup_error(name)
pub fn genLookupError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

// UTF-8 codec
pub fn genUtf8Encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

pub fn genUtf8Decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

// ASCII codec
pub fn genAsciiEncode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

pub fn genAsciiDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

// Latin-1 codec
pub fn genLatin1Encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

pub fn genLatin1Decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

// Escape codec
pub fn genEscapeEncode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

pub fn genEscapeDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

// Raw unicode escape
pub fn genRawUnicodeEscapeEncode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

pub fn genRawUnicodeEscapeDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

// Unicode escape
pub fn genUnicodeEscapeEncode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

pub fn genUnicodeEscapeDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

// Charmap codec
pub fn genCharmapEncode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

pub fn genCharmapDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

pub fn genCharmapBuild(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{} ** 256");
}

// MBCS (Windows only)
pub fn genMbcsEncode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

pub fn genMbcsDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(".len }");
    } else {
        try self.emit(".{ \"\", 0 }");
    }
}

// Readbuffer (bytes -> bytes)
pub fn genReadbufferEncode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}
