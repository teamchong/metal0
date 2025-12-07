/// interpconfig - Interpreter Configuration
/// Mirrors cpython/Python/interpconfig.c
///
/// This module handles sub-interpreter configuration:
/// - Per-interpreter settings
/// - GIL configuration (shared vs per-interpreter)
/// - Import state per interpreter
/// - Cross-interpreter data sharing policies

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;

// ============================================================================
// GIL Configuration
// ============================================================================

/// GIL sharing mode
pub const GILMode = enum(i32) {
    /// Use shared GIL (default for main interpreter)
    shared = 0,
    /// Use own GIL (for sub-interpreters)
    own = 1,
    /// Default behavior (shared for main, own for sub)
    default = -1,

    pub fn isOwn(self: GILMode) bool {
        return self == .own;
    }

    pub fn isShared(self: GILMode) bool {
        return self == .shared;
    }
};

// ============================================================================
// Check Multi-Interp Extensions
// ============================================================================

/// How to handle extensions that don't support multiple interpreters
pub const CheckMultiInterpExtensions = enum(i32) {
    /// Default behavior
    default = -1,
    /// Allow single-phase init extensions
    low = 0,
    /// Require multi-phase init
    high = 1,
};

// ============================================================================
// Interpreter Configuration
// ============================================================================

/// Configuration for creating a sub-interpreter
pub const PyInterpreterConfig = struct {
    /// Use main interpreter's __main__ dict
    use_main_obmalloc: bool = false,

    /// Allow fork
    allow_fork: bool = true,

    /// Allow exec
    allow_exec: bool = true,

    /// Allow threads
    allow_threads: bool = true,

    /// Allow daemon threads
    allow_daemon_threads: bool = true,

    /// Check multi-interp extension compatibility
    check_multi_interp_extensions: CheckMultiInterpExtensions = .default,

    /// GIL mode
    gil: GILMode = .default,

    const Self = @This();

    /// Default configuration for sub-interpreter
    pub fn initDefault() Self {
        return .{};
    }

    /// Configuration for isolated sub-interpreter
    pub fn initIsolated() Self {
        return .{
            .use_main_obmalloc = false,
            .allow_fork = false,
            .allow_exec = false,
            .allow_threads = true,
            .allow_daemon_threads = false,
            .check_multi_interp_extensions = .high,
            .gil = .own,
        };
    }

    /// Configuration for legacy sub-interpreter (shared GIL)
    pub fn initLegacy() Self {
        return .{
            .use_main_obmalloc = true,
            .allow_fork = true,
            .allow_exec = true,
            .allow_threads = true,
            .allow_daemon_threads = true,
            .check_multi_interp_extensions = .low,
            .gil = .shared,
        };
    }

    /// Copy configuration
    pub fn copy(self: *const Self) Self {
        return self.*;
    }

    /// Validate configuration
    pub fn validate(self: *const Self) !void {
        // Can't have daemon threads without threads
        if (self.allow_daemon_threads and !self.allow_threads) {
            return error.InvalidConfig;
        }

        // Own GIL requires not using main obmalloc
        if (self.gil == .own and self.use_main_obmalloc) {
            return error.InvalidConfig;
        }
    }
};

// ============================================================================
// Interpreter State (simplified)
// ============================================================================

/// Unique identifier for an interpreter
pub const InterpId = u64;

/// Simple interpreter state for configuration
pub const InterpreterState = struct {
    /// Unique ID
    id: InterpId,

    /// Configuration used to create this interpreter
    config: PyInterpreterConfig,

    /// Whether this is the main interpreter
    is_main: bool,

    /// Whether interpreter is finalized
    finalized: bool,

    /// Reference count (for management)
    refcount: Atomic(u32),

    /// Next interpreter in list
    next: ?*InterpreterState,

    /// Previous interpreter in list
    prev: ?*InterpreterState,

    const Self = @This();

    /// Create a new interpreter state
    pub fn create(id: InterpId, config: PyInterpreterConfig, is_main: bool) Self {
        return .{
            .id = id,
            .config = config,
            .is_main = is_main,
            .finalized = false,
            .refcount = Atomic(u32).init(1),
            .next = null,
            .prev = null,
        };
    }

    /// Check if interpreter uses own GIL
    pub fn hasOwnGil(self: *const Self) bool {
        return self.config.gil == .own or
            (self.config.gil == .default and !self.is_main);
    }

    /// Check if threads are allowed
    pub fn allowsThreads(self: *const Self) bool {
        return self.config.allow_threads;
    }

    /// Increment reference count
    pub fn incref(self: *Self) void {
        _ = self.refcount.fetchAdd(1, .release);
    }

    /// Decrement reference count
    pub fn decref(self: *Self) u32 {
        return self.refcount.fetchSub(1, .release) - 1;
    }
};

// ============================================================================
// Interpreter Manager
// ============================================================================

/// Manages multiple interpreters
pub const InterpreterManager = struct {
    /// Head of interpreter list
    head: ?*InterpreterState,
    /// Main interpreter
    main: ?*InterpreterState,
    /// Next interpreter ID
    next_id: Atomic(u64),
    /// Lock for list operations
    lock: std.Thread.Mutex,
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .head = null,
            .main = null,
            .next_id = Atomic(u64).init(1),
            .lock = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.lock.lock();
        defer self.lock.unlock();

        var current = self.head;
        while (current) |interp| {
            const next = interp.next;
            self.allocator.destroy(interp);
            current = next;
        }
        self.head = null;
        self.main = null;
    }

    /// Create main interpreter
    pub fn createMain(self: *Self) !*InterpreterState {
        self.lock.lock();
        defer self.lock.unlock();

        if (self.main != null) {
            return error.MainAlreadyExists;
        }

        const config = PyInterpreterConfig.initLegacy();
        const interp = try self.allocator.create(InterpreterState);
        interp.* = InterpreterState.create(0, config, true);

        self.head = interp;
        self.main = interp;

        return interp;
    }

    /// Create sub-interpreter
    pub fn createSubInterpreter(self: *Self, config: PyInterpreterConfig) !*InterpreterState {
        try config.validate();

        self.lock.lock();
        defer self.lock.unlock();

        const id = self.next_id.fetchAdd(1, .monotonic);
        const interp = try self.allocator.create(InterpreterState);
        interp.* = InterpreterState.create(id, config, false);

        // Add to list
        interp.next = self.head;
        if (self.head) |head| {
            head.prev = interp;
        }
        self.head = interp;

        return interp;
    }

    /// Destroy interpreter
    pub fn destroyInterpreter(self: *Self, interp: *InterpreterState) !void {
        if (interp.is_main) {
            return error.CannotDestroyMain;
        }

        self.lock.lock();
        defer self.lock.unlock();

        // Remove from list
        if (interp.prev) |prev| {
            prev.next = interp.next;
        } else {
            self.head = interp.next;
        }
        if (interp.next) |next| {
            next.prev = interp.prev;
        }

        interp.finalized = true;
        if (interp.decref() == 0) {
            self.allocator.destroy(interp);
        }
    }

    /// Get interpreter by ID
    pub fn getById(self: *Self, id: InterpId) ?*InterpreterState {
        self.lock.lock();
        defer self.lock.unlock();

        var current = self.head;
        while (current) |interp| {
            if (interp.id == id) {
                return interp;
            }
            current = interp.next;
        }
        return null;
    }

    /// Get interpreter count
    pub fn count(self: *Self) usize {
        self.lock.lock();
        defer self.lock.unlock();

        var n: usize = 0;
        var current = self.head;
        while (current) |interp| {
            n += 1;
            current = interp.next;
        }
        return n;
    }

    /// Get main interpreter
    pub fn getMain(self: *Self) ?*InterpreterState {
        return self.main;
    }
};

// ============================================================================
// Cross-Interpreter Data
// ============================================================================

/// Types that can be shared between interpreters
pub const CrossInterpDataType = enum {
    none,
    bool_type,
    int_type,
    float_type,
    bytes_type,
    str_type,
    tuple_type,

    pub fn isShareable(self: CrossInterpDataType) bool {
        return self != .none;
    }
};

/// Cross-interpreter data container
pub const CrossInterpData = struct {
    /// Data type
    data_type: CrossInterpDataType,
    /// Data storage (type-dependent)
    data: union {
        bool_val: bool,
        int_val: i64,
        float_val: f64,
        bytes_val: []const u8,
        str_val: []const u8,
    },
    /// Whether data is owned
    owned: bool,

    const Self = @This();

    pub fn initNone() Self {
        return .{
            .data_type = .none,
            .data = undefined,
            .owned = false,
        };
    }

    pub fn initBool(val: bool) Self {
        return .{
            .data_type = .bool_type,
            .data = .{ .bool_val = val },
            .owned = false,
        };
    }

    pub fn initInt(val: i64) Self {
        return .{
            .data_type = .int_type,
            .data = .{ .int_val = val },
            .owned = false,
        };
    }

    pub fn initFloat(val: f64) Self {
        return .{
            .data_type = .float_type,
            .data = .{ .float_val = val },
            .owned = false,
        };
    }

    pub fn initStr(val: []const u8, owned: bool) Self {
        return .{
            .data_type = .str_type,
            .data = .{ .str_val = val },
            .owned = owned,
        };
    }
};

// ============================================================================
// Global Manager
// ============================================================================

var g_manager: ?InterpreterManager = null;

/// Get or create global interpreter manager
pub fn getManager(allocator: Allocator) *InterpreterManager {
    if (g_manager == null) {
        g_manager = InterpreterManager.init(allocator);
    }
    return &g_manager.?;
}

/// Deinitialize global manager
pub fn deinitManager() void {
    if (g_manager) |*manager| {
        manager.deinit();
        g_manager = null;
    }
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "interpreter config defaults" {
    const config = PyInterpreterConfig.initDefault();
    try std.testing.expect(!config.use_main_obmalloc);
    try std.testing.expect(config.allow_fork);
    try std.testing.expect(config.allow_threads);
    try std.testing.expectEqual(GILMode.default, config.gil);
}

test "interpreter config isolated" {
    const config = PyInterpreterConfig.initIsolated();
    try std.testing.expect(!config.allow_fork);
    try std.testing.expect(!config.allow_exec);
    try std.testing.expect(!config.allow_daemon_threads);
    try std.testing.expectEqual(GILMode.own, config.gil);
}

test "interpreter config legacy" {
    const config = PyInterpreterConfig.initLegacy();
    try std.testing.expect(config.use_main_obmalloc);
    try std.testing.expect(config.allow_fork);
    try std.testing.expect(config.allow_daemon_threads);
    try std.testing.expectEqual(GILMode.shared, config.gil);
}

test "interpreter config validation" {
    // Invalid: daemon threads without threads
    var config1 = PyInterpreterConfig.initDefault();
    config1.allow_threads = false;
    config1.allow_daemon_threads = true;
    try std.testing.expectError(error.InvalidConfig, config1.validate());

    // Invalid: own GIL with main obmalloc
    var config2 = PyInterpreterConfig.initDefault();
    config2.gil = .own;
    config2.use_main_obmalloc = true;
    try std.testing.expectError(error.InvalidConfig, config2.validate());

    // Valid config
    const config3 = PyInterpreterConfig.initIsolated();
    try config3.validate();
}

test "interpreter state basics" {
    const config = PyInterpreterConfig.initDefault();
    var state = InterpreterState.create(42, config, false);

    try std.testing.expectEqual(@as(u64, 42), state.id);
    try std.testing.expect(!state.is_main);
    try std.testing.expect(!state.finalized);
}

test "interpreter manager" {
    var manager = InterpreterManager.init(std.testing.allocator);
    defer manager.deinit();

    // Create main
    const main_interp = try manager.createMain();
    try std.testing.expect(main_interp.is_main);
    try std.testing.expectEqual(@as(usize, 1), manager.count());

    // Create sub-interpreter
    const config = PyInterpreterConfig.initIsolated();
    const sub = try manager.createSubInterpreter(config);
    try std.testing.expect(!sub.is_main);
    try std.testing.expect(sub.id > 0);
    try std.testing.expectEqual(@as(usize, 2), manager.count());

    // Get by ID
    const found = manager.getById(sub.id);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(sub.id, found.?.id);

    // Destroy sub
    try manager.destroyInterpreter(sub);
    try std.testing.expectEqual(@as(usize, 1), manager.count());

    // Can't destroy main
    try std.testing.expectError(error.CannotDestroyMain, manager.destroyInterpreter(main_interp));
}

test "cross interp data" {
    const none = CrossInterpData.initNone();
    try std.testing.expect(!none.data_type.isShareable());

    const int_data = CrossInterpData.initInt(42);
    try std.testing.expect(int_data.data_type.isShareable());
    try std.testing.expectEqual(@as(i64, 42), int_data.data.int_val);

    const str_data = CrossInterpData.initStr("hello", false);
    try std.testing.expectEqual(CrossInterpDataType.str_type, str_data.data_type);
    try std.testing.expectEqualStrings("hello", str_data.data.str_val);
}
