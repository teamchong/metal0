/// Trie (Prefix Tree) for Unigram substring lookup
/// Ported from HuggingFace tokenizers/src/models/unigram/trie.rs (91 lines)

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Generic Trie supporting any label type
/// Can optionally store data at leaf nodes (e.g., token IDs)
pub fn Trie(comptime Label: type) type {
    return struct {
        const Self = @This();

        root: *Node,
        allocator: Allocator,

        pub const Node = struct {
            is_leaf: bool,
            leaf_id: u32, // Store token ID at leaf nodes (0 if not leaf)
            // OPTIMIZATION: For u8 labels, use array instead of HashMap (100x faster!)
            children: if (Label == u8) [256]?*Node else std.AutoHashMap(Label, *Node),

            pub fn init(allocator: Allocator) !*Node {
                const node = try allocator.create(Node);
                if (Label == u8) {
                    node.* = Node{
                        .is_leaf = false,
                        .leaf_id = 0,
                        .children = [_]?*Node{null} ** 256,
                    };
                } else {
                    node.* = Node{
                        .is_leaf = false,
                        .leaf_id = 0,
                        .children = std.AutoHashMap(Label, *Node).init(allocator),
                    };
                }
                return node;
            }

            pub fn deinit(self: *Node, allocator: Allocator) void {
                if (Label == u8) {
                    for (self.children) |maybe_child| {
                        if (maybe_child) |child| {
                            child.deinit(allocator);
                        }
                    }
                } else {
                    var it = self.children.valueIterator();
                    while (it.next()) |child| {
                        child.*.deinit(allocator);
                    }
                    self.children.deinit();
                }
                allocator.destroy(self);
            }
        };

        pub fn init(allocator: Allocator) !Self {
            return Self{
                .root = try Node.init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.root.deinit(self.allocator);
        }

        /// Insert a sequence into the trie
        pub fn push(self: *Self, element: []const Label) !void {
            var node = self.root;
            for (element) |label| {
                if (Label == u8) {
                    // Array lookup (O(1), no hash)
                    if (node.children[label]) |child| {
                        node = child;
                    } else {
                        const new_node = try Node.init(self.allocator);
                        node.children[label] = new_node;
                        node = new_node;
                    }
                } else {
                    // HashMap fallback for non-u8 labels
                    const entry = try node.children.getOrPut(label);
                    if (!entry.found_existing) {
                        entry.value_ptr.* = try Node.init(self.allocator);
                    }
                    node = entry.value_ptr.*;
                }
            }
            node.is_leaf = true;
        }

        /// Insert a sequence into the trie with associated ID (for fast lookup)
        pub fn pushWithId(self: *Self, element: []const Label, id: u32) !void {
            var node = self.root;
            for (element) |label| {
                if (Label == u8) {
                    // Array lookup (O(1), no hash)
                    if (node.children[label]) |child| {
                        node = child;
                    } else {
                        const new_node = try Node.init(self.allocator);
                        node.children[label] = new_node;
                        node = new_node;
                    }
                } else {
                    // HashMap fallback for non-u8 labels
                    const entry = try node.children.getOrPut(label);
                    if (!entry.found_existing) {
                        entry.value_ptr.* = try Node.init(self.allocator);
                    }
                    node = entry.value_ptr.*;
                }
            }
            node.is_leaf = true;
            node.leaf_id = id;
        }

        /// Find all common prefixes of the input sequence
        /// Returns an iterator that yields matching prefixes
        pub fn commonPrefixSearch(self: *const Self, labels: []const Label) CommonPrefixIterator(Label) {
            return CommonPrefixIterator(Label){
                .node = self.root,
                .labels = labels,
                .index = 0,
                .prefix_len = 0,
            };
        }

        /// Find all common prefixes and return (length, id) pairs
        /// Optimized version that avoids redundant HashMap lookups
        pub fn commonPrefixSearchWithIds(self: *const Self, labels: []const Label) CommonPrefixIteratorWithIds(Label) {
            return CommonPrefixIteratorWithIds(Label){
                .node = self.root,
                .labels = labels,
                .index = 0,
                .prefix_len = 0,
            };
        }
    };
}

/// Iterator for common prefix search results
pub fn CommonPrefixIterator(comptime Label: type) type {
    return struct {
        const Self = @This();
        const Node = Trie(Label).Node;

        node: *const Node,
        labels: []const Label,
        index: usize,
        prefix_len: usize,

        /// Returns the length of the next matching prefix, or null if none
        pub fn next(self: *Self) ?usize {
            while (self.index < self.labels.len) {
                const label = self.labels[self.index];
                self.index += 1;
                self.prefix_len += 1;

                if (Label == u8) {
                    // Array lookup (O(1), no hash)
                    if (self.node.children[label]) |child| {
                        self.node = child;
                        if (self.node.is_leaf) {
                            return self.prefix_len;
                        }
                    } else {
                        // No match found
                        return null;
                    }
                } else {
                    // HashMap fallback for non-u8 labels
                    if (self.node.children.get(label)) |child| {
                        self.node = child;
                        if (self.node.is_leaf) {
                            return self.prefix_len;
                        }
                    } else {
                        // No match found
                        return null;
                    }
                }
            }
            return null;
        }
    };
}

/// Result from commonPrefixSearchWithIds: (prefix_length, token_id)
pub const PrefixMatch = struct {
    len: usize,
    id: u32,
};

/// Iterator that returns both prefix length and token ID
pub fn CommonPrefixIteratorWithIds(comptime Label: type) type {
    return struct {
        const Self = @This();
        const Node = Trie(Label).Node;

        node: *const Node,
        labels: []const Label,
        index: usize,
        prefix_len: usize,

        /// Returns (length, id) of next matching prefix, or null if none
        pub fn next(self: *Self) ?PrefixMatch {
            while (self.index < self.labels.len) {
                const label = self.labels[self.index];
                self.index += 1;
                self.prefix_len += 1;

                if (Label == u8) {
                    // Array lookup (O(1), no hash)
                    if (self.node.children[label]) |child| {
                        self.node = child;
                        if (self.node.is_leaf) {
                            return PrefixMatch{
                                .len = self.prefix_len,
                                .id = self.node.leaf_id,
                            };
                        }
                    } else {
                        // No match found
                        return null;
                    }
                } else {
                    // HashMap fallback for non-u8 labels
                    if (self.node.children.get(label)) |child| {
                        self.node = child;
                        if (self.node.is_leaf) {
                            return PrefixMatch{
                                .len = self.prefix_len,
                                .id = self.node.leaf_id,
                            };
                        }
                    } else {
                        // No match found
                        return null;
                    }
                }
            }
            return null;
        }
    };
}

/// Builder for constructing a Trie
pub fn TrieBuilder(comptime Label: type) type {
    return struct {
        const Self = @This();

        trie: Trie(Label),

        pub fn init(allocator: Allocator) !Self {
            return Self{
                .trie = try Trie(Label).init(allocator),
            };
        }

        pub fn push(self: *Self, element: []const Label) !void {
            try self.trie.push(element);
        }

        pub fn build(self: Self) Trie(Label) {
            return self.trie;
        }
    };
}

// Tests
test "Trie basic operations" {
    const allocator = std.testing.allocator;

    var trie = try Trie(u8).init(allocator);
    defer trie.deinit();

    // Insert some sequences
    try trie.push("hello");
    try trie.push("help");
    try trie.push("world");

    // Search for prefixes in "hello world"
    const text = "hello world";
    var iter = trie.commonPrefixSearch(text);

    // Should find "hello" at length 5
    const len1 = iter.next();
    try std.testing.expectEqual(@as(?usize, 5), len1);

    // No more matches in "hello"
    const len2 = iter.next();
    try std.testing.expectEqual(@as(?usize, null), len2);
}

test "Trie with no matches" {
    const allocator = std.testing.allocator;

    var trie = try Trie(u8).init(allocator);
    defer trie.deinit();

    try trie.push("hello");

    var iter = trie.commonPrefixSearch("goodbye");
    try std.testing.expectEqual(@as(?usize, null), iter.next());
}
