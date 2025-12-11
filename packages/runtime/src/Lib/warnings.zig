//! CPython source: Lib/warnings.py
//!
//! Provides functions to issue warnings and control warning behavior.
//!
//! Mirrors: CPython Lib/warnings.py

// Re-export all public types
pub const FrameInfo = @import("warnings/types.zig").FrameInfo;
pub const WarningCategory = @import("warnings/types.zig").WarningCategory;
pub const FilterAction = @import("warnings/types.zig").FilterAction;
pub const WarningFilter = @import("warnings/types.zig").WarningFilter;
pub const WarningRecord = @import("warnings/types.zig").WarningRecord;

// Re-export stack functions
pub const pushFrame = @import("warnings/stack.zig").pushFrame;
pub const popFrame = @import("warnings/stack.zig").popFrame;
pub const clearCallStack = @import("warnings/stack.zig").clearCallStack;

// Re-export state
pub const WarningsState = @import("warnings/state.zig").WarningsState;

// Re-export core warning functions
pub const warn = @import("warnings/warn.zig").warn;
pub const warnExplicit = @import("warnings/warn.zig").warnExplicit;

// Re-export filter management
pub const simpleFilter = @import("warnings/filters.zig").simpleFilter;
pub const filterWarnings = @import("warnings/filters.zig").filterWarnings;
pub const resetWarnings = @import("warnings/filters.zig").resetWarnings;

// Re-export formatting functions
pub const formatWarning = @import("warnings/format.zig").formatWarning;
pub const showWarning = @import("warnings/format.zig").showWarning;

// Re-export convenience functions
pub const deprecationWarning = @import("warnings/convenience.zig").deprecationWarning;
pub const pendingDeprecationWarning = @import("warnings/convenience.zig").pendingDeprecationWarning;
pub const runtimeWarning = @import("warnings/convenience.zig").runtimeWarning;
pub const syntaxWarning = @import("warnings/convenience.zig").syntaxWarning;
pub const userWarning = @import("warnings/convenience.zig").userWarning;
pub const futureWarning = @import("warnings/convenience.zig").futureWarning;
pub const importWarning = @import("warnings/convenience.zig").importWarning;
pub const resourceWarning = @import("warnings/convenience.zig").resourceWarning;

// Re-export context manager
pub const CatchWarnings = @import("warnings/context.zig").CatchWarnings;
pub const catchWarnings = @import("warnings/context.zig").catchWarnings;

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");

test "WarningCategory names" {
    try std.testing.expectEqualStrings("DeprecationWarning", WarningCategory.DeprecationWarning.name());
    try std.testing.expectEqualStrings("UserWarning", WarningCategory.UserWarning.name());
    try std.testing.expectEqualStrings("RuntimeWarning", WarningCategory.RuntimeWarning.name());
}

test "WarningCategory isSubclassOf" {
    try std.testing.expect(WarningCategory.DeprecationWarning.isSubclassOf(.Warning));
    try std.testing.expect(WarningCategory.UserWarning.isSubclassOf(.Warning));
    try std.testing.expect(WarningCategory.Warning.isSubclassOf(.Warning));
    try std.testing.expect(!WarningCategory.DeprecationWarning.isSubclassOf(.UserWarning));
}

test "FilterAction conversion" {
    try std.testing.expectEqual(FilterAction.default, FilterAction.fromString("default").?);
    try std.testing.expectEqual(FilterAction.@"error", FilterAction.fromString("error").?);
    try std.testing.expectEqual(FilterAction.ignore, FilterAction.fromString("ignore").?);
    try std.testing.expect(FilterAction.fromString("invalid") == null);

    try std.testing.expectEqualStrings("always", FilterAction.always.toString());
}

test "WarningFilter matches" {
    const filter = WarningFilter{
        .action = .ignore,
        .category = .DeprecationWarning,
    };

    // Should match DeprecationWarning
    try std.testing.expect(filter.matches("test", .DeprecationWarning, "module", 1));

    // Should not match UserWarning (not a subclass of DeprecationWarning)
    try std.testing.expect(!filter.matches("test", .UserWarning, "module", 1));
}

test "WarningsState" {
    const allocator = std.testing.allocator;

    var state = WarningsState.init(allocator);
    defer state.deinit();

    try state.appendFilter(.{
        .action = .ignore,
        .category = .DeprecationWarning,
    });

    try std.testing.expectEqual(FilterAction.ignore, state.getAction("test", .DeprecationWarning, "mod", 1));
    try std.testing.expectEqual(FilterAction.default, state.getAction("test", .UserWarning, "mod", 1));
}

test "CatchWarnings" {
    const allocator = std.testing.allocator;

    var cw = catchWarnings(allocator, true);
    defer cw.deinit();

    _ = cw.enter();
    // Would record warnings here
    cw.exit();
}

test "formatWarning" {
    const allocator = std.testing.allocator;

    const formatted = try formatWarning(
        allocator,
        "test warning",
        .UserWarning,
        "test.py",
        42,
        null,
    );
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "UserWarning") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "test.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "42") != null);
}
