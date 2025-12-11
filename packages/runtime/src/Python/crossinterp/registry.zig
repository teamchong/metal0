/// Registries for Channels and Interpreters
/// Thread-safe management of communication channels and interpreter states

const std = @import("std");
const Allocator = std.mem.Allocator;
const data_mod = @import("data.zig");
const channel_mod = @import("channel.zig");

const InterpID = data_mod.InterpID;
const MAIN_INTERP_ID = data_mod.MAIN_INTERP_ID;
const Channel = channel_mod.Channel;

// ============================================================================
// Interpreter State
// ============================================================================

/// State of a sub-interpreter
pub const InterpreterState = struct {
    /// Interpreter ID
    id: InterpID,
    /// Is the main interpreter
    is_main: bool = false,
    /// Is running
    running: bool = false,
    /// Associated thread (if any)
    thread: ?std.Thread.Id = null,
    /// Reference count
    refcount: u32 = 1,
};

// ============================================================================
// Channel Registry
// ============================================================================

/// Registry for all channels
pub const ChannelRegistry = struct {
    const Self = @This();

    /// All channels by ID
    channels: std.AutoHashMap(u64, *Channel),
    /// Next channel ID
    next_id: u64 = 1,
    /// Mutex
    mutex: std.Thread.Mutex = .{},
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .channels = std.AutoHashMap(u64, *Channel).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.channels.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.channels.deinit();
    }

    /// Create a new channel
    pub fn create(self: *Self) !*Channel {
        self.mutex.lock();
        defer self.mutex.unlock();

        const id = self.next_id;
        self.next_id += 1;

        const channel = try self.allocator.create(Channel);
        channel.* = Channel.init(self.allocator, id);

        try self.channels.put(id, channel);
        return channel;
    }

    /// Get a channel by ID
    pub fn get(self: *Self, id: u64) ?*Channel {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.channels.get(id);
    }

    /// Destroy a channel
    pub fn destroy(self: *Self, id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.channels.fetchSwapRemove(id)) |entry| {
            entry.value.deinit();
            self.allocator.destroy(entry.value);
        }
    }
};

// ============================================================================
// Interpreter Registry
// ============================================================================

/// Registry of all interpreters
pub const InterpreterRegistry = struct {
    const Self = @This();

    /// All interpreters
    interpreters: std.AutoHashMap(InterpID, InterpreterState),
    /// Next interpreter ID
    next_id: InterpID = 1,
    /// Mutex
    mutex: std.Thread.Mutex = .{},
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        var self = Self{
            .interpreters = std.AutoHashMap(InterpID, InterpreterState).init(allocator),
            .allocator = allocator,
        };

        // Register main interpreter
        self.interpreters.put(MAIN_INTERP_ID, InterpreterState{
            .id = MAIN_INTERP_ID,
            .is_main = true,
            .running = true,
        }) catch {};

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.interpreters.deinit();
    }

    /// Create a new interpreter
    pub fn create(self: *Self) !InterpID {
        self.mutex.lock();
        defer self.mutex.unlock();

        const id = self.next_id;
        self.next_id += 1;

        try self.interpreters.put(id, InterpreterState{
            .id = id,
        });

        return id;
    }

    /// Get interpreter state
    pub fn get(self: *Self, id: InterpID) ?InterpreterState {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.interpreters.get(id);
    }

    /// Destroy an interpreter
    pub fn destroy(self: *Self, id: InterpID) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Can't destroy main interpreter
        if (id == MAIN_INTERP_ID) {
            return false;
        }

        return self.interpreters.remove(id);
    }

    /// List all interpreter IDs
    pub fn list(self: *Self, allocator: Allocator) ![]InterpID {
        self.mutex.lock();
        defer self.mutex.unlock();

        var ids: std.ArrayList(InterpID) = .{};
        var it = self.interpreters.iterator();
        while (it.next()) |entry| {
            try ids.append(allocator, entry.key_ptr.*);
        }
        return ids.toOwnedSlice(allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "interpreter registry" {
    const allocator = std.testing.allocator;
    var registry = InterpreterRegistry.init(allocator);
    defer registry.deinit();

    // Main interpreter should exist
    const main = registry.get(MAIN_INTERP_ID);
    try std.testing.expect(main != null);
    try std.testing.expect(main.?.is_main);

    // Create sub-interpreter
    const id = try registry.create();
    try std.testing.expect(id > 0);

    const sub = registry.get(id);
    try std.testing.expect(sub != null);
    try std.testing.expect(!sub.?.is_main);
}

test "interpreter list" {
    const allocator = std.testing.allocator;
    var registry = InterpreterRegistry.init(allocator);
    defer registry.deinit();

    const ids = try registry.list(allocator);
    defer allocator.free(ids);

    try std.testing.expect(ids.len >= 1);
}
