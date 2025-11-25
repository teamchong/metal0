/// PyAOT unittest module - test framework
/// Re-exports all unittest functionality from submodules
pub const runner = @import("unittest/runner.zig");
pub const assertions_basic = @import("unittest/assertions_basic.zig");
pub const assertions_type = @import("unittest/assertions_type.zig");
pub const subtest = @import("unittest/subtest.zig");

// Re-export runner functions
pub const TestResult = runner.TestResult;
pub const initRunner = runner.initRunner;
pub const printResults = runner.printResults;
pub const deinitRunner = runner.deinitRunner;
pub const main = runner.main;
pub const finalize = runner.finalize;

// Re-export basic assertions
pub const assertEqual = assertions_basic.assertEqual;
pub const assertTrue = assertions_basic.assertTrue;
pub const assertFalse = assertions_basic.assertFalse;
pub const assertIsNone = assertions_basic.assertIsNone;
pub const assertGreater = assertions_basic.assertGreater;
pub const assertLess = assertions_basic.assertLess;
pub const assertGreaterEqual = assertions_basic.assertGreaterEqual;
pub const assertLessEqual = assertions_basic.assertLessEqual;
pub const assertNotEqual = assertions_basic.assertNotEqual;
pub const assertIs = assertions_basic.assertIs;
pub const assertIsNot = assertions_basic.assertIsNot;
pub const assertIsNotNone = assertions_basic.assertIsNotNone;
pub const assertIn = assertions_basic.assertIn;
pub const assertNotIn = assertions_basic.assertNotIn;
pub const assertAlmostEqual = assertions_basic.assertAlmostEqual;
pub const assertNotAlmostEqual = assertions_basic.assertNotAlmostEqual;

// Re-export type/container assertions
pub const assertCountEqual = assertions_type.assertCountEqual;
pub const assertRegex = assertions_type.assertRegex;
pub const assertNotRegex = assertions_type.assertNotRegex;
pub const assertIsInstance = assertions_type.assertIsInstance;
pub const assertNotIsInstance = assertions_type.assertNotIsInstance;
pub const assertRaises = assertions_type.assertRaises;
pub const assertDictEqual = assertions_type.assertDictEqual;
pub const assertListEqual = assertions_type.assertListEqual;
pub const assertSetEqual = assertions_type.assertSetEqual;
pub const assertTupleEqual = assertions_type.assertTupleEqual;
pub const assertSequenceEqual = assertions_type.assertSequenceEqual;
pub const assertMultiLineEqual = assertions_type.assertMultiLineEqual;
pub const assertRaisesRegex = assertions_type.assertRaisesRegex;
pub const assertWarns = assertions_type.assertWarns;
pub const assertWarnsRegex = assertions_type.assertWarnsRegex;

// Re-export subtest
pub const subTest = subtest.subTest;
pub const subTestInt = subtest.subTestInt;

// Tests
test "assertEqual: integers" {
    assertEqual(@as(i64, 2 + 2), @as(i64, 4));
}

test "assertEqual: strings" {
    assertEqual("hello", "hello");
}

test "assertTrue" {
    assertTrue(true);
    assertTrue(1 == 1);
}

test "assertFalse" {
    assertFalse(false);
    assertFalse(1 == 2);
}
