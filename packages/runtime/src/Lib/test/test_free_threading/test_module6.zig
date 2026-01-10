//! test.test_free_threading.test_imports - Concurrent imports
//!
//! This module tests concurrent module import behavior in free-threaded Python.
//! It provides a thread-safe module registry and tests for import races.
const std = @import("std");

/// Module state for import tracking
pub const ModuleState = enum(u8) {
    not_loaded,
    loading,
    loaded,
    failed,
};

/// Module entry in the registry
pub const ModuleEntry = struct {
    name: []const u8,
    state: std.atomic.Value(u8),
    loader_thread: std.atomic.Value(usize),
    init_count: std.atomic.Value(usize),
    error_message: ?[]const u8,
    data: ?*anyopaque,

    pub fn init(name: []const u8) ModuleEntry {
        return .{
            .name = name,
            .state = std.atomic.Value(u8).init(@intFromEnum(ModuleState.not_loaded)),
            .loader_thread = std.atomic.Value(usize).init(0),
            .init_count = std.atomic.Value(usize).init(0),
            .error_message = null,
            .data = null,
        };
    }

    pub fn getState(self: *const ModuleEntry) ModuleState {
        return @enumFromInt(self.state.load(.acquire));
    }

    pub fn setState(self: *ModuleEntry, state: ModuleState) void {
        self.state.store(@intFromEnum(state), .release);
    }

    pub fn isLoaded(self: *const ModuleEntry) bool {
        return self.getState() == .loaded;
    }

    pub fn isLoading(self: *const ModuleEntry) bool {
        return self.getState() == .loading;
    }
};

/// Thread-safe module registry
pub const ModuleRegistry = struct {
    const Self = @This();

    modules: std.StringHashMap(ModuleEntry),
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    import_count: std.atomic.Value(usize),
    concurrent_imports: std.atomic.Value(usize),
    max_concurrent: std.atomic.Value(usize),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .modules = std.StringHashMap(ModuleEntry).init(allocator),
            .allocator = allocator,
            .mutex = .{},
            .import_count = std.atomic.Value(usize).init(0),
            .concurrent_imports = std.atomic.Value(usize).init(0),
            .max_concurrent = std.atomic.Value(usize).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.modules.deinit();
    }

    /// Attempt to start loading a module
    /// Returns true if this thread should load, false if another thread is loading
    pub fn startImport(self: *Self, name: []const u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const result = try self.modules.getOrPut(name);
        if (!result.found_existing) {
            result.value_ptr.* = ModuleEntry.init(name);
        }

        const entry = result.value_ptr;
        const current_state = entry.getState();

        if (current_state == .loaded) {
            return false; // Already loaded
        }

        if (current_state == .loading) {
            return false; // Another thread is loading
        }

        // Try to claim loading
        const current = @intFromEnum(ModuleState.not_loaded);
        const loading = @intFromEnum(ModuleState.loading);

        if (entry.state.cmpxchgStrong(current, loading, .acquire, .acquire)) |_| {
            return false; // Lost the race
        }

        entry.loader_thread.store(std.Thread.getCurrentId(), .release);
        _ = self.concurrent_imports.fetchAdd(1, .monotonic);
        self.updateMaxConcurrent();
        _ = self.import_count.fetchAdd(1, .monotonic);

        return true;
    }

    /// Complete loading a module
    pub fn finishImport(self: *Self, name: []const u8, success: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.modules.getPtr(name)) |entry| {
            entry.setState(if (success) .loaded else .failed);
            _ = entry.init_count.fetchAdd(1, .monotonic);
        }

        _ = self.concurrent_imports.fetchSub(1, .monotonic);
    }

    /// Wait for a module to finish loading
    pub fn waitForImport(self: *Self, name: []const u8, timeout_ns: u64) bool {
        const start = std.time.nanoTimestamp();

        while (true) {
            self.mutex.lock();
            const state = if (self.modules.get(name)) |entry|
                entry.getState()
            else
                ModuleState.not_loaded;
            self.mutex.unlock();

            if (state == .loaded or state == .failed) {
                return state == .loaded;
            }

            const elapsed: u64 = @intCast(std.time.nanoTimestamp() - start);
            if (elapsed >= timeout_ns) {
                return false;
            }

            std.atomic.spinLoopHint();
        }
    }

    /// Get module if loaded
    pub fn getModule(self: *Self, name: []const u8) ?*ModuleEntry {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.modules.getPtr(name)) |entry| {
            if (entry.isLoaded()) {
                return entry;
            }
        }
        return null;
    }

    fn updateMaxConcurrent(self: *Self) void {
        const current = self.concurrent_imports.load(.acquire);
        var max = self.max_concurrent.load(.acquire);
        while (current > max) {
            const result = self.max_concurrent.cmpxchgWeak(max, current, .release, .acquire);
            if (result) |new_max| {
                max = new_max;
            } else {
                break;
            }
        }
    }

    pub fn getStats(self: *const Self) struct {
        import_count: usize,
        max_concurrent: usize,
        current_concurrent: usize,
    } {
        return .{
            .import_count = self.import_count.load(.acquire),
            .max_concurrent = self.max_concurrent.load(.acquire),
            .current_concurrent = self.concurrent_imports.load(.acquire),
        };
    }
};

/// Import lock for preventing deadlocks in circular imports
pub const ImportLock = struct {
    const Self = @This();

    held_by: std.atomic.Value(usize),
    waiting: std.atomic.Value(usize),
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,

    pub fn init() Self {
        return .{
            .held_by = std.atomic.Value(usize).init(0),
            .waiting = std.atomic.Value(usize).init(0),
            .mutex = .{},
            .condition = .{},
        };
    }

    pub fn acquire(self: *Self) bool {
        const tid = std.Thread.getCurrentId();
        const holder = self.held_by.load(.acquire);

        if (holder == tid) {
            return true; // Reentrant
        }

        _ = self.waiting.fetchAdd(1, .monotonic);
        defer _ = self.waiting.fetchSub(1, .monotonic);

        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.held_by.load(.acquire) != 0) {
            self.condition.wait(&self.mutex);
        }

        self.held_by.store(tid, .release);
        return true;
    }

    pub fn release(self: *Self) void {
        const tid = std.Thread.getCurrentId();
        if (self.held_by.load(.acquire) != tid) {
            return; // Not held by us
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        self.held_by.store(0, .release);
        self.condition.signal();
    }

    pub fn isHeld(self: *const Self) bool {
        return self.held_by.load(.acquire) != 0;
    }

    pub fn heldByCurrentThread(self: *const Self) bool {
        return self.held_by.load(.acquire) == std.Thread.getCurrentId();
    }
};

/// Import graph for cycle detection
pub const ImportGraph = struct {
    const Self = @This();

    edges: std.StringHashMap(std.ArrayList([]const u8)),
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .edges = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .allocator = allocator,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.edges.valueIterator();
        while (iter.next()) |list| {
            list.deinit();
        }
        self.edges.deinit();
    }

    pub fn addEdge(self: *Self, from: []const u8, to: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const result = try self.edges.getOrPut(from);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }
        try result.value_ptr.append(to);
    }

    pub fn hasCycle(self: *Self, start: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();
        var in_stack = std.StringHashMap(void).init(self.allocator);
        defer in_stack.deinit();

        return self.hasCycleDFS(start, &visited, &in_stack);
    }

    fn hasCycleDFS(self: *Self, node: []const u8, visited: *std.StringHashMap(void), in_stack: *std.StringHashMap(void)) bool {
        if (in_stack.contains(node)) {
            return true;
        }

        if (visited.contains(node)) {
            return false;
        }

        visited.put(node, {}) catch return false;
        in_stack.put(node, {}) catch return false;

        if (self.edges.get(node)) |neighbors| {
            for (neighbors.items) |neighbor| {
                if (self.hasCycleDFS(neighbor, visited, in_stack)) {
                    return true;
                }
            }
        }

        _ = in_stack.remove(node);
        return false;
    }
};

/// Import loader simulation
pub const ImportLoader = struct {
    const Self = @This();

    registry: *ModuleRegistry,
    import_lock: ImportLock,
    load_delay_ns: u64,
    loads_in_progress: std.atomic.Value(usize),

    pub fn init(registry: *ModuleRegistry) Self {
        return .{
            .registry = registry,
            .import_lock = ImportLock.init(),
            .load_delay_ns = 1_000_000, // 1ms
            .loads_in_progress = std.atomic.Value(usize).init(0),
        };
    }

    pub fn importModule(self: *Self, name: []const u8) !bool {
        // Check if already loaded
        if (self.registry.getModule(name) != null) {
            return true;
        }

        // Try to start import
        if (!try self.registry.startImport(name)) {
            // Wait for other thread to finish
            return self.registry.waitForImport(name, 10_000_000_000);
        }

        _ = self.loads_in_progress.fetchAdd(1, .monotonic);
        defer _ = self.loads_in_progress.fetchSub(1, .monotonic);

        // Simulate module loading
        std.time.sleep(self.load_delay_ns);

        self.registry.finishImport(name, true);
        return true;
    }

    pub fn importWithLock(self: *Self, name: []const u8) !bool {
        _ = self.import_lock.acquire();
        defer self.import_lock.release();
        return self.importModule(name);
    }

    pub fn setLoadDelay(self: *Self, delay_ns: u64) void {
        self.load_delay_ns = delay_ns;
    }
};

/// Lazy import for deferred loading
pub fn LazyImport(comptime T: type) type {
    return struct {
        const Self = @This();

        value: ?*T,
        loader: *const fn () ?*T,
        loaded: std.atomic.Value(bool),
        loading: std.atomic.Value(bool),
        mutex: std.Thread.Mutex,

        pub fn init(loader: *const fn () ?*T) Self {
            return .{
                .value = null,
                .loader = loader,
                .loaded = std.atomic.Value(bool).init(false),
                .loading = std.atomic.Value(bool).init(false),
                .mutex = .{},
            };
        }

        pub fn get(self: *Self) ?*T {
            if (self.loaded.load(.acquire)) {
                return self.value;
            }

            self.mutex.lock();
            defer self.mutex.unlock();

            // Double-check after acquiring lock
            if (self.loaded.load(.acquire)) {
                return self.value;
            }

            if (self.loading.swap(true, .acquire)) {
                // Another thread is loading, wait
                return null;
            }

            self.value = self.loader();
            self.loaded.store(true, .release);
            return self.value;
        }

        pub fn isLoaded(self: *const Self) bool {
            return self.loaded.load(.acquire);
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "module_entry_basic" {
    var entry = ModuleEntry.init("test_module");

    try std.testing.expectEqual(ModuleState.not_loaded, entry.getState());
    try std.testing.expect(!entry.isLoaded());

    entry.setState(.loading);
    try std.testing.expect(entry.isLoading());

    entry.setState(.loaded);
    try std.testing.expect(entry.isLoaded());
}

test "module_registry_basic" {
    const allocator = std.testing.allocator;
    var registry = ModuleRegistry.init(allocator);
    defer registry.deinit();

    try std.testing.expect(try registry.startImport("foo"));
    registry.finishImport("foo", true);

    const module = registry.getModule("foo");
    try std.testing.expect(module != null);
    try std.testing.expect(module.?.isLoaded());
}

test "module_registry_already_loaded" {
    const allocator = std.testing.allocator;
    var registry = ModuleRegistry.init(allocator);
    defer registry.deinit();

    try std.testing.expect(try registry.startImport("bar"));
    registry.finishImport("bar", true);

    // Second import should return false (already loaded)
    try std.testing.expect(!try registry.startImport("bar"));
}

test "import_lock_basic" {
    var lock = ImportLock.init();

    try std.testing.expect(!lock.isHeld());

    try std.testing.expect(lock.acquire());
    try std.testing.expect(lock.isHeld());
    try std.testing.expect(lock.heldByCurrentThread());

    lock.release();
    try std.testing.expect(!lock.isHeld());
}

test "import_lock_reentrant" {
    var lock = ImportLock.init();

    try std.testing.expect(lock.acquire());
    try std.testing.expect(lock.acquire()); // Reentrant
    try std.testing.expect(lock.isHeld());

    lock.release();
    try std.testing.expect(!lock.isHeld());
}

test "import_graph_no_cycle" {
    const allocator = std.testing.allocator;
    var graph = ImportGraph.init(allocator);
    defer graph.deinit();

    try graph.addEdge("a", "b");
    try graph.addEdge("b", "c");
    try graph.addEdge("a", "c");

    try std.testing.expect(!graph.hasCycle("a"));
}

test "import_graph_cycle" {
    const allocator = std.testing.allocator;
    var graph = ImportGraph.init(allocator);
    defer graph.deinit();

    try graph.addEdge("a", "b");
    try graph.addEdge("b", "c");
    try graph.addEdge("c", "a");

    try std.testing.expect(graph.hasCycle("a"));
}

test "import_loader_basic" {
    const allocator = std.testing.allocator;
    var registry = ModuleRegistry.init(allocator);
    defer registry.deinit();

    var loader = ImportLoader.init(&registry);
    loader.setLoadDelay(0); // No delay for testing

    try std.testing.expect(try loader.importModule("test"));
    try std.testing.expect(registry.getModule("test") != null);
}

test "import_loader_concurrent" {
    const allocator = std.testing.allocator;
    var registry = ModuleRegistry.init(allocator);
    defer registry.deinit();

    var loader = ImportLoader.init(&registry);
    loader.setLoadDelay(100_000); // 100us

    const num_threads = 4;
    var threads: [num_threads]std.Thread = undefined;
    var success_count = std.atomic.Value(usize).init(0);

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(l: *ImportLoader, s: *std.atomic.Value(usize)) void {
                if (l.importModule("shared_module") catch false) {
                    _ = s.fetchAdd(1, .monotonic);
                }
            }
        }.run, .{ &loader, &success_count }) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    // All threads should eventually succeed
    try std.testing.expectEqual(@as(usize, num_threads), success_count.load(.acquire));

    // Module should be loaded exactly once
    if (registry.getModule("shared_module")) |module| {
        try std.testing.expectEqual(@as(usize, 1), module.init_count.load(.acquire));
    } else {
        try std.testing.expect(false);
    }
}

test "lazy_import_basic" {
    const TestModule = struct {
        value: i32,
    };

    var module = TestModule{ .value = 42 };

    var lazy = LazyImport(*TestModule).init(struct {
        var m: *TestModule = undefined;
        fn load() ?*TestModule {
            return m;
        }
    }.load);

    // Set the module pointer
    @constCast(&@as(*const *TestModule, &lazy.loader).*.*).m = &module;

    try std.testing.expect(!lazy.isLoaded());

    const result = lazy.get();
    try std.testing.expect(result != null);
    try std.testing.expect(lazy.isLoaded());
}

test "registry_stats" {
    const allocator = std.testing.allocator;
    var registry = ModuleRegistry.init(allocator);
    defer registry.deinit();

    try std.testing.expect(try registry.startImport("mod1"));
    registry.finishImport("mod1", true);

    try std.testing.expect(try registry.startImport("mod2"));
    registry.finishImport("mod2", true);

    const stats = registry.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.import_count);
    try std.testing.expectEqual(@as(usize, 0), stats.current_concurrent);
}
