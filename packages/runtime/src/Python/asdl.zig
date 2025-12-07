/// asdl - Abstract Syntax Description Language
/// Mirrors cpython/Python/asdl.c
///
/// ASDL (Abstract Syntax Definition Language) is used to define the abstract
/// syntax tree structure for Python. This module provides sequence and integer
/// support for ASDL-generated code.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// ASDL Sequence Types
// ============================================================================

/// Generic ASDL sequence - a dynamic array of elements
pub fn AsdlSeq(comptime T: type) type {
    return struct {
        const Self = @This();

        elements: []T,
        size: usize,
        allocator: Allocator,

        /// Create a new empty sequence
        pub fn init(allocator: Allocator) Self {
            return Self{
                .elements = &[_]T{},
                .size = 0,
                .allocator = allocator,
            };
        }

        /// Create a sequence with pre-allocated capacity
        pub fn initCapacity(allocator: Allocator, capacity: usize) !Self {
            const elements = try allocator.alloc(T, capacity);
            return Self{
                .elements = elements,
                .size = 0,
                .allocator = allocator,
            };
        }

        /// Free the sequence
        pub fn deinit(self: *Self) void {
            if (self.elements.len > 0) {
                self.allocator.free(self.elements);
            }
            self.elements = &[_]T{};
            self.size = 0;
        }

        /// Get element at index
        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= self.size) return null;
            return self.elements[index];
        }

        /// Set element at index
        pub fn set(self: *Self, index: usize, value: T) !void {
            if (index >= self.elements.len) {
                return error.IndexOutOfBounds;
            }
            self.elements[index] = value;
            if (index >= self.size) {
                self.size = index + 1;
            }
        }

        /// Append element to sequence
        pub fn append(self: *Self, value: T) !void {
            if (self.size >= self.elements.len) {
                // Grow the array
                const new_cap = if (self.elements.len == 0) 4 else self.elements.len * 2;
                const new_elements = try self.allocator.realloc(self.elements, new_cap);
                self.elements = new_elements;
            }
            self.elements[self.size] = value;
            self.size += 1;
        }

        /// Get number of elements
        pub fn len(self: *const Self) usize {
            return self.size;
        }

        /// Check if empty
        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        /// Iterate over elements
        pub fn iterator(self: *const Self) Iterator {
            return Iterator{ .seq = self, .index = 0 };
        }

        pub const Iterator = struct {
            seq: *const Self,
            index: usize,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.seq.size) return null;
                const value = self.seq.elements[self.index];
                self.index += 1;
                return value;
            }
        };
    };
}

/// ASDL integer sequence (optimized for integers)
pub const AsdlIntSeq = struct {
    const Self = @This();

    data: []i64,
    size: usize,
    allocator: Allocator,

    /// Create empty integer sequence
    pub fn init(allocator: Allocator) Self {
        return Self{
            .data = &[_]i64{},
            .size = 0,
            .allocator = allocator,
        };
    }

    /// Create with capacity
    pub fn initCapacity(allocator: Allocator, capacity: usize) !Self {
        const data = try allocator.alloc(i64, capacity);
        return Self{
            .data = data,
            .size = 0,
            .allocator = allocator,
        };
    }

    /// Free the sequence
    pub fn deinit(self: *Self) void {
        if (self.data.len > 0) {
            self.allocator.free(self.data);
        }
        self.data = &[_]i64{};
        self.size = 0;
    }

    /// Get integer at index
    pub fn get(self: *const Self, index: usize) ?i64 {
        if (index >= self.size) return null;
        return self.data[index];
    }

    /// Set integer at index
    pub fn set(self: *Self, index: usize, value: i64) !void {
        if (index >= self.data.len) {
            return error.IndexOutOfBounds;
        }
        self.data[index] = value;
        if (index >= self.size) {
            self.size = index + 1;
        }
    }

    /// Append integer
    pub fn append(self: *Self, value: i64) !void {
        if (self.size >= self.data.len) {
            const new_cap = if (self.data.len == 0) 8 else self.data.len * 2;
            const new_data = try self.allocator.realloc(self.data, new_cap);
            self.data = new_data;
        }
        self.data[self.size] = value;
        self.size += 1;
    }

    /// Get length
    pub fn len(self: *const Self) usize {
        return self.size;
    }
};

// ============================================================================
// ASDL Node Types
// ============================================================================

/// Base ASDL node with source location
pub const AsdlNode = struct {
    /// Line number (1-indexed)
    lineno: i32 = 0,
    /// Column offset (0-indexed)
    col_offset: i32 = 0,
    /// End line number
    end_lineno: i32 = 0,
    /// End column offset
    end_col_offset: i32 = 0,
};

/// ASDL identifier (interned string)
pub const AsdlIdentifier = struct {
    value: []const u8,

    pub fn init(value: []const u8) AsdlIdentifier {
        return .{ .value = value };
    }

    pub fn eql(self: AsdlIdentifier, other: AsdlIdentifier) bool {
        return std.mem.eql(u8, self.value, other.value);
    }

    pub fn hash(self: AsdlIdentifier) u64 {
        return std.hash.Wyhash.hash(0, self.value);
    }
};

/// ASDL constant value
pub const AsdlConstant = union(enum) {
    none: void,
    ellipsis: void,
    boolean: bool,
    integer: i64,
    float: f64,
    complex: struct { real: f64, imag: f64 },
    string: []const u8,
    bytes: []const u8,

    pub fn isNone(self: AsdlConstant) bool {
        return self == .none;
    }

    pub fn isTruthy(self: AsdlConstant) bool {
        return switch (self) {
            .none, .ellipsis => false,
            .boolean => |b| b,
            .integer => |i| i != 0,
            .float => |f| f != 0.0,
            .complex => |c| c.real != 0.0 or c.imag != 0.0,
            .string => |s| s.len > 0,
            .bytes => |b| b.len > 0,
        };
    }
};

// ============================================================================
// ASDL Arena Allocator
// ============================================================================

/// Arena for ASDL node allocation
/// All nodes allocated from the arena are freed together
pub const AsdlArena = struct {
    const Self = @This();

    allocator: Allocator,
    arena: std.heap.ArenaAllocator,

    /// Create a new arena
    pub fn init(backing_allocator: Allocator) Self {
        return Self{
            .allocator = backing_allocator,
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
        };
    }

    /// Free all arena memory
    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    /// Get arena allocator
    pub fn getAllocator(self: *Self) Allocator {
        return self.arena.allocator();
    }

    /// Allocate memory from arena
    pub fn alloc(self: *Self, comptime T: type, n: usize) ![]T {
        return self.arena.allocator().alloc(T, n);
    }

    /// Create single item in arena
    pub fn create(self: *Self, comptime T: type) !*T {
        return self.arena.allocator().create(T);
    }

    /// Duplicate string into arena
    pub fn dupe(self: *Self, bytes: []const u8) ![]u8 {
        return self.arena.allocator().dupe(u8, bytes);
    }
};

// ============================================================================
// ASDL Visitor Pattern
// ============================================================================

/// Generic visitor for ASDL nodes
pub fn AsdlVisitor(comptime NodeType: type, comptime ResultType: type) type {
    return struct {
        const Self = @This();

        visitFn: *const fn (*Self, NodeType) ResultType,

        pub fn visit(self: *Self, node: NodeType) ResultType {
            return self.visitFn(self, node);
        }
    };
}

/// Transformer that modifies nodes
pub fn AsdlTransformer(comptime NodeType: type) type {
    return struct {
        const Self = @This();

        transformFn: *const fn (*Self, NodeType) ?NodeType,

        pub fn transform(self: *Self, node: NodeType) ?NodeType {
            return self.transformFn(self, node);
        }
    };
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Compare two ASDL sequences for equality
pub fn seqEqual(comptime T: type, a: *const AsdlSeq(T), b: *const AsdlSeq(T), eqlFn: *const fn (T, T) bool) bool {
    if (a.size != b.size) return false;
    for (0..a.size) |i| {
        if (!eqlFn(a.elements[i], b.elements[i])) return false;
    }
    return true;
}

/// Copy sequence to new allocator
pub fn seqCopy(comptime T: type, seq: *const AsdlSeq(T), allocator: Allocator) !AsdlSeq(T) {
    var new_seq = try AsdlSeq(T).initCapacity(allocator, seq.size);
    for (0..seq.size) |i| {
        try new_seq.set(i, seq.elements[i]);
    }
    return new_seq;
}

/// Concatenate two sequences
pub fn seqConcat(comptime T: type, a: *const AsdlSeq(T), b: *const AsdlSeq(T), allocator: Allocator) !AsdlSeq(T) {
    var new_seq = try AsdlSeq(T).initCapacity(allocator, a.size + b.size);
    for (0..a.size) |i| {
        try new_seq.set(i, a.elements[i]);
    }
    for (0..b.size) |i| {
        try new_seq.set(a.size + i, b.elements[i]);
    }
    return new_seq;
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the ASDL module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "AsdlSeq basic operations" {
    const allocator = std.testing.allocator;

    var seq = try AsdlSeq(i32).initCapacity(allocator, 4);
    defer seq.deinit();

    try seq.append(1);
    try seq.append(2);
    try seq.append(3);

    try std.testing.expectEqual(@as(usize, 3), seq.len());
    try std.testing.expectEqual(@as(i32, 1), seq.get(0).?);
    try std.testing.expectEqual(@as(i32, 2), seq.get(1).?);
    try std.testing.expectEqual(@as(i32, 3), seq.get(2).?);
    try std.testing.expect(seq.get(3) == null);
}

test "AsdlIntSeq operations" {
    const allocator = std.testing.allocator;

    var seq = try AsdlIntSeq.initCapacity(allocator, 2);
    defer seq.deinit();

    try seq.append(100);
    try seq.append(200);
    try seq.append(300); // Should grow

    try std.testing.expectEqual(@as(usize, 3), seq.len());
    try std.testing.expectEqual(@as(i64, 100), seq.get(0).?);
    try std.testing.expectEqual(@as(i64, 300), seq.get(2).?);
}

test "AsdlIdentifier equality" {
    const id1 = AsdlIdentifier.init("foo");
    const id2 = AsdlIdentifier.init("foo");
    const id3 = AsdlIdentifier.init("bar");

    try std.testing.expect(id1.eql(id2));
    try std.testing.expect(!id1.eql(id3));
}

test "AsdlConstant truthiness" {
    try std.testing.expect(!AsdlConstant.none.isTruthy());
    try std.testing.expect(AsdlConstant{ .boolean = true }.isTruthy());
    try std.testing.expect(!AsdlConstant{ .boolean = false }.isTruthy());
    try std.testing.expect(AsdlConstant{ .integer = 42 }.isTruthy());
    try std.testing.expect(!AsdlConstant{ .integer = 0 }.isTruthy());
    try std.testing.expect(AsdlConstant{ .string = "hello" }.isTruthy());
    try std.testing.expect(!AsdlConstant{ .string = "" }.isTruthy());
}

test "AsdlArena allocation" {
    var arena = AsdlArena.init(std.testing.allocator);
    defer arena.deinit();

    const str = try arena.dupe("hello");
    try std.testing.expectEqualStrings("hello", str);

    const node = try arena.create(AsdlNode);
    node.lineno = 42;
    try std.testing.expectEqual(@as(i32, 42), node.lineno);
}

test "sequence iteration" {
    const allocator = std.testing.allocator;

    var seq = try AsdlSeq(i32).initCapacity(allocator, 4);
    defer seq.deinit();

    try seq.append(10);
    try seq.append(20);
    try seq.append(30);

    var iter = seq.iterator();
    var sum: i32 = 0;
    while (iter.next()) |val| {
        sum += val;
    }
    try std.testing.expectEqual(@as(i32, 60), sum);
}
