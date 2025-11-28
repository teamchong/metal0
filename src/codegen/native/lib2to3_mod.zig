/// Python lib2to3 module - Python 2 to 3 conversion library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate lib2to3.main(fixer_pkg, args=None) - Main entry point
pub fn genMain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate lib2to3.refactor.RefactoringTool class
pub fn genRefactoringTool(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate lib2to3.fixer_base.BaseFix class
pub fn genBaseFix(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate lib2to3.pytree.Base class
pub fn genBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate lib2to3.pytree.Node class
pub fn genNode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate lib2to3.pytree.Leaf class
pub fn genLeaf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate lib2to3.pygram.python_grammar
pub fn genPythonGrammar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate lib2to3.pygram.python_grammar_no_print_statement
pub fn genPythonGrammarNoPrintStatement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}
