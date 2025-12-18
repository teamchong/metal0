/// metal0.tokenizer module - native Zig BPE tokenizer (248x faster than tiktoken)
/// MIGRATED TO ZIGBUILDER
///
/// Usage in Python:
///   from metal0 import tokenizer
///   tokens = tokenizer.encode("Hello world")
///   text = tokenizer.decode(tokens)
///
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;
const type_traits = @import("../../analysis/traits/type_traits.zig");

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
    const id = self.nextNameId();
    try self.emitFmt("(__tok_enc_{d}: {{ ", .{id});

    // Check if argument is a PyObject (unknown type) - needs conversion via PyString.getValue
    const arg_type = if (args.len > 0) self.type_inferrer.inferExpr(args[0]) catch .unknown else .unknown;

    try self.emitFmt("const __enc_tokens_{d} = try runtime.tokenizer.encode(__global_allocator, ", .{id});
    if (args.len > 0) {
        if (type_traits.isUnknown(arg_type)) {
            // PyObject (PyString) - convert to native string
            try self.emit("runtime.PyString.getValue(");
            try self.genExpr(args[0]);
            try self.emit(")");
        } else {
            // Native string - use directly
            try self.genExpr(args[0]);
        }
    }
    try self.emit("); ");
    try self.emitFmt("const __enc_list_{d} = try runtime.PyList.create(__global_allocator); ", .{id});
    try self.emitFmt("for (__enc_tokens_{d}) |__enc_tok_{d}| {{ try runtime.PyList.append(__enc_list_{d}, try runtime.PyInt.create(__global_allocator, @intCast(__enc_tok_{d}))); }} ", .{ id, id, id, id });
    try self.emitFmt("break :__tok_enc_{d} __enc_list_{d}; }})", .{ id, id });
}

/// Generate code for tokenizer.decode(tokens)
/// Converts PyList of PyInt to []u32 before calling runtime decode
fn handleDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("(__tok_dec_{d}: {{ ", .{id});
    try self.emitFmt("const __dec_list_{d} = ", .{id});
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try self.emit("; ");
    // Convert PyList to []u32
    try self.emitFmt("var __dec_tokens_{d} = try __global_allocator.alloc(u32, runtime.PyList.len(__dec_list_{d})); ", .{ id, id });
    try self.emitFmt("var __dec_i_{d}: usize = 0; ", .{id});
    try self.emitFmt("while (__dec_i_{d} < __dec_tokens_{d}.len) : (__dec_i_{d} += 1) {{ ", .{ id, id, id });
    try self.emitFmt("const __dec_item_{d} = try runtime.PyList.getItem(__dec_list_{d}, __dec_i_{d}); ", .{ id, id, id });
    try self.emitFmt("__dec_tokens_{d}[__dec_i_{d}] = @intCast(runtime.PyInt.getValue(__dec_item_{d})); ", .{ id, id, id });
    try self.emit("} ");
    try self.emitFmt("break :__tok_dec_{d} try runtime.tokenizer.decode(__global_allocator, __dec_tokens_{d}); }})", .{ id, id });
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
