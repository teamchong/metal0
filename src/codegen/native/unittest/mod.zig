/// unittest module code generation - re-exports all submodules
pub const assertions = @import("assertions.zig");
pub const lifecycle = @import("lifecycle.zig");
pub const discovery = @import("discovery.zig");

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
pub const genAssertRaises = assertions.genAssertRaises;

// Re-export lifecycle functions
pub const genUnittestMain = lifecycle.genUnittestMain;
pub const genUnittestFinalize = lifecycle.genUnittestFinalize;

// Re-export discovery functions
pub const genSubTest = discovery.genSubTest;
