/// Python hashlib module - md5, sha1, sha256, sha512
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate hashlib.md5(data?) -> HashObject
pub fn genMd5(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("hashlib.md5()");
    _ = args; // Args handled separately if needed
}

/// Generate hashlib.sha1(data?) -> HashObject
pub fn genSha1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("hashlib.sha1()");
    _ = args;
}

/// Generate hashlib.sha224(data?) -> HashObject
pub fn genSha224(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("hashlib.sha224()");
    _ = args;
}

/// Generate hashlib.sha256(data?) -> HashObject
pub fn genSha256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("hashlib.sha256()");
    _ = args;
}

/// Generate hashlib.sha384(data?) -> HashObject
pub fn genSha384(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("hashlib.sha384()");
    _ = args;
}

/// Generate hashlib.sha512(data?) -> HashObject
pub fn genSha512(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("hashlib.sha512()");
    _ = args;
}

/// Generate hashlib.new(name, data?) -> HashObject
pub fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try hashlib.new(");
    try self.genExpr(args[0]);
    try self.emit(")");
}
