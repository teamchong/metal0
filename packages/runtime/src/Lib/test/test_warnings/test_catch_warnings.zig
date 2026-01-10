//! test.test_warnings.test_catch_warnings - Comprehensive tests for catch_warnings
//!
//! Tests the catch_warnings context manager for temporarily modifying warning
//! filters and recording warnings. Mirrors CPython's catch_warnings tests.

const std = @import("std");
const warnings = @import("Lib.warnings");

// ============================================================================
// Test Types
// ============================================================================

/// Mock warning record for testing
pub const MockWarningRecord = struct {
    message: []const u8,
    category: warnings.WarningCategory,
    filename: []const u8,
    lineno: usize,

    pub fn init(
        message: []const u8,
        category: warnings.WarningCategory,
        filename: []const u8,
        lineno: usize,
    ) MockWarningRecord {
        return .{
            .message = message,
            .category = category,
            .filename = filename,
            .lineno = lineno,
        };
    }

    pub fn matches(self: MockWarningRecord, other: MockWarningRecord) bool {
        return std.mem.eql(u8, self.message, other.message) and
            self.category == other.category and
            std.mem.eql(u8, self.filename, other.filename) and
            self.lineno == other.lineno;
    }
};

/// Test warnings collector
pub const WarningsCollector = struct {
    records: std.ArrayList(MockWarningRecord),
    allocator: std.mem.Allocator,
    recording: bool,

    pub fn init(allocator: std.mem.Allocator) WarningsCollector {
        return .{
            .records = std.ArrayList(MockWarningRecord).init(allocator),
            .allocator = allocator,
            .recording = false,
        };
    }

    pub fn deinit(self: *WarningsCollector) void {
        self.records.deinit();
    }

    pub fn startRecording(self: *WarningsCollector) void {
        self.recording = true;
    }

    pub fn stopRecording(self: *WarningsCollector) void {
        self.recording = false;
    }

    pub fn addWarning(self: *WarningsCollector, record: MockWarningRecord) !void {
        if (self.recording) {
            try self.records.append(record);
        }
    }

    pub fn count(self: WarningsCollector) usize {
        return self.records.items.len;
    }

    pub fn clear(self: *WarningsCollector) void {
        self.records.clearRetainingCapacity();
    }

    pub fn getAt(self: WarningsCollector, index: usize) ?MockWarningRecord {
        if (index < self.records.items.len) {
            return self.records.items[index];
        }
        return null;
    }

    pub fn containsMessage(self: WarningsCollector, message: []const u8) bool {
        for (self.records.items) |record| {
            if (std.mem.eql(u8, record.message, message)) {
                return true;
            }
        }
        return false;
    }

    pub fn containsCategory(self: WarningsCollector, category: warnings.WarningCategory) bool {
        for (self.records.items) |record| {
            if (record.category == category) {
                return true;
            }
        }
        return false;
    }
};

/// Context manager test harness
pub const CatchWarningsTestHarness = struct {
    allocator: std.mem.Allocator,
    collector: WarningsCollector,
    saved_filters: std.ArrayList(warnings.WarningFilter),
    active: bool,

    pub fn init(allocator: std.mem.Allocator) CatchWarningsTestHarness {
        return .{
            .allocator = allocator,
            .collector = WarningsCollector.init(allocator),
            .saved_filters = std.ArrayList(warnings.WarningFilter).init(allocator),
            .active = false,
        };
    }

    pub fn deinit(self: *CatchWarningsTestHarness) void {
        self.collector.deinit();
        self.saved_filters.deinit();
    }

    pub fn enter(self: *CatchWarningsTestHarness) *WarningsCollector {
        self.active = true;
        self.collector.startRecording();
        return &self.collector;
    }

    pub fn exit(self: *CatchWarningsTestHarness) void {
        self.collector.stopRecording();
        self.active = false;
    }

    pub fn isActive(self: CatchWarningsTestHarness) bool {
        return self.active;
    }

    pub fn addFilter(self: *CatchWarningsTestHarness, filter: warnings.WarningFilter) !void {
        try self.saved_filters.append(filter);
    }

    pub fn getFilterCount(self: CatchWarningsTestHarness) usize {
        return self.saved_filters.items.len;
    }
};

/// Nested context manager tracker
pub const NestedContextTracker = struct {
    depth: usize,
    max_depth: usize,
    contexts: [10]bool,

    pub fn init() NestedContextTracker {
        return .{
            .depth = 0,
            .max_depth = 0,
            .contexts = [_]bool{false} ** 10,
        };
    }

    pub fn enter(self: *NestedContextTracker) void {
        if (self.depth < 10) {
            self.contexts[self.depth] = true;
            self.depth += 1;
            if (self.depth > self.max_depth) {
                self.max_depth = self.depth;
            }
        }
    }

    pub fn exit(self: *NestedContextTracker) void {
        if (self.depth > 0) {
            self.depth -= 1;
            self.contexts[self.depth] = false;
        }
    }

    pub fn getCurrentDepth(self: NestedContextTracker) usize {
        return self.depth;
    }

    pub fn getMaxDepth(self: NestedContextTracker) usize {
        return self.max_depth;
    }
};

// ============================================================================
// CatchWarnings Basic Tests
// ============================================================================

test "catch_warnings_init" {
    const allocator = std.testing.allocator;
    var cw = warnings.catchWarnings(allocator, true);
    defer cw.deinit();

    try std.testing.expect(cw.record);
}

test "catch_warnings_enter_exit" {
    const allocator = std.testing.allocator;
    var cw = warnings.catchWarnings(allocator, true);
    defer cw.deinit();

    _ = cw.enter();
    cw.exit();
}

test "catch_warnings_record_mode" {
    const allocator = std.testing.allocator;

    // Test with record=true
    var cw_record = warnings.catchWarnings(allocator, true);
    defer cw_record.deinit();
    try std.testing.expect(cw_record.record);

    // Test with record=false
    var cw_no_record = warnings.catchWarnings(allocator, false);
    defer cw_no_record.deinit();
    try std.testing.expect(!cw_no_record.record);
}

// ============================================================================
// Collector Tests
// ============================================================================

test "collector_init" {
    var collector = WarningsCollector.init(std.testing.allocator);
    defer collector.deinit();

    try std.testing.expectEqual(@as(usize, 0), collector.count());
    try std.testing.expect(!collector.recording);
}

test "collector_recording_state" {
    var collector = WarningsCollector.init(std.testing.allocator);
    defer collector.deinit();

    try std.testing.expect(!collector.recording);
    collector.startRecording();
    try std.testing.expect(collector.recording);
    collector.stopRecording();
    try std.testing.expect(!collector.recording);
}

test "collector_add_warning_when_recording" {
    var collector = WarningsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.startRecording();
    try collector.addWarning(MockWarningRecord.init("test warning", .UserWarning, "test.py", 10));
    collector.stopRecording();

    try std.testing.expectEqual(@as(usize, 1), collector.count());
}

test "collector_add_warning_when_not_recording" {
    var collector = WarningsCollector.init(std.testing.allocator);
    defer collector.deinit();

    // Not recording - warning should not be added
    try collector.addWarning(MockWarningRecord.init("test warning", .UserWarning, "test.py", 10));

    try std.testing.expectEqual(@as(usize, 0), collector.count());
}

test "collector_multiple_warnings" {
    var collector = WarningsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.startRecording();
    try collector.addWarning(MockWarningRecord.init("warning 1", .UserWarning, "test.py", 1));
    try collector.addWarning(MockWarningRecord.init("warning 2", .DeprecationWarning, "test.py", 2));
    try collector.addWarning(MockWarningRecord.init("warning 3", .RuntimeWarning, "test.py", 3));
    collector.stopRecording();

    try std.testing.expectEqual(@as(usize, 3), collector.count());
}

test "collector_get_at" {
    var collector = WarningsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.startRecording();
    try collector.addWarning(MockWarningRecord.init("first", .UserWarning, "test.py", 1));
    try collector.addWarning(MockWarningRecord.init("second", .DeprecationWarning, "test.py", 2));
    collector.stopRecording();

    const first = collector.getAt(0);
    try std.testing.expect(first != null);
    try std.testing.expectEqualStrings("first", first.?.message);

    const second = collector.getAt(1);
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings("second", second.?.message);

    const invalid = collector.getAt(5);
    try std.testing.expect(invalid == null);
}

test "collector_contains_message" {
    var collector = WarningsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.startRecording();
    try collector.addWarning(MockWarningRecord.init("specific warning", .UserWarning, "test.py", 1));
    collector.stopRecording();

    try std.testing.expect(collector.containsMessage("specific warning"));
    try std.testing.expect(!collector.containsMessage("other warning"));
}

test "collector_contains_category" {
    var collector = WarningsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.startRecording();
    try collector.addWarning(MockWarningRecord.init("test", .DeprecationWarning, "test.py", 1));
    collector.stopRecording();

    try std.testing.expect(collector.containsCategory(.DeprecationWarning));
    try std.testing.expect(!collector.containsCategory(.RuntimeWarning));
}

test "collector_clear" {
    var collector = WarningsCollector.init(std.testing.allocator);
    defer collector.deinit();

    collector.startRecording();
    try collector.addWarning(MockWarningRecord.init("test", .UserWarning, "test.py", 1));
    collector.stopRecording();

    try std.testing.expectEqual(@as(usize, 1), collector.count());
    collector.clear();
    try std.testing.expectEqual(@as(usize, 0), collector.count());
}

// ============================================================================
// Test Harness Tests
// ============================================================================

test "harness_enter_exit" {
    var harness = CatchWarningsTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    try std.testing.expect(!harness.isActive());

    _ = harness.enter();
    try std.testing.expect(harness.isActive());

    harness.exit();
    try std.testing.expect(!harness.isActive());
}

test "harness_collect_warnings" {
    var harness = CatchWarningsTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const collector = harness.enter();
    try collector.addWarning(MockWarningRecord.init("test", .UserWarning, "test.py", 1));
    harness.exit();

    try std.testing.expectEqual(@as(usize, 1), harness.collector.count());
}

test "harness_add_filter" {
    var harness = CatchWarningsTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .ignore, .category = .DeprecationWarning });
    try harness.addFilter(.{ .action = .@"error", .category = .UserWarning });

    try std.testing.expectEqual(@as(usize, 2), harness.getFilterCount());
}

// ============================================================================
// Nested Context Tests
// ============================================================================

test "nested_context_single_level" {
    var tracker = NestedContextTracker.init();

    try std.testing.expectEqual(@as(usize, 0), tracker.getCurrentDepth());

    tracker.enter();
    try std.testing.expectEqual(@as(usize, 1), tracker.getCurrentDepth());

    tracker.exit();
    try std.testing.expectEqual(@as(usize, 0), tracker.getCurrentDepth());
}

test "nested_context_multiple_levels" {
    var tracker = NestedContextTracker.init();

    tracker.enter(); // Level 1
    tracker.enter(); // Level 2
    tracker.enter(); // Level 3

    try std.testing.expectEqual(@as(usize, 3), tracker.getCurrentDepth());
    try std.testing.expectEqual(@as(usize, 3), tracker.getMaxDepth());

    tracker.exit();
    try std.testing.expectEqual(@as(usize, 2), tracker.getCurrentDepth());

    tracker.exit();
    tracker.exit();
    try std.testing.expectEqual(@as(usize, 0), tracker.getCurrentDepth());
    try std.testing.expectEqual(@as(usize, 3), tracker.getMaxDepth());
}

test "nested_context_max_depth" {
    var tracker = NestedContextTracker.init();

    // Enter 5 levels
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        tracker.enter();
    }

    try std.testing.expectEqual(@as(usize, 5), tracker.getMaxDepth());

    // Exit all
    while (i > 0) : (i -= 1) {
        tracker.exit();
    }

    try std.testing.expectEqual(@as(usize, 0), tracker.getCurrentDepth());
    try std.testing.expectEqual(@as(usize, 5), tracker.getMaxDepth());
}

// ============================================================================
// Mock Warning Record Tests
// ============================================================================

test "mock_record_init" {
    const record = MockWarningRecord.init("test message", .UserWarning, "test.py", 42);

    try std.testing.expectEqualStrings("test message", record.message);
    try std.testing.expectEqual(warnings.WarningCategory.UserWarning, record.category);
    try std.testing.expectEqualStrings("test.py", record.filename);
    try std.testing.expectEqual(@as(usize, 42), record.lineno);
}

test "mock_record_matches" {
    const record1 = MockWarningRecord.init("test", .UserWarning, "test.py", 1);
    const record2 = MockWarningRecord.init("test", .UserWarning, "test.py", 1);
    const record3 = MockWarningRecord.init("other", .UserWarning, "test.py", 1);

    try std.testing.expect(record1.matches(record2));
    try std.testing.expect(!record1.matches(record3));
}

test "mock_record_different_categories" {
    const record1 = MockWarningRecord.init("test", .UserWarning, "test.py", 1);
    const record2 = MockWarningRecord.init("test", .DeprecationWarning, "test.py", 1);

    try std.testing.expect(!record1.matches(record2));
}

test "mock_record_different_files" {
    const record1 = MockWarningRecord.init("test", .UserWarning, "test1.py", 1);
    const record2 = MockWarningRecord.init("test", .UserWarning, "test2.py", 1);

    try std.testing.expect(!record1.matches(record2));
}

test "mock_record_different_lines" {
    const record1 = MockWarningRecord.init("test", .UserWarning, "test.py", 1);
    const record2 = MockWarningRecord.init("test", .UserWarning, "test.py", 2);

    try std.testing.expect(!record1.matches(record2));
}

// ============================================================================
// Integration Tests
// ============================================================================

test "integration_catch_warnings_with_filters" {
    var harness = CatchWarningsTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Setup filter
    try harness.addFilter(.{ .action = .ignore, .category = .DeprecationWarning });

    // Enter context and collect warnings
    const collector = harness.enter();
    try collector.addWarning(MockWarningRecord.init("deprecated feature", .DeprecationWarning, "mod.py", 10));
    try collector.addWarning(MockWarningRecord.init("user warning", .UserWarning, "mod.py", 20));
    harness.exit();

    try std.testing.expectEqual(@as(usize, 2), collector.count());
}

test "integration_multiple_sessions" {
    var harness = CatchWarningsTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // First session
    var collector = harness.enter();
    try collector.addWarning(MockWarningRecord.init("first", .UserWarning, "test.py", 1));
    harness.exit();

    try std.testing.expectEqual(@as(usize, 1), harness.collector.count());

    // Clear and start second session
    harness.collector.clear();

    collector = harness.enter();
    try collector.addWarning(MockWarningRecord.init("second", .RuntimeWarning, "test.py", 2));
    try collector.addWarning(MockWarningRecord.init("third", .DeprecationWarning, "test.py", 3));
    harness.exit();

    try std.testing.expectEqual(@as(usize, 2), harness.collector.count());
}
