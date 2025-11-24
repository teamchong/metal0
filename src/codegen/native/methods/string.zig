/// String methods - .split(), .upper(), .lower(), .strip(), etc.
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Generate code for text.split(separator)
/// Example: "a b c".split(" ") -> ArrayList([]const u8)
pub fn genSplit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Generate block expression that returns ArrayList([]const u8)
    // Keep as ArrayList to match type inference (.list type)
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
    try self.output.appendSlice(self.allocator, "    break :blk _split_result;\n");
    try self.output.appendSlice(self.allocator, "}");
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

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const label_id = @as(u64, @intCast(std.time.milliTimestamp()));
    try self.output.writer(self.allocator).print("strip_{d}: {{\n", .{label_id});
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _trimmed = std.mem.trim(u8, _text, \" \\t\\n\\r\");\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _trimmed.len);\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result, _trimmed);\n");
    try self.output.writer(self.allocator).print("    break :strip_{d} _result;\n", .{label_id});
    try self.output.appendSlice(self.allocator, "}");
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

    // Generate loop to count occurrences
    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _needle = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    var _count: i64 = 0;\n");
    try self.output.appendSlice(self.allocator, "    var _pos: usize = 0;\n");
    try self.output.appendSlice(self.allocator, "    while (_pos < _text.len) {\n");
    try self.output.appendSlice(self.allocator, "        if (std.mem.indexOf(u8, _text[_pos..], _needle)) |idx| {\n");
    try self.output.appendSlice(self.allocator, "            _count += 1;\n");
    try self.output.appendSlice(self.allocator, "            _pos += idx + _needle.len;\n");
    try self.output.appendSlice(self.allocator, "        } else break;\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _count;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.isdigit()
/// Returns true if all characters are digits (0-9)
pub fn genIsdigit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // SIMD-optimized digit validation using @Vector
    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len == 0) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    const vec_size = 16;\n");
    try self.output.appendSlice(self.allocator, "    const zero: @Vector(vec_size, u8) = @splat('0');\n");
    try self.output.appendSlice(self.allocator, "    const nine: @Vector(vec_size, u8) = @splat('9');\n");
    try self.output.appendSlice(self.allocator, "    var i: usize = 0;\n");
    try self.output.appendSlice(self.allocator, "    while (i + vec_size <= _text.len) : (i += vec_size) {\n");
    try self.output.appendSlice(self.allocator, "        const chunk: @Vector(vec_size, u8) = _text[i..][0..vec_size].*;\n");
    try self.output.appendSlice(self.allocator, "        const ge_zero = chunk >= zero;\n");
    try self.output.appendSlice(self.allocator, "        const le_nine = chunk <= nine;\n");
    try self.output.appendSlice(self.allocator, "        const is_digit = ge_zero & le_nine;\n");
    try self.output.appendSlice(self.allocator, "        if (!@reduce(.And, is_digit)) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    while (i < _text.len) : (i += 1) {\n");
    try self.output.appendSlice(self.allocator, "        if (!std.ascii.isDigit(_text[i])) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk true;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.isalpha()
/// Returns true if all characters are alphabetic
pub fn genIsalpha(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len == 0) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    for (_text) |c| {\n");
    try self.output.appendSlice(self.allocator, "        if (!std.ascii.isAlphabetic(c)) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk true;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.isalnum()
/// Returns true if all characters are alphanumeric
pub fn genIsalnum(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len == 0) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    for (_text) |c| {\n");
    try self.output.appendSlice(self.allocator, "        if (!std.ascii.isAlphanumeric(c)) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk true;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.isspace()
/// Returns true if all characters are whitespace
pub fn genIsspace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len == 0) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    for (_text) |c| {\n");
    try self.output.appendSlice(self.allocator, "        if (!std.ascii.isWhitespace(c)) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk true;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.islower()
/// Returns true if all cased characters are lowercase
pub fn genIslower(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len == 0) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    var has_cased = false;\n");
    try self.output.appendSlice(self.allocator, "    for (_text) |c| {\n");
    try self.output.appendSlice(self.allocator, "        if (std.ascii.isUpper(c)) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "        if (std.ascii.isLower(c)) has_cased = true;\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk has_cased;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.isupper()
/// Returns true if all cased characters are uppercase
pub fn genIsupper(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len == 0) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    var has_cased = false;\n");
    try self.output.appendSlice(self.allocator, "    for (_text) |c| {\n");
    try self.output.appendSlice(self.allocator, "        if (std.ascii.isLower(c)) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "        if (std.ascii.isUpper(c)) has_cased = true;\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk has_cased;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.lstrip()
/// Removes leading whitespace
pub fn genLstrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const label_id = @as(u64, @intCast(std.time.milliTimestamp()));
    try self.output.writer(self.allocator).print("lstrip_{d}: {{\n", .{label_id});
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _trimmed = std.mem.trimLeft(u8, _text, \" \\t\\n\\r\");\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _trimmed.len);\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result, _trimmed);\n");
    try self.output.writer(self.allocator).print("    break :lstrip_{d} _result;\n", .{label_id});
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.rstrip()
/// Removes trailing whitespace
pub fn genRstrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const label_id = @as(u64, @intCast(std.time.milliTimestamp()));
    try self.output.writer(self.allocator).print("rstrip_{d}: {{\n", .{label_id});
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _trimmed = std.mem.trimRight(u8, _text, \" \\t\\n\\r\");\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _trimmed.len);\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result, _trimmed);\n");
    try self.output.writer(self.allocator).print("    break :rstrip_{d} _result;\n", .{label_id});
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.capitalize()
/// First char upper, rest lower
pub fn genCapitalize(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len == 0) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _text.len);\n");
    try self.output.appendSlice(self.allocator, "    _result[0] = std.ascii.toUpper(_text[0]);\n");
    try self.output.appendSlice(self.allocator, "    for (_text[1..], 0..) |c, i| {\n");
    try self.output.appendSlice(self.allocator, "        _result[i + 1] = std.ascii.toLower(c);\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.title()
/// Titlecase each word
pub fn genTitle(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len == 0) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _text.len);\n");
    try self.output.appendSlice(self.allocator, "    var _prev_space = true;\n");
    try self.output.appendSlice(self.allocator, "    for (_text, 0..) |c, i| {\n");
    try self.output.appendSlice(self.allocator, "        if (_prev_space and std.ascii.isAlphabetic(c)) {\n");
    try self.output.appendSlice(self.allocator, "            _result[i] = std.ascii.toUpper(c);\n");
    try self.output.appendSlice(self.allocator, "        } else {\n");
    try self.output.appendSlice(self.allocator, "            _result[i] = std.ascii.toLower(c);\n");
    try self.output.appendSlice(self.allocator, "        }\n");
    try self.output.appendSlice(self.allocator, "        _prev_space = !std.ascii.isAlphanumeric(c);\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.swapcase()
/// Swap upper/lower
pub fn genSwapcase(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, _text.len);\n");
    try self.output.appendSlice(self.allocator, "    for (_text, 0..) |c, i| {\n");
    try self.output.appendSlice(self.allocator, "        if (std.ascii.isUpper(c)) {\n");
    try self.output.appendSlice(self.allocator, "            _result[i] = std.ascii.toLower(c);\n");
    try self.output.appendSlice(self.allocator, "        } else if (std.ascii.isLower(c)) {\n");
    try self.output.appendSlice(self.allocator, "            _result[i] = std.ascii.toUpper(c);\n");
    try self.output.appendSlice(self.allocator, "        } else {\n");
    try self.output.appendSlice(self.allocator, "            _result[i] = c;\n");
    try self.output.appendSlice(self.allocator, "        }\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.index(sub)
/// Like find() but returns -1 if not found
pub fn genIndex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "if (std.mem.indexOf(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.rfind(sub)
/// Find from right
pub fn genRfind(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "if (std.mem.lastIndexOf(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.rindex(sub)
/// Like rfind() but returns -1 if not found
pub fn genRindex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "if (std.mem.lastIndexOf(u8, ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")) |idx| @as(i64, @intCast(idx)) else -1");
}

/// Generate code for text.ljust(width)
/// Left justify with spaces
pub fn genLjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _width = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len >= _width) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, @intCast(_width));\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result[0.._text.len], _text);\n");
    try self.output.appendSlice(self.allocator, "    @memset(_result[_text.len..], ' ');\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.rjust(width)
/// Right justify with spaces
pub fn genRjust(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _width = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len >= _width) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, @intCast(_width));\n");
    try self.output.appendSlice(self.allocator, "    const _pad = @as(usize, @intCast(_width)) - _text.len;\n");
    try self.output.appendSlice(self.allocator, "    @memset(_result[0.._pad], ' ');\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result[_pad..], _text);\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.center(width)
/// Center with spaces
pub fn genCenter(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _width = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len >= _width) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, @intCast(_width));\n");
    try self.output.appendSlice(self.allocator, "    const _total_pad = @as(usize, @intCast(_width)) - _text.len;\n");
    try self.output.appendSlice(self.allocator, "    const _left_pad = _total_pad / 2;\n");
    try self.output.appendSlice(self.allocator, "    @memset(_result[0.._left_pad], ' ');\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result[_left_pad.._left_pad + _text.len], _text);\n");
    try self.output.appendSlice(self.allocator, "    @memset(_result[_left_pad + _text.len..], ' ');\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.zfill(width)
/// Pad with zeros on left
pub fn genZfill(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    const _width = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len >= _width) break :blk _text;\n");
    try self.output.appendSlice(self.allocator, "    const _result = try allocator.alloc(u8, @intCast(_width));\n");
    try self.output.appendSlice(self.allocator, "    const _pad = @as(usize, @intCast(_width)) - _text.len;\n");
    try self.output.appendSlice(self.allocator, "    @memset(_result[0.._pad], '0');\n");
    try self.output.appendSlice(self.allocator, "    @memcpy(_result[_pad..], _text);\n");
    try self.output.appendSlice(self.allocator, "    break :blk _result;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.isascii()
/// All chars < 128
pub fn genIsascii(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    for (_text) |c| {\n");
    try self.output.appendSlice(self.allocator, "        if (c >= 128) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk true;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.istitle()
/// Titlecase format
pub fn genIstitle(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    if (_text.len == 0) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    var _prev_space = true;\n");
    try self.output.appendSlice(self.allocator, "    var _has_title = false;\n");
    try self.output.appendSlice(self.allocator, "    for (_text) |c| {\n");
    try self.output.appendSlice(self.allocator, "        if (std.ascii.isAlphabetic(c)) {\n");
    try self.output.appendSlice(self.allocator, "            if (_prev_space) {\n");
    try self.output.appendSlice(self.allocator, "                if (!std.ascii.isUpper(c)) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "                _has_title = true;\n");
    try self.output.appendSlice(self.allocator, "            } else {\n");
    try self.output.appendSlice(self.allocator, "                if (!std.ascii.isLower(c)) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "            }\n");
    try self.output.appendSlice(self.allocator, "            _prev_space = false;\n");
    try self.output.appendSlice(self.allocator, "        } else {\n");
    try self.output.appendSlice(self.allocator, "            _prev_space = true;\n");
    try self.output.appendSlice(self.allocator, "        }\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk _has_title;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for text.isprintable()
/// All printable chars
pub fn genIsprintable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "    const _text = ");
    try self.genExpr(obj);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    for (_text) |c| {\n");
    try self.output.appendSlice(self.allocator, "        if (!std.ascii.isPrint(c)) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk true;\n");
    try self.output.appendSlice(self.allocator, "}");
}
