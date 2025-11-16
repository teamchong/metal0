/// String/List/Dict methods - .split(), .append(), .keys(), etc.
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for text.split(separator)
/// Example: "a b c".split(" ") -> std.mem.split(u8, text, sep)
pub fn genSplit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Generate: std.mem.split(u8, text, sep)
    try self.output.appendSlice(self.allocator, "std.mem.split(u8, ");
    try self.genExpr(obj); // The string object
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]); // The separator
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for list.append(item)
/// NOTE: Zig arrays are fixed size, need ArrayList for dynamic appending
pub fn genAppend(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj; // Unused for now - will need when detecting ArrayList vs array
    if (args.len != 1) {
        return;
    }

    // For now: compile error placeholder
    // TODO: Need to detect if obj is ArrayList vs array
    try self.output.appendSlice(
        self.allocator,
        "@compileError(\"list.append() requires ArrayList, not yet supported\")",
    );
}

/// Generate code for text.upper()
/// Converts string to uppercase
pub fn genUpper(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj; // Unused for now - will need when generating actual code
    _ = args; // upper() takes no arguments

    // For now: compile error placeholder
    // TODO: Need to allocate new string and transform characters
    // Would use std.ascii.toUpper() in a loop
    try self.output.appendSlice(
        self.allocator,
        "@compileError(\"text.upper() not yet supported\")",
    );
}

/// Generate code for text.lower()
/// Converts string to lowercase
pub fn genLower(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj; // Unused for now - will need when generating actual code
    _ = args; // lower() takes no arguments

    // For now: compile error placeholder
    // TODO: Need to allocate new string and transform characters
    // Would use std.ascii.toLower() in a loop
    try self.output.appendSlice(
        self.allocator,
        "@compileError(\"text.lower() not yet supported\")",
    );
}

/// Generate code for text.strip()
/// Removes leading/trailing whitespace
pub fn genStrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // strip() takes no arguments

    // Generate: std.mem.trim(u8, text, " \t\n\r")
    try self.output.appendSlice(self.allocator, "std.mem.trim(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", \" \\t\\n\\r\")");
}

/// Generate code for text.replace(old, new)
/// Replaces all occurrences of old with new
pub fn genReplace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj; // Unused for now - will need when generating actual code
    if (args.len != 2) {
        // TODO: Error handling
        return;
    }

    // For now: compile error placeholder
    // TODO: Need std.mem.replace() or custom implementation
    try self.output.appendSlice(
        self.allocator,
        "@compileError(\"text.replace() not yet supported\")",
    );
}

// TODO: Implement string methods - DONE
// ✅ text.upper() -> []const u8 (placeholder)
// ✅ text.lower() -> []const u8 (placeholder)
// ✅ text.strip() -> []const u8 (FULLY IMPLEMENTED)
// ✅ text.replace(old, new) -> []const u8 (placeholder)

// TODO: Implement list methods
// - list.pop() -> T
// - list.extend(other)
// - list.insert(index, item)
// - list.remove(item)

// TODO: Implement dict methods
// - dict.get(key) -> ?V
// - dict.keys() -> []K
// - dict.values() -> []V
// - dict.items() -> [][2]{K, V}
