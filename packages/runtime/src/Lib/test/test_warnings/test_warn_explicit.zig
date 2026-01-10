//! test.test_warnings.test_warn_explicit - Comprehensive tests for warn_explicit
//!
//! Tests the warn_explicit function for issuing warnings with explicit origin.
//! Mirrors CPython's warn_explicit tests.

const std = @import("std");
const warnings = @import("Lib.warnings");

// ============================================================================
// Test Types
// ============================================================================

/// Explicit warning parameters
pub const ExplicitWarningParams = struct {
    message: []const u8,
    category: warnings.WarningCategory,
    filename: []const u8,
    lineno: usize,
    module_name: ?[]const u8 = null,
    source: ?[]const u8 = null,

    pub fn validate(self: ExplicitWarningParams) ValidationResult {
        var result = ValidationResult{};

        result.has_message = self.message.len > 0;
        result.has_filename = self.filename.len > 0;
        result.has_lineno = self.lineno > 0;
        result.is_valid = result.has_message and result.has_filename;

        return result;
    }

    pub const ValidationResult = struct {
        has_message: bool = false,
        has_filename: bool = false,
        has_lineno: bool = false,
        is_valid: bool = false,
    };
};

/// Explicit warning capture
pub const ExplicitWarningCapture = struct {
    params: ?ExplicitWarningParams,
    action_taken: ?warnings.FilterAction,
    captured: bool,

    pub fn init() ExplicitWarningCapture {
        return .{
            .params = null,
            .action_taken = null,
            .captured = false,
        };
    }

    pub fn capture(self: *ExplicitWarningCapture, params: ExplicitWarningParams, action: warnings.FilterAction) void {
        self.params = params;
        self.action_taken = action;
        self.captured = true;
    }

    pub fn reset(self: *ExplicitWarningCapture) void {
        self.params = null;
        self.action_taken = null;
        self.captured = false;
    }
};

/// Warn explicit test harness
pub const WarnExplicitHarness = struct {
    state: warnings.WarningsState,
    captures: std.ArrayList(ExplicitWarningCapture),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WarnExplicitHarness {
        return .{
            .state = warnings.WarningsState.init(allocator),
            .captures = std.ArrayList(ExplicitWarningCapture).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WarnExplicitHarness) void {
        self.captures.deinit();
        self.state.deinit();
    }

    pub fn addFilter(self: *WarnExplicitHarness, filter: warnings.WarningFilter) !void {
        try self.state.appendFilter(filter);
    }

    pub fn warnExplicit(
        self: *WarnExplicitHarness,
        message: []const u8,
        category: warnings.WarningCategory,
        filename: []const u8,
        lineno: usize,
        module_name: ?[]const u8,
    ) !WarnResult {
        const mod = module_name orelse filename;
        const action = self.state.getAction(message, category, mod, lineno);

        var cap = ExplicitWarningCapture.init();
        cap.capture(.{
            .message = message,
            .category = category,
            .filename = filename,
            .lineno = lineno,
            .module_name = module_name,
        }, action);
        try self.captures.append(cap);

        return switch (action) {
            .ignore => .ignored,
            .@"error" => .raised_error,
            else => .shown,
        };
    }

    pub fn getCaptureCount(self: WarnExplicitHarness) usize {
        return self.captures.items.len;
    }

    pub fn getLastCapture(self: WarnExplicitHarness) ?ExplicitWarningCapture {
        if (self.captures.items.len > 0) {
            return self.captures.items[self.captures.items.len - 1];
        }
        return null;
    }

    pub fn reset(self: *WarnExplicitHarness) void {
        self.captures.clearRetainingCapacity();
        self.state.resetFilters();
    }

    pub const WarnResult = enum {
        shown,
        ignored,
        raised_error,
    };
};

/// Module resolver for testing
pub const ModuleResolver = struct {
    filename_to_module: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ModuleResolver {
        return .{
            .filename_to_module = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ModuleResolver) void {
        self.filename_to_module.deinit();
    }

    pub fn register(self: *ModuleResolver, filename: []const u8, module: []const u8) !void {
        try self.filename_to_module.put(filename, module);
    }

    pub fn resolve(self: ModuleResolver, filename: []const u8) ?[]const u8 {
        return self.filename_to_module.get(filename);
    }

    pub fn resolveOrDefault(self: ModuleResolver, filename: []const u8) []const u8 {
        return self.filename_to_module.get(filename) orelse filename;
    }
};

// ============================================================================
// ExplicitWarningParams Tests
// ============================================================================

test "params_basic" {
    const params = ExplicitWarningParams{
        .message = "test message",
        .category = .UserWarning,
        .filename = "test.py",
        .lineno = 42,
    };

    try std.testing.expectEqualStrings("test message", params.message);
    try std.testing.expectEqual(warnings.WarningCategory.UserWarning, params.category);
    try std.testing.expectEqualStrings("test.py", params.filename);
    try std.testing.expectEqual(@as(usize, 42), params.lineno);
}

test "params_with_module" {
    const params = ExplicitWarningParams{
        .message = "test",
        .category = .DeprecationWarning,
        .filename = "mymodule/file.py",
        .lineno = 10,
        .module_name = "mymodule",
    };

    try std.testing.expectEqualStrings("mymodule", params.module_name.?);
}

test "params_validate" {
    const valid_params = ExplicitWarningParams{
        .message = "test",
        .category = .UserWarning,
        .filename = "test.py",
        .lineno = 1,
    };
    const valid_result = valid_params.validate();
    try std.testing.expect(valid_result.is_valid);

    const invalid_params = ExplicitWarningParams{
        .message = "",
        .category = .UserWarning,
        .filename = "test.py",
        .lineno = 1,
    };
    const invalid_result = invalid_params.validate();
    try std.testing.expect(!invalid_result.has_message);
}

test "params_validate_no_filename" {
    const params = ExplicitWarningParams{
        .message = "test",
        .category = .UserWarning,
        .filename = "",
        .lineno = 1,
    };
    const result = params.validate();
    try std.testing.expect(!result.has_filename);
    try std.testing.expect(!result.is_valid);
}

// ============================================================================
// ExplicitWarningCapture Tests
// ============================================================================

test "capture_init" {
    const capture = ExplicitWarningCapture.init();

    try std.testing.expect(!capture.captured);
    try std.testing.expect(capture.params == null);
    try std.testing.expect(capture.action_taken == null);
}

test "capture_capture" {
    var capture = ExplicitWarningCapture.init();

    const params = ExplicitWarningParams{
        .message = "test",
        .category = .UserWarning,
        .filename = "test.py",
        .lineno = 1,
    };

    capture.capture(params, .always);

    try std.testing.expect(capture.captured);
    try std.testing.expectEqualStrings("test", capture.params.?.message);
    try std.testing.expectEqual(warnings.FilterAction.always, capture.action_taken.?);
}

test "capture_reset" {
    var capture = ExplicitWarningCapture.init();

    capture.capture(.{
        .message = "test",
        .category = .UserWarning,
        .filename = "test.py",
        .lineno = 1,
    }, .ignore);

    try std.testing.expect(capture.captured);

    capture.reset();
    try std.testing.expect(!capture.captured);
    try std.testing.expect(capture.params == null);
}

// ============================================================================
// WarnExplicitHarness Tests
// ============================================================================

test "harness_init" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
    defer harness.deinit();

    try std.testing.expectEqual(@as(usize, 0), harness.getCaptureCount());
}

test "harness_warn_explicit_basic" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .always, .category = .Warning });

    const result = try harness.warnExplicit(
        "test message",
        .UserWarning,
        "test.py",
        42,
        null,
    );

    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.shown, result);
    try std.testing.expectEqual(@as(usize, 1), harness.getCaptureCount());
}

test "harness_warn_explicit_with_module" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .ignore, .module = "mymodule", .category = .Warning });

    const result = try harness.warnExplicit(
        "test",
        .UserWarning,
        "mymodule/file.py",
        10,
        "mymodule",
    );

    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.ignored, result);
}

test "harness_warn_explicit_ignore" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .ignore, .category = .DeprecationWarning });

    const result = try harness.warnExplicit(
        "deprecated",
        .DeprecationWarning,
        "test.py",
        1,
        null,
    );

    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.ignored, result);
}

test "harness_warn_explicit_error" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .@"error", .category = .Warning });

    const result = try harness.warnExplicit(
        "critical",
        .UserWarning,
        "test.py",
        1,
        null,
    );

    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.raised_error, result);
}

test "harness_get_last_capture" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .always, .category = .Warning });

    _ = try harness.warnExplicit("first", .UserWarning, "a.py", 1, null);
    _ = try harness.warnExplicit("second", .DeprecationWarning, "b.py", 2, null);

    const last = harness.getLastCapture();
    try std.testing.expect(last != null);
    try std.testing.expectEqualStrings("second", last.?.params.?.message);
}

test "harness_reset" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .always, .category = .Warning });
    _ = try harness.warnExplicit("test", .UserWarning, "test.py", 1, null);

    try std.testing.expectEqual(@as(usize, 1), harness.getCaptureCount());

    harness.reset();
    try std.testing.expectEqual(@as(usize, 0), harness.getCaptureCount());
}

// ============================================================================
// ModuleResolver Tests
// ============================================================================

test "resolver_init" {
    var resolver = ModuleResolver.init(std.testing.allocator);
    defer resolver.deinit();

    try std.testing.expect(resolver.resolve("test.py") == null);
}

test "resolver_register" {
    var resolver = ModuleResolver.init(std.testing.allocator);
    defer resolver.deinit();

    try resolver.register("mypackage/module.py", "mypackage.module");

    const module = resolver.resolve("mypackage/module.py");
    try std.testing.expect(module != null);
    try std.testing.expectEqualStrings("mypackage.module", module.?);
}

test "resolver_resolve_or_default" {
    var resolver = ModuleResolver.init(std.testing.allocator);
    defer resolver.deinit();

    try resolver.register("known.py", "known_module");

    // Known file
    const known = resolver.resolveOrDefault("known.py");
    try std.testing.expectEqualStrings("known_module", known);

    // Unknown file - returns filename
    const unknown = resolver.resolveOrDefault("unknown.py");
    try std.testing.expectEqualStrings("unknown.py", unknown);
}

// ============================================================================
// Filename-Based Filter Tests
// ============================================================================

test "warn_explicit_filename_filter" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Filter based on module pattern (uses filename as module if module_name is null)
    try harness.addFilter(.{ .action = .ignore, .module = "test", .category = .Warning });

    // Should match - filename contains "test"
    var result = try harness.warnExplicit("msg", .UserWarning, "test_module.py", 1, null);
    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.ignored, result);

    // Should not match - filename doesn't contain "test"
    result = try harness.warnExplicit("msg", .UserWarning, "other.py", 1, null);
    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.shown, result);
}

test "warn_explicit_lineno_filter" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .ignore, .lineno = 42, .category = .Warning });

    // Should match specific line
    var result = try harness.warnExplicit("msg", .UserWarning, "test.py", 42, null);
    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.ignored, result);

    // Should not match other lines
    result = try harness.warnExplicit("msg", .UserWarning, "test.py", 1, null);
    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.shown, result);
}

// ============================================================================
// All Categories Tests
// ============================================================================

test "warn_explicit_all_categories" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
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
        const result = try harness.warnExplicit("test", cat, "test.py", 1, null);
        try std.testing.expectEqual(WarnExplicitHarness.WarnResult.shown, result);
    }

    try std.testing.expectEqual(@as(usize, 12), harness.getCaptureCount());
}

// ============================================================================
// Integration Tests
// ============================================================================

test "integration_warn_explicit_workflow" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Set up filters
    try harness.addFilter(.{ .action = .ignore, .category = .DeprecationWarning });
    try harness.addFilter(.{ .action = .@"error", .message = "critical", .category = .Warning });
    try harness.addFilter(.{ .action = .always, .category = .Warning });

    // Test deprecation - should be ignored
    var result = try harness.warnExplicit(
        "deprecated feature",
        .DeprecationWarning,
        "module.py",
        50,
        "mymodule",
    );
    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.ignored, result);

    // Test critical warning - should be error
    result = try harness.warnExplicit(
        "critical issue",
        .RuntimeWarning,
        "critical.py",
        100,
        null,
    );
    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.raised_error, result);

    // Test regular warning - should be shown
    result = try harness.warnExplicit(
        "regular warning",
        .UserWarning,
        "main.py",
        10,
        "main",
    );
    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.shown, result);
}

test "integration_module_resolution" {
    var resolver = ModuleResolver.init(std.testing.allocator);
    defer resolver.deinit();

    // Register modules
    try resolver.register("mypackage/__init__.py", "mypackage");
    try resolver.register("mypackage/utils.py", "mypackage.utils");
    try resolver.register("mypackage/core/engine.py", "mypackage.core.engine");

    // Test resolution
    try std.testing.expectEqualStrings("mypackage", resolver.resolveOrDefault("mypackage/__init__.py"));
    try std.testing.expectEqualStrings("mypackage.utils", resolver.resolveOrDefault("mypackage/utils.py"));
    try std.testing.expectEqualStrings("mypackage.core.engine", resolver.resolveOrDefault("mypackage/core/engine.py"));

    // Unknown files return filename
    try std.testing.expectEqualStrings("unknown.py", resolver.resolveOrDefault("unknown.py"));
}

test "integration_complex_explicit_warnings" {
    var harness = WarnExplicitHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Complex filter chain
    try harness.addFilter(.{ .action = .always, .category = .Warning });
    try harness.addFilter(.{ .action = .ignore, .module = "test_", .category = .Warning });
    try harness.addFilter(.{ .action = .@"error", .lineno = 100, .category = .Warning });

    // Specific line should error
    var result = try harness.warnExplicit("msg", .UserWarning, "main.py", 100, "main");
    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.raised_error, result);

    // Test module should be ignored
    result = try harness.warnExplicit("msg", .UserWarning, "test_file.py", 50, "test_module");
    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.ignored, result);

    // Regular warning should be shown
    result = try harness.warnExplicit("msg", .UserWarning, "main.py", 50, "main");
    try std.testing.expectEqual(WarnExplicitHarness.WarnResult.shown, result);
}
