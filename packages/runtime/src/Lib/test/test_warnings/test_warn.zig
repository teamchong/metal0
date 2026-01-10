//! test.test_warnings.test_warn - Comprehensive tests for warn function
//!
//! Tests the warn function for issuing warnings with stack-level tracking.
//! Mirrors CPython's warn tests.

const std = @import("std");
const warnings = @import("Lib.warnings");

// ============================================================================
// Test Types
// ============================================================================

/// Mock frame info for testing
pub const MockFrame = struct {
    filename: []const u8,
    lineno: usize,
    function: []const u8,

    pub fn init(filename: []const u8, lineno: usize, function: []const u8) MockFrame {
        return .{
            .filename = filename,
            .lineno = lineno,
            .function = function,
        };
    }

    pub fn toFrameInfo(self: MockFrame) warnings.FrameInfo {
        return .{
            .filename = self.filename,
            .lineno = self.lineno,
            .function = self.function,
        };
    }
};

/// Warning capture for testing
pub const WarningCapture = struct {
    message: ?[]const u8,
    category: ?warnings.WarningCategory,
    filename: ?[]const u8,
    lineno: ?usize,
    captured: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WarningCapture {
        return .{
            .message = null,
            .category = null,
            .filename = null,
            .lineno = null,
            .captured = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WarningCapture) void {
        if (self.message) |msg| {
            self.allocator.free(msg);
        }
        if (self.filename) |fname| {
            self.allocator.free(fname);
        }
    }

    pub fn capture(
        self: *WarningCapture,
        message: []const u8,
        category: warnings.WarningCategory,
        filename: []const u8,
        lineno: usize,
    ) !void {
        if (self.message) |msg| {
            self.allocator.free(msg);
        }
        if (self.filename) |fname| {
            self.allocator.free(fname);
        }

        self.message = try self.allocator.dupe(u8, message);
        self.category = category;
        self.filename = try self.allocator.dupe(u8, filename);
        self.lineno = lineno;
        self.captured = true;
    }

    pub fn reset(self: *WarningCapture) void {
        if (self.message) |msg| {
            self.allocator.free(msg);
            self.message = null;
        }
        if (self.filename) |fname| {
            self.allocator.free(fname);
            self.filename = null;
        }
        self.category = null;
        self.lineno = null;
        self.captured = false;
    }
};

/// Warn test harness
pub const WarnTestHarness = struct {
    state: warnings.WarningsState,
    captures: std.ArrayList(WarningCapture),
    allocator: std.mem.Allocator,
    suppress_output: bool,

    pub fn init(allocator: std.mem.Allocator) WarnTestHarness {
        return .{
            .state = warnings.WarningsState.init(allocator),
            .captures = std.ArrayList(WarningCapture).init(allocator),
            .allocator = allocator,
            .suppress_output = true,
        };
    }

    pub fn deinit(self: *WarnTestHarness) void {
        for (self.captures.items) |*cap| {
            cap.deinit();
        }
        self.captures.deinit();
        self.state.deinit();
    }

    pub fn addFilter(self: *WarnTestHarness, filter: warnings.WarningFilter) !void {
        try self.state.appendFilter(filter);
    }

    pub fn getAction(
        self: WarnTestHarness,
        message: []const u8,
        category: warnings.WarningCategory,
    ) warnings.FilterAction {
        return self.state.getAction(message, category, "<module>", 0);
    }

    pub fn simulateWarn(
        self: *WarnTestHarness,
        message: []const u8,
        category: warnings.WarningCategory,
    ) !WarnResult {
        const action = self.getAction(message, category);

        switch (action) {
            .ignore => return .ignored,
            .@"error" => return .raised_error,
            .always => {
                var cap = WarningCapture.init(self.allocator);
                try cap.capture(message, category, "<module>", 0);
                try self.captures.append(cap);
                return .shown;
            },
            .once => {
                if (!self.state.hasSeen(message)) {
                    try self.state.markSeen(message);
                    var cap = WarningCapture.init(self.allocator);
                    try cap.capture(message, category, "<module>", 0);
                    try self.captures.append(cap);
                    return .shown;
                }
                return .ignored;
            },
            else => {
                if (!self.state.hasSeen(message)) {
                    try self.state.markSeen(message);
                    var cap = WarningCapture.init(self.allocator);
                    try cap.capture(message, category, "<module>", 0);
                    try self.captures.append(cap);
                    return .shown;
                }
                return .ignored;
            },
        }
    }

    pub fn getCaptureCount(self: WarnTestHarness) usize {
        return self.captures.items.len;
    }

    pub fn getLastCapture(self: WarnTestHarness) ?*WarningCapture {
        if (self.captures.items.len > 0) {
            return &self.captures.items[self.captures.items.len - 1];
        }
        return null;
    }

    pub const WarnResult = enum {
        shown,
        ignored,
        raised_error,
    };
};

/// Stack level calculator
pub const StackLevelCalculator = struct {
    frames: [10]MockFrame,
    frame_count: usize,

    pub fn init() StackLevelCalculator {
        return .{
            .frames = undefined,
            .frame_count = 0,
        };
    }

    pub fn pushFrame(self: *StackLevelCalculator, frame: MockFrame) void {
        if (self.frame_count < 10) {
            self.frames[self.frame_count] = frame;
            self.frame_count += 1;
        }
    }

    pub fn popFrame(self: *StackLevelCalculator) ?MockFrame {
        if (self.frame_count > 0) {
            self.frame_count -= 1;
            return self.frames[self.frame_count];
        }
        return null;
    }

    pub fn getFrame(self: StackLevelCalculator, level: usize) ?MockFrame {
        if (level > 0 and level <= self.frame_count) {
            return self.frames[self.frame_count - level];
        }
        return null;
    }

    pub fn getCurrentDepth(self: StackLevelCalculator) usize {
        return self.frame_count;
    }
};

// ============================================================================
// MockFrame Tests
// ============================================================================

test "mock_frame_init" {
    const frame = MockFrame.init("test.py", 42, "test_function");

    try std.testing.expectEqualStrings("test.py", frame.filename);
    try std.testing.expectEqual(@as(usize, 42), frame.lineno);
    try std.testing.expectEqualStrings("test_function", frame.function);
}

test "mock_frame_to_frame_info" {
    const frame = MockFrame.init("module.py", 100, "main");
    const info = frame.toFrameInfo();

    try std.testing.expectEqualStrings("module.py", info.filename);
    try std.testing.expectEqual(@as(usize, 100), info.lineno);
    try std.testing.expectEqualStrings("main", info.function);
}

// ============================================================================
// WarningCapture Tests
// ============================================================================

test "capture_init" {
    var capture = WarningCapture.init(std.testing.allocator);
    defer capture.deinit();

    try std.testing.expect(!capture.captured);
    try std.testing.expect(capture.message == null);
}

test "capture_capture" {
    var capture = WarningCapture.init(std.testing.allocator);
    defer capture.deinit();

    try capture.capture("test warning", .UserWarning, "test.py", 10);

    try std.testing.expect(capture.captured);
    try std.testing.expectEqualStrings("test warning", capture.message.?);
    try std.testing.expectEqual(warnings.WarningCategory.UserWarning, capture.category.?);
    try std.testing.expectEqualStrings("test.py", capture.filename.?);
    try std.testing.expectEqual(@as(usize, 10), capture.lineno.?);
}

test "capture_reset" {
    var capture = WarningCapture.init(std.testing.allocator);
    defer capture.deinit();

    try capture.capture("test", .UserWarning, "test.py", 1);
    try std.testing.expect(capture.captured);

    capture.reset();
    try std.testing.expect(!capture.captured);
    try std.testing.expect(capture.message == null);
}

test "capture_multiple_captures" {
    var capture = WarningCapture.init(std.testing.allocator);
    defer capture.deinit();

    try capture.capture("first", .UserWarning, "a.py", 1);
    try std.testing.expectEqualStrings("first", capture.message.?);

    try capture.capture("second", .DeprecationWarning, "b.py", 2);
    try std.testing.expectEqualStrings("second", capture.message.?);
    try std.testing.expectEqual(warnings.WarningCategory.DeprecationWarning, capture.category.?);
}

// ============================================================================
// WarnTestHarness Tests
// ============================================================================

test "harness_init" {
    var harness = WarnTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    try std.testing.expectEqual(@as(usize, 0), harness.getCaptureCount());
}

test "harness_simulate_warn_always" {
    var harness = WarnTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .always, .category = .Warning });

    const result = try harness.simulateWarn("test warning", .UserWarning);
    try std.testing.expectEqual(WarnTestHarness.WarnResult.shown, result);
    try std.testing.expectEqual(@as(usize, 1), harness.getCaptureCount());
}

test "harness_simulate_warn_ignore" {
    var harness = WarnTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .ignore, .category = .Warning });

    const result = try harness.simulateWarn("test warning", .UserWarning);
    try std.testing.expectEqual(WarnTestHarness.WarnResult.ignored, result);
    try std.testing.expectEqual(@as(usize, 0), harness.getCaptureCount());
}

test "harness_simulate_warn_error" {
    var harness = WarnTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .@"error", .category = .Warning });

    const result = try harness.simulateWarn("test warning", .UserWarning);
    try std.testing.expectEqual(WarnTestHarness.WarnResult.raised_error, result);
}

test "harness_simulate_warn_once" {
    var harness = WarnTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .once, .category = .Warning });

    // First warning should be shown
    var result = try harness.simulateWarn("test warning", .UserWarning);
    try std.testing.expectEqual(WarnTestHarness.WarnResult.shown, result);

    // Same warning again should be ignored
    result = try harness.simulateWarn("test warning", .UserWarning);
    try std.testing.expectEqual(WarnTestHarness.WarnResult.ignored, result);

    // Only one capture
    try std.testing.expectEqual(@as(usize, 1), harness.getCaptureCount());
}

test "harness_get_last_capture" {
    var harness = WarnTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .always, .category = .Warning });

    _ = try harness.simulateWarn("first", .UserWarning);
    _ = try harness.simulateWarn("second", .DeprecationWarning);

    const last = harness.getLastCapture();
    try std.testing.expect(last != null);
    try std.testing.expectEqualStrings("second", last.?.message.?);
}

// ============================================================================
// StackLevelCalculator Tests
// ============================================================================

test "stack_level_init" {
    const calc = StackLevelCalculator.init();
    try std.testing.expectEqual(@as(usize, 0), calc.getCurrentDepth());
}

test "stack_level_push_pop" {
    var calc = StackLevelCalculator.init();

    calc.pushFrame(MockFrame.init("a.py", 1, "func_a"));
    calc.pushFrame(MockFrame.init("b.py", 2, "func_b"));
    calc.pushFrame(MockFrame.init("c.py", 3, "func_c"));

    try std.testing.expectEqual(@as(usize, 3), calc.getCurrentDepth());

    const popped = calc.popFrame();
    try std.testing.expect(popped != null);
    try std.testing.expectEqualStrings("c.py", popped.?.filename);
    try std.testing.expectEqual(@as(usize, 2), calc.getCurrentDepth());
}

test "stack_level_get_frame" {
    var calc = StackLevelCalculator.init();

    calc.pushFrame(MockFrame.init("a.py", 1, "func_a"));
    calc.pushFrame(MockFrame.init("b.py", 2, "func_b"));
    calc.pushFrame(MockFrame.init("c.py", 3, "func_c"));

    // Level 1 = most recent (c.py)
    const level1 = calc.getFrame(1);
    try std.testing.expect(level1 != null);
    try std.testing.expectEqualStrings("c.py", level1.?.filename);

    // Level 2 = one up (b.py)
    const level2 = calc.getFrame(2);
    try std.testing.expect(level2 != null);
    try std.testing.expectEqualStrings("b.py", level2.?.filename);

    // Level 3 = two up (a.py)
    const level3 = calc.getFrame(3);
    try std.testing.expect(level3 != null);
    try std.testing.expectEqualStrings("a.py", level3.?.filename);

    // Level 4 = invalid
    try std.testing.expect(calc.getFrame(4) == null);
}

// ============================================================================
// All Categories Tests
// ============================================================================

test "warn_all_categories" {
    var harness = WarnTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .always, .category = .Warning });

    const categories = [_]warnings.WarningCategory{
        .Warning,
        .UserWarning,
        .DeprecationWarning,
        .PendingDeprecationWarning,
        .SyntaxWarning,
        .RuntimeWarning,
        .FutureWarning,
        .ImportWarning,
        .UnicodeWarning,
        .BytesWarning,
        .EncodingWarning,
        .ResourceWarning,
    };

    for (categories) |cat| {
        const result = try harness.simulateWarn("test", cat);
        try std.testing.expectEqual(WarnTestHarness.WarnResult.shown, result);
    }

    try std.testing.expectEqual(@as(usize, 12), harness.getCaptureCount());
}

// ============================================================================
// Integration Tests
// ============================================================================

test "integration_warn_workflow" {
    var harness = WarnTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Set up filters
    try harness.addFilter(.{ .action = .ignore, .category = .DeprecationWarning });
    try harness.addFilter(.{ .action = .@"error", .message = "critical", .category = .Warning });
    try harness.addFilter(.{ .action = .always, .category = .Warning });

    // Deprecation warning should be ignored
    var result = try harness.simulateWarn("deprecated feature", .DeprecationWarning);
    try std.testing.expectEqual(WarnTestHarness.WarnResult.ignored, result);

    // Critical warning should raise error (but in our simulation, just returns error)
    result = try harness.simulateWarn("critical issue", .UserWarning);
    try std.testing.expectEqual(WarnTestHarness.WarnResult.raised_error, result);

    // Regular user warning should be shown
    result = try harness.simulateWarn("regular warning", .UserWarning);
    try std.testing.expectEqual(WarnTestHarness.WarnResult.shown, result);
}

test "integration_stack_level_simulation" {
    var calc = StackLevelCalculator.init();

    // Simulate call stack
    calc.pushFrame(MockFrame.init("main.py", 10, "main"));
    calc.pushFrame(MockFrame.init("utils.py", 20, "helper"));
    calc.pushFrame(MockFrame.init("warnings_mod.py", 30, "warn"));

    // Stack level 1 = warnings_mod.py (where warn is called)
    const level1 = calc.getFrame(1);
    try std.testing.expectEqualStrings("warnings_mod.py", level1.?.filename);

    // Stack level 2 = utils.py (caller of warn)
    const level2 = calc.getFrame(2);
    try std.testing.expectEqualStrings("utils.py", level2.?.filename);

    // Stack level 3 = main.py (caller's caller)
    const level3 = calc.getFrame(3);
    try std.testing.expectEqualStrings("main.py", level3.?.filename);
}
