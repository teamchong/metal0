/// WASM bindings for metal0 Tokenizer
/// Compile: zig build-lib src/wasm.zig -target wasm32-freestanding -O ReleaseFast -dynamic
const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

// WASM allocator (uses linear memory)
var gpa = std.heap.wasm_allocator;

// Global tokenizer instance
var global_tokenizer: ?*Tokenizer = null;

// Reusable output buffer (avoids per-call allocation)
var output_buffer: [16384]u32 = undefined;
var last_output_len: usize = 0;

/// Initialize tokenizer from JSON data (called once from JavaScript)
/// Returns 1 on success, negative for errors
export fn initFromData(json_ptr: [*]const u8, json_len: usize) i32 {
    const json_data = json_ptr[0..json_len];

    // Store for debugging
    last_json_ptr = json_ptr;
    last_json_len = json_len;

    // Try to parse
    const tokenizer = Tokenizer.initFromData(json_data, gpa) catch |err| {
        if (err == error.InvalidJson) return -1;
        if (err == error.OutOfMemory) return -2;
        if (err == error.InvalidCharacter) return -3;
        return -10;
    };

    // Allocate and store
    const tok_ptr = gpa.create(Tokenizer) catch return -20;
    tok_ptr.* = tokenizer;
    global_tokenizer = tok_ptr;

    return 1;
}

// Store last JSON for debugging
var last_json_ptr: ?[*]const u8 = null;
var last_json_len: usize = 0;

/// Debug: get JSON byte at position (for debugging parser)
export fn debug_get_byte(pos: usize) i32 {
    if (last_json_ptr) |ptr| {
        if (pos < last_json_len) {
            return ptr[pos];
        }
    }
    return -1;
}

export fn debug_get_json_len() i32 {
    return @intCast(last_json_len);
}

/// Test function - returns memory address to verify WASM is working
export fn test_basic() i32 {
    return 12345;
}

/// Encode text to tokens (auto-selects HashMap for WASM - less memory)
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
