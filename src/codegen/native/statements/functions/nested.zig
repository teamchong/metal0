/// Nested function (closure) code generation
/// This module re-exports functionality from focused submodules
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;

// Import submodules
const var_tracking = @import("nested/var_tracking.zig");
const recursive = @import("nested/recursive.zig");
const zero_capture = @import("nested/zero_capture.zig");
const closure_gen = @import("nested/closure_gen.zig");

/// Generate nested function with closure support (immediate call only)
pub fn genNestedFunctionDef(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError!void {
    // Use captured variables from AST (pre-computed by closure analyzer)
    const captured_vars = func.captured_vars;

    // Check if this is a recursive function
    const is_recursive = var_tracking.isRecursiveFunction(func.name, func.body);

    // Recursive functions need special handling (even with zero captures)
    // because the function name must be defined before the body is generated
    if (is_recursive) {
        // Recursive closures need special handling - generate as a struct with
        // the function name defined at struct scope level (accessible during body generation)
        try recursive.genRecursiveClosure(self, func, captured_vars);
        return;
    }

    if (captured_vars.len == 0) {
        // No captures and not recursive - use ZeroClosure comptime pattern
        try self.emitIndent();
        try zero_capture.genZeroCaptureClosure(self, func);
        return;
    }

    // Standard closure with captures
    try closure_gen.genStandardClosure(self, func, captured_vars);
}
