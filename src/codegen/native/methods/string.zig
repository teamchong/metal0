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
pub const genIsdecimal = validation.genIsdecimal;
pub const genIsnumeric = validation.genIsnumeric;

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

/// Generate code for text.split([separator[, maxsplit]])
/// Example: "a b c".split(" ") -> ArrayList([]const u8)
/// Example: "a  b c".split() -> splits on any whitespace, removes empty strings
/// Example: "a b c d".split(" ", 2) -> ["a", "b", "c d"]
pub fn genSplit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // split() with no args - split on whitespace using runtime function
        try self.emit("try runtime.stringSplitWhitespace(");
        try self.genExpr(obj);
        try self.emit(", __global_allocator)");
        return;
    }

    // split(separator) or split(separator, maxsplit)
    try self.emit("blk: {\n");
    try self.emit("    var _split_result = std.ArrayList([]const u8){};\n");
    try self.emit("    var _split_iter = std.mem.splitSequence(u8, ");
    try self.genExpr(obj);
    try self.emit(", ");
    try self.genExpr(args[0]);
    try self.emit(");\n");

    if (args.len >= 2) {
        // maxsplit argument provided
        try self.emit("    const _maxsplit = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try self.emit("));\n");
        try self.emit("    var _split_count: usize = 0;\n");
        try self.emit("    while (_split_iter.next()) |part| {\n");
        try self.emit("        if (_split_count >= _maxsplit) {\n");
        try self.emit("            // Append rest of string after last split\n");
        try self.emit("            const _rest = _split_iter.rest();\n");
        try self.emit("            if (part.len > 0) {\n");
        try self.emit("                if (_rest.len > 0) {\n");
        try self.emit("                    const _combined = try __global_allocator.alloc(u8, part.len + ");
        try self.genExpr(args[0]);
        try self.emit(".len + _rest.len);\n");
        try self.emit("                    @memcpy(_combined[0..part.len], part);\n");
        try self.emit("                    @memcpy(_combined[part.len..part.len + ");
        try self.genExpr(args[0]);
        try self.emit(".len], ");
        try self.genExpr(args[0]);
        try self.emit(");\n");
        try self.emit("                    @memcpy(_combined[part.len + ");
        try self.genExpr(args[0]);
        try self.emit(".len..], _rest);\n");
        try self.emit("                    try _split_result.append(__global_allocator, _combined);\n");
        try self.emit("                } else {\n");
        try self.emit("                    try _split_result.append(__global_allocator, part);\n");
        try self.emit("                }\n");
        try self.emit("            }\n");
        try self.emit("            break;\n");
        try self.emit("        }\n");
        try self.emit("        try _split_result.append(__global_allocator, part);\n");
        try self.emit("        _split_count += 1;\n");
        try self.emit("    }\n");
    } else {
        try self.emit("    while (_split_iter.next()) |part| {\n");
        try self.emit("        try _split_result.append(__global_allocator, part);\n");
        try self.emit("    }\n");
    }

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

/// Generate code for text.replace(old, new[, count])
/// Replaces all occurrences of old with new, or first count occurrences
pub fn genReplace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        return;
    }

    if (args.len >= 3) {
        // replace(old, new, count) - limited replacement
        try self.emit("blk: {\n");
        try self.emit("    const _repl_text = ");
        try self.genExpr(obj);
        try self.emit(";\n");
        try self.emit("    const _repl_old = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emit("    const _repl_new = ");
        try self.genExpr(args[1]);
        try self.emit(";\n");
        try self.emit("    var _repl_count = @as(usize, @intCast(");
        try self.genExpr(args[2]);
        try self.emit("));\n");
        try self.emit("    if (_repl_count == 0) break :blk _repl_text;\n");
        try self.emit("    var _repl_result = std.ArrayList(u8){};\n");
        try self.emit("    var _repl_pos: usize = 0;\n");
        try self.emit("    while (_repl_pos < _repl_text.len and _repl_count > 0) {\n");
        try self.emit("        if (std.mem.indexOf(u8, _repl_text[_repl_pos..], _repl_old)) |idx| {\n");
        try self.emit("            try _repl_result.appendSlice(__global_allocator, _repl_text[_repl_pos.._repl_pos + idx]);\n");
        try self.emit("            try _repl_result.appendSlice(__global_allocator, _repl_new);\n");
        try self.emit("            _repl_pos += idx + _repl_old.len;\n");
        try self.emit("            _repl_count -= 1;\n");
        try self.emit("        } else break;\n");
        try self.emit("    }\n");
        try self.emit("    try _repl_result.appendSlice(__global_allocator, _repl_text[_repl_pos..]);\n");
        try self.emit("    break :blk _repl_result.items;\n");
        try self.emit("}");
    } else {
        // replace(old, new) - replace all
        try self.emit("try std.mem.replaceOwned(u8, __global_allocator, ");
        try self.genExpr(obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(")");
    }
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

/// Generate code for text.startswith(prefix[, start[, end]])
/// Checks if string starts with prefix
pub fn genStartswith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    if (args.len == 1) {
        // Simple case: s.startswith(prefix)
        try self.emit("std.mem.startsWith(u8, ");
        try self.genExpr(obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        // s.startswith(prefix, start) or s.startswith(prefix, start, end)
        try self.emit("blk: {\n");
        try self.emit("    const __sw_text = ");
        try self.genExpr(obj);
        try self.emit(";\n");
        try self.emit("    const __sw_prefix = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emit("    const __sw_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try self.emit("));\n");

        if (args.len >= 3) {
            try self.emit("    const __sw_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try self.emit(")), __sw_text.len);\n");
        } else {
            try self.emit("    const __sw_end = __sw_text.len;\n");
        }

        try self.emit("    if (__sw_start >= __sw_end) break :blk false;\n");
        try self.emit("    break :blk std.mem.startsWith(u8, __sw_text[__sw_start..__sw_end], __sw_prefix);\n");
        try self.emit("}");
    }
}

/// Generate code for text.endswith(suffix[, start[, end]])
/// Checks if string ends with suffix
pub fn genEndswith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    if (args.len == 1) {
        // Simple case: s.endswith(suffix)
        try self.emit("std.mem.endsWith(u8, ");
        try self.genExpr(obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        // s.endswith(suffix, start) or s.endswith(suffix, start, end)
        try self.emit("blk: {\n");
        try self.emit("    const __ew_text = ");
        try self.genExpr(obj);
        try self.emit(";\n");
        try self.emit("    const __ew_suffix = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emit("    const __ew_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try self.emit("));\n");

        if (args.len >= 3) {
            try self.emit("    const __ew_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try self.emit(")), __ew_text.len);\n");
        } else {
            try self.emit("    const __ew_end = __ew_text.len;\n");
        }

        try self.emit("    if (__ew_start >= __ew_end) break :blk false;\n");
        try self.emit("    break :blk std.mem.endsWith(u8, __ew_text[__ew_start..__ew_end], __ew_suffix);\n");
        try self.emit("}");
    }
}

/// Generate code for text.find(substring[, start[, end]])
/// Returns index of first occurrence, or -1 if not found
pub fn genFind(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    if (args.len == 1) {
        // Simple case: s.find(sub) - no start/end
        // Generate: if (std.mem.indexOf(u8, text, substring)) |idx| @as(i64, @intCast(idx)) else -1
        try self.emit("if (std.mem.indexOf(u8, ");
        try self.genExpr(obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(")) |idx| @as(i64, @intCast(idx)) else -1");
    } else {
        // s.find(sub, start) or s.find(sub, start, end)
        // Generate a block that slices the string and adjusts the result
        try self.emit("blk: {\n");
        try self.emit("    const __find_text = ");
        try self.genExpr(obj);
        try self.emit(";\n");
        try self.emit("    const __find_sub = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emit("    const __find_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try self.emit("));\n");

        if (args.len >= 3) {
            try self.emit("    const __find_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try self.emit(")), __find_text.len);\n");
        } else {
            try self.emit("    const __find_end = __find_text.len;\n");
        }

        try self.emit("    if (__find_start >= __find_end) break :blk @as(i64, -1);\n");
        try self.emit("    const __find_slice = __find_text[__find_start..__find_end];\n");
        try self.emit("    break :blk if (std.mem.indexOf(u8, __find_slice, __find_sub)) |idx| @as(i64, @intCast(idx + __find_start)) else -1;\n");
        try self.emit("}");
    }
}

/// Generate code for text.count(substring[, start[, end]])
/// Counts non-overlapping occurrences
pub fn genCount(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Generate loop to count occurrences
    try self.emit("blk: {\n");
    try self.emit("    const __cnt_text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    const __cnt_needle = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");

    if (args.len >= 2) {
        try self.emit("    const __cnt_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try self.emit("));\n");
    } else {
        try self.emit("    const __cnt_start: usize = 0;\n");
    }

    if (args.len >= 3) {
        try self.emit("    const __cnt_end = @min(@as(usize, @intCast(");
        try self.genExpr(args[2]);
        try self.emit(")), __cnt_text.len);\n");
    } else {
        try self.emit("    const __cnt_end = __cnt_text.len;\n");
    }

    try self.emit("    if (__cnt_start >= __cnt_end) break :blk @as(i64, 0);\n");
    try self.emit("    const __cnt_slice = __cnt_text[__cnt_start..__cnt_end];\n");
    try self.emit("    var __cnt_count: i64 = 0;\n");
    try self.emit("    var __cnt_pos: usize = 0;\n");
    try self.emit("    while (__cnt_pos < __cnt_slice.len) {\n");
    try self.emit("        if (std.mem.indexOf(u8, __cnt_slice[__cnt_pos..], __cnt_needle)) |idx| {\n");
    try self.emit("            __cnt_count += 1;\n");
    try self.emit("            __cnt_pos += idx + __cnt_needle.len;\n");
    try self.emit("        } else break;\n");
    try self.emit("    }\n");
    try self.emit("    break :blk __cnt_count;\n");
    try self.emit("}");
}

/// Alias for genIndex (string.index() in methods.zig)
pub const genStrIndex = genIndex;

/// Generate code for text.encode(encoding="utf-8")
/// In Zig, strings are already UTF-8, so this just returns the string as bytes
pub fn genEncode(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // Just return the string - Zig strings are UTF-8 bytes already
    // The encoding argument is ignored (UTF-8 is the only encoding we support)
    _ = args;
    try self.genExpr(obj);
}

/// Generate code for bytes.decode(encoding="utf-8")
/// In Zig, bytes and strings are already UTF-8, so this just returns the bytes as string
pub fn genDecode(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // Just return the bytes - Zig bytes are UTF-8 strings already
    // The encoding argument is ignored (UTF-8 is the only encoding we support)
    _ = args;
    try self.genExpr(obj);
}

/// Generate code for text.splitlines([keepends])
/// Splits string at line boundaries (\n, \r, \r\n)
pub fn genSplitlines(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const label_id = @as(u64, @intCast(std.time.milliTimestamp()));
    try self.emitFmt("splitlines_{d}: {{\n", .{label_id});
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");

    // keepends argument (default false)
    if (args.len > 0) {
        try self.emit("    const _keepends = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
    } else {
        try self.emit("    const _keepends = false;\n");
    }

    try self.emit("    var _result = std.ArrayList([]const u8){};\n");
    try self.emit("    var _start: usize = 0;\n");
    try self.emit("    var _i: usize = 0;\n");
    try self.emit("    while (_i < _text.len) {\n");
    try self.emit("        if (_i + 1 < _text.len and _text[_i] == '\\r' and _text[_i + 1] == '\\n') {\n");
    try self.emit("            const _end = if (_keepends) _i + 2 else _i;\n");
    try self.emit("            try _result.append(__global_allocator, _text[_start.._end]);\n");
    try self.emit("            _i += 2;\n");
    try self.emit("            _start = _i;\n");
    try self.emit("        } else if (_text[_i] == '\\n' or _text[_i] == '\\r') {\n");
    try self.emit("            const _end = if (_keepends) _i + 1 else _i;\n");
    try self.emit("            try _result.append(__global_allocator, _text[_start.._end]);\n");
    try self.emit("            _i += 1;\n");
    try self.emit("            _start = _i;\n");
    try self.emit("        } else {\n");
    try self.emit("            _i += 1;\n");
    try self.emit("        }\n");
    try self.emit("    }\n");
    try self.emit("    if (_start < _text.len) {\n");
    try self.emit("        try _result.append(__global_allocator, _text[_start..]);\n");
    try self.emit("    }\n");
    try self.emitFmt("    break :splitlines_{d} _result;\n", .{label_id});
    try self.emit("}");
}
