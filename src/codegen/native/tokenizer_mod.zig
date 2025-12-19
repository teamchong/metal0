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

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

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
    {
        const b = try self.getBuilder();
        try b.writeFmt("(__tok_enc_{d}: {{ ", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }

    // Check if argument is a PyObject (unknown type) - needs conversion via PyString.getValue
    const arg_type = if (args.len > 0) self.type_inferrer.inferExpr(args[0]) catch .unknown else .unknown;

    {
        const b = try self.getBuilder();
        try b.writeFmt("const __enc_tokens_{d} = try runtime.tokenizer.encode(__global_allocator, ", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (args.len > 0) {
        if (type_traits.isUnknown(arg_type)) {
            // PyObject (PyString) - convert to native string
            try emitConst(self, "runtime.PyString.getValue(");
            try self.genExpr(args[0]);
            try emitConst(self, ")");
        } else {
            // Native string - use directly
            try self.genExpr(args[0]);
        }
    }
    try emitConst(self, "); ");
    {
        const b = try self.getBuilder();
        try b.writeFmt("const __enc_list_{d} = try runtime.PyList.create(__global_allocator); ", .{id});
        try b.writeFmt("for (__enc_tokens_{d}) |__enc_tok_{d}| {{ try runtime.PyList.append(__enc_list_{d}, try runtime.PyInt.create(__global_allocator, @intCast(__enc_tok_{d}))); }} ", .{ id, id, id, id });
        try b.writeFmt("break :__tok_enc_{d} __enc_list_{d}; }})", .{ id, id });
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for tokenizer.decode(tokens)
/// Converts PyList of PyInt to []u32 before calling runtime decode
fn handleDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    {
        const b = try self.getBuilder();
        try b.writeFmt("(__tok_dec_{d}: {{ ", .{id});
        try b.writeFmt("const __dec_list_{d} = ", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try emitConst(self, "; ");
    // Convert PyList to []u32
    {
        const b = try self.getBuilder();
        try b.writeFmt("var __dec_tokens_{d} = try __global_allocator.alloc(u32, runtime.PyList.len(__dec_list_{d})); ", .{ id, id });
        try b.writeFmt("var __dec_i_{d}: usize = 0; ", .{id});
        try b.writeFmt("while (__dec_i_{d} < __dec_tokens_{d}.len) : (__dec_i_{d} += 1) {{ ", .{ id, id, id });
        try b.writeFmt("const __dec_item_{d} = try runtime.PyList.getItem(__dec_list_{d}, __dec_i_{d}); ", .{ id, id, id });
        try b.writeFmt("__dec_tokens_{d}[__dec_i_{d}] = @intCast(runtime.PyInt.getValue(__dec_item_{d})); ", .{ id, id, id });
        try b.write("} ");
        try b.writeFmt("break :__tok_dec_{d} try runtime.tokenizer.decode(__global_allocator, __dec_tokens_{d}); }})", .{ id, id });
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for tokenizer.count_tokens(text)
fn handleCountTokens(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitConst(self, "(try runtime.tokenizer.encode(__global_allocator, ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try emitConst(self, ")).len");
}

/// Generate code for tokenizer.load(path) or tokenizer.init(path)
fn handleLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitConst(self, "try runtime.tokenizer.init(__global_allocator, ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    }
    try emitConst(self, ")");
}

/// Generate code for tokenizer.init(path) - alias for load
fn handleInit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return handleLoad(self, args);
}

/// Generate code for tokenizer.pre_tokenize(text, method="whitespace")
fn handlePreTokenize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitConst(self, "runtime.tokenizer.Tokenizer.pre_tokenizers.whitespace(");

    if (args.len > 0) {
        try self.genExpr(args[0]);
    }

    try emitConst(self, ", __global_allocator)");
}

/// Generate code for tokenizer.normalize(text, method="lowercase")
fn handleNormalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitConst(self, "runtime.tokenizer.Tokenizer.normalizers.lowercase(");

    if (args.len > 0) {
        try self.genExpr(args[0]);
    }

    try emitConst(self, ", __global_allocator)");
}
