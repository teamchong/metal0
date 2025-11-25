/// RE module - re.search(), re.match(), re.sub(), re.findall() code generation
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for re.search(pattern, text)
/// Returns match object or None
pub fn genReSearch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) {
        return;
    }

    try self.output.appendSlice(self.allocator, "try runtime.re.search(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for re.match(pattern, text)
/// Returns match object or None (only matches at start)
pub fn genReMatch(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) {
        return;
    }

    try self.output.appendSlice(self.allocator, "try runtime.re.match(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for re.sub(pattern, replacement, text)
/// Returns new string with all matches replaced
pub fn genReSub(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 3) {
        return;
    }

    try self.output.appendSlice(self.allocator, "try runtime.re.sub(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[2]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for re.findall(pattern, text)
/// Returns list of all matched strings
pub fn genReFindall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) {
        return;
    }

    try self.output.appendSlice(self.allocator, "try runtime.re.findall(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for re.compile(pattern)
/// Returns compiled regex object
pub fn genReCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    try self.output.appendSlice(self.allocator, "try runtime.re.compile(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}
