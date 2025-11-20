/// WASM bindings for PyAOT Tokenizer
/// Compile: zig build-lib src/wasm.zig -target wasm32-freestanding -O ReleaseFast -dynamic
const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

// WASM allocator (uses linear memory)
var gpa = std.heap.wasm_allocator;

// Global tokenizer instance
var global_tokenizer: ?*Tokenizer = null;

/// Initialize tokenizer (called once from JavaScript)
/// Returns 1 on success, 0 on failure
export fn init(vocab_ptr: [*]const u8, vocab_len: usize, merges_ptr: [*]const u8, merges_len: usize) i32 {
    const vocab_json = vocab_ptr[0..vocab_len];
    const merges_txt = merges_ptr[0..merges_len];

    const tokenizer = Tokenizer.init(gpa, vocab_json, merges_txt) catch return 0;

    global_tokenizer = tokenizer;
    return 1;
}

/// Encode text to tokens
/// Returns pointer to token array in WASM memory
/// Token count is written to out_len
export fn encode(text_ptr: [*]const u8, text_len: usize, out_len: *usize) [*]u32 {
    const tokenizer = global_tokenizer orelse return undefined;
    const text = text_ptr[0..text_len];

    const tokens = tokenizer.encode(text) catch return undefined;

    out_len.* = tokens.len;
    return tokens.ptr;
}

/// Free previously allocated tokens
export fn free_tokens(tokens_ptr: [*]u32, tokens_len: usize) void {
    const tokens = tokens_ptr[0..tokens_len];
    gpa.free(tokens);
}

/// Cleanup tokenizer
export fn deinit() void {
    if (global_tokenizer) |tokenizer| {
        tokenizer.deinit();
        global_tokenizer = null;
    }
}

/// Memory allocation (required for WASM)
export fn alloc(size: usize) [*]u8 {
    const ptr = gpa.alloc(u8, size) catch return undefined;
    return ptr.ptr;
}

export fn dealloc(ptr: [*]u8, size: usize) void {
    const slice = ptr[0..size];
    gpa.free(slice);
}
