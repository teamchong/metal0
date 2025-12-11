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

// Re-export submodules
pub const gil = @import("interpconfig/gil.zig");
pub const config = @import("interpconfig/config.zig");
pub const state = @import("interpconfig/state.zig");
pub const manager = @import("interpconfig/manager.zig");
pub const cross_interp_data = @import("interpconfig/cross_interp_data.zig");
pub const global = @import("interpconfig/global.zig");

// Re-export common types for convenience
pub const GILMode = gil.GILMode;
pub const CheckMultiInterpExtensions = gil.CheckMultiInterpExtensions;
pub const PyInterpreterConfig = config.PyInterpreterConfig;
pub const InterpId = state.InterpId;
pub const InterpreterState = state.InterpreterState;
pub const InterpreterManager = manager.InterpreterManager;
pub const CrossInterpDataType = cross_interp_data.CrossInterpDataType;
pub const CrossInterpData = cross_interp_data.CrossInterpData;
pub const getManager = global.getManager;
pub const deinitManager = global.deinitManager;

/// Initialization
pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "interpreter config defaults" {
    const cfg = PyInterpreterConfig.initDefault();
    try std.testing.expect(!cfg.use_main_obmalloc);
    try std.testing.expect(cfg.allow_fork);
    try std.testing.expect(cfg.allow_threads);
    try std.testing.expectEqual(GILMode.default, cfg.gil);
}

test "interpreter config isolated" {
    const cfg = PyInterpreterConfig.initIsolated();
    try std.testing.expect(!cfg.allow_fork);
    try std.testing.expect(!cfg.allow_exec);
    try std.testing.expect(!cfg.allow_daemon_threads);
    try std.testing.expectEqual(GILMode.own, cfg.gil);
}

test "interpreter config legacy" {
    const cfg = PyInterpreterConfig.initLegacy();
    try std.testing.expect(cfg.use_main_obmalloc);
    try std.testing.expect(cfg.allow_fork);
    try std.testing.expect(cfg.allow_daemon_threads);
    try std.testing.expectEqual(GILMode.shared, cfg.gil);
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
    const cfg = PyInterpreterConfig.initDefault();
    var st = InterpreterState.create(42, cfg, false);

    try std.testing.expectEqual(@as(u64, 42), st.id);
    try std.testing.expect(!st.is_main);
    try std.testing.expect(!st.finalized);
}

test "interpreter manager" {
    var mgr = InterpreterManager.init(std.testing.allocator);
    defer mgr.deinit();

    // Create main
    const main_interp = try mgr.createMain();
    try std.testing.expect(main_interp.is_main);
    try std.testing.expectEqual(@as(usize, 1), mgr.count());

    // Create sub-interpreter
    const cfg = PyInterpreterConfig.initIsolated();
    const sub = try mgr.createSubInterpreter(cfg);
    try std.testing.expect(!sub.is_main);
    try std.testing.expect(sub.id > 0);
    try std.testing.expectEqual(@as(usize, 2), mgr.count());

    // Get by ID
    const found = mgr.getById(sub.id);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(sub.id, found.?.id);

    // Destroy sub
    try mgr.destroyInterpreter(sub);
    try std.testing.expectEqual(@as(usize, 1), mgr.count());

    // Can't destroy main
    try std.testing.expectError(error.CannotDestroyMain, mgr.destroyInterpreter(main_interp));
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
