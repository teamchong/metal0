//! test.test_import.test_circular - Circular import handling
//!
//! Tests for Python's circular import handling including:
//! - Circular import detection
//! - Partial module exposure during import
//! - Import lock handling
//! - Import graph analysis
//! - Circular import resolution strategies

const std = @import("std");
const Allocator = std.mem.Allocator;

/// CircularImportError - Errors related to circular imports
pub const CircularImportError = error{
    CircularImportDetected,
    ImportLockTimeout,
    ImportInProgress,
    ModuleNotFullyInitialized,
    OutOfMemory,
};

/// ImportState - Tracks the state of a module during import
pub const ImportState = enum {
    /// Module not started importing
    not_started,

    /// Module is currently being imported (partial state)
    importing,

    /// Module import completed successfully
    imported,

    /// Module import failed
    failed,

    pub fn isComplete(self: ImportState) bool {
        return self == .imported or self == .failed;
    }

    pub fn isInProgress(self: ImportState) bool {
        return self == .importing;
    }
};

/// ModuleImportInfo - Information about a module's import status
pub const ModuleImportInfo = struct {
    name: []const u8,
    state: ImportState,
    /// Thread that is importing this module (for locking)
    importing_thread: ?std.Thread.Id,
    /// Time import started (for timeout detection)
    import_start_time: ?i64,
    /// Modules that this module depends on
    dependencies: std.StringHashMapUnmanaged(void),
    /// Modules waiting for this module
    dependents: std.StringHashMapUnmanaged(void),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) !*ModuleImportInfo {
        const info = try allocator.create(ModuleImportInfo);
        info.* = .{
            .name = name,
            .state = .not_started,
            .importing_thread = null,
            .import_start_time = null,
            .dependencies = .{},
            .dependents = .{},
            .allocator = allocator,
        };
        return info;
    }

    pub fn deinit(self: *ModuleImportInfo) void {
        self.dependencies.deinit(self.allocator);
        self.dependents.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn addDependency(self: *ModuleImportInfo, dep: []const u8) !void {
        try self.dependencies.put(self.allocator, dep, {});
    }

    pub fn addDependent(self: *ModuleImportInfo, dep: []const u8) !void {
        try self.dependents.put(self.allocator, dep, {});
    }

    pub fn hasDependency(self: *const ModuleImportInfo, dep: []const u8) bool {
        return self.dependencies.contains(dep);
    }
};

/// ImportGraph - Tracks dependencies between modules
pub const ImportGraph = struct {
    modules: std.StringHashMapUnmanaged(*ModuleImportInfo),
    allocator: Allocator,

    pub fn init(allocator: Allocator) ImportGraph {
        return .{
            .modules = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImportGraph) void {
        var iter = self.modules.valueIterator();
        while (iter.next()) |info| {
            info.*.deinit();
        }
        self.modules.deinit(self.allocator);
    }

    /// Get or create module info
    pub fn getOrCreate(self: *ImportGraph, name: []const u8) !*ModuleImportInfo {
        if (self.modules.get(name)) |info| {
            return info;
        }
        const info = try ModuleImportInfo.init(self.allocator, name);
        try self.modules.put(self.allocator, name, info);
        return info;
    }

    /// Record a dependency: 'from_module' imports 'to_module'
    pub fn addEdge(self: *ImportGraph, from_module: []const u8, to_module: []const u8) !void {
        const from_info = try self.getOrCreate(from_module);
        const to_info = try self.getOrCreate(to_module);
        try from_info.addDependency(to_module);
        try to_info.addDependent(from_module);
    }

    /// Check if there's a path from 'from' to 'to' (circular check)
    pub fn hasPath(self: *ImportGraph, from: []const u8, to: []const u8) bool {
        var visited = std.StringHashMapUnmanaged(void).init(self.allocator);
        defer visited.deinit(self.allocator);

        return self.hasPathDFS(from, to, &visited);
    }

    fn hasPathDFS(
        self: *ImportGraph,
        current: []const u8,
        target: []const u8,
        visited: *std.StringHashMapUnmanaged(void),
    ) bool {
        if (std.mem.eql(u8, current, target)) return true;
        if (visited.contains(current)) return false;

        visited.put(self.allocator, current, {}) catch return false;

        if (self.modules.get(current)) |info| {
            var dep_iter = info.dependencies.keyIterator();
            while (dep_iter.next()) |dep| {
                if (self.hasPathDFS(dep.*, target, visited)) return true;
            }
        }

        return false;
    }

    /// Detect all cycles in the import graph
    pub fn detectCycles(self: *ImportGraph, allocator: Allocator) ![][]const []const u8 {
        var cycles = std.ArrayList([]const []const u8).init(allocator);
        var visited = std.StringHashMapUnmanaged(void).init(allocator);
        defer visited.deinit(allocator);

        var on_stack = std.StringHashMapUnmanaged(void).init(allocator);
        defer on_stack.deinit(allocator);

        var stack = std.ArrayList([]const u8).init(allocator);
        defer stack.deinit();

        var key_iter = self.modules.keyIterator();
        while (key_iter.next()) |name| {
            if (!visited.contains(name.*)) {
                try self.detectCyclesDFS(name.*, &visited, &on_stack, &stack, &cycles, allocator);
            }
        }

        return cycles.toOwnedSlice();
    }

    fn detectCyclesDFS(
        self: *ImportGraph,
        node: []const u8,
        visited: *std.StringHashMapUnmanaged(void),
        on_stack: *std.StringHashMapUnmanaged(void),
        stack: *std.ArrayList([]const u8),
        cycles: *std.ArrayList([]const []const u8),
        allocator: Allocator,
    ) !void {
        try visited.put(allocator, node, {});
        try on_stack.put(allocator, node, {});
        try stack.append(node);

        if (self.modules.get(node)) |info| {
            var dep_iter = info.dependencies.keyIterator();
            while (dep_iter.next()) |dep| {
                if (!visited.contains(dep.*)) {
                    try self.detectCyclesDFS(dep.*, visited, on_stack, stack, cycles, allocator);
                } else if (on_stack.contains(dep.*)) {
                    // Found a cycle - extract it
                    var cycle = std.ArrayList([]const u8).init(allocator);
                    var in_cycle = false;
                    for (stack.items) |s| {
                        if (std.mem.eql(u8, s, dep.*)) in_cycle = true;
                        if (in_cycle) try cycle.append(s);
                    }
                    try cycle.append(dep.*);
                    try cycles.append(try cycle.toOwnedSlice());
                }
            }
        }

        _ = on_stack.remove(node);
        _ = stack.pop();
    }

    /// Get topological sort of modules (if no cycles)
    pub fn topologicalSort(self: *ImportGraph, allocator: Allocator) !?[][]const u8 {
        var result = std.ArrayList([]const u8).init(allocator);
        var in_degree = std.StringHashMapUnmanaged(u32).init(allocator);
        defer in_degree.deinit(allocator);

        // Calculate in-degrees
        var key_iter = self.modules.keyIterator();
        while (key_iter.next()) |name| {
            try in_degree.put(allocator, name.*, 0);
        }

        var val_iter = self.modules.valueIterator();
        while (val_iter.next()) |info| {
            var dep_iter = info.*.dependencies.keyIterator();
            while (dep_iter.next()) |dep| {
                const current = in_degree.get(dep.*) orelse 0;
                try in_degree.put(allocator, dep.*, current + 1);
            }
        }

        // Find all nodes with in-degree 0
        var queue = std.ArrayList([]const u8).init(allocator);
        defer queue.deinit();

        var deg_iter = in_degree.iterator();
        while (deg_iter.next()) |entry| {
            if (entry.value_ptr.* == 0) {
                try queue.append(entry.key_ptr.*);
            }
        }

        // Process queue
        while (queue.items.len > 0) {
            const node = queue.orderedRemove(0);
            try result.append(node);

            if (self.modules.get(node)) |info| {
                var dep_iter = info.dependencies.keyIterator();
                while (dep_iter.next()) |dep| {
                    const deg = in_degree.get(dep.*) orelse continue;
                    try in_degree.put(allocator, dep.*, deg - 1);
                    if (deg - 1 == 0) {
                        try queue.append(dep.*);
                    }
                }
            }
        }

        // If result doesn't contain all nodes, there's a cycle
        if (result.items.len != self.modules.count()) {
            result.deinit();
            return null;
        }

        return result.toOwnedSlice();
    }
};

/// ImportLock - Handles import locking for thread safety
pub const ImportLock = struct {
    module_locks: std.StringHashMapUnmanaged(LockInfo),
    global_lock: std.Thread.Mutex,
    allocator: Allocator,

    pub const LockInfo = struct {
        owner: ?std.Thread.Id,
        count: u32, // Reentrant count
        waiters: u32,
    };

    pub fn init(allocator: Allocator) ImportLock {
        return .{
            .module_locks = .{},
            .global_lock = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImportLock) void {
        self.module_locks.deinit(self.allocator);
    }

    /// Acquire lock for a module
    pub fn acquire(self: *ImportLock, module_name: []const u8) !void {
        self.global_lock.lock();
        defer self.global_lock.unlock();

        const current_thread = std.Thread.getCurrentId();

        if (self.module_locks.getPtr(module_name)) |lock| {
            if (lock.owner == current_thread) {
                // Reentrant
                lock.count += 1;
                return;
            }
            // Would wait here in real implementation
            lock.waiters += 1;
        } else {
            try self.module_locks.put(self.allocator, module_name, .{
                .owner = current_thread,
                .count = 1,
                .waiters = 0,
            });
        }
    }

    /// Release lock for a module
    pub fn release(self: *ImportLock, module_name: []const u8) void {
        self.global_lock.lock();
        defer self.global_lock.unlock();

        if (self.module_locks.getPtr(module_name)) |lock| {
            lock.count -= 1;
            if (lock.count == 0) {
                lock.owner = null;
            }
        }
    }

    /// Check if current thread holds the lock
    pub fn isHeldByCurrentThread(self: *ImportLock, module_name: []const u8) bool {
        self.global_lock.lock();
        defer self.global_lock.unlock();

        if (self.module_locks.get(module_name)) |lock| {
            return lock.owner == std.Thread.getCurrentId();
        }
        return false;
    }
};

/// CircularImportDetector - Detects circular imports in real-time
pub const CircularImportDetector = struct {
    import_stack: std.ArrayListUnmanaged([]const u8),
    import_set: std.StringHashMapUnmanaged(void),
    allocator: Allocator,

    pub fn init(allocator: Allocator) CircularImportDetector {
        return .{
            .import_stack = .{},
            .import_set = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CircularImportDetector) void {
        self.import_stack.deinit(self.allocator);
        self.import_set.deinit(self.allocator);
    }

    /// Push a module onto the import stack
    pub fn push(self: *CircularImportDetector, module_name: []const u8) !bool {
        // Check if already importing (circular)
        if (self.import_set.contains(module_name)) {
            return false; // Circular import detected
        }

        try self.import_stack.append(self.allocator, module_name);
        try self.import_set.put(self.allocator, module_name, {});
        return true;
    }

    /// Pop a module from the import stack
    pub fn pop(self: *CircularImportDetector) void {
        if (self.import_stack.items.len > 0) {
            const name = self.import_stack.pop();
            _ = self.import_set.remove(name);
        }
    }

    /// Get the current import depth
    pub fn getDepth(self: *const CircularImportDetector) usize {
        return self.import_stack.items.len;
    }

    /// Get the import chain (for error messages)
    pub fn getImportChain(self: *const CircularImportDetector, allocator: Allocator) ![][]const u8 {
        const result = try allocator.alloc([]const u8, self.import_stack.items.len);
        @memcpy(result, self.import_stack.items);
        return result;
    }

    /// Check if a module is currently being imported
    pub fn isImporting(self: *const CircularImportDetector, module_name: []const u8) bool {
        return self.import_set.contains(module_name);
    }
};

/// PartialModuleRegistry - Tracks partially initialized modules
pub const PartialModuleRegistry = struct {
    partial_modules: std.StringHashMapUnmanaged(PartialModule),
    allocator: Allocator,

    pub const PartialModule = struct {
        name: []const u8,
        attributes_set: std.StringHashMapUnmanaged(void),
        is_complete: bool,
    };

    pub fn init(allocator: Allocator) PartialModuleRegistry {
        return .{
            .partial_modules = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PartialModuleRegistry) void {
        var iter = self.partial_modules.valueIterator();
        while (iter.next()) |pm| {
            pm.attributes_set.deinit(self.allocator);
        }
        self.partial_modules.deinit(self.allocator);
    }

    /// Register a module as being imported
    pub fn registerPartial(self: *PartialModuleRegistry, name: []const u8) !void {
        try self.partial_modules.put(self.allocator, name, .{
            .name = name,
            .attributes_set = .{},
            .is_complete = false,
        });
    }

    /// Mark an attribute as set
    pub fn setAttribute(self: *PartialModuleRegistry, module: []const u8, attr: []const u8) !void {
        if (self.partial_modules.getPtr(module)) |pm| {
            try pm.attributes_set.put(self.allocator, attr, {});
        }
    }

    /// Check if an attribute is available
    pub fn hasAttribute(self: *const PartialModuleRegistry, module: []const u8, attr: []const u8) bool {
        if (self.partial_modules.get(module)) |pm| {
            return pm.attributes_set.contains(attr);
        }
        return false;
    }

    /// Mark module as complete
    pub fn markComplete(self: *PartialModuleRegistry, name: []const u8) void {
        if (self.partial_modules.getPtr(name)) |pm| {
            pm.is_complete = true;
        }
    }

    /// Check if module is complete
    pub fn isComplete(self: *const PartialModuleRegistry, name: []const u8) bool {
        if (self.partial_modules.get(name)) |pm| {
            return pm.is_complete;
        }
        return false;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "import_state_enum" {
    try std.testing.expect(!ImportState.not_started.isComplete());
    try std.testing.expect(!ImportState.importing.isComplete());
    try std.testing.expect(ImportState.imported.isComplete());
    try std.testing.expect(ImportState.failed.isComplete());

    try std.testing.expect(ImportState.importing.isInProgress());
    try std.testing.expect(!ImportState.imported.isInProgress());
}

test "module_import_info" {
    const info = try ModuleImportInfo.init(std.testing.allocator, "test_module");
    defer info.deinit();

    try std.testing.expectEqualStrings("test_module", info.name);
    try std.testing.expectEqual(ImportState.not_started, info.state);

    try info.addDependency("dep1");
    try info.addDependency("dep2");

    try std.testing.expect(info.hasDependency("dep1"));
    try std.testing.expect(!info.hasDependency("dep3"));
}

test "import_graph_basic" {
    var graph = ImportGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.addEdge("a", "b");
    try graph.addEdge("b", "c");

    try std.testing.expect(graph.hasPath("a", "c"));
    try std.testing.expect(!graph.hasPath("c", "a"));
}

test "import_graph_cycle_detection" {
    var graph = ImportGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.addEdge("a", "b");
    try graph.addEdge("b", "c");
    try graph.addEdge("c", "a"); // Creates cycle

    try std.testing.expect(graph.hasPath("a", "a"));
}

test "circular_import_detector" {
    var detector = CircularImportDetector.init(std.testing.allocator);
    defer detector.deinit();

    try std.testing.expect(try detector.push("module_a"));
    try std.testing.expect(try detector.push("module_b"));
    try std.testing.expect(try detector.push("module_c"));

    // Try to push module_a again (circular)
    try std.testing.expect(!try detector.push("module_a"));

    try std.testing.expectEqual(@as(usize, 3), detector.getDepth());
    try std.testing.expect(detector.isImporting("module_b"));
    try std.testing.expect(!detector.isImporting("module_d"));
}

test "circular_import_detector_chain" {
    var detector = CircularImportDetector.init(std.testing.allocator);
    defer detector.deinit();

    _ = try detector.push("a");
    _ = try detector.push("b");
    _ = try detector.push("c");

    const chain = try detector.getImportChain(std.testing.allocator);
    defer std.testing.allocator.free(chain);

    try std.testing.expectEqual(@as(usize, 3), chain.len);
    try std.testing.expectEqualStrings("a", chain[0]);
    try std.testing.expectEqualStrings("b", chain[1]);
    try std.testing.expectEqualStrings("c", chain[2]);
}

test "partial_module_registry" {
    var registry = PartialModuleRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerPartial("mymodule");
    try std.testing.expect(!registry.isComplete("mymodule"));

    try registry.setAttribute("mymodule", "foo");
    try registry.setAttribute("mymodule", "bar");

    try std.testing.expect(registry.hasAttribute("mymodule", "foo"));
    try std.testing.expect(!registry.hasAttribute("mymodule", "baz"));

    registry.markComplete("mymodule");
    try std.testing.expect(registry.isComplete("mymodule"));
}

test "import_lock_basic" {
    var lock = ImportLock.init(std.testing.allocator);
    defer lock.deinit();

    try lock.acquire("test_module");
    try std.testing.expect(lock.isHeldByCurrentThread("test_module"));

    lock.release("test_module");
}

test "import_lock_reentrant" {
    var lock = ImportLock.init(std.testing.allocator);
    defer lock.deinit();

    try lock.acquire("test_module");
    try lock.acquire("test_module"); // Reentrant
    try std.testing.expect(lock.isHeldByCurrentThread("test_module"));

    lock.release("test_module");
    try std.testing.expect(lock.isHeldByCurrentThread("test_module")); // Still held

    lock.release("test_module");
}

test "import_graph_topological_sort" {
    var graph = ImportGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.addEdge("main", "utils");
    try graph.addEdge("main", "config");
    try graph.addEdge("utils", "helpers");

    const sorted = try graph.topologicalSort(std.testing.allocator);
    if (sorted) |s| {
        defer std.testing.allocator.free(s);
        // Just verify we get the right count
        try std.testing.expectEqual(@as(usize, 4), s.len);
    }
}

test "import_graph_topological_sort_with_cycle" {
    var graph = ImportGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.addEdge("a", "b");
    try graph.addEdge("b", "c");
    try graph.addEdge("c", "a"); // Cycle

    const sorted = try graph.topologicalSort(std.testing.allocator);
    try std.testing.expect(sorted == null);
}
