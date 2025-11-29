/// Python hashlib module - md5, sha1, sha256, sha512
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Helper to generate hash function with optional initial data
fn genHashFunc(self: *NativeCodegen, func_name: []const u8, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // With initial data: use inline block wrapped in parens for method chaining
        try self.emit("(blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("var _h = hashlib.");
        try self.emit(func_name);
        try self.emit("();\n");
        try self.emitIndent();
        try self.emit("_h.update(");
        try self.genExpr(args[0]);
        try self.emit(");\n");
        try self.emitIndent();
        try self.emit("break :blk _h;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("})");
    } else {
        // No initial data: simple call
        try self.emit("hashlib.");
        try self.emit(func_name);
        try self.emit("()");
    }
}

/// Generate hashlib.md5(data?) -> HashObject
pub fn genMd5(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genHashFunc(self, "md5", args);
}

/// Generate hashlib.sha1(data?) -> HashObject
pub fn genSha1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genHashFunc(self, "sha1", args);
}

/// Generate hashlib.sha224(data?) -> HashObject
pub fn genSha224(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genHashFunc(self, "sha224", args);
}

/// Generate hashlib.sha256(data?) -> HashObject
pub fn genSha256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genHashFunc(self, "sha256", args);
}

/// Generate hashlib.sha384(data?) -> HashObject
pub fn genSha384(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genHashFunc(self, "sha384", args);
}

/// Generate hashlib.sha512(data?) -> HashObject
pub fn genSha512(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genHashFunc(self, "sha512", args);
}

/// Generate hashlib.new(name, data?) -> HashObject
pub fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    if (args.len > 1) {
        // With initial data: need var for update
        try self.emit("blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("var _h = try hashlib.new(");
        try self.genExpr(args[0]);
        try self.emit(");\n");
        try self.emitIndent();
        try self.emit("_h.update(");
        try self.genExpr(args[1]);
        try self.emit(");\n");
        try self.emitIndent();
        try self.emit("break :blk _h;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}");
    } else {
        // No initial data: simple inline expression
        try self.emit("try hashlib.new(");
        try self.genExpr(args[0]);
        try self.emit(")");
    }
}
