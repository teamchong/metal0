/// Function and class definition code generation - re-exports from submodules
const generators = @import("functions/generators.zig");
const nested = @import("functions/nested.zig");

pub const genFunctionDef = generators.genFunctionDef;
pub const genClassDef = generators.genClassDef;
pub const genNestedFunctionDef = nested.genNestedFunctionDef;
