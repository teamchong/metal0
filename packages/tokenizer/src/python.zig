/// Python bindings via C ABI
/// Compatible with nanochat's rustbpe API
/// Usage: import pyaot_tokenizer

const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Trainer = @import("trainer.zig").Trainer;
const allocator_helper = @import("allocator_helper.zig");

// Global allocator for Python integration
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Get optimal allocator (comptime selection for WASM compatibility)
fn getAllocator() std.mem.Allocator {
    return allocator_helper.getBenchmarkAllocator(gpa);
}

/// Opaque handle for Python
const TokenizerHandle = opaque {};
const TrainerHandle = opaque {};

/// Create tokenizer from file
export fn tokenizer_new(path: [*:0]const u8) ?*TokenizerHandle {
    const allocator = getAllocator();

    const tokenizer = allocator.create(Tokenizer) catch return null;
    tokenizer.* = Tokenizer.init(
        std.mem.span(path),
        allocator,
    ) catch {
        allocator.destroy(tokenizer);
        return null;
    };

    return @ptrCast(tokenizer);
}

/// Free tokenizer
export fn tokenizer_free(handle: *TokenizerHandle) void {
    const allocator = getAllocator();
    const tokenizer: *Tokenizer = @ptrCast(@alignCast(handle));
    tokenizer.deinit();
    allocator.destroy(tokenizer);
}

/// Encode text to tokens
export fn tokenizer_encode(
    handle: *TokenizerHandle,
    text: [*:0]const u8,
    out_len: *usize,
) [*]u32 {
    const tokenizer: *Tokenizer = @ptrCast(@alignCast(handle));

    const tokens = tokenizer.encode(std.mem.span(text)) catch {
        out_len.* = 0;
        return undefined;
    };

    out_len.* = tokens.len;
    return tokens.ptr;
}

/// Free tokens array
export fn tokenizer_free_tokens(tokens: [*]u32, len: usize) void {
    const allocator = getAllocator();
    allocator.free(tokens[0..len]);
}

/// Decode tokens to text
export fn tokenizer_decode(
    handle: *TokenizerHandle,
    tokens: [*]const u32,
    len: usize,
    out_len: *usize,
) [*]u8 {
    const tokenizer: *Tokenizer = @ptrCast(@alignCast(handle));

    const text = tokenizer.decode(tokens[0..len]) catch {
        out_len.* = 0;
        return undefined;
    };

    out_len.* = text.len;
    return text.ptr;
}

/// Free text array
export fn tokenizer_free_text(text: [*]u8, len: usize) void {
    const allocator = getAllocator();
    allocator.free(text[0..len]);
}

/// Create trainer
export fn trainer_new(vocab_size: u32) ?*TrainerHandle {
    const allocator = getAllocator();

    const trainer = allocator.create(Trainer) catch return null;
    trainer.* = Trainer.init(vocab_size, allocator) catch {
        allocator.destroy(trainer);
        return null;
    };

    return @ptrCast(trainer);
}

/// Free trainer
export fn trainer_free(handle: *TrainerHandle) void {
    const allocator = getAllocator();
    const trainer: *Trainer = @ptrCast(@alignCast(handle));
    trainer.deinit();
    allocator.destroy(trainer);
}

/// Train from texts
export fn trainer_train(
    handle: *TrainerHandle,
    texts: [*]const [*:0]const u8,
    num_texts: usize,
) ?*TokenizerHandle {
    const allocator = getAllocator();
    const trainer: *Trainer = @ptrCast(@alignCast(handle));

    // Convert C strings to Zig slices
    const text_slices = allocator.alloc([]const u8, num_texts) catch return null;
    defer allocator.free(text_slices);

    for (0..num_texts) |i| {
        text_slices[i] = std.mem.span(texts[i]);
    }

    // Train
    var tokenizer = trainer.trainFromIterator(text_slices) catch return null;

    // Move to heap
    const tokenizer_ptr = allocator.create(Tokenizer) catch {
        tokenizer.deinit();
        return null;
    };
    tokenizer_ptr.* = tokenizer;

    return @ptrCast(tokenizer_ptr);
}

/// Get version
export fn pyaot_tokenizer_version() [*:0]const u8 {
    return "0.1.0";
}
