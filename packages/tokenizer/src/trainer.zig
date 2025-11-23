/// Tokenizer Trainer - Comptime algorithm selection
/// Ensures dead code elimination (unused algorithms → 0 bytes)
const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const BpeTrainer = @import("bpe_trainer.zig").BpeTrainer;
const WordPieceTrainer = @import("wordpiece_trainer.zig").WordPieceTrainer;
const UnigramTrainer = @import("unigram_trainer.zig").UnigramTrainer;

/// Available training algorithms
pub const Algorithm = enum {
    BPE,       // Byte Pair Encoding (GPT-2, GPT-3, RoBERTa)
    WordPiece, // WordPiece (BERT, DistilBERT)
    Unigram,   // Unigram Language Model (T5, ALBERT) - TODO: Full implementation
};

/// Comptime trainer selection - only selected algorithm is compiled
/// Unused algorithms compile to 0 bytes (dead code elimination)
///
/// Example usage:
/// ```zig
/// const BPE = TrainerFor(.BPE);      // Only BPE compiled
/// const WP = TrainerFor(.WordPiece); // Only WordPiece compiled
/// const UG = TrainerFor(.Unigram);   // Only Unigram compiled
/// ```
pub fn TrainerFor(comptime algorithm: Algorithm) type {
    return switch (algorithm) {
        .BPE => BpeTrainer,
        .WordPiece => WordPieceTrainer,
        .Unigram => UnigramTrainer,
    };
}

/// Default trainer (BPE)
pub const Trainer = TrainerFor(.BPE);

/// Runtime trainer selection - includes only opted-in algorithms
/// Binary size depends on which algorithms are included
pub const RuntimeTrainer = struct {
    const build_options = @import("build_options");

    algorithm: Algorithm,
    bpe_trainer: if (build_options.include_bpe) ?BpeTrainer else void = if (build_options.include_bpe) null else {},
    wordpiece_trainer: if (build_options.include_wordpiece) ?WordPieceTrainer else void = if (build_options.include_wordpiece) null else {},
    unigram_trainer: if (build_options.include_unigram) ?UnigramTrainer else void = if (build_options.include_unigram) null else {},
    allocator: std.mem.Allocator,

    pub fn init(vocab_size: usize, allocator: std.mem.Allocator, algorithm: Algorithm) !RuntimeTrainer {
        var trainer = RuntimeTrainer{
            .algorithm = algorithm,
            .allocator = allocator,
        };

        switch (algorithm) {
            .BPE => {
                if (build_options.include_bpe) {
                    trainer.bpe_trainer = try BpeTrainer.init(vocab_size, allocator);
                } else {
                    return error.AlgorithmNotIncluded;
                }
            },
            .WordPiece => {
                if (build_options.include_wordpiece) {
                    trainer.wordpiece_trainer = try WordPieceTrainer.init(vocab_size, allocator);
                } else {
                    return error.AlgorithmNotIncluded;
                }
            },
            .Unigram => {
                if (build_options.include_unigram) {
                    trainer.unigram_trainer = try UnigramTrainer.init(vocab_size, allocator);
                } else {
                    return error.AlgorithmNotIncluded;
                }
            },
        }

        return trainer;
    }

    pub fn deinit(self: *RuntimeTrainer) void {
        switch (self.algorithm) {
            .BPE => if (build_options.include_bpe) {
                if (self.bpe_trainer) |*t| t.deinit();
            },
            .WordPiece => if (build_options.include_wordpiece) {
                if (self.wordpiece_trainer) |*t| t.deinit();
            },
            .Unigram => if (build_options.include_unigram) {
                if (self.unigram_trainer) |*t| t.deinit();
            },
        }
    }

    pub fn trainFromIterator(self: *RuntimeTrainer, texts: []const []const u8) !Tokenizer {
        return switch (self.algorithm) {
            .BPE => if (build_options.include_bpe)
                self.bpe_trainer.?.trainFromIterator(texts)
            else
                error.AlgorithmNotIncluded,
            .WordPiece => if (build_options.include_wordpiece)
                self.wordpiece_trainer.?.trainFromIterator(texts)
            else
                error.AlgorithmNotIncluded,
            .Unigram => if (build_options.include_unigram)
                self.unigram_trainer.?.trainFromIterator(texts)
            else
                error.AlgorithmNotIncluded,
        };
    }
};
