/// String methods - .split(), .upper(), .lower(), .strip(), etc.
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

// Import submodules
const validation = @import("string/validation.zig");
const formatting = @import("string/formatting.zig");

// Re-export validation methods
pub const genIsdigit = validation.genIsdigit;
pub const genIsalpha = validation.genIsalpha;
pub const genIsalnum = validation.genIsalnum;
pub const genIsspace = validation.genIsspace;
pub const genIslower = validation.genIslower;
pub const genIsupper = validation.genIsupper;
pub const genIsascii = validation.genIsascii;
pub const genIstitle = validation.genIstitle;
pub const genIsprintable = validation.genIsprintable;

// Re-export formatting methods
pub const genLstrip = formatting.genLstrip;
pub const genRstrip = formatting.genRstrip;
pub const genCapitalize = formatting.genCapitalize;
pub const genTitle = formatting.genTitle;
pub const genSwapcase = formatting.genSwapcase;
pub const genIndex = formatting.genIndex;
pub const genRfind = formatting.genRfind;
pub const genRindex = formatting.genRindex;
pub const genLjust = formatting.genLjust;
pub const genRjust = formatting.genRjust;
pub const genCenter = formatting.genCenter;
pub const genZfill = formatting.genZfill;

/// Generate code for text.split(separator) or text.split() for whitespace
/// Example: "a b c".split(" ") -> ArrayList([]const u8)
/// Example: "a  b c".split() -> splits on any whitespace, removes empty strings
pub fn genSplit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // split() with no args - split on whitespace using runtime function
        try self.emit("try runtime.stringSplitWhitespace(");
        try self.genExpr(obj);
        try self.emit(", __global_allocator)");
        return;
    }

    // split(separator) - use std.mem.splitSequence
    // Generate block expression that returns ArrayList([]const u8)
    // Keep as ArrayList to match type inference (.list type)
    try self.emit("blk: {\n");
    try self.emit("    var _split_result = std.ArrayList([]const u8){};\n");
    try self.emit("    var _split_iter = std.mem.splitSequence(u8, ");
    try self.genExpr(obj); // The string to split
    try self.emit(", ");
    try self.genExpr(args[0]); // The separator
    try self.emit(");\n");
    try self.emit("    while (_split_iter.next()) |part| {\n");
    try self.emit("        try _split_result.append(__global_allocator, part);\n");
    try self.emit("    }\n");
    try self.emit("    break :blk _split_result;\n");
    try self.emit("}");
}

/// Generate code for text.upper()
/// Converts string to uppercase
pub fn genUpper(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate block expression (use _idx to avoid shadowing user variables)
    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _result = try __global_allocator.alloc(u8, _text.len);\n");
    try self.emit("    for (_text, 0..) |_c, _idx| {\n");
    try self.emit("        _result[_idx] = std.ascii.toUpper(_c);\n");
    try self.emit("    }\n");
    try self.emit("    break :blk _result;\n");
    try self.emit("}");
}

/// Generate code for text.lower()
/// Converts string to lowercase
pub fn genLower(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate block expression (use _idx to avoid shadowing user variables)
    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _result = try __global_allocator.alloc(u8, _text.len);\n");
    try self.emit("    for (_text, 0..) |_c, _idx| {\n");
    try self.emit("        _result[_idx] = std.ascii.toLower(_c);\n");
    try self.emit("    }\n");
    try self.emit("    break :blk _result;\n");
    try self.emit("}");
}

/// Generate code for text.strip()
/// Removes leading/trailing whitespace
pub fn genStrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // strip() takes no arguments

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const label_id = @as(u64, @intCast(std.time.milliTimestamp()));
    try self.emitFmt("strip_{d}: {{\n", .{label_id});
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _trimmed = std.mem.trim(u8, _text, \" \\t\\n\\r\");\n");
    try self.emit("    const _result = try __global_allocator.alloc(u8, _trimmed.len);\n");
    try self.emit("    @memcpy(_result, _trimmed);\n");
    try self.emitFmt("    break :strip_{d} _result;\n", .{label_id});
    try self.emit("}");
}

/// Generate code for text.replace(old, new)
/// Replaces all occurrences of old with new
pub fn genReplace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 2) {
        return;
    }

    // Generate: try std.mem.replaceOwned(u8, allocator, text, old, new)
    try self.emit("try std.mem.replaceOwned(u8, __global_allocator, ");
    try self.genExpr(obj);
    try self.emit(", ");
    try self.genExpr(args[0]); // old
    try self.emit(", ");
    try self.genExpr(args[1]); // new
    try self.emit(")");
}

/// Generate code for sep.join(list)
/// Joins list elements with separator
pub fn genJoin(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.join(allocator, separator, list)
    try self.emit("std.mem.join(__global_allocator, ");
    try self.genExpr(obj); // The separator string
    try self.emit(", ");
    try self.genExpr(args[0]); // The list
    try self.emit(")");
}

/// Generate code for text.startswith(prefix)
/// Checks if string starts with prefix
pub fn genStartswith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.startsWith(u8, text, prefix)
    try self.emit("std.mem.startsWith(u8, ");
    try self.genExpr(obj);
    try self.emit(", ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for text.endswith(suffix)
/// Checks if string ends with suffix
pub fn genEndswith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.endsWith(u8, text, suffix)
    try self.emit("std.mem.endsWith(u8, ");
    try self.genExpr(obj);
    try self.emit(", ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for text.find(substring)
/// Returns index of first occurrence, or -1 if not found
pub fn genFind(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: if (std.mem.indexOf(u8, text, substring)) |idx| @as(i64, @intCast(idx)) else -1
    try self.emit("if (std.mem.indexOf(u8, ");
    try self.genExpr(obj);
    try self.emit(", ");
    try self.genExpr(args[0]);
    try self.emit(")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.count(substring)
/// Counts non-overlapping occurrences
pub fn genCount(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate loop to count occurrences
    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const _needle = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emit("    var _count: i64 = 0;\n");
    try self.emit("    var _pos: usize = 0;\n");
    try self.emit("    while (_pos < _text.len) {\n");
    try self.emit("        if (std.mem.indexOf(u8, _text[_pos..], _needle)) |idx| {\n");
    try self.emit("            _count += 1;\n");
    try self.emit("            _pos += idx + _needle.len;\n");
    try self.emit("        } else break;\n");
    try self.emit("    }\n");
    try self.emit("    break :blk _count;\n");
    try self.emit("}");
}

/// Alias for genIndex (string.index() in methods.zig)
pub const genStrIndex = genIndex;

/// Generate code for text.encode(encoding="utf-8")
/// In Zig, strings are already UTF-8, so this just returns the string as bytes
pub fn genEncode(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // Ignore encoding arg - Zig strings are UTF-8
    // Simply return the string as-is (it's already []const u8)
    try self.genExpr(obj);
}
