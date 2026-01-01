/// Centralized method name constants and category helpers
/// Eliminates scattered if-else chains with string comparisons
const std = @import("std");

// =============================================================================
// Unittest Framework Methods
// =============================================================================

/// Unittest lifecycle method kinds
pub const UnittestLifecycleKind = enum { setUp, tearDown, setUpClass, tearDownClass };

/// Unittest lifecycle methods (setUp, tearDown, etc.)
pub const UNITTEST_LIFECYCLE = std.StaticStringMap(UnittestLifecycleKind).initComptime(.{
    .{ "setUp", .setUp },
    .{ "tearDown", .tearDown },
    .{ "setUpClass", .setUpClass },
    .{ "tearDownClass", .tearDownClass },
});

/// Assert context managers (used in with statements)
pub const ASSERT_CONTEXT_MANAGERS = std.StaticStringMap(void).initComptime(.{
    .{ "assertRaises", {} },
    .{ "assertRaisesRegex", {} },
    .{ "assertWarns", {} },
    .{ "assertWarnsRegex", {} },
    .{ "assertLogs", {} },
    .{ "subTest", {} },
});

/// ALL unittest assertion methods (dispatched to runtime, self not used in generated code)
/// Used by self_analyzer.zig and core.zig to identify unittest method calls
pub const UNITTEST_ALL_ASSERTIONS = std.StaticStringMap(void).initComptime(.{
    // Basic assertions
    .{ "assertEqual", {} },
    .{ "assertNotEqual", {} },
    .{ "assertTrue", {} },
    .{ "assertFalse", {} },
    .{ "assertIs", {} },
    .{ "assertIsNot", {} },
    .{ "assertIsNone", {} },
    .{ "assertIsNotNone", {} },
    // Comparison assertions
    .{ "assertGreater", {} },
    .{ "assertGreaterEqual", {} },
    .{ "assertLess", {} },
    .{ "assertLessEqual", {} },
    .{ "assertAlmostEqual", {} },
    .{ "assertNotAlmostEqual", {} },
    // Membership/type assertions
    .{ "assertIn", {} },
    .{ "assertNotIn", {} },
    .{ "assertIsInstance", {} },
    .{ "assertNotIsInstance", {} },
    .{ "assertIsSubclass", {} },
    .{ "assertNotIsSubclass", {} },
    // Context manager assertions (also in ASSERT_CONTEXT_MANAGERS)
    .{ "assertRaises", {} },
    .{ "assertRaisesRegex", {} },
    .{ "assertWarns", {} },
    .{ "assertWarnsRegex", {} },
    .{ "assertLogs", {} },
    .{ "assertNoLogs", {} },
    // Regex assertions
    .{ "assertRegex", {} },
    .{ "assertNotRegex", {} },
    // Collection assertions
    .{ "assertCountEqual", {} },
    .{ "assertSequenceEqual", {} },
    .{ "assertListEqual", {} },
    .{ "assertTupleEqual", {} },
    .{ "assertSetEqual", {} },
    .{ "assertDictEqual", {} },
    .{ "assertMultiLineEqual", {} },
    // Attribute assertions
    .{ "assertHasAttr", {} },
    .{ "assertNotHasAttr", {} },
    // String assertions
    .{ "assertStartsWith", {} },
    .{ "assertNotStartsWith", {} },
    .{ "assertEndsWith", {} },
    .{ "assertNotEndsWith", {} },
    // Float assertions
    .{ "assertFloatsAreIdentical", {} },
    // Control flow
    .{ "subTest", {} },
    .{ "fail", {} },
    .{ "skipTest", {} },
});

// =============================================================================
// Special Python Methods
// =============================================================================

/// Special dunder methods for class construction
pub const CLASS_CONSTRUCTORS = std.StaticStringMap(void).initComptime(.{
    .{ "__init__", {} },
    .{ "__new__", {} },
});

/// Primitive type conversion methods
pub const PRIMITIVE_CONVERSIONS = std.StaticStringMap(void).initComptime(.{
    .{ "__index__", {} },
    .{ "__int__", {} },
    .{ "__hash__", {} },
});

// =============================================================================
// PyValue String Methods (Uncertain Type Flow)
// =============================================================================

/// Return type categories for PyValue string methods
pub const PyValueStringMethodKind = enum {
    /// Methods returning bool (startswith, endswith)
    bool_result,
    /// Methods returning []const u8 with no args (strip, lstrip, rstrip)
    slice_result,
    /// Methods returning []const u8 with 2 args: old, new (replace)
    replace_result,
    /// Methods returning i64 (find, rfind, index)
    find_result,
    /// Methods returning ArrayList (split)
    list_result,
};

/// PyValue string methods mapped by return type category
pub const PYVALUE_STRING_METHODS = std.StaticStringMap(PyValueStringMethodKind).initComptime(.{
    .{ "startswith", .bool_result },
    .{ "endswith", .bool_result },
    .{ "strip", .slice_result },
    .{ "lstrip", .slice_result },
    .{ "rstrip", .slice_result },
    .{ "upper", .slice_result },
    .{ "lower", .slice_result },
    .{ "replace", .replace_result },
    .{ "find", .find_result },
    .{ "rfind", .find_result },
    .{ "split", .list_result },
});

// =============================================================================
// Helper Functions
// =============================================================================

/// Check if method is a unittest lifecycle method
pub fn isUnittestLifecycle(name: []const u8) bool {
    return UNITTEST_LIFECYCLE.has(name);
}

/// Get the specific unittest lifecycle kind (for setting flags)
pub fn getUnittestLifecycleKind(name: []const u8) ?UnittestLifecycleKind {
    return UNITTEST_LIFECYCLE.get(name);
}

/// Check if method is an assert context manager
pub fn isAssertContextManager(name: []const u8) bool {
    return ASSERT_CONTEXT_MANAGERS.has(name);
}

/// Check if method is any unittest assertion method (for self-usage detection)
pub fn isUnittestAssertion(name: []const u8) bool {
    return UNITTEST_ALL_ASSERTIONS.has(name);
}

/// Check if method is a class constructor (__init__, __new__)
pub fn isClassConstructor(name: []const u8) bool {
    return CLASS_CONSTRUCTORS.has(name);
}

/// Check if method is a primitive conversion (__index__, __int__, __hash__)
pub fn isPrimitiveConversion(name: []const u8) bool {
    return PRIMITIVE_CONVERSIONS.has(name);
}

/// Get the return type category for a PyValue string method
pub fn getPyValueStringMethodKind(name: []const u8) ?PyValueStringMethodKind {
    return PYVALUE_STRING_METHODS.get(name);
}

/// Check if method is a PyValue string method (for uncertain type dispatch)
pub fn isPyValueStringMethod(name: []const u8) bool {
    return PYVALUE_STRING_METHODS.has(name);
}

// =============================================================================
// Tests
// =============================================================================

test "unittest lifecycle methods" {
    try std.testing.expect(isUnittestLifecycle("setUp"));
    try std.testing.expect(isUnittestLifecycle("tearDown"));
    try std.testing.expect(isUnittestLifecycle("setUpClass"));
    try std.testing.expect(isUnittestLifecycle("tearDownClass"));
    try std.testing.expect(!isUnittestLifecycle("testFoo"));
    try std.testing.expectEqual(UnittestLifecycleKind.setUp, getUnittestLifecycleKind("setUp").?);
    try std.testing.expectEqual(UnittestLifecycleKind.tearDownClass, getUnittestLifecycleKind("tearDownClass").?);
}

test "assert context managers" {
    try std.testing.expect(isAssertContextManager("assertRaises"));
    try std.testing.expect(isAssertContextManager("assertRaisesRegex"));
    try std.testing.expect(isAssertContextManager("assertWarns"));
    try std.testing.expect(isAssertContextManager("subTest"));
    try std.testing.expect(!isAssertContextManager("assertEqual"));
}

test "pyvalue string methods" {
    try std.testing.expectEqual(PyValueStringMethodKind.bool_result, getPyValueStringMethodKind("startswith").?);
    try std.testing.expectEqual(PyValueStringMethodKind.slice_result, getPyValueStringMethodKind("strip").?);
    try std.testing.expectEqual(PyValueStringMethodKind.slice_result, getPyValueStringMethodKind("upper").?);
    try std.testing.expectEqual(PyValueStringMethodKind.replace_result, getPyValueStringMethodKind("replace").?);
    try std.testing.expectEqual(PyValueStringMethodKind.find_result, getPyValueStringMethodKind("find").?);
    try std.testing.expectEqual(PyValueStringMethodKind.list_result, getPyValueStringMethodKind("split").?);
    try std.testing.expect(getPyValueStringMethodKind("unknown") == null);
    try std.testing.expect(isPyValueStringMethod("startswith"));
    try std.testing.expect(isPyValueStringMethod("lower"));
    try std.testing.expect(!isPyValueStringMethod("unknown"));
}

test "unittest all assertions" {
    // Basic assertions
    try std.testing.expect(isUnittestAssertion("assertEqual"));
    try std.testing.expect(isUnittestAssertion("assertTrue"));
    try std.testing.expect(isUnittestAssertion("assertFalse"));
    // Context managers are also assertions
    try std.testing.expect(isUnittestAssertion("assertRaises"));
    try std.testing.expect(isUnittestAssertion("subTest"));
    // Control flow
    try std.testing.expect(isUnittestAssertion("fail"));
    try std.testing.expect(isUnittestAssertion("skipTest"));
    // Non-assertions
    try std.testing.expect(!isUnittestAssertion("setUp"));
    try std.testing.expect(!isUnittestAssertion("testFoo"));
}
