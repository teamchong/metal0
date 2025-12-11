/// Module initialization for Python-ast
/// Mirrors cpython/Python/Python-ast.c (initialization)

var initialized: bool = false;

/// Initialize the Python-ast module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}
