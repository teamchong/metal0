/// Statement-level code generation - index file
/// Re-exports all statement generators from subdirectory modules
const std = @import("std");
const ast = @import("../../ast.zig");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

// Import statement modules
const functions = @import("statements/functions.zig");
const control = @import("statements/control.zig");
const assign = @import("statements/assign.zig");
const misc = @import("statements/misc.zig");

// Re-export public functions
pub const genFunctionDef = functions.genFunctionDef;
pub const genClassDef = functions.genClassDef;
pub const genReturn = misc.genReturn;
pub const genImportFrom = misc.genImportFrom;
pub const genPrint = misc.genPrint;
pub const genAssert = misc.genAssert;
pub const genTry = misc.genTry;
pub const genAssign = assign.genAssign;
pub const genAugAssign = assign.genAugAssign;
pub const genExprStmt = assign.genExprStmt;
pub const genIf = control.genIf;
pub const genWhile = control.genWhile;
pub const genFor = control.genFor;
pub const genPass = control.genPass;
pub const genBreak = control.genBreak;
pub const genContinue = control.genContinue;
