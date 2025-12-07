/// crossinterp - Cross-Interpreter Support
/// Mirrors cpython/Python/crossinterp.c
///
/// Support for communication between sub-interpreters (PEP 554).
/// Handles data sharing, channel-based communication, and interpreter isolation.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Interpreter ID
// ============================================================================

/// Unique identifier for an interpreter
pub const InterpID = i64;

/// Invalid interpreter ID
pub const INVALID_INTERP_ID: InterpID = -1;

/// Main interpreter ID
pub const MAIN_INTERP_ID: InterpID = 0;

// ============================================================================
// Cross-Interpreter Data
// ============================================================================

/// Types that can be shared across interpreters
pub const CrossInterpDataType = enum {
    /// None value
    none,
    /// Boolean value
    bool_val,
    /// Integer value
    int_val,
    /// Float value
    float_val,
    /// Bytes (immutable)
    bytes,
    /// String (immutable)
    str,
    /// Tuple of shareable items
    tuple,
    /// Exception info
    exception,
    /// Code object
    code,
    /// Memoryview
    memoryview,
};

/// Data that can be passed between interpreters
pub const CrossInterpData = struct {
    const Self = @This();

    /// Data type
    data_type: CrossInterpDataType,
    /// Raw data storage
    data: DataUnion,
    /// Allocator used
    allocator: Allocator,
    /// Whether data is owned
    owned: bool = true,

    const DataUnion = union {
        none: void,
        bool_val: bool,
        int_val: i64,
        float_val: f64,
        bytes: []const u8,
        str: []const u8,
        tuple: []Self,
        exception: ExceptionInfo,
        code: []const u8, // Serialized code
        memoryview: MemoryViewData,
    };

    pub fn initNone(allocator: Allocator) Self {
        return Self{
            .data_type = .none,
            .data = .{ .none = {} },
            .allocator = allocator,
        };
    }

    pub fn initInt(allocator: Allocator, value: i64) Self {
        return Self{
            .data_type = .int_val,
            .data = .{ .int_val = value },
            .allocator = allocator,
        };
    }

    pub fn initFloat(allocator: Allocator, value: f64) Self {
        return Self{
            .data_type = .float_val,
            .data = .{ .float_val = value },
            .allocator = allocator,
        };
    }

    pub fn initBytes(allocator: Allocator, bytes: []const u8) !Self {
        const owned = try allocator.dupe(u8, bytes);
        return Self{
            .data_type = .bytes,
            .data = .{ .bytes = owned },
            .allocator = allocator,
        };
    }

    pub fn initStr(allocator: Allocator, str: []const u8) !Self {
        const owned = try allocator.dupe(u8, str);
        return Self{
            .data_type = .str,
            .data = .{ .str = owned },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (!self.owned) return;

        switch (self.data_type) {
            .bytes => self.allocator.free(self.data.bytes),
            .str => self.allocator.free(self.data.str),
            .tuple => {
                for (self.data.tuple) |*item| {
                    item.deinit();
                }
                self.allocator.free(self.data.tuple);
            },
            .code => self.allocator.free(self.data.code),
            else => {},
        }
    }
};

/// Exception information for cross-interpreter transfer
pub const ExceptionInfo = struct {
    /// Exception type name
    type_name: []const u8,
    /// Exception message
    message: []const u8,
    /// Traceback (serialized)
    traceback: ?[]const u8 = null,
};

/// Memory view data for sharing buffers
pub const MemoryViewData = struct {
    /// Buffer pointer (must be managed carefully)
    ptr: [*]const u8,
    /// Buffer length
    len: usize,
    /// Item size
    itemsize: usize = 1,
    /// Format string
    format: []const u8 = "B",
    /// Is readonly
    readonly: bool = true,
};

// ============================================================================
// Channel
// ============================================================================

/// Channel for inter-interpreter communication
pub const Channel = struct {
    const Self = @This();

    /// Channel ID
    id: u64,
    /// Message queue
    queue: std.ArrayList(CrossInterpData),
    /// Mutex for thread safety
    mutex: std.Thread.Mutex = .{},
    /// Condition for blocking recv
    cond: std.Thread.Condition = .{},
    /// Is open for sending
    open: bool = true,
    /// Reference count
    refcount: u32 = 1,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator, id: u64) Self {
        return Self{
            .id = id,
            .queue = std.ArrayList(CrossInterpData).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.queue.items) |*item| {
            item.deinit();
        }
        self.queue.deinit();
    }

    /// Send data through the channel
    pub fn send(self: *Self, data: CrossInterpData) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.open) {
            return error.ChannelClosed;
        }

        try self.queue.append(data);
        self.cond.signal();
    }

    /// Receive data from the channel (blocking)
    pub fn recv(self: *Self) ?CrossInterpData {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.queue.items.len == 0 and self.open) {
            self.cond.wait(&self.mutex);
        }

        if (self.queue.items.len == 0) {
            return null;
        }

        return self.queue.orderedRemove(0);
    }

    /// Try to receive without blocking
    pub fn tryRecv(self: *Self) ?CrossInterpData {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.queue.items.len == 0) {
            return null;
        }

        return self.queue.orderedRemove(0);
    }

    /// Close the channel
    pub fn close(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.open = false;
        self.cond.broadcast();
    }

    /// Get queue length
    pub fn len(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.queue.items.len;
    }
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

        if (self.channels.fetchRemove(id)) |entry| {
            entry.value.deinit();
            self.allocator.destroy(entry.value);
        }
    }
};

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

        var ids = std.ArrayList(InterpID).init(allocator);
        var it = self.interpreters.iterator();
        while (it.next()) |entry| {
            try ids.append(entry.key_ptr.*);
        }
        return ids.toOwnedSlice();
    }
};

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var channel_registry: ?ChannelRegistry = null;
var interp_registry: ?InterpreterRegistry = null;

/// Initialize the crossinterp module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get channel registry
pub fn getChannelRegistry(allocator: Allocator) *ChannelRegistry {
    if (channel_registry == null) {
        channel_registry = ChannelRegistry.init(allocator);
    }
    return &channel_registry.?;
}

/// Get interpreter registry
pub fn getInterpRegistry(allocator: Allocator) *InterpreterRegistry {
    if (interp_registry == null) {
        interp_registry = InterpreterRegistry.init(allocator);
    }
    return &interp_registry.?;
}

/// Reset module state
pub fn reset() void {
    if (channel_registry) |*reg| {
        reg.deinit();
    }
    if (interp_registry) |*reg| {
        reg.deinit();
    }
    channel_registry = null;
    interp_registry = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "cross interp data int" {
    const allocator = std.testing.allocator;
    var data = CrossInterpData.initInt(allocator, 42);
    defer data.deinit();

    try std.testing.expectEqual(CrossInterpDataType.int_val, data.data_type);
    try std.testing.expectEqual(@as(i64, 42), data.data.int_val);
}

test "cross interp data str" {
    const allocator = std.testing.allocator;
    var data = try CrossInterpData.initStr(allocator, "hello");
    defer data.deinit();

    try std.testing.expectEqual(CrossInterpDataType.str, data.data_type);
    try std.testing.expectEqualStrings("hello", data.data.str);
}

test "channel" {
    const allocator = std.testing.allocator;
    var channel = Channel.init(allocator, 1);
    defer channel.deinit();

    const data = CrossInterpData.initInt(allocator, 42);
    try channel.send(data);

    try std.testing.expectEqual(@as(usize, 1), channel.len());

    const received = channel.tryRecv();
    try std.testing.expect(received != null);
    try std.testing.expectEqual(@as(i64, 42), received.?.data.int_val);
}

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
