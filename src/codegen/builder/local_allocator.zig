/// LocalAllocator - Local variable pool with type-based reuse
///
/// Inspired by Zig's C backend LocalsMap pattern:
/// - Track local variables by type
/// - Reuse locals when they go out of scope
/// - Reduce variable declarations for cleaner output
/// - Better register allocation hints for backend
///
/// Key insight: Many temporaries have the same type (i64, f64, etc.)
/// By reusing locals of the same type, we reduce declaration count
/// and produce cleaner generated code.
///
const std = @import("std");
const Allocator = std.mem.Allocator;
const ZigType = @import("zig_type.zig").ZigType;
const LocalIndex = @import("zig_value.zig").LocalIndex;

/// Information about a single local variable
pub const Local = struct {
    /// Unique index
    index: LocalIndex,

    /// Type of this local
    type_: ZigType,

    /// Generated name (e.g., "__m0_t", "t0", etc.)
    name: []const u8,

    /// Is this local currently in use?
    in_use: bool,

    /// Scope depth where this was allocated
    scope_depth: u32,

    /// Was this local ever assigned?
    was_assigned: bool,
};

/// Pool of local variables with type-based reuse
pub const LocalAllocator = struct {
    allocator: Allocator,

    /// All allocated locals (Zig 0.15: ArrayList is empty struct)
    locals: std.ArrayList(Local),

    /// Free lists by type (type string -> list of free local indices)
    /// Using string keys because ZigType is a union and needs custom hashing
    free_by_type: std.StringHashMap(std.ArrayList(LocalIndex)),

    /// Current scope depth
    scope_depth: u32,

    /// Counter for unique names
    name_counter: usize,

    /// Name prefix (default: "__m")
    name_prefix: []const u8,

    /// Initialize the allocator
    pub fn init(allocator: Allocator) LocalAllocator {
        return .{
            .allocator = allocator,
            // Zig 0.15: empty ArrayList struct
            .locals = .{},
            .free_by_type = std.StringHashMap(std.ArrayList(LocalIndex)).init(allocator),
            .scope_depth = 0,
            .name_counter = 0,
            .name_prefix = "__m",
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *LocalAllocator) void {
        // Free all local names
        for (self.locals.items) |local| {
            self.allocator.free(local.name);
        }
        // Zig 0.15: pass allocator to deinit
        self.locals.deinit(self.allocator);

        // Free free lists and their keys
        var it = self.free_by_type.iterator();
        while (it.next()) |entry| {
            // Free the key (type string)
            self.allocator.free(entry.key_ptr.*);
            // Free the ArrayList
            entry.value_ptr.deinit(self.allocator);
        }
        self.free_by_type.deinit();
    }

    /// Allocate a local of the given type
    /// Reuses existing locals if available
    pub fn alloc(self: *LocalAllocator, type_: ZigType) !LocalIndex {
        const type_key = try self.typeKey(type_);
        defer self.allocator.free(type_key);

        // Try to reuse an existing free local
        if (self.free_by_type.getPtr(type_key)) |free_list| {
            // Zig 0.15: pop() returns ?T
            if (free_list.pop()) |idx| {
                self.locals.items[idx].in_use = true;
                self.locals.items[idx].scope_depth = self.scope_depth;
                return idx;
            }
        }

        // Allocate new local
        const idx: LocalIndex = @intCast(self.locals.items.len);
        const name = try self.generateName();

        // Zig 0.15: pass allocator to append
        try self.locals.append(self.allocator, .{
            .index = idx,
            .type_ = type_,
            .name = name,
            .in_use = true,
            .scope_depth = self.scope_depth,
            .was_assigned = false,
        });

        return idx;
    }

    /// Allocate a local with a specific name (no reuse)
    pub fn allocNamed(self: *LocalAllocator, type_: ZigType, name: []const u8) !LocalIndex {
        const idx: LocalIndex = @intCast(self.locals.items.len);
        const owned_name = try self.allocator.dupe(u8, name);

        // Zig 0.15: pass allocator to append
        try self.locals.append(self.allocator, .{
            .index = idx,
            .type_ = type_,
            .name = owned_name,
            .in_use = true,
            .scope_depth = self.scope_depth,
            .was_assigned = false,
        });

        return idx;
    }

    /// Free a local for reuse
    pub fn free(self: *LocalAllocator, idx: LocalIndex) !void {
        if (idx >= self.locals.items.len) return;

        var local = &self.locals.items[idx];
        if (!local.in_use) return; // Already free

        local.in_use = false;
        local.was_assigned = false;

        // Add to free list
        const type_key = try self.typeKey(local.type_);
        const gop = try self.free_by_type.getOrPut(type_key);
        if (gop.found_existing) {
            // Key already exists, free the duplicate we just allocated
            self.allocator.free(type_key);
        } else {
            // New entry, key is now owned by the HashMap
            gop.value_ptr.* = .{};
        }
        // Zig 0.15: pass allocator to append
        try gop.value_ptr.append(self.allocator, idx);
    }

    /// Get local by index
    pub fn get(self: *LocalAllocator, idx: LocalIndex) ?*const Local {
        if (idx >= self.locals.items.len) return null;
        return &self.locals.items[idx];
    }

    /// Get mutable local by index
    pub fn getMut(self: *LocalAllocator, idx: LocalIndex) ?*Local {
        if (idx >= self.locals.items.len) return null;
        return &self.locals.items[idx];
    }

    /// Get the name of a local
    pub fn getName(self: *LocalAllocator, idx: LocalIndex) ?[]const u8 {
        if (idx >= self.locals.items.len) return null;
        return self.locals.items[idx].name;
    }

    /// Get the type of a local
    pub fn getType(self: *LocalAllocator, idx: LocalIndex) ?ZigType {
        if (idx >= self.locals.items.len) return null;
        return self.locals.items[idx].type_;
    }

    /// Mark a local as assigned
    pub fn markAssigned(self: *LocalAllocator, idx: LocalIndex) void {
        if (idx < self.locals.items.len) {
            self.locals.items[idx].was_assigned = true;
        }
    }

    /// Enter a new scope
    pub fn enterScope(self: *LocalAllocator) u32 {
        self.scope_depth += 1;
        return self.scope_depth;
    }

    /// Exit current scope and free locals
    pub fn exitScope(self: *LocalAllocator) !void {
        if (self.scope_depth == 0) return;

        // Free all locals allocated in this scope
        for (self.locals.items, 0..) |*local, idx| {
            if (local.in_use and local.scope_depth == self.scope_depth) {
                try self.free(@intCast(idx));
            }
        }

        self.scope_depth -= 1;
    }

    /// Get count of active (in-use) locals
    pub fn activeCount(self: *LocalAllocator) usize {
        var count: usize = 0;
        for (self.locals.items) |local| {
            if (local.in_use) count += 1;
        }
        return count;
    }

    /// Get total allocated locals (for declaration emission)
    pub fn totalCount(self: *LocalAllocator) usize {
        return self.locals.items.len;
    }

    /// Get all locals that need declaration
    /// Returns locals that were assigned at least once
    pub fn getDeclarations(self: *LocalAllocator) []const Local {
        // For now, return all locals
        // TODO: Filter to only those that were actually used
        return self.locals.items;
    }

    /// Reset the allocator (clear all locals)
    pub fn reset(self: *LocalAllocator) void {
        for (self.locals.items) |local| {
            self.allocator.free(local.name);
        }
        self.locals.clearRetainingCapacity();

        var it = self.free_by_type.valueIterator();
        while (it.next()) |list| {
            list.clearRetainingCapacity();
        }

        self.scope_depth = 0;
        self.name_counter = 0;
    }

    // ============================================
    // Private helpers
    // ============================================

    fn generateName(self: *LocalAllocator) ![]const u8 {
        const id = self.name_counter;
        self.name_counter += 1;
        return std.fmt.allocPrint(self.allocator, "{s}{d}_t", .{ self.name_prefix, id });
    }

    fn typeKey(self: *LocalAllocator, type_: ZigType) ![]const u8 {
        // Generate a canonical string key for the type
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try type_.emit(buf.writer(self.allocator));
        return try self.allocator.dupe(u8, buf.items);
    }
};

/// Statistics about local allocation
pub const LocalStats = struct {
    total_allocated: usize,
    currently_in_use: usize,
    reuse_count: usize,
    types_tracked: usize,
};

// ============================================
// Tests
// ============================================

test "LocalAllocator basic allocation" {
    var alloc = LocalAllocator.init(std.testing.allocator);
    defer alloc.deinit();

    const idx1 = try alloc.alloc(.i64);
    try std.testing.expectEqual(@as(LocalIndex, 0), idx1);
    try std.testing.expectEqualStrings("__m0_t", alloc.getName(idx1).?);

    const idx2 = try alloc.alloc(.f64);
    try std.testing.expectEqual(@as(LocalIndex, 1), idx2);
    try std.testing.expectEqualStrings("__m1_t", alloc.getName(idx2).?);

    try std.testing.expectEqual(@as(usize, 2), alloc.activeCount());
}

test "LocalAllocator reuse" {
    var alloc = LocalAllocator.init(std.testing.allocator);
    defer alloc.deinit();

    // Allocate an i64
    const idx1 = try alloc.alloc(.i64);
    try std.testing.expectEqual(@as(LocalIndex, 0), idx1);

    // Free it
    try alloc.free(idx1);
    try std.testing.expectEqual(@as(usize, 0), alloc.activeCount());

    // Allocate another i64 - should reuse
    const idx2 = try alloc.alloc(.i64);
    try std.testing.expectEqual(@as(LocalIndex, 0), idx2); // Same index!

    // Allocate f64 - should be new
    const idx3 = try alloc.alloc(.f64);
    try std.testing.expectEqual(@as(LocalIndex, 1), idx3);
}

test "LocalAllocator named allocation" {
    var alloc = LocalAllocator.init(std.testing.allocator);
    defer alloc.deinit();

    const idx = try alloc.allocNamed(.i64, "my_var");
    try std.testing.expectEqualStrings("my_var", alloc.getName(idx).?);

    const local_type = alloc.getType(idx).?;
    try std.testing.expect(local_type == .i64);
}

test "LocalAllocator scope management" {
    var alloc = LocalAllocator.init(std.testing.allocator);
    defer alloc.deinit();

    // Allocate in outer scope
    const outer = try alloc.alloc(.i64);
    _ = outer;

    // Enter inner scope
    _ = alloc.enterScope();
    const inner = try alloc.alloc(.f64);
    _ = inner;
    try std.testing.expectEqual(@as(usize, 2), alloc.activeCount());

    // Exit inner scope - inner local freed
    try alloc.exitScope();
    try std.testing.expectEqual(@as(usize, 1), alloc.activeCount());
}

test "LocalAllocator mark assigned" {
    var alloc = LocalAllocator.init(std.testing.allocator);
    defer alloc.deinit();

    const idx = try alloc.alloc(.i64);
    try std.testing.expect(!alloc.get(idx).?.was_assigned);

    alloc.markAssigned(idx);
    try std.testing.expect(alloc.get(idx).?.was_assigned);
}

test "LocalAllocator reset" {
    var alloc = LocalAllocator.init(std.testing.allocator);
    defer alloc.deinit();

    _ = try alloc.alloc(.i64);
    _ = try alloc.alloc(.f64);
    try std.testing.expectEqual(@as(usize, 2), alloc.totalCount());

    alloc.reset();
    try std.testing.expectEqual(@as(usize, 0), alloc.totalCount());
    try std.testing.expectEqual(@as(u32, 0), alloc.scope_depth);
}
