/// Python unicodedata module - Unicode character database
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate unicodedata.lookup(name)
pub fn genLookup(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const name = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = name; break :blk \"?\"; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate unicodedata.name(chr, default=None)
pub fn genName(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const c = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = c; break :blk \"UNKNOWN\"; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate unicodedata.decimal(chr, default=None)
pub fn genDecimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const c = ");
        try self.genExpr(args[0]);
        try self.emit("[0]; if (c >= '0' and c <= '9') break :blk @as(i32, c - '0') else break :blk -1; }");
    } else {
        try self.emit("@as(i32, -1)");
    }
}

/// Generate unicodedata.digit(chr, default=None)
pub fn genDigit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const c = ");
        try self.genExpr(args[0]);
        try self.emit("[0]; if (c >= '0' and c <= '9') break :blk @as(i32, c - '0') else break :blk -1; }");
    } else {
        try self.emit("@as(i32, -1)");
    }
}

/// Generate unicodedata.numeric(chr, default=None)
pub fn genNumeric(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const c = ");
        try self.genExpr(args[0]);
        try self.emit("[0]; if (c >= '0' and c <= '9') break :blk @as(f64, @floatFromInt(c - '0')) else break :blk -1.0; }");
    } else {
        try self.emit("@as(f64, -1.0)");
    }
}

/// Generate unicodedata.category(chr)
pub fn genCategory(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const c = ");
        try self.genExpr(args[0]);
        try self.emit("[0]; if (c >= 'a' and c <= 'z') break :blk \"Ll\" else if (c >= 'A' and c <= 'Z') break :blk \"Lu\" else if (c >= '0' and c <= '9') break :blk \"Nd\" else if (c == ' ') break :blk \"Zs\" else break :blk \"Cn\"; }");
    } else {
        try self.emit("\"Cn\"");
    }
}

/// Generate unicodedata.bidirectional(chr)
pub fn genBidirectional(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const c = ");
        try self.genExpr(args[0]);
        try self.emit("[0]; if (c >= 'a' and c <= 'z') break :blk \"L\" else if (c >= 'A' and c <= 'Z') break :blk \"L\" else if (c >= '0' and c <= '9') break :blk \"EN\" else break :blk \"ON\"; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate unicodedata.combining(chr)
pub fn genCombining(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate unicodedata.east_asian_width(chr)
pub fn genEastAsianWidth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"N\"");
}

/// Generate unicodedata.mirrored(chr)
pub fn genMirrored(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate unicodedata.decomposition(chr)
pub fn genDecomposition(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate unicodedata.normalize(form, unistr)
pub fn genNormalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate unicodedata.is_normalized(form, unistr)
pub fn genIsNormalized(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate unicodedata.unidata_version
pub fn genUnidataVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"15.0.0\"");
}

/// Generate unicodedata.ucd_3_2_0
pub fn genUcd320(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}
