/// metal0.tokenizer module - native Zig BPE tokenizer (248x faster than tiktoken)
///
/// Usage in Python:
///   from metal0 import tokenizer
///   tokens = tokenizer.encode("Hello world")
///   text = tokenizer.decode(tokens)
///
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

/// Handler function type (same as other modules)
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// Tokenizer module functions
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "encode", handleEncode },
    .{ "decode", handleDecode },
    .{ "count_tokens", handleCountTokens },
    .{ "load", handleLoad },
    .{ "init", handleInit },
    // Pre-tokenization methods
    .{ "pre_tokenize", handlePreTokenize },
    .{ "normalize", handleNormalize },
});

/// Generate code for tokenizer.encode(text)
fn handleEncode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Wrap in PyList for Python compatibility
    try self.emit("(blk: { ");
    try self.emit("const __enc_tokens = try runtime.tokenizer.encode(__global_allocator, ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try self.emit("); ");
    try self.emit("const __enc_list = try runtime.PyList.create(__global_allocator); ");
    try self.emit("for (__enc_tokens) |__enc_tok| { try runtime.PyList.append(__enc_list, try runtime.PyInt.create(__global_allocator, @intCast(__enc_tok))); } ");
    try self.emit("break :blk __enc_list; })");
}

/// Generate code for tokenizer.decode(tokens)
fn handleDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("try runtime.tokenizer.decode(__global_allocator, ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try self.emit(")");
}

/// Generate code for tokenizer.count_tokens(text)
fn handleCountTokens(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("(try runtime.tokenizer.encode(__global_allocator, ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try self.emit(")).len");
}

/// Generate code for tokenizer.load(path) or tokenizer.init(path)
fn handleLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("try runtime.tokenizer.init(__global_allocator, ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try self.emit(")");
}

/// Generate code for tokenizer.init(path) - alias for load
fn handleInit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return handleLoad(self, args);
}

/// Generate code for tokenizer.pre_tokenize(text, method="whitespace")
fn handlePreTokenize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("runtime.tokenizer.Tokenizer.pre_tokenizers.whitespace(");

    if (args.len > 0) {
        try self.genExpr(args[0]);
    }

    try self.emit(", __global_allocator)");
}

/// Generate code for tokenizer.normalize(text, method="lowercase")
fn handleNormalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("runtime.tokenizer.Tokenizer.normalizers.lowercase(");

    if (args.len > 0) {
        try self.genExpr(args[0]);
    }

    try self.emit(", __global_allocator)");
}
