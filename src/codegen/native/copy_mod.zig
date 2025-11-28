/// Python copy module - copy, deepcopy
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate copy.copy(obj)
/// Creates a shallow copy of the object
pub fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    
    // For primitive types, just return the value (immutable)
    // For lists/dicts, we need to create a new container
    try self.emit("copy_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _src = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    // Use Zig's comptime type detection
    try self.emit("if (@TypeOf(_src) == std.ArrayList(@TypeOf(_src.items[0]))) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _copy = std.ArrayList(@TypeOf(_src.items[0])).init(allocator);\n");
    try self.emitIndent();
    try self.emit("_copy.appendSlice(allocator, _src.items) catch {};\n");
    try self.emitIndent();
    try self.emit("break :copy_blk _copy;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :copy_blk _src;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate copy.deepcopy(obj)
/// Creates a deep copy of the object (recursive)
pub fn genDeepcopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    
    // For AOT, deep copy is complex because we need to recursively copy
    // nested structures. For now, implement like shallow copy.
    try self.emit("deepcopy_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _src = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    // For simple types, just return the value
    try self.emit("if (@TypeOf(_src) == i64 or @TypeOf(_src) == f64 or @TypeOf(_src) == bool or @TypeOf(_src) == []const u8) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :deepcopy_blk _src;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    // For ArrayList, deep copy elements
    try self.emit("if (@typeInfo(@TypeOf(_src)) == .@\"struct\" and @hasField(@TypeOf(_src), \"items\")) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _copy = @TypeOf(_src).init(allocator);\n");
    try self.emitIndent();
    try self.emit("for (_src.items) |item| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_copy.append(allocator, item) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :deepcopy_blk _copy;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :deepcopy_blk _src;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
