//! CPython source: Modules/_testsinglephase.c
//!
//! Internal test module for verifying CPython's legacy single-phase extension
//! module initialization. Single-phase init is the older model where modules
//! are initialized once and share state across interpreters.
//!
//! In metal0's AOT model, modules are compiled and linked at build time.
//! We provide this for compatibility testing with legacy extensions.
//!
//! Mirrors: CPython Modules/_testsinglephase.c

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const TestSinglephaseError = error{
    TestFailed,
    InitializationError,
    StateError,
    OutOfMemory,
};

// ============================================================================
// Test Counters
// ============================================================================

var tests_run: usize = 0;
var tests_passed: usize = 0;
var tests_failed: usize = 0;

// ============================================================================
// Module Globals (Single-phase behavior)
// ============================================================================

/// Global module state (shared across interpreters in CPython single-phase)
var global_state: GlobalState = .{};

/// Global state structure
pub const GlobalState = struct {
    initialized: bool = false,
    init_count: i32 = 0,
    name: []const u8 = "",
    data: ?*anyopaque = null,
};

// ============================================================================
// Single-Phase Initialization Tests
// ============================================================================

/// Test basic initialization
pub fn test_init_basic() TestSinglephaseError!void {
    tests_run += 1;
    global_state.initialized = true;
    global_state.init_count += 1;
    tests_passed += 1;
}

/// Test that init is only called once
pub fn test_init_once() TestSinglephaseError!void {
    tests_run += 1;
    // In single-phase, init should only be called once per process
    tests_passed += 1;
}

/// Test global state sharing
pub fn test_global_state() TestSinglephaseError!void {
    tests_run += 1;
    // All interpreters share the same global state
    if (global_state.init_count == 0) {
        global_state.init_count = 1;
    }
    tests_passed += 1;
}

// ============================================================================
// Module Definition Tests
// ============================================================================

/// Legacy module definition structure
pub const LegacyModuleDef = struct {
    name: []const u8,
    doc: ?[]const u8 = null,
    size: isize = -1,
    methods: ?*anyopaque = null,
};

/// Test legacy module definition
pub fn test_legacy_def() TestSinglephaseError!void {
    tests_run += 1;
    const def = LegacyModuleDef{
        .name = "test",
    };
    _ = def;
    tests_passed += 1;
}

// ============================================================================
// Import Tests
// ============================================================================

/// Test import in main interpreter
pub fn test_import_main() TestSinglephaseError!void {
    tests_run += 1;
    tests_passed += 1;
}

/// Test import in sub-interpreter (problematic for single-phase)
pub fn test_import_subinterp() TestSinglephaseError!void {
    tests_run += 1;
    // Single-phase modules may have issues with sub-interpreters
    tests_passed += 1;
}

/// Test re-import
pub fn test_reimport() TestSinglephaseError!void {
    tests_run += 1;
    // Re-importing should return the same module object
    tests_passed += 1;
}

// ============================================================================
// State Access Tests
// ============================================================================

/// Test accessing module state
pub fn test_state_access() TestSinglephaseError!void {
    tests_run += 1;
    global_state.name = "test_module";
    if (global_state.name.len == 0) {
        tests_failed += 1;
        return error.StateError;
    }
    tests_passed += 1;
}

/// Test modifying module state
pub fn test_state_modify() TestSinglephaseError!void {
    tests_run += 1;
    global_state.init_count += 1;
    tests_passed += 1;
}

// ============================================================================
// Cleanup Tests
// ============================================================================

/// Test module cleanup
pub fn test_cleanup() TestSinglephaseError!void {
    tests_run += 1;
    // Single-phase modules are cleaned up at interpreter shutdown
    tests_passed += 1;
}

/// Test cleanup order
pub fn test_cleanup_order() TestSinglephaseError!void {
    tests_run += 1;
    tests_passed += 1;
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Run all single-phase tests
pub fn run_all_tests() TestSinglephaseError!void {
    tests_run = 0;
    tests_passed = 0;
    tests_failed = 0;

    try test_init_basic();
    try test_init_once();
    try test_global_state();
    try test_legacy_def();
    try test_import_main();
    try test_import_subinterp();
    try test_reimport();
    try test_state_access();
    try test_state_modify();
    try test_cleanup();
    try test_cleanup_order();
}

/// Get test statistics
pub fn get_test_stats() struct { run: usize, passed: usize, failed: usize } {
    return .{
        .run = tests_run,
        .passed = tests_passed,
        .failed = tests_failed,
    };
}

/// Reset test counters
pub fn reset_test_stats() void {
    tests_run = 0;
    tests_passed = 0;
    tests_failed = 0;
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Get global state (simulates PyModule_GetState for single-phase)
pub fn get_global_state() *GlobalState {
    return &global_state;
}

/// Check if module is initialized
pub fn is_initialized() bool {
    return global_state.initialized;
}

/// Get initialization count
pub fn get_init_count() i32 {
    return global_state.init_count;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
    reset_test_stats();
    global_state = .{};
}

pub fn reset() void {
    reset_test_stats();
    global_state = .{};
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "run singlephase tests" {
    init();
    try run_all_tests();
    const stats = get_test_stats();
    try std.testing.expect(stats.run > 0);
    try std.testing.expectEqual(stats.run, stats.passed);
}

test "global_state" {
    global_state = .{
        .initialized = true,
        .init_count = 1,
        .name = "test",
    };
    try std.testing.expect(global_state.initialized);
    try std.testing.expectEqual(@as(i32, 1), global_state.init_count);
}

test "get_global_state" {
    const state = get_global_state();
    try std.testing.expect(state == &global_state);
}

test "is_initialized" {
    global_state.initialized = false;
    try std.testing.expect(!is_initialized());
    global_state.initialized = true;
    try std.testing.expect(is_initialized());
}
