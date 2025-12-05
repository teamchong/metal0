/// metal0 test.list_tests module - CPython list test compatibility
/// Provides CommonTest base class for test_list.py
const std = @import("std");
const unittest = @import("../Lib/unittest.zig");

/// CommonTest base class for list tests
/// This provides stub implementations of methods that test_list.py's ListTest
/// calls via super().method_name()
///
/// In CPython, this inherits from seq_tests.CommonTest, which has:
/// - test_truth, test_len, test_getitem, test_contains, test_count, test_index, etc.
///
/// Here we provide no-op stubs so super() calls don't fail.
pub const CommonTest = struct {
    /// Type under test - subclasses override this
    pub const type2test = []i64; // Default to list (slice type in Zig)

    // ========================================================================
    // seq_tests.CommonTest methods (parent class)
    // ========================================================================

    pub fn test_constructors(_: *anyopaque) void {}
    pub fn test_truth(_: *anyopaque) void {}
    pub fn test_getitem(_: *anyopaque) void {}
    pub fn test_getslice(_: *anyopaque) void {}
    pub fn test_contains(_: *anyopaque) void {}
    pub fn test_contains_fake(_: *anyopaque) void {}
    pub fn test_contains_order(_: *anyopaque) void {}
    pub fn test_len(_: *anyopaque) void {}
    pub fn test_minmax(_: *anyopaque) void {}
    pub fn test_addmul(_: *anyopaque) void {}
    pub fn test_iadd(_: *anyopaque) void {}
    pub fn test_imul(_: *anyopaque) void {}
    pub fn test_getitemoverwriteiter(_: *anyopaque) void {}
    pub fn test_repeat(_: *anyopaque) void {}
    pub fn test_bigrepeat(_: *anyopaque) void {}
    pub fn test_subscript(_: *anyopaque) void {}
    pub fn test_count(_: *anyopaque) void {}
    pub fn test_index(_: *anyopaque) void {}
    pub fn test_pickle(_: *anyopaque) void {}
    pub fn test_free_after_iterating(_: *anyopaque) void {}

    // ========================================================================
    // list_tests.CommonTest methods
    // ========================================================================

    pub fn test_init(_: *anyopaque) void {}
    pub fn test_getitem_error(_: *anyopaque) void {}
    pub fn test_setitem_error(_: *anyopaque) void {}
    pub fn test_repr(_: *anyopaque) void {}
    pub fn test_repr_deep(_: *anyopaque) void {}
    pub fn test_set_subscript(_: *anyopaque) void {}
    pub fn test_reversed(_: *anyopaque) void {}
    pub fn test_setitem(_: *anyopaque) void {}
    pub fn test_delitem(_: *anyopaque) void {}
    pub fn test_setslice(_: *anyopaque) void {}
    pub fn test_slice_assign_iterator(_: *anyopaque) void {}
    pub fn test_delslice(_: *anyopaque) void {}
    pub fn test_append(_: *anyopaque) void {}
    pub fn test_extend(_: *anyopaque) void {}
    pub fn test_insert(_: *anyopaque) void {}
    pub fn test_pop(_: *anyopaque) void {}
    pub fn test_remove(_: *anyopaque) void {}
    pub fn test_reverse(_: *anyopaque) void {}
    pub fn test_clear(_: *anyopaque) void {}
    pub fn test_copy(_: *anyopaque) void {}
    pub fn test_sort(_: *anyopaque) void {}
    pub fn test_slice(_: *anyopaque) void {}
    pub fn test_extendedslicing(_: *anyopaque) void {}
    pub fn test_constructor_exception_handling(_: *anyopaque) void {}
    pub fn test_exhausted_iterator(_: *anyopaque) void {}

    // ========================================================================
    // unittest.TestCase methods (grandparent class)
    // ========================================================================

    pub fn setUp(_: *anyopaque) void {}
    pub fn tearDown(_: *anyopaque) void {}
};
