/// metal0 unittest assertions - basic comparison assertions
/// Main entry point re-exporting all assertion functions.

const std = @import("std");
const runtime = @import("../../../runtime.zig");
pub const PyValue = runtime.PyValue;

// Re-export equality helpers
pub const helpers = @import("equality_helpers.zig");
pub const pythonEql = helpers.pythonEql;
pub const elemEql = helpers.elemEql;
pub const equalArrayList = helpers.equalArrayList;
pub const equalHashMap = helpers.equalHashMap;
pub const equalPyValueWith = helpers.equalPyValueWith;
pub const equalWithBaseValue = helpers.equalWithBaseValue;
pub const deepEqualUnion = helpers.deepEqualUnion;
pub const equalTuples = helpers.equalTuples;
pub const isStringType = helpers.isStringType;
pub const floatsEqual = helpers.floatsEqual;
pub const equalValues = helpers.equalValues;

// Re-export assertEqual
pub const assert_equal = @import("assert_equal.zig");
pub const assertEqual = assert_equal.assertEqual;

// Re-export basic assertions
pub const assert_basic = @import("assert_basic.zig");
pub const assertTrue = assert_basic.assertTrue;
pub const assertFalse = assert_basic.assertFalse;
pub const assertIsNone = assert_basic.assertIsNone;
pub const assertGreater = assert_basic.assertGreater;
pub const assertLess = assert_basic.assertLess;
pub const assertGreaterEqual = assert_basic.assertGreaterEqual;
pub const assertLessEqual = assert_basic.assertLessEqual;
pub const assertNotEqual = assert_basic.assertNotEqual;

// Re-export type and identity assertions
pub const assert_type = @import("assert_type.zig");
pub const assertIs = assert_type.assertIs;
pub const assertTypeIs = assert_type.assertTypeIs;
pub const assertTypeIsStr = assert_type.assertTypeIsStr;
pub const assertIsNot = assert_type.assertIsNot;
pub const assertIsNotNone = assert_type.assertIsNotNone;

// Re-export collection assertions
pub const assert_collection = @import("assert_collection.zig");
pub const assertIn = assert_collection.assertIn;
pub const assertNotIn = assert_collection.assertNotIn;
pub const assertHasAttr = assert_collection.assertHasAttr;
pub const assertNotHasAttr = assert_collection.assertNotHasAttr;

// Re-export string and float assertions
pub const assert_string = @import("assert_string.zig");
pub const assertStartsWith = assert_string.assertStartsWith;
pub const assertNotStartsWith = assert_string.assertNotStartsWith;
pub const assertEndsWith = assert_string.assertEndsWith;
pub const assertAlmostEqual = assert_string.assertAlmostEqual;
pub const assertNotAlmostEqual = assert_string.assertNotAlmostEqual;
pub const assertFloatsAreIdentical = assert_string.assertFloatsAreIdentical;
pub const pyValueEql = assert_string.pyValueEql;
pub const assertEqualPyValue = assert_string.assertEqualPyValue;
pub const toPyValue = assert_string.toPyValue;
