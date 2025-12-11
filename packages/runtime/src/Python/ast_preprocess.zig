/// ast_preprocess - AST Pre-processing
/// Mirrors cpython/Python/ast_preprocess.c
///
/// Pre-processes the AST before compilation, handling:
/// - Constant folding
/// - Control flow in finally warnings (PEP 765)
/// - Docstring extraction
/// - Optimization passes

// Re-export submodules
pub const control_flow = @import("ast_preprocess/control_flow.zig");
pub const diagnostics = @import("ast_preprocess/diagnostics.zig");
pub const constant_folding = @import("ast_preprocess/constant_folding.zig");
pub const docstring = @import("ast_preprocess/docstring.zig");
pub const state = @import("ast_preprocess/state.zig");

// Re-export commonly used types for convenience
pub const ControlFlowContext = control_flow.ControlFlowContext;
pub const ContextStack = control_flow.ContextStack;
pub const PreprocessState = state.PreprocessState;
pub const WarningKind = diagnostics.WarningKind;
pub const Warning = diagnostics.Warning;
pub const ErrorKind = diagnostics.ErrorKind;
pub const PreprocessError = diagnostics.PreprocessError;
pub const ConstValue = constant_folding.ConstValue;
pub const BinOp = constant_folding.BinOp;
pub const UnaryOp = constant_folding.UnaryOp;
pub const foldBinaryOp = constant_folding.foldBinaryOp;
pub const foldUnaryOp = constant_folding.foldUnaryOp;
pub const extractDocstring = docstring.extractDocstring;
pub const Statement = docstring.Statement;
pub const StmtKind = docstring.StmtKind;
pub const Expression = docstring.Expression;
pub const ExprKind = docstring.ExprKind;

// Module initialization
var initialized: bool = false;

/// Initialize the ast_preprocess module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// Tests
test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("ast_preprocess/tests.zig");
}
