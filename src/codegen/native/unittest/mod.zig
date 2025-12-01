/// unittest module code generation - re-exports all submodules
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

pub const assertions = @import("assertions.zig");
pub const lifecycle = @import("lifecycle.zig");
pub const discovery = @import("discovery.zig");

/// Handler function type
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// Module function map - exported for dispatch
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "main", genUnittestMain },
});

// Re-export assertion functions
pub const genAssertEqual = assertions.genAssertEqual;
pub const genAssertTrue = assertions.genAssertTrue;
pub const genAssertFalse = assertions.genAssertFalse;
pub const genAssertIsNone = assertions.genAssertIsNone;
pub const genAssertGreater = assertions.genAssertGreater;
pub const genAssertLess = assertions.genAssertLess;
pub const genAssertGreaterEqual = assertions.genAssertGreaterEqual;
pub const genAssertLessEqual = assertions.genAssertLessEqual;
pub const genAssertNotEqual = assertions.genAssertNotEqual;
pub const genAssertIs = assertions.genAssertIs;
pub const genAssertIsNot = assertions.genAssertIsNot;
pub const genAssertIsNotNone = assertions.genAssertIsNotNone;
pub const genAssertIn = assertions.genAssertIn;
pub const genAssertNotIn = assertions.genAssertNotIn;
pub const genAssertAlmostEqual = assertions.genAssertAlmostEqual;
pub const genAssertNotAlmostEqual = assertions.genAssertNotAlmostEqual;
pub const genAssertCountEqual = assertions.genAssertCountEqual;
pub const genAssertRegex = assertions.genAssertRegex;
pub const genAssertNotRegex = assertions.genAssertNotRegex;
pub const genAssertIsInstance = assertions.genAssertIsInstance;
pub const genAssertNotIsInstance = assertions.genAssertNotIsInstance;
pub const genAssertIsSubclass = assertions.genAssertIsSubclass;
pub const genAssertNotIsSubclass = assertions.genAssertNotIsSubclass;
pub const genAssertRaises = assertions.genAssertRaises;
pub const genAssertRaisesRegex = assertions.genAssertRaisesRegex;
pub const genAssertWarns = assertions.genAssertWarns;
pub const genAssertWarnsRegex = assertions.genAssertWarnsRegex;
pub const genAssertStartsWith = assertions.genAssertStartsWith;
pub const genAssertNotStartsWith = assertions.genAssertNotStartsWith;
pub const genAssertEndsWith = assertions.genAssertEndsWith;
pub const genAssertHasAttr = assertions.genAssertHasAttr;
pub const genAssertNotHasAttr = assertions.genAssertNotHasAttr;
pub const genAssertSequenceEqual = assertions.genAssertSequenceEqual;
pub const genAssertListEqual = assertions.genAssertListEqual;
pub const genAssertTupleEqual = assertions.genAssertTupleEqual;
pub const genAssertSetEqual = assertions.genAssertSetEqual;
pub const genAssertDictEqual = assertions.genAssertDictEqual;
pub const genAssertMultiLineEqual = assertions.genAssertMultiLineEqual;
pub const genAssertLogs = assertions.genAssertLogs;
pub const genAssertNoLogs = assertions.genAssertNoLogs;
pub const genFail = assertions.genFail;
pub const genSkipTest = assertions.genSkipTest;
pub const genAssertFloatsAreIdentical = assertions.genAssertFloatsAreIdentical;

// Re-export lifecycle functions
pub const genUnittestMain = lifecycle.genUnittestMain;
pub const genUnittestFinalize = lifecycle.genUnittestFinalize;
pub const genAddCleanup = lifecycle.genAddCleanup;

// Re-export discovery functions
pub const genSubTest = discovery.genSubTest;
