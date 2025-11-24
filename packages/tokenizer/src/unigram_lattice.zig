/// Lattice for Unigram Language Model tokenization
/// Implements Viterbi algorithm and forward-backward for EM training
/// Ported from HuggingFace tokenizers/src/models/unigram/lattice.rs (670 lines)

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Returns log(exp(x) + exp(y)) for numerical stability
/// Used in forward-backward algorithm
/// Optimized version with fast paths for common cases
inline fn logSumExp(x: f64, y: f64, init_mode: bool) f64 {
    if (init_mode) {
        return y;
    }

    // Fast path: if one value dominates, skip expensive exp/log
    const k_minus_log_epsilon = 50.0;
    const diff = x - y;

    if (diff > k_minus_log_epsilon) {
        return x;  // x >> y, so log(exp(x) + exp(y)) ≈ x
    }
    if (diff < -k_minus_log_epsilon) {
        return y;  // y >> x, so log(exp(x) + exp(y)) ≈ y
    }

    // Need full computation - use max for numerical stability
    const vmax = if (x > y) x else y;
    const vmin = if (x > y) y else x;

    // log(exp(x) + exp(y)) = vmax + log(exp(vmin - vmax) + 1)
    // Use log1p for better accuracy when vmin ≈ vmax
    return vmax + @log(@exp(vmin - vmax) + 1.0);
}

/// A node in the lattice
pub const Node = struct {
    id: usize,           // Vocabulary ID
    node_id: usize,      // Lattice node ID
    pos: usize,          // Position in sentence (bytes)
    length: usize,       // Length in bytes
    score: f64,          // Log probability
    backtrace_score: f64, // Best path score to this node
    prev: ?*Node,        // Previous node in best path

    pub fn init(id: usize, node_id: usize, pos: usize, length: usize, score: f64) Node {
        return Node{
            .id = id,
            .node_id = node_id,
            .pos = pos,
            .length = length,
            .score = score,
            .backtrace_score = 0.0,
            .prev = null,
        };
    }
};

/// Lattice structure for Viterbi decoding and EM training
pub const Lattice = struct {
    sentence: []const u8,
    len: usize,  // Byte length
    nodes: std.ArrayList(*Node),
    begin_nodes: std.ArrayList(std.ArrayList(*Node)), // begin_nodes[pos] = nodes starting at pos
    end_nodes: std.ArrayList(std.ArrayList(*Node)),   // end_nodes[pos] = nodes ending at pos
    bos_id: usize,
    eos_id: usize,
    allocator: Allocator,
    /// Optional arena allocator for node allocations (performance optimization)
    /// If provided, all nodes are allocated from arena and freed in one shot
    arena: ?*std.heap.ArenaAllocator,

    pub fn init(allocator: Allocator, sentence: []const u8, bos_id: usize, eos_id: usize) !Lattice {
        return initWithArena(allocator, sentence, bos_id, eos_id, null);
    }

    /// Initialize lattice with optional arena allocator for node allocations
    /// If arena is provided, all nodes will be allocated from it (faster, fewer allocations)
    pub fn initWithArena(allocator: Allocator, sentence: []const u8, bos_id: usize, eos_id: usize, arena: ?*std.heap.ArenaAllocator) !Lattice {
        const len = sentence.len;
        // OPTIMIZATION: Increased from 16 to 32 to reduce reallocations
        // Profiling shows ~2-3 nodes per position on average for typical sentences
        const k_reserved_node_size = 32;

        // Use arena for node allocations if provided, otherwise use main allocator
        const node_allocator = if (arena) |a| a.allocator() else allocator;

        var nodes = std.ArrayList(*Node){};
        // OPTIMIZATION: Pre-allocate nodes ArrayList to avoid reallocation
        // Typical sentence has ~1000-2000 total nodes
        try nodes.ensureTotalCapacity(allocator, len * 3);

        var begin_nodes = std.ArrayList(std.ArrayList(*Node)){};
        var end_nodes = std.ArrayList(std.ArrayList(*Node)){};

        // Create begin_nodes and end_nodes vectors
        var i: usize = 0;
        while (i <= len) : (i += 1) {
            var begin_list = std.ArrayList(*Node){};
            try begin_list.ensureTotalCapacity(allocator, k_reserved_node_size);
            try begin_nodes.append(allocator, begin_list);

            var end_list = std.ArrayList(*Node){};
            try end_list.ensureTotalCapacity(allocator, k_reserved_node_size);
            try end_nodes.append(allocator, end_list);
        }

        // Create BOS (beginning of sentence) node
        const bos = try node_allocator.create(Node);
        bos.* = Node.init(bos_id, 0, 0, 0, 0.0);
        try nodes.append(allocator, bos);
        try end_nodes.items[0].append(allocator, bos);

        // Create EOS (end of sentence) node
        const eos = try node_allocator.create(Node);
        eos.* = Node.init(eos_id, 1, len, 0, 0.0);
        try nodes.append(allocator, eos);
        try begin_nodes.items[len].append(allocator, eos);

        return Lattice{
            .sentence = sentence,
            .len = len,
            .nodes = nodes,
            .begin_nodes = begin_nodes,
            .end_nodes = end_nodes,
            .bos_id = bos_id,
            .eos_id = eos_id,
            .allocator = allocator,
            .arena = arena,
        };
    }

    pub fn deinit(self: *Lattice) void {
        // If using arena, nodes are freed automatically with arena.deinit()
        // Otherwise, free each node individually
        if (self.arena == null) {
            for (self.nodes.items) |node| {
                self.allocator.destroy(node);
            }
        }
        self.nodes.deinit(self.allocator);

        // Free begin_nodes lists
        for (self.begin_nodes.items) |*list| {
            list.deinit(self.allocator);
        }
        self.begin_nodes.deinit(self.allocator);

        // Free end_nodes lists
        for (self.end_nodes.items) |*list| {
            list.deinit(self.allocator);
        }
        self.end_nodes.deinit(self.allocator);
    }

    /// Clear all nodes from lattice (for reuse with different vocabulary)
    /// Keeps sentence structure intact - just clears token nodes
    pub fn clearNodes(self: *Lattice) void {
        // Free all nodes except BOS/EOS (first 2 nodes)
        // Actually, BOS/EOS are at index 0 and 1, but let's just free all and recreate
        for (self.nodes.items) |node| {
            self.allocator.destroy(node);
        }
        self.nodes.clearRetainingCapacity();

        // Clear begin_nodes and end_nodes lists
        for (self.begin_nodes.items) |*list| {
            list.clearRetainingCapacity();
        }
        for (self.end_nodes.items) |*list| {
            list.clearRetainingCapacity();
        }

        // Recreate BOS and EOS nodes (required for lattice to work)
        // BOS: node_id=0, pos=0, length=0, ends at position 0
        const bos = self.allocator.create(Node) catch unreachable;
        bos.* = Node.init(self.bos_id, 0, 0, 0, 0.0);
        self.nodes.append(self.allocator, bos) catch unreachable;
        self.end_nodes.items[0].append(self.allocator, bos) catch unreachable;

        // EOS: node_id=1, pos=len, length=0, begins at position len
        const eos = self.allocator.create(Node) catch unreachable;
        eos.* = Node.init(self.eos_id, 1, self.len, 0, 0.0);
        self.nodes.append(self.allocator, eos) catch unreachable;
        self.begin_nodes.items[self.len].append(self.allocator, eos) catch unreachable;
    }

    /// Insert a token candidate into the lattice
    pub fn insert(self: *Lattice, pos: usize, length: usize, score: f64, id: usize) !void {
        const node_id = self.nodes.items.len;

        // Use arena allocator if available, otherwise use main allocator
        const node_allocator = if (self.arena) |a| a.allocator() else self.allocator;
        const node = try node_allocator.create(Node);
        node.* = Node.init(id, node_id, pos, length, score);

        try self.nodes.append(self.allocator, node);
        try self.begin_nodes.items[pos].append(self.allocator, node);
        try self.end_nodes.items[pos + length].append(self.allocator, node);
    }

    /// Viterbi algorithm - find the best tokenization path
    pub fn viterbi(self: *Lattice) ![]*Node {
        var result = std.ArrayList(*Node){};
        errdefer result.deinit(self.allocator);

        var pos: usize = 0;
        while (pos <= self.len) {
            if (self.begin_nodes.items[pos].items.len == 0) {
                return result.toOwnedSlice(self.allocator);
            }

            // For each node starting at pos
            for (self.begin_nodes.items[pos].items) |rnode| {
                rnode.prev = null;
                var best_score: f64 = 0.0;
                var best_node: ?*Node = null;

                // Find best predecessor (node ending at pos)
                for (self.end_nodes.items[pos].items) |lnode| {
                    const score = lnode.backtrace_score + rnode.score;
                    if (best_node == null or score > best_score) {
                        best_node = lnode;
                        best_score = score;
                    }
                }

                if (best_node) |bnode| {
                    rnode.prev = bnode;
                    rnode.backtrace_score = best_score;
                }
            }

            // Move to next character position
            if (pos < self.len) {
                const remaining = self.sentence[pos..];
                const char_len = std.unicode.utf8ByteSequenceLength(remaining[0]) catch break;
                pos += char_len;
            } else {
                break;
            }
        }

        // Backtrace from EOS to BOS
        if (self.begin_nodes.items[self.len].items.len == 0) {
            return result.toOwnedSlice(self.allocator);
        }

        const root = self.begin_nodes.items[self.len].items[0];
        var node_opt = root.prev;

        while (node_opt) |node| {
            if (node.prev == null) break;
            try result.append(self.allocator, node);
            node_opt = node.prev;
        }

        // Reverse to get forward order
        std.mem.reverse(*Node, result.items);
        return result.toOwnedSlice(self.allocator);
    }

    /// Get the token string for a node
    pub fn piece(self: *const Lattice, node: *const Node) []const u8 {
        return self.sentence[node.pos .. node.pos + node.length];
    }

    /// Get token strings for best path
    pub fn tokens(self: *Lattice, allocator: Allocator) ![][]const u8 {
        const path = try self.viterbi();
        defer allocator.free(path);

        var result = std.ArrayList([]const u8){};
        for (path) |node| {
            const token = try allocator.dupe(u8, self.piece(node));
            try result.append(allocator, token);
        }
        return result.toOwnedSlice(allocator);
    }

    /// Hypothesis for N-best search (A* algorithm)
    const Hypothesis = struct {
        node: *Node,
        next: ?*Hypothesis, // Linked list to previous hypothesis
        fx: f64,  // f(x) = g(x) + h(x) - total score for ordering
        gx: f64,  // g(x) = score so far
        allocator: Allocator,

        pub fn init(allocator: Allocator, node: *Node, next: ?*Hypothesis, fx: f64, gx: f64) !*Hypothesis {
            const hyp = try allocator.create(Hypothesis);
            hyp.* = Hypothesis{
                .node = node,
                .next = next,
                .fx = fx,
                .gx = gx,
                .allocator = allocator,
            };
            return hyp;
        }

        pub fn deinit(self: *Hypothesis) void {
            self.allocator.destroy(self);
        }

        pub fn lessThan(_: void, a: *Hypothesis, b: *Hypothesis) std.math.Order {
            // Higher fx is better (max heap)
            if (a.fx > b.fx) return .lt;
            if (a.fx < b.fx) return .gt;
            return .eq;
        }
    };

    /// Find N-best tokenization paths using A* search
    pub fn nbest(self: *Lattice, allocator: Allocator, n: usize) ![][]*Node {
        if (n == 0) {
            return try allocator.alloc([]*Node, 0);
        }

        if (n == 1) {
            const best = try self.viterbi();
            var result = try allocator.alloc([]*Node, 1);
            result[0] = best;
            return result;
        }

        // Priority queue (max heap by fx score)
        const PQ = std.PriorityQueue(*Hypothesis, void, Hypothesis.lessThan);
        var agenda = PQ.init(allocator, {});
        defer agenda.deinit();

        // Track all allocated hypotheses for cleanup
        var all_hyps = std.ArrayList(*Hypothesis){};
        defer {
            for (all_hyps.items) |hyp| {
                hyp.deinit();
            }
            all_hyps.deinit(allocator);
        }

        var results = std.ArrayList([]*Node){};
        errdefer {
            for (results.items) |path| {
                allocator.free(path);
            }
            results.deinit(allocator);
        }

        // Initialize: start from EOS node
        const eos = self.begin_nodes.items[self.len].items[0];
        const eos_hyp = try Hypothesis.init(allocator, eos, null, eos.score, eos.score);
        try all_hyps.append(allocator, eos_hyp);
        try agenda.add(eos_hyp);

        // Fill backtrace scores first (needed for heuristic)
        {
            const vit_path = try self.viterbi();
            defer allocator.free(vit_path);
        }

        // A* search
        const k_max_agenda_size = 100_000;
        const k_min_agenda_size = 512;

        while (agenda.removeOrNull()) |top| {
            const node = top.node;

            // Check if we reached BOS (beginning of sentence)
            if (node.node_id == self.end_nodes.items[0].items[0].node_id) {
                // Reconstruct path by following linked list
                var path = std.ArrayList(*Node){};
                var curr: ?*Hypothesis = top.next;

                while (curr) |h| {
                    if (h.next == null) break; // Skip BOS
                    try path.append(allocator, h.node);
                    curr = h.next;
                }

                // Reverse to get forward order
                std.mem.reverse(*Node, path.items);
                try results.append(allocator, try path.toOwnedSlice(allocator));

                if (results.items.len >= n) {
                    return results.toOwnedSlice(allocator);
                }
                continue;
            }

            // Expand: add predecessors to agenda
            for (self.end_nodes.items[node.pos].items) |lnode| {
                const new_fx = lnode.backtrace_score + top.gx;
                const new_gx = lnode.score + top.gx;

                const new_hyp = try Hypothesis.init(allocator, lnode, top, new_fx, new_gx);
                try all_hyps.append(allocator, new_hyp);
                try agenda.add(new_hyp);
            }

            // Prune agenda if too large (prevent memory explosion)
            if (agenda.count() > k_max_agenda_size) {
                const keep_size = @min(k_min_agenda_size, n * 10);
                var new_agenda = PQ.init(allocator, {});

                var kept: usize = 0;
                while (kept < keep_size and agenda.removeOrNull() != null) {
                    const hyp = agenda.removeOrNull().?;
                    try new_agenda.add(hyp);
                    kept += 1;
                }

                // Clean up remaining hypotheses
                while (agenda.removeOrNull()) |_| {}

                agenda.deinit();
                agenda = new_agenda;
            }
        }

        return results.toOwnedSlice(allocator);
    }

    /// Forward-backward algorithm for EM training (E-step)
    /// Computes expected counts for each token
    pub fn populateMarginal(self: *const Lattice, freq: f64, expected: []f64) !f64 {
        const n_nodes = self.nodes.items.len;
        const alpha = try self.allocator.alloc(f64, n_nodes);
        defer self.allocator.free(alpha);
        const beta = try self.allocator.alloc(f64, n_nodes);
        defer self.allocator.free(beta);

        return self.populateMarginalWithBuffers(freq, expected, alpha, beta);
    }

    /// Optimized version that accepts preallocated buffers (avoids allocation in hot path!)
    pub fn populateMarginalWithBuffers(self: *const Lattice, freq: f64, expected: []f64, alpha: []f64, beta: []f64) f64 {
        const n_nodes = self.nodes.items.len;

        // Resize buffers if needed (rarely happens after first sentence)
        if (alpha.len < n_nodes or beta.len < n_nodes) {
            // Caller must provide large enough buffers
            @panic("Buffer too small for populateMarginal");
        }

        @memset(alpha[0..n_nodes], 0.0);
        @memset(beta[0..n_nodes], 0.0);

        // Forward pass
        var pos: usize = 0;
        while (pos <= self.len) : (pos += 1) {
            for (self.begin_nodes.items[pos].items) |rnode| {
                for (self.end_nodes.items[pos].items, 0..) |lnode, idx| {
                    const lid = lnode.node_id;
                    const rid = rnode.node_id;
                    alpha[rid] = logSumExp(
                        alpha[rid],
                        lnode.score + alpha[lid],
                        idx == 0,
                    );
                }
            }
        }

        // Backward pass
        var rev_pos: usize = self.len + 1;
        while (rev_pos > 0) {
            rev_pos -= 1;
            for (self.end_nodes.items[rev_pos].items) |lnode| {
                for (self.begin_nodes.items[rev_pos].items, 0..) |rnode, idx| {
                    const lid = lnode.node_id;
                    const rid = rnode.node_id;
                    beta[lid] = logSumExp(
                        beta[lid],
                        rnode.score + beta[rid],
                        idx == 0,
                    );
                }
            }
        }

        // Compute expected counts
        const eos_id = self.begin_nodes.items[self.len].items[0].node_id;
        const z = alpha[eos_id];

        for (0..self.len) |i| {
            for (self.begin_nodes.items[i].items) |node| {
                const node_id = node.node_id;
                const id = node.id;
                const a = alpha[node_id];
                const b = beta[node_id];
                const total = a + node.score + b - z;
                const update = freq * @exp(total);
                expected[id] += update;
            }
        }

        return freq * z;
    }
};

// Tests
test "Lattice basic operations" {
    const allocator = std.testing.allocator;

    var lattice = try Lattice.init(allocator, "test", 0, 1);
    defer lattice.deinit();

    try std.testing.expectEqual(@as(usize, 4), lattice.len);
    try std.testing.expectEqual(@as(usize, 0), lattice.bos_id);
    try std.testing.expectEqual(@as(usize, 1), lattice.eos_id);
}

test "Lattice insert and viterbi" {
    const allocator = std.testing.allocator;

    var lattice = try Lattice.init(allocator, "ab", 0, 1);
    defer lattice.deinit();

    // Insert some token candidates
    try lattice.insert(0, 1, -1.0, 2); // "a" with score -1.0
    try lattice.insert(1, 1, -1.0, 3); // "b" with score -1.0
    try lattice.insert(0, 2, -0.5, 4); // "ab" with score -0.5 (better!)

    const path = try lattice.viterbi();
    defer allocator.free(path);

    // Should choose "ab" (single token) over "a" + "b"
    try std.testing.expectEqual(@as(usize, 1), path.len);
    try std.testing.expectEqual(@as(usize, 4), path[0].id);
}

test "Lattice nbest" {
    const allocator = std.testing.allocator;

    var lattice = try Lattice.init(allocator, "ab", 0, 1);
    defer lattice.deinit();

    // Insert candidates
    try lattice.insert(0, 1, -1.0, 2); // "a"
    try lattice.insert(1, 1, -1.0, 3); // "b"
    try lattice.insert(0, 2, -0.5, 4); // "ab" (best)

    // Get 2-best paths
    const paths = try lattice.nbest(allocator, 2);
    defer {
        for (paths) |path| {
            allocator.free(path);
        }
        allocator.free(paths);
    }

    // Should get 2 paths
    try std.testing.expect(paths.len > 0);
    try std.testing.expect(paths.len <= 2);

    // First path should be best (single "ab" token)
    if (paths.len > 0) {
        try std.testing.expectEqual(@as(usize, 1), paths[0].len);
    }
}
