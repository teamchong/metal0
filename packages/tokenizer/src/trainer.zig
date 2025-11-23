/// Comptime algorithm selector for tokenizer training
/// Only the selected algorithm gets compiled into the binary (zero-cost abstraction)
///
/// Usage:
///   const trainer = Trainer(.BPE).init(allocator, config);
///   const trainer = Trainer(.WordPiece).init(allocator, config);
///
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Available tokenization algorithms
pub const Algorithm = enum {
    BPE,       // Byte Pair Encoding (GPT-2, GPT-3, RoBERTa)
    WordPiece, // WordPiece (BERT, DistilBERT)
    // Unigram,   // Unigram Language Model (T5, ALBERT) - TODO
};

/// Comptime algorithm selection - only selected algorithm compiled in
pub fn Trainer(comptime algorithm: Algorithm) type {
    return switch (algorithm) {
        .BPE => @import("tokenizer.zig").Tokenizer,
        .WordPiece => @import("wordpiece.zig").WordPiece,
        // .Unigram => @import("unigram.zig").Unigram,  // TODO
    };
}

/// Example: Create BPE trainer
pub fn createBPE(allocator: Allocator) !Trainer(.BPE) {
    return Trainer(.BPE).init(allocator);
}

/// Example: Create WordPiece trainer
pub fn createWordPiece(allocator: Allocator, config: @import("wordpiece.zig").Config) Trainer(.WordPiece) {
    return Trainer(.WordPiece).init(allocator, config);
}

test "Trainer comptime selection WordPiece" {
    const allocator = std.testing.allocator;

    // Only WordPiece code gets compiled
    var trainer = Trainer(.WordPiece).init(allocator, .{});
    defer trainer.deinit();

    try std.testing.expect(trainer.vocab.count() == 0);
}

test "Trainer zero-cost - WordPiece only" {
    const allocator = std.testing.allocator;

    // This binary will NOT include BPE code at all (zero overhead)
    var wp = Trainer(.WordPiece).init(allocator, .{ .vocab_size = 50 });
    defer wp.deinit();

    const texts = [_][]const u8{ "hello world" };
    try wp.train(&texts);

    try std.testing.expect(wp.vocab.count() > 0);
}

test "Trainer API demonstration" {
    const allocator = std.testing.allocator;

    // Comptime selection - only one algorithm compiled
    const AlgorithmType = Algorithm.WordPiece;
    var trainer = Trainer(AlgorithmType).init(allocator, .{ .vocab_size = 30 });
    defer trainer.deinit();

    const texts = [_][]const u8{ "test" };
    try trainer.train(&texts);

    // Type is resolved at compile time - zero runtime cost
    try std.testing.expect(@TypeOf(trainer) == Trainer(.WordPiece));
}
