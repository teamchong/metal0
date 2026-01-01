/// Nested function (closure) code generation
/// This module re-exports functionality from focused submodules
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;

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

    // Check if this is a recursive function or self-referential (e.g., f.x accesses f itself)
    const is_recursive = var_tracking.isRecursiveFunction(func.name, func.body);
    const is_self_referential = var_tracking.isSelfReferential(func.name, func.body);

    // Both patterns need special handling because the function name must be defined
    // before the body is generated (to allow f() calls or f.x attribute access)
    if (is_recursive or is_self_referential) {
        // Recursive/self-referential closures need special handling - generate as a struct with
        // the function name defined at struct scope level (accessible during body generation)
        try recursive.genRecursiveClosure(self, func, captured_vars);
        return;
    }

    if (captured_vars.len == 0) {
        // Check if this nested function has a pre-generated closure type at module level
        if (self.pending_closure_types.get(func.name)) |_| {
            // Skip generating inline - the closure type already exists at module level
            // The return statement will handle instantiating it
            return;
        }

        // No captures and not recursive - use ZeroClosure comptime pattern
        const b = try self.getBuilder();
        try b.writeIndent();
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);

        try zero_capture.genZeroCaptureClosure(self, func);
        return;
    }

    // Standard closure with captures
    try closure_gen.genStandardClosure(self, func, captured_vars);
}
