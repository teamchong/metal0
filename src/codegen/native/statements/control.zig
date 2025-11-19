/// Control flow statement code generation - Re-exports from submodules
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const ast = @import("../../../ast.zig");

// Re-export loop functions
pub const genFor = @import("control/loops.zig").genFor;
pub const genWhile = @import("control/loops.zig").genWhile;

// Re-export conditional functions
pub const genIf = @import("control/conditionals.zig").genIf;
pub const genPass = @import("control/conditionals.zig").genPass;
pub const genBreak = @import("control/conditionals.zig").genBreak;
pub const genContinue = @import("control/conditionals.zig").genContinue;
