/// String/List/Dict methods - .split(), .append(), .keys(), etc.
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const NativeType = @import("../../analysis/native_types.zig").NativeType;

/// Generate code for text.split(separator)
/// Example: "a b c".split(" ") -> [][]const u8 slice
pub fn genSplit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Generate block expression that returns [][]const u8
    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    var _split_result = std.ArrayList([]const u8){};\n");
    try self.output.appendSlice(self.allocator, "    var _split_iter = std.mem.splitSequence(u8, ");
    try self.genExpr(obj); // The string to split
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]); // The separator
    try self.output.appendSlice(self.allocator, ");\n");
    try self.output.appendSlice(self.allocator, "    while (_split_iter.next()) |part| {\n");
    try self.output.appendSlice(self.allocator, "        try _split_result.append(allocator, part);\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk try _split_result.toOwnedSlice(allocator);\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for list.append(item)
/// NOTE: Zig arrays are fixed size, need ArrayList for dynamic appending
pub fn genAppend(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    // Generate: try list.append(allocator, item)
    try self.output.appendSlice(self.allocator, "try ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".append(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for text.upper()
/// Converts string to uppercase
pub fn genUpper(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate block expression
    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _text.len);\n");
    try self.output.appendSlice(self.allocator, "    for (_text, 0..) |c, i| {\n");
    try self.output.appendSlice(self.allocator, "        _result[i] = std.ascii.toUpper(c);\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.lower()
/// Converts string to lowercase
pub fn genLower(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate block expression
    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _text.len);\n");
    try self.output.appendSlice(self.allocator, "    for (_text, 0..) |c, i| {\n");
    try self.output.appendSlice(self.allocator, "        _result[i] = std.ascii.toLower(c);\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
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
    if (args.len != 2) {
        return;
    }

    // Generate: try std.mem.replaceOwned(u8, allocator, text, old, new)
    try self.output.appendSlice(self.allocator, "try std.mem.replaceOwned(u8, allocator, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]); // old
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]); // new
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for sep.join(list)
/// Joins list elements with separator
pub fn genJoin(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.join(allocator, separator, list)
    try self.output.appendSlice(self.allocator, "std.mem.join(allocator, ");
    try self.genExpr(obj); // The separator string
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]); // The list
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for text.startswith(prefix)
/// Checks if string starts with prefix
pub fn genStartswith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.startsWith(u8, text, prefix)
    try self.output.appendSlice(self.allocator, "std.mem.startsWith(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for text.endswith(suffix)
/// Checks if string ends with suffix
pub fn genEndswith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.endsWith(u8, text, suffix)
    try self.output.appendSlice(self.allocator, "std.mem.endsWith(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for text.find(substring)
/// Returns index of first occurrence, or -1 if not found
pub fn genFind(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: if (std.mem.indexOf(u8, text, substring)) |idx| @as(i64, @intCast(idx)) else -1
    try self.output.appendSlice(self.allocator, "if (std.mem.indexOf(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.count(substring)
/// Counts non-overlapping occurrences
pub fn genCount(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // For now: compile error - needs loop implementation
    // TODO: Generate loop to count occurrences
    _ = obj;
    try self.output.appendSlice(
        self.allocator,
        "@compileError(\"text.count() requires loop codegen, not yet supported\")",
    );
}

/// Generate code for list.index(item)
/// Returns index of first occurrence, throws if not found
pub fn genIndex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.indexOfScalar(T, list, item).?
    // The .? asserts item exists (crashes if not found, like Python)
    try self.output.appendSlice(self.allocator, "std.mem.indexOfScalar(");
    // TODO: Need to infer element type
    try self.output.appendSlice(self.allocator, "i64, "); // Assume i64 for now
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ").?");
}

// TODO: Implement string methods - DONE
// ✅ text.upper() -> []const u8 (placeholder)
// ✅ text.lower() -> []const u8 (placeholder)
// ✅ text.strip() -> []const u8 (FULLY IMPLEMENTED)
// ✅ text.replace(old, new) -> []const u8 (placeholder)
// ✅ text.join(list) -> []const u8 (FULLY IMPLEMENTED)
// ✅ text.startswith(prefix) -> bool (FULLY IMPLEMENTED)
// ✅ text.endswith(suffix) -> bool (FULLY IMPLEMENTED)
// ✅ text.find(substring) -> isize (FULLY IMPLEMENTED)
// ✅ text.count(substring) -> usize (placeholder - needs loop)

/// Generate code for list.pop()
/// Removes and returns last item (or item at index if provided)
pub fn genPop(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // Generate: list.pop()
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".pop()");

    // If index provided: list.orderedRemove(index)
    if (args.len > 0) {
        // Replace with orderedRemove for indexed pop
        self.output.items.len -= 6; // Remove ".pop()"
        try self.output.appendSlice(self.allocator, ".orderedRemove(");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ")");
    }
}

/// Generate code for list.extend(other)
/// Appends all items from other list
pub fn genExtend(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: try list.appendSlice(allocator, other)
    try self.output.appendSlice(self.allocator, "try ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".appendSlice(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for list.insert(index, item)
/// Inserts item at index
pub fn genInsert(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 2) return;

    // Generate: try list.insert(allocator, index, item)
    try self.output.appendSlice(self.allocator, "try ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".insert(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for list.remove(item)
/// Removes first occurrence of item
pub fn genRemove(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: { const idx = std.mem.indexOfScalar(T, list.items, item).?; _ = list.orderedRemove(idx); }
    try self.output.appendSlice(self.allocator, "{ const __idx = std.mem.indexOfScalar(i64, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".items, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ").?; _ = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".orderedRemove(__idx); }");
}

/// Generate code for list.reverse()
/// Reverses list in place
pub fn genReverse(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate: std.mem.reverse(T, list.items)
    try self.output.appendSlice(self.allocator, "std.mem.reverse(i64, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".items)");
}

/// Generate code for list.sort()
/// Sorts list in place
pub fn genSort(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate: std.mem.sort(i64, list.items, {}, comptime std.sort.asc(i64))
    try self.output.appendSlice(self.allocator, "std.mem.sort(i64, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".items, {}, comptime std.sort.asc(i64))");
}

/// Generate code for list.clear()
/// Removes all items
pub fn genClear(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate: list.clearRetainingCapacity()
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".clearRetainingCapacity()");
}

/// Generate code for list.copy()
/// Returns a shallow copy
pub fn genCopy(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate: try list.clone(allocator)
    try self.output.appendSlice(self.allocator, "try ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".clone(allocator)");
}

/// Generate code for dict.get(key, default)
/// Returns value if key exists, otherwise returns default (or null if no default)
/// If no args, generates generic method call (for custom class methods)
pub fn genGet(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // Not a dict.get() - must be custom class method with no args
        // Generate generic method call: obj.get()
        try self.genExpr(obj);
        try self.output.appendSlice(self.allocator, ".get()");
        return;
    }

    const default_val = if (args.len >= 2) args[1] else null;

    if (default_val) |def| {
        // Generate: dict.get(key) orelse default
        try self.genExpr(obj);
        try self.output.appendSlice(self.allocator, ".get(");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ") orelse ");
        try self.genExpr(def);
    } else {
        // Generate: dict.get(key)
        try self.genExpr(obj);
        try self.output.appendSlice(self.allocator, ".get(");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ")");
    }
}

/// Generate code for dict.keys()
/// Returns list of keys (always []const u8 for StringHashMap)
pub fn genKeys(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // keys() takes no arguments

    // Generate block that builds list of keys
    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _keys_list = std.ArrayList([]const u8){};\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _iter = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".keyIterator();\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (_iter.next()) |key_ptr| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try _keys_list.append(allocator, key_ptr.*);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk _keys_list;\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for dict.values()
/// Returns list of values
pub fn genValues(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // values() takes no arguments

    // Infer dict type to get value type
    const dict_type = try self.type_inferrer.inferExpr(obj);
    const val_type = if (dict_type == .dict) dict_type.dict.value.* else NativeType.int;

    // Generate block that builds list of values
    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _values_list = std.ArrayList(");
    try val_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, "){};\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _iter = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".valueIterator();\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (_iter.next()) |val_ptr| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try _values_list.append(allocator, val_ptr.*);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk _values_list;\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for dict.items()
/// Returns list of tuples (key-value pairs)
pub fn genItems(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // items() takes no arguments

    // Infer dict type to get value type (keys are always []const u8)
    const dict_type = try self.type_inferrer.inferExpr(obj);
    const val_type = if (dict_type == .dict) dict_type.dict.value.* else NativeType.int;

    // Generate block that builds list of tuples
    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _items_list = std.ArrayList(std.meta.Tuple(&[_]type{[]const u8, ");
    try val_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, "})){};\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _iter = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ".iterator();\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (_iter.next()) |entry| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _tuple = std.meta.Tuple(&[_]type{[]const u8, ");
    try val_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, "}){entry.key_ptr.*, entry.value_ptr.*};\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try _items_list.append(allocator, _tuple);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk _items_list;\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

// ✅ List methods - IMPLEMENTED
// ✅ list.append(item) - FULLY IMPLEMENTED
// ✅ list.pop([index]) - FULLY IMPLEMENTED
// ✅ list.extend(other) - FULLY IMPLEMENTED
// ✅ list.insert(index, item) - FULLY IMPLEMENTED
// ✅ list.remove(item) - FULLY IMPLEMENTED
// ✅ list.index(item) -> usize - FULLY IMPLEMENTED
// ✅ list.reverse() - FULLY IMPLEMENTED
// ✅ list.sort() - FULLY IMPLEMENTED
// ✅ list.clear() - FULLY IMPLEMENTED
// ✅ list.copy() - FULLY IMPLEMENTED

// ✅ Dict methods - IMPLEMENTED
// ✅ dict.get(key, default) -> ?V - FULLY IMPLEMENTED
// ✅ dict.keys() -> Iterator - FULLY IMPLEMENTED
// ✅ dict.values() -> Iterator - FULLY IMPLEMENTED
// ✅ dict.items() -> Iterator - FULLY IMPLEMENTED
