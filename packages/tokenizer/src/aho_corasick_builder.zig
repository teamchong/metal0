/// Builder for constructing double-array Aho-Corasick automaton
/// EXACT port of daachorse (github.com/daac-tools/daachorse/src/bytewise.rs)
const std = @import("std");
const Allocator = std.mem.Allocator;
const State = @import("aho_corasick.zig").State;

const ROOT_STATE_IDX: u32 = 0;
/// Sentinel value for "no output" - using maxInt since token IDs are sequential from 0
pub const NO_OUTPUT: u32 = std.math.maxInt(u32);

/// Builder for constructing double-array (port of daachorse Builder)
pub const Builder = struct {
    allocator: Allocator,
    nfa_states: std.ArrayList(NFAState),
    patterns: std.ArrayList([]const u8),
    token_ids: std.ArrayList(u32),

    const NFAState = struct {
        children: std.AutoHashMap(u8, u32),
        fail: u32 = ROOT_STATE_IDX,
        output: u32 = NO_OUTPUT, // Use sentinel for "no output"

        fn init(allocator: Allocator) NFAState {
            return .{
                .children = std.AutoHashMap(u8, u32).init(allocator),
                .fail = ROOT_STATE_IDX,
                .output = NO_OUTPUT,
            };
        }

        fn deinit(self: *NFAState) void {
            self.children.deinit();
        }
    };

    pub fn init(allocator: Allocator) Builder {
        return .{
            .allocator = allocator,
            .nfa_states = std.ArrayList(NFAState){},
            .patterns = std.ArrayList([]const u8){},
            .token_ids = std.ArrayList(u32){},
        };
    }

    pub fn deinit(self: *Builder) void {
        for (self.nfa_states.items) |*state| {
            state.deinit();
        }
        self.nfa_states.deinit(self.allocator);
        self.patterns.deinit(self.allocator);
        self.token_ids.deinit(self.allocator);
    }

    /// Build NFA (trie + failure links)
    pub fn buildNFA(self: *Builder, patterns: []const []const u8, token_ids: []const u32) !void {
        // Add root state
        try self.nfa_states.append(self.allocator, NFAState.init(self.allocator));

        // Build trie
        for (patterns, 0..) |pattern, i| {
            try self.addPattern(pattern, token_ids[i]);
        }

        // Build failure links (BFS)
        try self.buildFailureLinks();
    }

    fn addPattern(self: *Builder, pattern: []const u8, token_id: u32) !void {
        var state_id: u32 = ROOT_STATE_IDX;

        for (pattern) |c| {
            const entry = try self.nfa_states.items[state_id].children.getOrPut(c);
            if (!entry.found_existing) {
                // Create new state
                const new_id = @as(u32, @intCast(self.nfa_states.items.len));
                entry.value_ptr.* = new_id;
                try self.nfa_states.append(self.allocator, NFAState.init(self.allocator));
            }
            state_id = entry.value_ptr.*;
        }

        // Mark final state
        self.nfa_states.items[state_id].output = token_id;
    }

    fn buildFailureLinks(self: *Builder) !void {
        var queue = std.ArrayList(u32){};
        defer queue.deinit(self.allocator);

        // Initialize: root's children fail to root
        var it = self.nfa_states.items[ROOT_STATE_IDX].children.iterator();
        while (it.next()) |entry| {
            const child_id = entry.value_ptr.*;
            self.nfa_states.items[child_id].fail = ROOT_STATE_IDX;
            try queue.append(self.allocator, child_id);
        }

        // BFS to build failure links
        var head: usize = 0;
        while (head < queue.items.len) : (head += 1) {
            const state_id = queue.items[head];
            var child_it = self.nfa_states.items[state_id].children.iterator();

            while (child_it.next()) |entry| {
                const c = entry.key_ptr.*;
                const child_id = entry.value_ptr.*;

                // Find failure link
                var fail_state = self.nfa_states.items[state_id].fail;
                while (fail_state != ROOT_STATE_IDX) {
                    if (self.nfa_states.items[fail_state].children.get(c)) |target| {
                        self.nfa_states.items[child_id].fail = target;
                        break;
                    }
                    fail_state = self.nfa_states.items[fail_state].fail;
                } else {
                    // Check root
                    if (self.nfa_states.items[ROOT_STATE_IDX].children.get(c)) |target| {
                        self.nfa_states.items[child_id].fail = target;
                    } else {
                        self.nfa_states.items[child_id].fail = ROOT_STATE_IDX;
                    }
                }

                try queue.append(self.allocator, child_id);
            }
        }
    }

    /// Convert NFA to double-array (port of daachorse arrange())
    pub fn arrangeStates(self: *Builder) ![]State {
        var helper = try BuildHelper.init(self.allocator, self.nfa_states.items.len);
        defer helper.deinit();

        var states = std.ArrayList(State){};
        errdefer states.deinit(self.allocator);

        // Preallocate
        try states.ensureTotalCapacity(self.allocator, self.nfa_states.items.len * 2);

        // Add root
        try states.append(self.allocator, State{});
        try helper.markUsed(0);

        // Mapping from NFA state ID to DA state index
        var nfa_to_da = try self.allocator.alloc(u32, self.nfa_states.items.len);
        defer self.allocator.free(nfa_to_da);
        @memset(nfa_to_da, 0);

        // Priority Queue for density sorting (process states with most children first)
        const PQContext = struct {
            nfa_states: []const NFAState,
            fn compare(ctx: @This(), a: u32, b: u32) std.math.Order {
                const count_a = ctx.nfa_states[a].children.count();
                const count_b = ctx.nfa_states[b].children.count();
                // Descending order (more children = higher priority)
                return std.math.order(count_b, count_a);
            }
        };
        var pq = std.PriorityQueue(u32, PQContext, PQContext.compare).init(self.allocator, PQContext{ .nfa_states = self.nfa_states.items });
        defer pq.deinit();

        // Start with root
        try pq.add(ROOT_STATE_IDX);

        while (pq.removeOrNull()) |nfa_id| {
            const da_idx = nfa_to_da[nfa_id];
            const nfa_state = &self.nfa_states.items[nfa_id];

            if (nfa_state.children.count() == 0) continue;

            // Get sorted labels
            var labels = std.ArrayList(u8){};
            defer labels.deinit(self.allocator);

            var child_iter = nfa_state.children.iterator();
            while (child_iter.next()) |entry| {
                try labels.append(self.allocator, entry.key_ptr.*);
            }
            std.sort.insertion(u8, labels.items, {}, std.sort.asc(u8));

            // Find base
            const base = try self.findBase(labels.items, &helper);

            // Ensure capacity for parent
            if (da_idx >= states.items.len) {
                while (states.items.len <= da_idx) {
                    try states.append(self.allocator, State{});
                }
            }
            states.items[da_idx].setBase(base);
            try helper.markUsedBase(base);

            // Process children
            for (labels.items) |c| {
                const child_da_idx = base ^ c;
                const child_nfa_id = nfa_state.children.get(c).?;

                // Ensure capacity
                while (states.items.len <= child_da_idx) {
                    try states.append(self.allocator, State{});
                }

                // Mark used
                try helper.markUsed(child_da_idx);

                // Link
                states.items[child_da_idx].setCheck(c);

                // Store NFA ID in fail temporarily (resolved in second pass)
                states.items[child_da_idx].fail = self.nfa_states.items[child_nfa_id].fail;

                // Output: check if this NFA state has a token output
                // We use NO_OUTPUT sentinel since token ID 0 is valid ("!")
                const nfa_output = self.nfa_states.items[child_nfa_id].output;
                if (nfa_output != NO_OUTPUT) {
                    // Store the NFA ID which indexes into outputs array
                    states.items[child_da_idx].setOutputPos(child_nfa_id);
                }

                // Update map and add to PQ
                nfa_to_da[child_nfa_id] = child_da_idx;
                try pq.add(child_nfa_id);
            }
        }

        // Second pass: Resolve failure links
        for (states.items, 0..) |*s, i| {
            if (i == 0) continue;
            // s.fail currently holds NFA ID
            const fail_nfa_id = s.fail;
            // Root's fail is 0 (Root)
            if (fail_nfa_id == ROOT_STATE_IDX) {
                s.setFail(ROOT_STATE_IDX);
            } else {
                s.setFail(nfa_to_da[fail_nfa_id]);
            }
        }

        // Avoid toOwnedSlice overhead - just dupe used portion
        const items = states.items[0..states.items.len];
        const owned = try self.allocator.dupe(State, items);
        states.clearRetainingCapacity();
        return owned;
    }

    /// Find conflict-free base value using block-based search
    fn findBase(self: *Builder, labels: []const u8, helper: *BuildHelper) !u32 {
        _ = self;
        const num_children = @as(u32, @intCast(labels.len));
        var iter = helper.vacantIter(num_children);

        while (iter.next()) |block_idx| {
            const base_start = block_idx << 8;

            // Try lower bits 0..255
            for (0..256) |l| {
                const base = base_start | @as(u32, @intCast(l));
                if (checkValidBase(base, labels, helper)) |valid_base| {
                    return valid_base;
                }
            }
        }

        unreachable; // Should always find a base (infinite blocks)
    }

    pub fn buildOutputs(self: *Builder) ![]u32 {
        var outputs = std.ArrayList(u32){};
        errdefer outputs.deinit(self.allocator);

        for (self.nfa_states.items) |*nfa_state| {
            try outputs.append(self.allocator, nfa_state.output);
        }

        // Avoid toOwnedSlice overhead - just dupe used portion
        const items = outputs.items[0..outputs.items.len];
        const owned = try self.allocator.dupe(u32, items);
        outputs.clearRetainingCapacity();
        return owned;
    }
};

/// Check if base is valid (conflict check)
fn checkValidBase(base: u32, labels: []const u8, helper: *BuildHelper) ?u32 {
    if (base == 0) return null;
    if (helper.isUsedBase(base)) return null;

    for (labels) |c| {
        const idx = base ^ c;
        if (idx == 0) return null;
        if (helper.isUsedIndex(idx)) return null;
    }

    return base;
}

/// Helper for tracking used indices with block-based optimization
const BuildHelper = struct {
    used_indices: std.bit_set.DynamicBitSet,
    used_bases: std.bit_set.DynamicBitSet,
    block_capacity: std.ArrayList(u16), // Free slots per 256-block
    max_idx: u32,
    allocator: Allocator,

    fn init(allocator: Allocator, estimated_nfa_size: usize) !BuildHelper {
        // Initial capacity
        const init_size = estimated_nfa_size * 2;
        const used_indices = try std.bit_set.DynamicBitSet.initEmpty(allocator, init_size);
        const used_bases = try std.bit_set.DynamicBitSet.initEmpty(allocator, init_size);

        const num_blocks = (init_size + 255) / 256;
        var block_capacity = try std.ArrayList(u16).initCapacity(allocator, num_blocks);
        for (0..num_blocks) |_| {
            block_capacity.appendAssumeCapacity(256);
        }

        return .{
            .used_indices = used_indices,
            .used_bases = used_bases,
            .block_capacity = block_capacity,
            .max_idx = 0,
            .allocator = allocator,
        };
    }

    fn deinit(self: *BuildHelper) void {
        self.used_indices.deinit();
        self.used_bases.deinit();
        self.block_capacity.deinit(self.allocator);
    }

    fn markUsed(self: *BuildHelper, idx: u32) !void {
        if (idx >= self.used_indices.capacity()) {
            try self.resize(idx + 1);
        }

        if (!self.used_indices.isSet(idx)) {
            self.used_indices.set(idx);
            const block = idx >> 8;
            if (block < self.block_capacity.items.len) {
                if (self.block_capacity.items[block] > 0) {
                    self.block_capacity.items[block] -= 1;
                }
            }
            if (idx > self.max_idx) self.max_idx = idx;
        }
    }

    fn markUsedBase(self: *BuildHelper, base: u32) !void {
        if (base >= self.used_bases.capacity()) {
            var new_len = self.used_bases.capacity();
            while (new_len <= base) new_len *= 2;
            try self.used_bases.resize(new_len, false);
        }
        self.used_bases.set(base);
    }

    fn resize(self: *BuildHelper, new_size: usize) !void {
        var size = self.used_indices.capacity();
        while (size < new_size) size *= 2;

        try self.used_indices.resize(size, false);

        // Update blocks
        const old_blocks = self.block_capacity.items.len;
        const new_blocks = (size + 255) / 256;
        try self.block_capacity.ensureTotalCapacity(self.allocator, new_blocks);
        for (old_blocks..new_blocks) |_| {
            self.block_capacity.appendAssumeCapacity(256);
        }
    }

    fn isUsedIndex(self: *BuildHelper, idx: u32) bool {
        if (idx >= self.used_indices.capacity()) return false;
        return self.used_indices.isSet(idx);
    }

    fn isUsedBase(self: *BuildHelper, base: u32) bool {
        if (base >= self.used_bases.capacity()) return false;
        return self.used_bases.isSet(base);
    }

    fn vacantIter(self: *BuildHelper, num_children: u32) VacantIterator {
        return VacantIterator{
            .helper = self,
            .current_block = 0,
            .num_children = num_children,
        };
    }
};

const VacantIterator = struct {
    helper: *BuildHelper,
    current_block: u32,
    num_children: u32,

    fn next(self: *VacantIterator) ?u32 {
        while (self.current_block < self.helper.block_capacity.items.len) {
            if (self.helper.block_capacity.items[self.current_block] >= self.num_children) {
                const blk = self.current_block;
                self.current_block += 1;
                return blk;
            }
            self.current_block += 1;
        }

        // Return next virtual block (will trigger resize)
        const blk = self.current_block;
        self.current_block += 1;
        return blk;
    }
};
