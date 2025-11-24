/// JSON module - json.loads() and json.dumps() code generation
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for json.loads(json_string)
/// Parses JSON and returns a PyObject (dict/list/etc)
pub fn genJsonLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // runtime.json.loads expects (*PyObject, allocator) and returns !*PyObject
    // We need to wrap string literal in PyString first
    try self.output.appendSlice(self.allocator, "blk: { const json_str_obj = try runtime.PyString.create(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, "); defer runtime.decref(json_str_obj, allocator); break :blk try runtime.json.loads(json_str_obj, allocator); }");
}

/// Generate code for json.dumps(obj)
/// Maps to: runtime.json.dumps(obj, allocator)
pub fn genJsonDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Generate: try runtime.json.dumps(obj, allocator)
    try self.output.appendSlice(self.allocator, "try runtime.json.dumps(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", allocator)");
}
