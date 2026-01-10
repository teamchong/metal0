//! test.test_module.test_circular - Circular import testing
//! Tests for Python's handling of circular imports
//! Reference: CPython Lib/test/test_importlib/test_circular.py

const std = @import("std");
const importlib = @import("../../importlib.zig");

// ============================================================================
// Types
// ============================================================================

pub const ModuleSpec = importlib.ModuleSpec;
pub const ImportError = importlib.ImportError;

// ============================================================================
// Circular Import Detection
// ============================================================================

/// State of a module in the import process
pub const ModuleState = enum {
    /// Not yet imported
    not_imported,
    /// Currently being imported (in import stack)
    importing,
    /// Fully imported
    imported,
    /// Failed to import
    failed,
};

/// Track import state for circular import detection
pub const ImportTracker = struct {
    states: std.StringHashMap(ModuleState),
    import_stack: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .states = std.StringHashMap(ModuleState).init(allocator),
            .import_stack = std.ArrayList([]const u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.states.deinit();
        self.import_stack.deinit(self.allocator);
    }

    /// Begin importing a module
    pub fn beginImport(self: *Self, name: []const u8) !ImportResult {
        const current_state = self.states.get(name) orelse .not_imported;

        switch (current_state) {
            .imported => return .{ .status = .already_imported },
            .importing => return .{ .status = .circular_detected },
            .failed => return .{ .status = .previous_failure },
            .not_imported => {
                try self.states.put(name, .importing);
                try self.import_stack.append(self.allocator, name);
                return .{ .status = .started };
            },
        }
    }

    /// Complete importing a module
    pub fn endImport(self: *Self, name: []const u8, success: bool) void {
        const new_state: ModuleState = if (success) .imported else .failed;
        self.states.put(name, new_state) catch {};

        // Remove from import stack
        if (self.import_stack.items.len > 0) {
            const last = self.import_stack.items[self.import_stack.items.len - 1];
            if (std.mem.eql(u8, last, name)) {
                _ = self.import_stack.pop();
            }
        }
    }

    /// Check if module is currently being imported
    pub fn isImporting(self: *const Self, name: []const u8) bool {
        return self.states.get(name) == .importing;
    }

    /// Check if module was already imported
    pub fn isImported(self: *const Self, name: []const u8) bool {
        return self.states.get(name) == .imported;
    }

    /// Get the current import stack
    pub fn getImportStack(self: *const Self) []const []const u8 {
        return self.import_stack.items;
    }

    /// Get import depth
    pub fn getDepth(self: *const Self) usize {
        return self.import_stack.items.len;
    }

    /// Reset all states
    pub fn reset(self: *Self) void {
        self.states.clearRetainingCapacity();
        self.import_stack.clearRetainingCapacity();
    }
};

/// Result of beginning an import
pub const ImportResult = struct {
    status: Status,

    pub const Status = enum {
        started,
        already_imported,
        circular_detected,
        previous_failure,
    };

    pub fn isCircular(self: ImportResult) bool {
        return self.status == .circular_detected;
    }

    pub fn canProceed(self: ImportResult) bool {
        return self.status == .started;
    }
};

// ============================================================================
// Circular Import Scenarios
// ============================================================================

/// Represents a dependency graph for testing
pub const DependencyGraph = struct {
    edges: std.StringHashMap(std.ArrayList([]const u8)),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .edges = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.edges.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.edges.deinit();
    }

    /// Add a dependency: `from_module` imports `to_module`
    pub fn addDependency(self: *Self, from_module: []const u8, to_module: []const u8) !void {
        const result = try self.edges.getOrPut(from_module);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList([]const u8){};
        }
        try result.value_ptr.append(self.allocator, to_module);
    }

    /// Get dependencies of a module
    pub fn getDependencies(self: *const Self, module: []const u8) ?[]const []const u8 {
        if (self.edges.get(module)) |deps| {
            return deps.items;
        }
        return null;
    }

    /// Check if there's a direct circular dependency
    pub fn hasDirectCircle(self: *const Self, a: []const u8, b: []const u8) bool {
        const a_deps = self.getDependencies(a) orelse return false;
        const b_deps = self.getDependencies(b) orelse return false;

        for (a_deps) |dep| {
            if (std.mem.eql(u8, dep, b)) {
                for (b_deps) |bdep| {
                    if (std.mem.eql(u8, bdep, a)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /// Detect any circular dependency using DFS
    pub fn detectCycle(self: *Self) ?[]const u8 {
        var visited = std.StringHashMap(bool).init(self.allocator);
        defer visited.deinit();
        var in_stack = std.StringHashMap(bool).init(self.allocator);
        defer in_stack.deinit();

        var it = self.edges.keyIterator();
        while (it.next()) |key| {
            if (self.dfsDetectCycle(key.*, &visited, &in_stack)) |cycle_node| {
                return cycle_node;
            }
        }
        return null;
    }

    fn dfsDetectCycle(
        self: *Self,
        node: []const u8,
        visited: *std.StringHashMap(bool),
        in_stack: *std.StringHashMap(bool),
    ) ?[]const u8 {
        if (in_stack.get(node) orelse false) {
            return node; // Found cycle
        }
        if (visited.get(node) orelse false) {
            return null; // Already visited, no cycle through here
        }

        visited.put(node, true) catch return null;
        in_stack.put(node, true) catch return null;

        if (self.getDependencies(node)) |deps| {
            for (deps) |dep| {
                if (self.dfsDetectCycle(dep, visited, in_stack)) |cycle| {
                    return cycle;
                }
            }
        }

        in_stack.put(node, false) catch {};
        return null;
    }
};

// ============================================================================
// Test Functions
// ============================================================================

/// Test ImportTracker initialization
pub fn testImportTrackerInit(allocator: std.mem.Allocator) !void {
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();
    try std.testing.expectEqual(@as(usize, 0), tracker.getDepth());
}

/// Test normal import flow
pub fn testNormalImport(allocator: std.mem.Allocator) !void {
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();

    const result = try tracker.beginImport("mymodule");
    try std.testing.expect(result.canProceed());
    try std.testing.expect(tracker.isImporting("mymodule"));

    tracker.endImport("mymodule", true);
    try std.testing.expect(tracker.isImported("mymodule"));
}

/// Test circular import detection
pub fn testCircularDetection(allocator: std.mem.Allocator) !void {
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();

    // Start importing A
    _ = try tracker.beginImport("A");

    // A tries to import B
    _ = try tracker.beginImport("B");

    // B tries to import A (circular!)
    const result = try tracker.beginImport("A");
    try std.testing.expect(result.isCircular());
}

/// Test already imported module
pub fn testAlreadyImported(allocator: std.mem.Allocator) !void {
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();

    _ = try tracker.beginImport("cached");
    tracker.endImport("cached", true);

    const result = try tracker.beginImport("cached");
    try std.testing.expectEqual(ImportResult.Status.already_imported, result.status);
}

/// Test DependencyGraph
pub fn testDependencyGraph(allocator: std.mem.Allocator) !void {
    var graph = DependencyGraph.init(allocator);
    defer graph.deinit();

    try graph.addDependency("A", "B");
    try graph.addDependency("B", "C");

    const a_deps = graph.getDependencies("A").?;
    try std.testing.expectEqual(@as(usize, 1), a_deps.len);
    try std.testing.expectEqualStrings("B", a_deps[0]);
}

/// Test direct circle detection
pub fn testDirectCircle(allocator: std.mem.Allocator) !void {
    var graph = DependencyGraph.init(allocator);
    defer graph.deinit();

    try graph.addDependency("A", "B");
    try graph.addDependency("B", "A");

    try std.testing.expect(graph.hasDirectCircle("A", "B"));
}

// ============================================================================
// Zig Tests
// ============================================================================

test "ImportTracker init" {
    const allocator = std.testing.allocator;
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();
    try std.testing.expectEqual(@as(usize, 0), tracker.getDepth());
}

test "ImportTracker begin import" {
    const allocator = std.testing.allocator;
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();

    const result = try tracker.beginImport("mod");
    try std.testing.expect(result.canProceed());
    try std.testing.expectEqual(@as(usize, 1), tracker.getDepth());
}

test "ImportTracker end import success" {
    const allocator = std.testing.allocator;
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();

    _ = try tracker.beginImport("mod");
    tracker.endImport("mod", true);
    try std.testing.expect(tracker.isImported("mod"));
}

test "ImportTracker end import failure" {
    const allocator = std.testing.allocator;
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();

    _ = try tracker.beginImport("failing");
    tracker.endImport("failing", false);

    const result = try tracker.beginImport("failing");
    try std.testing.expectEqual(ImportResult.Status.previous_failure, result.status);
}

test "ImportTracker circular detection" {
    const allocator = std.testing.allocator;
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();

    _ = try tracker.beginImport("A");
    const circular = try tracker.beginImport("A");
    try std.testing.expect(circular.isCircular());
}

test "ImportTracker already imported" {
    const allocator = std.testing.allocator;
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();

    _ = try tracker.beginImport("done");
    tracker.endImport("done", true);

    const result = try tracker.beginImport("done");
    try std.testing.expectEqual(ImportResult.Status.already_imported, result.status);
}

test "ImportTracker import stack" {
    const allocator = std.testing.allocator;
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();

    _ = try tracker.beginImport("A");
    _ = try tracker.beginImport("B");
    _ = try tracker.beginImport("C");

    const stack = tracker.getImportStack();
    try std.testing.expectEqual(@as(usize, 3), stack.len);
    try std.testing.expectEqualStrings("A", stack[0]);
    try std.testing.expectEqualStrings("B", stack[1]);
    try std.testing.expectEqualStrings("C", stack[2]);
}

test "ImportTracker reset" {
    const allocator = std.testing.allocator;
    var tracker = ImportTracker.init(allocator);
    defer tracker.deinit();

    _ = try tracker.beginImport("mod");
    tracker.reset();
    try std.testing.expectEqual(@as(usize, 0), tracker.getDepth());
}

test "DependencyGraph init" {
    const allocator = std.testing.allocator;
    var graph = DependencyGraph.init(allocator);
    defer graph.deinit();
    try std.testing.expect(graph.getDependencies("none") == null);
}

test "DependencyGraph add dependency" {
    const allocator = std.testing.allocator;
    var graph = DependencyGraph.init(allocator);
    defer graph.deinit();

    try graph.addDependency("A", "B");
    const deps = graph.getDependencies("A").?;
    try std.testing.expectEqual(@as(usize, 1), deps.len);
}

test "DependencyGraph multiple dependencies" {
    const allocator = std.testing.allocator;
    var graph = DependencyGraph.init(allocator);
    defer graph.deinit();

    try graph.addDependency("A", "B");
    try graph.addDependency("A", "C");
    try graph.addDependency("A", "D");

    const deps = graph.getDependencies("A").?;
    try std.testing.expectEqual(@as(usize, 3), deps.len);
}

test "DependencyGraph direct circle true" {
    const allocator = std.testing.allocator;
    var graph = DependencyGraph.init(allocator);
    defer graph.deinit();

    try graph.addDependency("X", "Y");
    try graph.addDependency("Y", "X");
    try std.testing.expect(graph.hasDirectCircle("X", "Y"));
}

test "DependencyGraph direct circle false" {
    const allocator = std.testing.allocator;
    var graph = DependencyGraph.init(allocator);
    defer graph.deinit();

    try graph.addDependency("X", "Y");
    try graph.addDependency("Y", "Z");
    try std.testing.expect(!graph.hasDirectCircle("X", "Y"));
}

test "DependencyGraph detect cycle" {
    const allocator = std.testing.allocator;
    var graph = DependencyGraph.init(allocator);
    defer graph.deinit();

    try graph.addDependency("A", "B");
    try graph.addDependency("B", "C");
    try graph.addDependency("C", "A");

    const cycle = graph.detectCycle();
    try std.testing.expect(cycle != null);
}

test "DependencyGraph no cycle" {
    const allocator = std.testing.allocator;
    var graph = DependencyGraph.init(allocator);
    defer graph.deinit();

    try graph.addDependency("A", "B");
    try graph.addDependency("B", "C");
    try graph.addDependency("A", "C");

    const cycle = graph.detectCycle();
    try std.testing.expect(cycle == null);
}

test "ImportResult isCircular" {
    const circular = ImportResult{ .status = .circular_detected };
    try std.testing.expect(circular.isCircular());

    const normal = ImportResult{ .status = .started };
    try std.testing.expect(!normal.isCircular());
}

test "ImportResult canProceed" {
    const started = ImportResult{ .status = .started };
    try std.testing.expect(started.canProceed());

    const cached = ImportResult{ .status = .already_imported };
    try std.testing.expect(!cached.canProceed());
}

test "ModuleState enum" {
    const state: ModuleState = .importing;
    try std.testing.expect(state == .importing);
}
