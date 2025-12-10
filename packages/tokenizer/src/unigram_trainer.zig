/// Unigram Trainer - T5/ALBERT-style tokenization training
/// Delegates to unigram_full_trainer.zig for the full EM algorithm implementation
///
/// Unigram Language Model tokenization:
/// - Uses probabilistic model instead of deterministic merges
/// - EM (Expectation-Maximization) algorithm for training
/// - Lattice-based forward-backward algorithm
/// - Viterbi decoding for tokenization
/// - Log probabilities for numerical stability

const std = @import("std");
const Allocator = std.mem.Allocator;
const full_trainer = @import("unigram_full_trainer.zig");
const UnigramTokenizer = @import("unigram_tokenizer.zig").UnigramTokenizer;

/// Simplified Unigram Trainer interface
/// For full control, use unigram_full_trainer.UnigramTrainer directly
pub const UnigramTrainer = struct {
    inner: full_trainer.UnigramTrainer,
    allocator: Allocator,

    pub fn init(vocab_size: usize, allocator: Allocator) !UnigramTrainer {
        return UnigramTrainer{
            .inner = try full_trainer.UnigramTrainer.init(vocab_size, allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UnigramTrainer) void {
        self.inner.deinit();
    }

    /// Train Unigram tokenizer from texts
    /// Uses EM (Expectation-Maximization) algorithm:
    /// 1. Build initial vocabulary (characters + frequent substrings)
    /// 2. Initialize probabilities uniformly
    /// 3. EM iterations:
    ///    a. E-step: Compute expected counts using forward-backward
    ///    b. M-step: Update probabilities from counts
    ///    c. Prune low-probability tokens
    /// 4. Build final model with Viterbi decoder
    pub fn trainFromIterator(self: *UnigramTrainer, texts: []const []const u8) !UnigramTokenizer {
        // Convert texts to sentences with count=1
        var sentences = try self.allocator.alloc(full_trainer.Sentence, texts.len);
        defer self.allocator.free(sentences);

        for (texts, 0..) |text, i| {
            sentences[i] = full_trainer.Sentence{
                .text = text,
                .count = 1,
            };
        }

        // Train using full EM algorithm
        const model = try self.inner.train(sentences);

        return UnigramTokenizer.init(model, self.allocator);
    }

    /// Train from sentences with frequency counts (more efficient for repeated texts)
    pub fn trainFromSentences(self: *UnigramTrainer, sentences: []const full_trainer.Sentence) !UnigramTokenizer {
        const model = try self.inner.train(sentences);
        return UnigramTokenizer.init(model, self.allocator);
    }
};

// Re-export types for convenience
pub const Sentence = full_trainer.Sentence;
pub const UnigramTrainerConfig = full_trainer.UnigramTrainerConfig;
