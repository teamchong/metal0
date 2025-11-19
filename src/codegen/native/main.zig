/// Native Zig code generation - No PyObject overhead
/// Generates stack-allocated native types based on type inference
/// Core module - delegates to json/http/builtins/methods/async

// Re-export core types and functions
pub const core = @import("main/core.zig");
pub const imports = @import("main/imports.zig");
pub const generator = @import("main/generator.zig");

// Re-export main types
pub const CodegenError = core.CodegenError;
pub const DecoratedFunction = core.DecoratedFunction;
pub const NativeCodegen = core.NativeCodegen;

// Re-export main functions for backward compatibility
pub const generate = generator.generate;
pub const generateStmt = generator.generateStmt;
pub const genExpr = generator.genExpr;
