/// Loop code generation - Re-exports from submodules
const while_loops = @import("loops/while.zig");
const for_basic = @import("loops/for_basic.zig");
const for_special = @import("loops/for_special.zig");

// Re-export all functions
pub const genWhile = while_loops.genWhile;
pub const genFor = for_basic.genFor;
pub const genRangeLoop = for_basic.genRangeLoop;
pub const genTupleUnpackLoop = for_basic.genTupleUnpackLoop;
pub const genEnumerateLoop = for_special.genEnumerateLoop;
pub const genZipLoop = for_special.genZipLoop;
