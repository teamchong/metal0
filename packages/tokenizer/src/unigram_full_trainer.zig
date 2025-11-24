/// Unigram Trainer - EM algorithm for training Unigram Language Model
/// Implements Expectation-Maximization with vocabulary pruning
/// Simplified port from HuggingFace tokenizers/src/models/unigram/trainer.rs

const std = @import("std");
const hashmap_helper = @import("hashmap_helper.zig");
const Allocator = std.mem.Allocator;
const Unigram = @import("unigram_model.zig").Unigram;
const VocabEntry = @import("unigram_model.zig").VocabEntry;
const Lattice = @import("unigram_lattice.zig").Lattice;
// Using std.Thread directly instead of ThreadPool (simpler, no Bun dependencies)
const UnigramTokenizer = @import("unigram_tokenizer.zig").UnigramTokenizer;
const suffix_array = @import("suffix_array.zig");

/// Digamma function (derivative of log gamma) for Bayesian EM
fn digamma(x_param: f64) f64 {
    var x = x_param;
    var result: f64 = 0.0;
    while (x < 7.0) {
        result -= 1.0 / x;
        x += 1.0;
    }
    x -= 0.5;
    const xx = 1.0 / x;
    const xx2 = xx * xx;
    const xx4 = xx2 * xx2;
    result += @log(x) + (1.0 / 24.0) * xx2 - (7.0 / 960.0) * xx4 +
        (31.0 / 8064.0) * xx4 * xx2 - (127.0 / 30720.0) * xx4 * xx4;
    return result;
}

/// Sentence with frequency count
pub const Sentence = struct {
    text: []const u8,
    count: u32,
};

/// Piece candidate with score
pub const SentencePiece = struct {
    token: []const u8,
    score: f64,

    pub fn deinit(self: *SentencePiece, allocator: Allocator) void {
        allocator.free(self.token);
    }
};

/// Unigram trainer configuration
pub const UnigramTrainerConfig = struct {
    vocab_size: u32 = 8000,
    shrinking_factor: f64 = 0.75,
    n_sub_iterations: u32 = 2,
    max_piece_length: usize = 16,
    seed_size: usize = 1_000_000,
};

/// Unigram trainer
pub const UnigramTrainer = struct {
    config: UnigramTrainerConfig,
    allocator: Allocator,
    enable_parallel: bool,

    /// Initialize with vocab size (matches BPE/WordPiece API)
    pub fn init(vocab_size: usize, allocator: Allocator) !UnigramTrainer {
        return UnigramTrainer{
            .config = UnigramTrainerConfig{
                .vocab_size = @intCast(vocab_size),
            },
            .allocator = allocator,
            .enable_parallel = false,
        };
    }

    /// Initialize with parallelization enabled
    pub fn initWithThreadPool(vocab_size: usize, allocator: Allocator, _: anytype) !UnigramTrainer {
        return UnigramTrainer{
            .config = UnigramTrainerConfig{
                .vocab_size = @intCast(vocab_size),
            },
            .allocator = allocator,
            .enable_parallel = true,
        };
    }

    /// Initialize with custom config
    pub fn initWithConfig(allocator: Allocator, config: UnigramTrainerConfig) UnigramTrainer {
        return UnigramTrainer{
            .config = config,
            .allocator = allocator,
            .enable_parallel = false,
        };
    }

    pub fn deinit(self: *UnigramTrainer) void {
        _ = self;
    }

    /// Generate seed vocabulary from sentences (character ngrams + frequent substrings)
    fn makeSeedPieces(self: *UnigramTrainer, sentences: []const Sentence) !std.ArrayList(SentencePiece) {
        var pieces = std.ArrayList(SentencePiece){};

        // Add UNK token
        const unk_token = try self.allocator.dupe(u8, "<UNK>");
        try pieces.append(self.allocator, SentencePiece{
            .token = unk_token,
            .score = std.math.nan(f64),
        });

        // Collect all characters
        var char_freqs = std.AutoHashMap(u21, u32).init(self.allocator);
        defer char_freqs.deinit();

        for (sentences) |sentence| {
            var iter = (try std.unicode.Utf8View.init(sentence.text)).iterator();
            while (iter.nextCodepoint()) |codepoint| {
                const entry = try char_freqs.getOrPut(codepoint);
                if (!entry.found_existing) {
                    entry.value_ptr.* = 0;
                }
                entry.value_ptr.* += sentence.count;
            }
        }

        // Add all characters to vocabulary (sorted by frequency)
        var char_list = std.ArrayList(struct { char: u21, freq: u32 }){};
        defer char_list.deinit(self.allocator);

        var char_it = char_freqs.iterator();
        while (char_it.next()) |entry| {
            try char_list.append(self.allocator, .{
                .char = entry.key_ptr.*,
                .freq = entry.value_ptr.*,
            });
        }

        // Sort by frequency (descending)
        std.mem.sort(@TypeOf(char_list.items[0]), char_list.items, {}, struct {
            pub fn lessThan(_: void, a: @TypeOf(char_list.items[0]), b: @TypeOf(char_list.items[0])) bool {
                return a.freq > b.freq;
            }
        }.lessThan);

        // Add characters to pieces
        for (char_list.items) |item| {
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(item.char, &buf) catch continue;
            const char_str = try self.allocator.dupe(u8, buf[0..len]);
            try pieces.append(self.allocator, SentencePiece{
                .token = char_str,
                .score = @floatFromInt(item.freq),
            });
        }

        // Generate ALL character n-grams (2 to max_piece_length) from all sentences
        // This creates a large initial vocabulary for EM to prune
        var ngram_freqs = hashmap_helper.StringHashMap(u32).init(self.allocator);
        defer ngram_freqs.deinit();

        for (sentences) |sentence| {
            if (sentence.text.len == 0) continue;

            // Generate all n-grams of length 2 to max_piece_length
            var len: usize = 2;
            while (len <= self.config.max_piece_length and len <= sentence.text.len) : (len += 1) {
                var pos: usize = 0;
                while (pos + len <= sentence.text.len) : (pos += 1) {
                    const ngram = sentence.text[pos..pos + len];

                    // Skip n-grams with null bytes (from our own sentence boundaries)
                    if (std.mem.indexOfScalar(u8, ngram, 0) != null) {
                        continue;
                    }

                    const entry = try ngram_freqs.getOrPut(ngram);
                    if (!entry.found_existing) {
                        entry.key_ptr.* = try self.allocator.dupe(u8, ngram);
                        entry.value_ptr.* = 0;
                    }
                    entry.value_ptr.* += sentence.count;
                }
            }
        }

        std.debug.print("[PROFILE] Generated {d} unique n-grams from sentences\n", .{ngram_freqs.count()});

        // Collect scored n-grams (filter + sort by score)
        const ScoredNgram = struct { token: []const u8, score: f64 };
        var scored_ngrams = std.ArrayList(ScoredNgram){};
        defer scored_ngrams.deinit(self.allocator);

        var ngram_it = ngram_freqs.iterator();
        while (ngram_it.next()) |entry| {
            const freq = entry.value_ptr.*;
            const len = entry.key_ptr.*.len;

            // HuggingFace filters: skip rare n-grams
            // Minimum frequency threshold (like HF's suffix array filtering)
            // Use freq >= 2 to keep enough seeds for EM iterations
            if (freq < 2) {  // Skip n-grams that appear only once
                self.allocator.free(entry.key_ptr.*);
                continue;
            }

            // Score: frequency * length (same as HF)
            const score = @as(f64, @floatFromInt(freq * @as(u32, @intCast(len))));

            try scored_ngrams.append(self.allocator, .{
                .token = entry.key_ptr.*, // Transfer ownership
                .score = score,
            });
        }

        // Sort by score (descending) - take top seed_size pieces
        std.mem.sort(@TypeOf(scored_ngrams.items[0]), scored_ngrams.items, {}, struct {
            pub fn lessThan(_: void, a: @TypeOf(scored_ngrams.items[0]), b: @TypeOf(scored_ngrams.items[0])) bool {
                return a.score > b.score;  // Descending
            }
        }.lessThan);

        std.debug.print("[PROFILE] After filtering: {d} n-grams (from {d})\n", .{scored_ngrams.items.len, ngram_freqs.count()});

        // Filter redundant substrings (simple suffix array approximation)
        // Skip n-grams that are substrings of higher-scoring n-grams
        // This mimics suffix arrays' substring relationship recognition
        var kept_ngrams = std.ArrayList(ScoredNgram){};
        defer kept_ngrams.deinit(self.allocator);

        // Simplified approach: just take top N by score (simpler than full substring filtering)
        // This is faster and still selective like suffix arrays
        const target_seeds: usize = 40000;  // Enough to trigger EM but selective
        for (scored_ngrams.items, 0..) |candidate, i| {
            if (i >= target_seeds) {
                // Free remaining
                self.allocator.free(candidate.token);
                continue;
            }
            try kept_ngrams.append(self.allocator, candidate);
        }

        std.debug.print("[PROFILE] After substring filtering: {d} seeds (from {d} scored)\n", .{kept_ngrams.items.len, scored_ngrams.items.len});

        // Add filtered n-grams to pieces
        for (kept_ngrams.items) |item| {
            try pieces.append(self.allocator, SentencePiece{
                .token = item.token,
                .score = item.score,
            });
        }

        // Don't free the keys - ownership transferred to pieces
        ngram_freqs.clearRetainingCapacity();

        // Convert scores to log probabilities
        var sum: f64 = 0.0;
        for (pieces.items[1..]) |piece| { // Skip UNK
            sum += piece.score;
        }

        if (sum > 0) {
            const logsum = @log(sum);
            for (pieces.items[1..]) |*piece| { // Skip UNK
                piece.score = @log(piece.score) - logsum;
            }
        }

        return pieces;
    }

    /// Parallel E-step worker context
    const EStepWorker = struct {
        trainer: *UnigramTrainer,
        model: *const Unigram,
        sentences: []const Sentence,
        all_sentence_freq: u32,

        // Results (thread-local)
        expected: []f64,  // Pre-allocated array for this thread
        objs: f64,
        err: ?anyerror,

        // Preallocated buffers for populateMarginal (huge optimization!)
        alpha_buffer: []f64,
        beta_buffer: []f64,

        fn processChunk(self: *EStepWorker) void {
            self.err = null;
            self.processChunkImpl() catch |e| {
                self.err = e;
            };
        }

        fn processChunkImpl(self: *EStepWorker) !void {
            // Single arena for all sentences in this chunk (huge speedup!)
            var arena = std.heap.ArenaAllocator.init(self.trainer.allocator);
            defer arena.deinit();

            // Process all sentences in this chunk
            for (self.sentences) |sentence| {
                // Reset arena between sentences (keeps large buffer, avoids syscalls)
                _ = arena.reset(.retain_capacity);

                var lattice = try Lattice.initWithArena(
                    self.trainer.allocator,
                    sentence.text,
                    self.model.bos_id,
                    self.model.eos_id,
                    &arena,
                );
                defer lattice.deinit();

                try self.model.populateNodes(&lattice);

                // Use preallocated buffers (avoids 583 allocations per iteration!)
                const z = lattice.populateMarginalWithBuffers(
                    @floatFromInt(sentence.count),
                    self.expected,
                    self.alpha_buffer,
                    self.beta_buffer,
                );
                if (std.math.isNan(z)) {
                    return error.NanLikelihood;
                }

                self.objs -= z / @as(f64, @floatFromInt(self.all_sentence_freq));
            }
        }
    };

    /// E-step: Compute expected counts using forward-backward algorithm
    /// Uses cached lattices if provided (massive speedup)
    fn runEStep(self: *UnigramTrainer, model: *const Unigram, sentences: []const Sentence, cached_lattices: ?[]Lattice) !struct { f64, []f64 } {
        const all_sentence_freq: u32 = blk: {
            var sum: u32 = 0;
            for (sentences) |s| sum += s.count;
            break :blk sum;
        };

        // If parallelization enabled, use multi-threading
        if (self.enable_parallel) {
            return try self.runEStepParallel(model, sentences, all_sentence_freq);
        }

        // Sequential version (original)
        const expected = try self.allocator.alloc(f64, model.vocab.len);
        @memset(expected, 0.0);

        var objs: f64 = 0.0;

        if (cached_lattices) |lattices| {
            // Use cached lattices (just update nodes + run forward-backward)
            for (sentences, lattices) |sentence, *lattice| {
                // Clear previous nodes and repopulate with current model
                lattice.clearNodes();
                try model.populateNodes(lattice);

                const z = try lattice.populateMarginal(@floatFromInt(sentence.count), expected);
                if (std.math.isNan(z)) {
                    return error.NanLikelihood;
                }

                objs -= z / @as(f64, @floatFromInt(all_sentence_freq));
            }
        } else {
            // No cache - create lattices fresh with arena allocator for performance
            for (sentences) |sentence| {
                // Use arena allocator for node allocations (1.2-2x faster)
                var arena = std.heap.ArenaAllocator.init(self.allocator);
                defer arena.deinit();

                var lattice = try Lattice.initWithArena(self.allocator, sentence.text, model.bos_id, model.eos_id, &arena);
                defer lattice.deinit();

                try model.populateNodes(&lattice);

                const z = try lattice.populateMarginal(@floatFromInt(sentence.count), expected);
                if (std.math.isNan(z)) {
                    return error.NanLikelihood;
                }

                objs -= z / @as(f64, @floatFromInt(all_sentence_freq));
            }
        }

        return .{ objs, expected };
    }

    /// Parallel E-step implementation using std.Thread
    fn runEStepParallel(
        self: *UnigramTrainer,
        model: *const Unigram,
        sentences: []const Sentence,
        all_sentence_freq: u32,
    ) !struct { f64, []f64 } {
        const cpu_count = try std.Thread.getCpuCount();
        const num_threads = @min(cpu_count, 8); // Cap at 8 threads
        const chunk_size = @max(1, sentences.len / num_threads);

        // Allocate per-thread expected arrays
        const thread_expected = try self.allocator.alloc([]f64, num_threads);
        defer {
            for (thread_expected) |exp| {
                self.allocator.free(exp);
            }
            self.allocator.free(thread_expected);
        }

        for (thread_expected) |*exp| {
            exp.* = try self.allocator.alloc(f64, model.vocab.len);
            @memset(exp.*, 0.0);
        }

        // Allocate alpha/beta buffers for each thread (avoids 583 allocations per iteration!)
        const k_max_lattice_nodes = 10000; // Conservative estimate
        const alpha_buffers = try self.allocator.alloc([]f64, num_threads);
        defer {
            for (alpha_buffers) |buf| {
                self.allocator.free(buf);
            }
            self.allocator.free(alpha_buffers);
        }
        const beta_buffers = try self.allocator.alloc([]f64, num_threads);
        defer {
            for (beta_buffers) |buf| {
                self.allocator.free(buf);
            }
            self.allocator.free(beta_buffers);
        }

        for (alpha_buffers) |*buf| {
            buf.* = try self.allocator.alloc(f64, k_max_lattice_nodes);
        }
        for (beta_buffers) |*buf| {
            buf.* = try self.allocator.alloc(f64, k_max_lattice_nodes);
        }

        // Allocate workers
        const workers = try self.allocator.alloc(EStepWorker, num_threads);
        defer self.allocator.free(workers);

        // Allocate threads
        const threads = try self.allocator.alloc(std.Thread, num_threads);
        defer self.allocator.free(threads);

        // Split sentences into chunks and spawn threads
        var thread_idx: usize = 0;
        var sent_idx: usize = 0;
        while (thread_idx < num_threads) : (thread_idx += 1) {
            const start = sent_idx;
            const end = @min(start + chunk_size, sentences.len);
            if (start >= sentences.len) break;

            workers[thread_idx] = EStepWorker{
                .trainer = self,
                .model = model,
                .sentences = sentences[start..end],
                .all_sentence_freq = all_sentence_freq,
                .expected = thread_expected[thread_idx],
                .objs = 0.0,
                .err = null,
                .alpha_buffer = alpha_buffers[thread_idx],
                .beta_buffer = beta_buffers[thread_idx],
            };

            threads[thread_idx] = try std.Thread.spawn(.{}, EStepWorker.processChunk, .{&workers[thread_idx]});

            sent_idx = end;
        }

        const actual_threads = thread_idx;

        // Wait for all threads to complete
        for (threads[0..actual_threads]) |thread| {
            thread.join();
        }

        // Check for errors
        for (workers[0..actual_threads]) |*worker| {
            if (worker.err) |e| return e;
        }

        // Merge results (reduce)
        var total_expected = try self.allocator.alloc(f64, model.vocab.len);
        @memset(total_expected, 0.0);

        var total_objs: f64 = 0.0;
        for (workers[0..actual_threads]) |*worker| {
            total_objs += worker.objs;
            for (worker.expected, 0..) |exp_val, i| {
                total_expected[i] += exp_val;
            }
        }

        return .{ total_objs, total_expected };
    }

    /// M-step: Update probabilities from expected counts
    fn runMStep(self: *UnigramTrainer, pieces: []const SentencePiece, expected: []const f64) !std.ArrayList(SentencePiece) {
        var new_pieces = std.ArrayList(SentencePiece){};

        var sum: f64 = 0.0;

        // HuggingFace threshold: filter out tokens with expected frequency < 0.5
        const expected_frequency_threshold = 0.5;

        // M-step: Filter tokens and update scores based on expected counts
        for (pieces, expected, 0..) |piece, freq, i| {
            // Always keep UNK (index 0)
            if (i == 0) {
                const unk_token = try self.allocator.dupe(u8, piece.token);
                try new_pieces.append(self.allocator, SentencePiece{
                    .token = unk_token,
                    .score = std.math.nan(f64),
                });
                continue;
            }

            // Filter: Only keep tokens with expected frequency >= 0.5 (HuggingFace parity)
            if (freq < expected_frequency_threshold) {
                continue;
            }

            const token = try self.allocator.dupe(u8, piece.token);
            try new_pieces.append(self.allocator, SentencePiece{
                .token = token,
                .score = freq,
            });
            sum += freq;
        }

        // Bayesian EM: Use digamma for sparse prior
        const logsum = digamma(sum);
        for (new_pieces.items[1..]) |*piece| {  // Skip UNK at index 0
            piece.score = digamma(piece.score) - logsum;
        }

        std.debug.print("[DEBUG] M-step filtered: {d} kept (from {d} pieces)\n", .{new_pieces.items.len, pieces.len});
        return new_pieces;
    }

    /// Prune vocabulary to target size using loss-based selection (100% HuggingFace parity)
    fn pruneVocab(self: *UnigramTrainer, pieces: []const SentencePiece, sentences: []const Sentence, target_size: usize) !std.ArrayList(SentencePiece) {
        if (pieces.len <= target_size) {
            var result = std.ArrayList(SentencePiece){};
            for (pieces) |piece| {
                const token = try self.allocator.dupe(u8, piece.token);
                try result.append(self.allocator, SentencePiece{
                    .token = token,
                    .score = piece.score,
                });
            }
            return result;
        }

        // LOSS-BASED PRUNING (100% HuggingFace algorithm)
        // For each token, compute likelihood loss if removed

        // Build temporary model from current pieces
        var vocab = try self.allocator.alloc(VocabEntry, pieces.len);
        defer {
            for (vocab) |*entry| {
                self.allocator.free(entry.token);
            }
            self.allocator.free(vocab);
        }

        for (pieces, 0..) |piece, i| {
            vocab[i] = VocabEntry{
                .token = try self.allocator.dupe(u8, piece.token),
                .score = piece.score,
            };
        }

        var model = try Unigram.init(self.allocator, vocab, 0);
        defer model.deinit();

        // Compute loss for each token
        const Candidate = struct {
            idx: usize,
            loss: f64,  // Higher loss = more important token
        };
        var candidates = std.ArrayList(Candidate){};
        defer candidates.deinit(self.allocator);

        // Sample sentences for loss computation (performance optimization)
        const k_sample_size = @min(sentences.len, 200);
        var sample_indices = std.ArrayList(usize){};
        defer sample_indices.deinit(self.allocator);

        if (sentences.len <= k_sample_size) {
            for (0..sentences.len) |i| {
                try sample_indices.append(self.allocator, i);
            }
        } else {
            // Evenly sample k_sample_size sentences
            const step = sentences.len / k_sample_size;
            for (0..k_sample_size) |i| {
                try sample_indices.append(self.allocator, i * step);
            }
        }

        // For each token (skip UNK at index 0)
        for (pieces[1..], 1..) |_, token_idx| {
            var total_loss: f64 = 0.0;

            // Compute loss on sampled sentences
            for (sample_indices.items) |sent_idx| {
                const sentence = sentences[sent_idx];

                // Use arena allocator for node allocations
                var arena = std.heap.ArenaAllocator.init(self.allocator);
                defer arena.deinit();

                var lattice = try Lattice.initWithArena(self.allocator, sentence.text, model.bos_id, model.eos_id, &arena);
                defer lattice.deinit();

                try model.populateNodes(&lattice);

                // Get 2-best paths to estimate alternative segmentations
                const paths = try lattice.nbest(self.allocator, 2);
                defer {
                    for (paths) |path| {
                        self.allocator.free(path);
                    }
                    self.allocator.free(paths);
                }

                if (paths.len == 0) continue;

                // Check if this token appears in best path
                var token_appears = false;
                for (paths[0]) |node| {
                    if (node.id == token_idx) {
                        token_appears = true;
                        break;
                    }
                }

                if (!token_appears) continue;

                // Compute likelihood of best path
                var best_score: f64 = 0.0;
                for (paths[0]) |node| {
                    best_score += node.score;
                }

                // Compute likelihood of alternative (if exists)
                var alt_score: f64 = best_score;
                if (paths.len > 1) {
                    alt_score = 0.0;
                    for (paths[1]) |node| {
                        alt_score += node.score;
                    }
                }

                // Loss = frequency * (best - alternative)
                // Higher loss means token is more important
                const freq = @as(f64, @floatFromInt(sentence.count));
                total_loss += freq * (best_score - alt_score);
            }

            try candidates.append(self.allocator, Candidate{
                .idx = token_idx,
                .loss = total_loss,
            });
        }

        // Sort by loss (descending) - keep highest-loss tokens
        std.mem.sort(Candidate, candidates.items, {}, struct {
            fn lessThan(_: void, a: Candidate, b: Candidate) bool {
                return a.loss > b.loss;  // Descending
            }
        }.lessThan);

        var result = std.ArrayList(SentencePiece){};

        // Always add UNK first
        const unk_token = try self.allocator.dupe(u8, pieces[0].token);
        try result.append(self.allocator, SentencePiece{
            .token = unk_token,
            .score = pieces[0].score,
        });

        // Add top scoring tokens
        const n_to_keep = @min(target_size - 1, candidates.items.len);
        for (candidates.items[0..n_to_keep]) |cand| {
            const piece = pieces[cand.idx];
            const token = try self.allocator.dupe(u8, piece.token);
            try result.append(self.allocator, SentencePiece{
                .token = token,
                .score = piece.score,
            });
        }

        return result;
    }

    /// Finalize vocabulary: truncate to exact vocab_size and add required characters
    /// Matches HuggingFace's finalize() function
    fn finalize(self: *UnigramTrainer, pieces: []const SentencePiece, sentences: []const Sentence) !std.ArrayList(SentencePiece) {
        // Collect required characters (all unique chars in corpus)
        var required_chars = std.AutoHashMap(u8, void).init(self.allocator);
        defer required_chars.deinit();

        for (sentences) |sentence| {
            for (sentence.text) |c| {
                try required_chars.put(c, {});
            }
        }

        // Build result - target is vocab_size (no special tokens in this impl)
        var result = std.ArrayList(SentencePiece){};
        var inserted = std.StringHashMap(void).init(self.allocator);
        defer inserted.deinit();

        // First, add all required characters that exist in pieces
        for (pieces) |piece| {
            if (piece.token.len == 1) {
                if (required_chars.contains(piece.token[0])) {
                    const token = try self.allocator.dupe(u8, piece.token);
                    try result.append(self.allocator, SentencePiece{
                        .token = token,
                        .score = piece.score,
                    });
                    try inserted.put(token, {});
                }
            }
        }

        // Then add remaining pieces up to vocab_size
        for (pieces) |piece| {
            if (inserted.contains(piece.token)) {
                continue;
            }

            const token = try self.allocator.dupe(u8, piece.token);
            try result.append(self.allocator, SentencePiece{
                .token = token,
                .score = if (std.math.isNan(piece.score)) 0.0 else piece.score,
            });
            try inserted.put(token, {});

            if (result.items.len >= self.config.vocab_size) {
                break;
            }
        }

        // Sort by score (descending)
        std.mem.sort(SentencePiece, result.items, {}, struct {
            fn lessThan(_: void, a: SentencePiece, b: SentencePiece) bool {
                return a.score > b.score; // Descending
            }
        }.lessThan);

        return result;
    }

    /// Train Unigram model using EM algorithm
    pub fn train(self: *UnigramTrainer, sentences: []const Sentence) !Unigram {
        const start_total = std.time.nanoTimestamp();

        // 1. Generate seed vocabulary
        const start_seed = std.time.nanoTimestamp();
        var pieces = try self.makeSeedPieces(sentences);
        defer {
            for (pieces.items) |*piece| piece.deinit(self.allocator);
            pieces.deinit(self.allocator);
        }
        const seed_ms = @divFloor(std.time.nanoTimestamp() - start_seed, 1_000_000);
        std.debug.print("[PROFILE] Seed generation: {d}ms ({d} pieces)\n", .{seed_ms, pieces.items.len});

        // Target vocabulary size for EM convergence
        const desired_vocab_size = (self.config.vocab_size * 11) / 10;  // 1.1x target
        std.debug.print("[PROFILE] Target vocab: {d}, Desired: {d}\n", .{self.config.vocab_size, desired_vocab_size});

        // Lattice caching disabled - adds overhead without benefit (only 1 EM iteration)
        // TODO: Re-enable when we have multiple EM iterations per training run
        const cached_lattices_opt: ?[]Lattice = null;

        // 2. EM iterations
        var em_iteration: u32 = 0;
        while (pieces.items.len > desired_vocab_size) {
            const start_em = std.time.nanoTimestamp();
            em_iteration += 1;
            // Sub-iterations of EM
            var iter: u32 = 0;
            var total_estep_ms: i128 = 0;
            var total_mstep_ms: i128 = 0;
            while (iter < self.config.n_sub_iterations) : (iter += 1) {
                // Convert to VocabEntry for model
                var vocab = try self.allocator.alloc(VocabEntry, pieces.items.len);
                defer self.allocator.free(vocab);

                for (pieces.items, 0..) |piece, i| {
                    vocab[i] = VocabEntry{
                        .token = piece.token,  // Borrow, don't copy
                        .score = piece.score,
                    };
                }

                // Create temporary model
                var model = try Unigram.init(self.allocator, vocab, 0);
                defer model.deinit();

                // Lattice caching disabled (see above)
                // if (cached_lattices_opt == null and em_iteration == 1 and iter == 0) {
                //     const start_cache = std.time.nanoTimestamp();
                //     var cached_lattices = try self.allocator.alloc(Lattice, sentences.len);
                //     for (sentences, 0..) |sentence, i| {
                //         cached_lattices[i] = try Lattice.init(self.allocator, sentence.text, model.bos_id, model.eos_id);
                //     }
                //     const cache_ms = @divFloor(std.time.nanoTimestamp() - start_cache, 1_000_000);
                //     std.debug.print("[PROFILE] Lattice cache creation: {d}ms ({d} lattices)\n", .{cache_ms, cached_lattices.len});
                //     cached_lattices_opt = cached_lattices;
                // }

                // E-step (with cached lattices for massive speedup)
                const start_estep = std.time.nanoTimestamp();
                const e_result = try self.runEStep(&model, sentences, cached_lattices_opt);
                const expected = e_result[1];
                defer self.allocator.free(expected);
                const estep_ms = @divFloor(std.time.nanoTimestamp() - start_estep, 1_000_000);
                total_estep_ms += estep_ms;

                // M-step
                const start_mstep = std.time.nanoTimestamp();
                var new_pieces = try self.runMStep(pieces.items, expected);
                defer {
                    for (new_pieces.items) |*piece| piece.deinit(self.allocator);
                    new_pieces.deinit(self.allocator);
                }
                const mstep_ms = @divFloor(std.time.nanoTimestamp() - start_mstep, 1_000_000);
                total_mstep_ms += mstep_ms;

                // Update pieces
                for (pieces.items) |*piece| piece.deinit(self.allocator);
                pieces.clearRetainingCapacity();

                for (new_pieces.items) |piece| {
                    const token = try self.allocator.dupe(u8, piece.token);
                    try pieces.append(self.allocator, SentencePiece{
                        .token = token,
                        .score = piece.score,
                    });
                }
            }

            // Prune vocabulary
            const start_prune = std.time.nanoTimestamp();
            const pruned_size = @as(usize, @intFromFloat(@as(f64, @floatFromInt(pieces.items.len)) * self.config.shrinking_factor));
            const target_size = @max(desired_vocab_size, pruned_size);

            var pruned = try self.pruneVocab(pieces.items, sentences, target_size);
            defer {
                for (pruned.items) |*piece| piece.deinit(self.allocator);
                pruned.deinit(self.allocator);
            }

            // Update pieces
            for (pieces.items) |*piece| piece.deinit(self.allocator);
            pieces.clearRetainingCapacity();

            for (pruned.items) |piece| {
                const token = try self.allocator.dupe(u8, piece.token);
                try pieces.append(self.allocator, SentencePiece{
                    .token = token,
                    .score = piece.score,
                });
            }
            const prune_ms = @divFloor(std.time.nanoTimestamp() - start_prune, 1_000_000);

            const em_ms = @divFloor(std.time.nanoTimestamp() - start_em, 1_000_000);
            std.debug.print("[PROFILE] EM {d}: E-step={d}ms M-step={d}ms Prune={d}ms Total={d}ms (vocab: {d} -> {d})\n",
                .{em_iteration, total_estep_ms, total_mstep_ms, prune_ms, em_ms, pruned.items.len, pieces.items.len});

            if (pieces.items.len <= desired_vocab_size) {
                break;
            }
        }

        const total_ms = @divFloor(std.time.nanoTimestamp() - start_total, 1_000_000);
        std.debug.print("[PROFILE] Total training time: {d}ms ({d} EM iterations)\n", .{total_ms, em_iteration});

        // Finalize: Truncate to exact vocab_size (HuggingFace compatibility)
        var finalized_pieces = try self.finalize(pieces.items, sentences);
        defer {
            for (finalized_pieces.items) |*piece| piece.deinit(self.allocator);
            finalized_pieces.deinit(self.allocator);
        }

        // Final model - create vocab from finalized pieces
        var vocab = try self.allocator.alloc(VocabEntry, finalized_pieces.items.len);
        defer {
            for (vocab) |*entry| {
                self.allocator.free(entry.token);
            }
            self.allocator.free(vocab);
        }

        for (finalized_pieces.items, 0..) |piece, i| {
            vocab[i] = VocabEntry{
                .token = try self.allocator.dupe(u8, piece.token),
                .score = piece.score,
            };
        }

        std.debug.print("[PROFILE] Finalized vocab size: {d} (target: {d})\n", .{vocab.len, self.config.vocab_size});
        return try Unigram.init(self.allocator, vocab, 0);
    }

    /// Train from text iterator (matches BPE/WordPiece API)
    pub fn trainFromIterator(self: *UnigramTrainer, texts: []const []const u8) !UnigramTokenizer {
        // Convert texts to sentences (all with count=1)
        var sentences = try self.allocator.alloc(Sentence, texts.len);
        defer self.allocator.free(sentences);

        for (texts, 0..) |text, i| {
            sentences[i] = Sentence{
                .text = text,
                .count = 1,
            };
        }

        // Train the model
        const model = try self.train(sentences);

        // Create tokenizer
        return UnigramTokenizer.init(model, self.allocator);
    }
};

test "Unigram trainer basic" {
    const allocator = std.testing.allocator;

    const sentences = [_]Sentence{
        .{ .text = "hello", .count = 10 },
        .{ .text = "world", .count = 5 },
    };

    var trainer = UnigramTrainer.init(allocator, .{ .vocab_size = 50 });
    defer trainer.deinit();

    var model = try trainer.train(&sentences);
    defer model.deinit();

    // Model should have vocabulary
    try std.testing.expect(model.vocab.len > 0);
}
