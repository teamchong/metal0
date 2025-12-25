/// String methods - .split(), .upper(), .lower(), .strip(), etc.
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const expr_emitter = @import("../expr_emitter.zig");

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}


// Import submodules
const validation = @import("string/validation.zig");
const formatting = @import("string/formatting.zig");

/// Check if a string expression is uncertain (needs PyValue extraction)
/// Two-Flow: routes uncertain strings to handle PyValue.string
fn isStringUncertain(self: *NativeCodegen, obj: ast.Node) bool {
    if (obj == .name) {
        const name = obj.name.id;
        // Check scoped vars first (for loop variables, function params)
        // then fall back to global var_types
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            switch (vt) {
                .pyvalue, .unknown => return true,
                else => {},
            }
        }
        // Variable not in type map - it's likely a local with inferred type
        // Don't assume uncertain - let Zig compiler catch type mismatches
        return false;
    }
    return false;
}

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
/// Two-Flow: routes uncertain strings to PyValue-aware runtime helpers
pub fn genSplit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // Two-Flow: Check if string is uncertain (PyValue)
    // For uncertain strings, extract .string field from PyValue
    const emit_obj = if (isStringUncertain(self, obj)) blk: {
        // Generate inline extraction: obj.string
        break :blk true;
    } else false;

    if (args.len == 0) {
        // split() with no args - split on whitespace using runtime function
        try emitConst(self,"try runtime.stringSplitWhitespace(");
        if (emit_obj) {
            try self.genExpr(obj);
            try emitConst(self,".string");
        } else {
            try self.genExpr(obj);
        }
        try emitConst(self,", __global_allocator)");
        return;
    }

    // split(separator) or split(separator, maxsplit)
    const split_label = self.nextLabelId();
    try emitFmtConst(self, "split_{d}: {{\n", .{split_label});
    try emitConst(self,"    var _split_result = std.ArrayListUnmanaged([]const u8){};\n");
    try emitConst(self,"    var _split_iter = std.mem.splitSequence(u8, ");
    try self.genExpr(obj);
    try emitConst(self,", ");
    try self.genExpr(args[0]);
    try emitConst(self,");\n");

    if (args.len >= 2) {
        // maxsplit argument provided
        try emitConst(self,"    const _maxsplit = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self,"));\n");
        try emitConst(self,"    var _split_count: usize = 0;\n");
        try emitConst(self,"    while (_split_iter.next()) |part| {\n");
        try emitConst(self,"        if (_split_count >= _maxsplit) {\n");
        try emitConst(self,"            // Append rest of string after last split\n");
        try emitConst(self,"            const _rest = _split_iter.rest();\n");
        try emitConst(self,"            if (part.len > 0) {\n");
        try emitConst(self,"                if (_rest.len > 0) {\n");
        try emitConst(self,"                    const _combined = try __global_allocator.alloc(u8, part.len + ");
        try self.genExpr(args[0]);
        try emitConst(self,".len + _rest.len);\n");
        try emitConst(self,"                    @memcpy(_combined[0..part.len], part);\n");
        try emitConst(self,"                    @memcpy(_combined[part.len..part.len + ");
        try self.genExpr(args[0]);
        try emitConst(self,".len], ");
        try self.genExpr(args[0]);
        try emitConst(self,");\n");
        try emitConst(self,"                    @memcpy(_combined[part.len + ");
        try self.genExpr(args[0]);
        try emitConst(self,".len..], _rest);\n");
        try emitConst(self,"                    try _split_result.append(__global_allocator, _combined);\n");
        try emitConst(self,"                } else {\n");
        try emitConst(self,"                    try _split_result.append(__global_allocator, part);\n");
        try emitConst(self,"                }\n");
        try emitConst(self,"            }\n");
        try emitConst(self,"            break;\n");
        try emitConst(self,"        }\n");
        try emitConst(self,"        try _split_result.append(__global_allocator, part);\n");
        try emitConst(self,"        _split_count += 1;\n");
        try emitConst(self,"    }\n");
    } else {
        try emitConst(self,"    while (_split_iter.next()) |part| {\n");
        try emitConst(self,"        try _split_result.append(__global_allocator, part);\n");
        try emitConst(self,"    }\n");
    }

    try emitFmtConst(self, "    break :split_{d} _split_result;\n", .{split_label});
    try emitConst(self,"}");
}

/// Generate code for text.upper()
/// Converts string to uppercase
pub fn genUpper(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate block expression with unique label (use _idx to avoid shadowing user variables)
    const upper_label = self.nextLabelId();
    try emitFmtConst(self, "upper_{d}: {{\n", .{upper_label});
    try emitConst(self,"    const _text = ");
    try self.genExpr(obj);
    try emitConst(self,";\n");
    try emitConst(self,"    const _result = try __global_allocator.alloc(u8, _text.len);\n");
    try emitConst(self,"    for (_text, 0..) |_c, _idx| {\n");
    try emitConst(self,"        _result[_idx] = std.ascii.toUpper(_c);\n");
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :upper_{d} _result;\n", .{upper_label});
    try emitConst(self,"}");
}

/// Generate code for text.lower()
/// Converts string to lowercase
pub fn genLower(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate block expression with unique label (use _idx to avoid shadowing user variables)
    const lower_label = self.nextLabelId();
    try emitFmtConst(self, "lower_{d}: {{\n", .{lower_label});
    try emitConst(self,"    const _text = ");
    try self.genExpr(obj);
    try emitConst(self,";\n");
    try emitConst(self,"    const _result = try __global_allocator.alloc(u8, _text.len);\n");
    try emitConst(self,"    for (_text, 0..) |_c, _idx| {\n");
    try emitConst(self,"        _result[_idx] = std.ascii.toLower(_c);\n");
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :lower_{d} _result;\n", .{lower_label});
    try emitConst(self,"}");
}

/// Generate code for text.strip()
/// Removes leading/trailing whitespace
/// Two-Flow: handles uncertain strings (PyValue.string)
pub fn genStrip(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // strip() takes no arguments

    // Two-Flow: Check if string is uncertain (PyValue)
    const is_uncertain = isStringUncertain(self, obj);

    // Allocate a copy to avoid "Invalid free" when result is used with defer
    const label_id = @as(u64, @intCast(std.time.milliTimestamp()));
    try emitFmtConst(self, "strip_{d}: {{\n", .{label_id});
    try emitConst(self,"    const _text = ");
    try self.genExpr(obj);
    // Two-Flow: Extract string from PyValue if uncertain
    if (is_uncertain) {
        try emitConst(self,".string");
    }
    try emitConst(self,";\n");
    try emitConst(self,"    const _trimmed = std.mem.trim(u8, _text, \" \\t\\n\\r\");\n");
    try emitConst(self,"    const _result = try __global_allocator.alloc(u8, _trimmed.len);\n");
    try emitConst(self,"    @memcpy(_result, _trimmed);\n");
    try emitFmtConst(self, "    break :strip_{d} _result;\n", .{label_id});
    try emitConst(self,"}");
}

/// Generate code for text.replace(old, new[, count])
/// Replaces all occurrences of old with new, or first count occurrences
pub fn genReplace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        return;
    }

    if (args.len >= 3) {
        // replace(old, new, count) - limited replacement
        const repl_label = self.nextLabelId();
        try emitFmtConst(self, "repl_{d}: {{\n", .{repl_label});
        try emitConst(self,"    const _repl_text = ");
        try self.genExpr(obj);
        try emitConst(self,";\n");
        try emitConst(self,"    const _repl_old = ");
        try self.genExpr(args[0]);
        try emitConst(self,";\n");
        try emitConst(self,"    const _repl_new = ");
        try self.genExpr(args[1]);
        try emitConst(self,";\n");
        try emitConst(self,"    var _repl_count = @as(usize, @intCast(");
        try self.genExpr(args[2]);
        try emitConst(self,"));\n");
        try emitFmtConst(self, "    if (_repl_count == 0) break :repl_{d} _repl_text;\n", .{repl_label});
        try emitConst(self,"    var _repl_result = std.ArrayListUnmanaged(u8){};\n");
        try emitConst(self,"    var _repl_pos: usize = 0;\n");
        try emitConst(self,"    while (_repl_pos < _repl_text.len and _repl_count > 0) {\n");
        try emitConst(self,"        if (std.mem.indexOf(u8, _repl_text[_repl_pos..], _repl_old)) |idx| {\n");
        try emitConst(self,"            try _repl_result.appendSlice(__global_allocator, _repl_text[_repl_pos.._repl_pos + idx]);\n");
        try emitConst(self,"            try _repl_result.appendSlice(__global_allocator, _repl_new);\n");
        try emitConst(self,"            _repl_pos += idx + _repl_old.len;\n");
        try emitConst(self,"            _repl_count -= 1;\n");
        try emitConst(self,"        } else break;\n");
        try emitConst(self,"    }\n");
        try emitConst(self,"    try _repl_result.appendSlice(__global_allocator, _repl_text[_repl_pos..]);\n");
        try emitFmtConst(self, "    break :repl_{d} _repl_result.items;\n", .{repl_label});
        try emitConst(self,"}");
    } else {
        // replace(old, new) - replace all, using labeled block like other string methods
        const repl_label = self.nextLabelId();
        try emitFmtConst(self, "repl_{d}: {{\n", .{repl_label});
        try emitConst(self, "    const __repl_result = std.mem.replaceOwned(u8, __global_allocator, ");
        try self.genExpr(obj);
        try emitConst(self, ", ");
        try self.genExpr(args[0]);
        try emitConst(self, ", ");
        try self.genExpr(args[1]);
        try emitConst(self, ") catch \"\";\n");
        try emitFmtConst(self, "    break :repl_{d} __repl_result;\n", .{repl_label});
        try emitConst(self, "}");
    }
}

/// Generate code for sep.join(list)
/// Joins list elements with separator
/// Two-Flow: runtime.string_utils.pyJoin already handles PyValue types
pub fn genJoin(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // sep.join() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Two-Flow: Check if separator is uncertain (PyValue)
    const is_uncertain = isStringUncertain(self, obj);

    // Generate unique labeled block for join operation
    const join_label = self.nextLabelId();
    try emitFmtConst(self, "join_{d}: {{\n", .{join_label});
    try emitConst(self,"const __join_sep = ");
    try self.genExpr(obj); // The separator string
    // Two-Flow: Extract string from PyValue if uncertain
    if (is_uncertain) {
        try emitConst(self,".string");
    }
    try emitConst(self,";\n");
    try emitConst(self,"const __join_list = ");
    try self.genExpr(args[0]); // The list
    try emitConst(self,";\n");
    try emitFmtConst(self, "break :join_{d} try runtime.string_utils.pyJoin(__global_allocator, __join_sep, __join_list);\n", .{join_label});
    try emitConst(self,"}");
}

/// Generate code for text.startswith(prefix[, start[, end]])
/// Checks if string starts with prefix
pub fn genStartswith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.startswith() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    if (args.len == 1) {
        // Simple case: s.startswith(prefix)
        try emitConst(self,"std.mem.startsWith(u8, ");
        try self.genExpr(obj);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,")");
    } else {
        // s.startswith(prefix, start) or s.startswith(prefix, start, end)
        const sw_label = self.nextLabelId();
        try emitFmtConst(self, "sw_{d}: {{\n", .{sw_label});
        try emitConst(self,"    const __sw_text = ");
        try self.genExpr(obj);
        try emitConst(self,";\n");
        try emitConst(self,"    const __sw_prefix = ");
        try self.genExpr(args[0]);
        try emitConst(self,";\n");
        try emitConst(self,"    const __sw_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self,"));\n");

        if (args.len >= 3) {
            try emitConst(self,"    const __sw_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try emitConst(self,")), __sw_text.len);\n");
        } else {
            try emitConst(self,"    const __sw_end = __sw_text.len;\n");
        }

        try emitFmtConst(self, "    if (__sw_start >= __sw_end) break :sw_{d} false;\n", .{sw_label});
        try emitFmtConst(self, "    break :sw_{d} std.mem.startsWith(u8, __sw_text[__sw_start..__sw_end], __sw_prefix);\n", .{sw_label});
        try emitConst(self,"}");
    }
}

/// Generate code for text.endswith(suffix[, start[, end]])
/// Checks if string ends with suffix
pub fn genEndswith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.endswith() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    if (args.len == 1) {
        // Simple case: s.endswith(suffix)
        try emitConst(self,"std.mem.endsWith(u8, ");
        try self.genExpr(obj);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,")");
    } else {
        // s.endswith(suffix, start) or s.endswith(suffix, start, end)
        const ew_label = self.nextLabelId();
        try emitFmtConst(self, "ew_{d}: {{\n", .{ew_label});
        try emitConst(self,"    const __ew_text = ");
        try self.genExpr(obj);
        try emitConst(self,";\n");
        try emitConst(self,"    const __ew_suffix = ");
        try self.genExpr(args[0]);
        try emitConst(self,";\n");
        try emitConst(self,"    const __ew_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self,"));\n");

        if (args.len >= 3) {
            try emitConst(self,"    const __ew_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try emitConst(self,")), __ew_text.len);\n");
        } else {
            try emitConst(self,"    const __ew_end = __ew_text.len;\n");
        }

        try emitFmtConst(self, "    if (__ew_start >= __ew_end) break :ew_{d} false;\n", .{ew_label});
        try emitFmtConst(self, "    break :ew_{d} std.mem.endsWith(u8, __ew_text[__ew_start..__ew_end], __ew_suffix);\n", .{ew_label});
        try emitConst(self,"}");
    }
}

/// Generate code for text.find(substring[, start[, end]])
/// Returns index of first occurrence, or -1 if not found
pub fn genFind(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.find() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    if (args.len == 1) {
        // Simple case: s.find(sub) - no start/end
        // Generate: if (std.mem.indexOf(u8, text, substring)) |idx| @as(i64, @intCast(idx)) else -1
        try emitConst(self,"if (std.mem.indexOf(u8, ");
        try self.genExpr(obj);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,")) |idx| @as(i64, @intCast(idx)) else -1");
    } else {
        // s.find(sub, start) or s.find(sub, start, end)
        // Generate a block that slices the string and adjusts the result
        const find_label = self.nextLabelId();
        try emitFmtConst(self, "find_{d}: {{\n", .{find_label});
        try emitConst(self,"    const __find_text = ");
        try self.genExpr(obj);
        try emitConst(self,";\n");
        try emitConst(self,"    const __find_sub = ");
        try self.genExpr(args[0]);
        try emitConst(self,";\n");
        try emitConst(self,"    const __find_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self,"));\n");

        if (args.len >= 3) {
            try emitConst(self,"    const __find_end = @min(@as(usize, @intCast(");
            try self.genExpr(args[2]);
            try emitConst(self,")), __find_text.len);\n");
        } else {
            try emitConst(self,"    const __find_end = __find_text.len;\n");
        }

        try emitFmtConst(self, "    if (__find_start >= __find_end) break :find_{d} @as(i64, -1);\n", .{find_label});
        try emitConst(self,"    const __find_slice = __find_text[__find_start..__find_end];\n");
        try emitFmtConst(self, "    break :find_{d} if (std.mem.indexOf(u8, __find_slice, __find_sub)) |idx| @as(i64, @intCast(idx + __find_start)) else -1;\n", .{find_label});
        try emitConst(self,"}");
    }
}

/// Generate code for text.count(substring[, start[, end]])
/// Counts non-overlapping occurrences
pub fn genCount(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.count() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;

    // Generate loop to count occurrences
    const cnt_label = self.nextLabelId();
    try emitFmtConst(self, "cnt_{d}: {{\n", .{cnt_label});
    try emitConst(self,"    const __cnt_text = ");
    try self.genExpr(obj);
    try emitConst(self,";\n");
    try emitConst(self,"    const __cnt_needle = ");
    try self.genExpr(args[0]);
    try emitConst(self,";\n");

    if (args.len >= 2) {
        try emitConst(self,"    const __cnt_start = @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self,"));\n");
    } else {
        try emitConst(self,"    const __cnt_start: usize = 0;\n");
    }

    if (args.len >= 3) {
        try emitConst(self,"    const __cnt_end = @min(@as(usize, @intCast(");
        try self.genExpr(args[2]);
        try emitConst(self,")), __cnt_text.len);\n");
    } else {
        try emitConst(self,"    const __cnt_end = __cnt_text.len;\n");
    }

    try emitFmtConst(self, "    if (__cnt_start >= __cnt_end) break :cnt_{d} @as(i64, 0);\n", .{cnt_label});
    try emitConst(self,"    const __cnt_slice = __cnt_text[__cnt_start..__cnt_end];\n");
    try emitConst(self,"    var __cnt_count: i64 = 0;\n");
    try emitConst(self,"    var __cnt_pos: usize = 0;\n");
    try emitConst(self,"    while (__cnt_pos < __cnt_slice.len) {\n");
    try emitConst(self,"        if (std.mem.indexOf(u8, __cnt_slice[__cnt_pos..], __cnt_needle)) |idx| {\n");
    try emitConst(self,"            __cnt_count += 1;\n");
    try emitConst(self,"            __cnt_pos += idx + __cnt_needle.len;\n");
    try emitConst(self,"        } else break;\n");
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :cnt_{d} __cnt_count;\n", .{cnt_label});
    try emitConst(self,"}");
}

/// Alias for genIndex (string.index() in methods.zig)
pub const genStrIndex = genIndex;

/// Generate code for text.encode(encoding="utf-8")
/// In Zig, strings are already UTF-8, so this just returns the string as bytes
pub fn genEncode(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // Just return the string - Zig strings are UTF-8 bytes already
    // The encoding argument is consumed via runtime.discard to prevent "unused" errors
    // and avoid "pointless discard of local constant" when arg is already a variable
    if (args.len > 0) {
        // Generate: encode_blk: { runtime.discard(encoding_arg); break :encode_blk text; }
        var em = self.exprEmitter();
        const id = em.reserveLabelId();
        try emitFmtConst(self, "encode_{d}: {{ runtime.discard(", .{id});
        try self.genExpr(args[0]);
        try emitFmtConst(self, "); break :encode_{d} ", .{id});
        try self.genExpr(obj);
        try emitConst(self,"; }");
    } else {
        try self.genExpr(obj);
    }
}

/// Generate code for bytes.decode(encoding="utf-8")
/// In Zig, bytes and strings are already UTF-8, so this just returns the bytes as string
pub fn genDecode(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // Just return the bytes - Zig bytes are UTF-8 strings already
    // The encoding argument is consumed via runtime.discard to prevent "unused" errors
    if (args.len > 0) {
        // Generate: decode_blk: { runtime.discard(encoding_arg); break :decode_blk bytes; }
        var em = self.exprEmitter();
        const id = em.reserveLabelId();
        try emitFmtConst(self, "decode_{d}: {{ runtime.discard(", .{id});
        try self.genExpr(args[0]);
        try emitFmtConst(self, "); break :decode_{d} ", .{id});
        try self.genExpr(obj);
        try emitConst(self,"; }");
    } else {
        try self.genExpr(obj);
    }
}

/// Generate code for text.splitlines([keepends])
/// Splits string at line boundaries (\n, \r, \r\n)
pub fn genSplitlines(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const label_id = @as(u64, @intCast(std.time.milliTimestamp()));
    try emitFmtConst(self, "splitlines_{d}: {{\n", .{label_id});
    try emitConst(self,"    const _text = ");
    try self.genExpr(obj);
    try emitConst(self,";\n");

    // keepends argument (default false)
    if (args.len > 0) {
        try emitConst(self,"    const _keepends = ");
        try self.genExpr(args[0]);
        try emitConst(self,";\n");
    } else {
        try emitConst(self,"    const _keepends = false;\n");
    }

    try emitConst(self,"    var _result = std.ArrayListUnmanaged([]const u8){};\n");
    try emitConst(self,"    var _start: usize = 0;\n");
    try emitConst(self,"    var _i: usize = 0;\n");
    try emitConst(self,"    while (_i < _text.len) {\n");
    try emitConst(self,"        if (_i + 1 < _text.len and _text[_i] == '\\r' and _text[_i + 1] == '\\n') {\n");
    try emitConst(self,"            const _end = if (_keepends) _i + 2 else _i;\n");
    try emitConst(self,"            try _result.append(__global_allocator, _text[_start.._end]);\n");
    try emitConst(self,"            _i += 2;\n");
    try emitConst(self,"            _start = _i;\n");
    try emitConst(self,"        } else if (_text[_i] == '\\n' or _text[_i] == '\\r') {\n");
    try emitConst(self,"            const _end = if (_keepends) _i + 1 else _i;\n");
    try emitConst(self,"            try _result.append(__global_allocator, _text[_start.._end]);\n");
    try emitConst(self,"            _i += 1;\n");
    try emitConst(self,"            _start = _i;\n");
    try emitConst(self,"        } else {\n");
    try emitConst(self,"            _i += 1;\n");
    try emitConst(self,"        }\n");
    try emitConst(self,"    }\n");
    try emitConst(self,"    if (_start < _text.len) {\n");
    try emitConst(self,"        try _result.append(__global_allocator, _text[_start..]);\n");
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :splitlines_{d} _result;\n", .{label_id});
    try emitConst(self,"}");
}

/// Generate code for text.partition(sep)
/// Returns 3-tuple: (before, sep, after) or (text, "", "") if sep not found
pub fn genPartition(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.partition() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();
    try emitFmtConst(self, "partition_{d}: {{\n", .{label_id});
    try emitConst(self,"    const _text = ");
    try self.genExpr(obj);
    try emitConst(self,";\n");
    try emitConst(self,"    const _sep = ");
    try self.genExpr(args[0]);
    try emitConst(self,";\n");
    try emitConst(self,"    if (std.mem.indexOf(u8, _text, _sep)) |idx| {\n");
    try emitFmtConst(self, "        break :partition_{d} .{{ _text[0..idx], _sep, _text[idx + _sep.len..] }};\n", .{label_id});
    try emitConst(self,"    } else {\n");
    try emitFmtConst(self, "        break :partition_{d} .{{ _text, \"\", \"\" }};\n", .{label_id});
    try emitConst(self,"    }\n");
    try emitConst(self,"}");
}

/// Generate code for text.rpartition(sep)
/// Like partition but searches from the right
pub fn genRpartition(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.rpartition() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();
    try emitFmtConst(self, "rpartition_{d}: {{\n", .{label_id});
    try emitConst(self,"    const _text = ");
    try self.genExpr(obj);
    try emitConst(self,";\n");
    try emitConst(self,"    const _sep = ");
    try self.genExpr(args[0]);
    try emitConst(self,";\n");
    try emitConst(self,"    if (std.mem.lastIndexOf(u8, _text, _sep)) |idx| {\n");
    try emitFmtConst(self, "        break :rpartition_{d} .{{ _text[0..idx], _sep, _text[idx + _sep.len..] }};\n", .{label_id});
    try emitConst(self,"    } else {\n");
    try emitFmtConst(self, "        break :rpartition_{d} .{{ \"\", \"\", _text }};\n", .{label_id});
    try emitConst(self,"    }\n");
    try emitConst(self,"}");
}

/// Generate code for text.removeprefix(prefix)
/// Returns string with prefix removed if present, otherwise original string
pub fn genRemoveprefix(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.removeprefix() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();
    try emitFmtConst(self, "removeprefix_{d}: {{\n", .{label_id});
    try emitConst(self,"    const _text = ");
    try self.genExpr(obj);
    try emitConst(self,";\n");
    try emitConst(self,"    const _prefix = ");
    try self.genExpr(args[0]);
    try emitConst(self,";\n");
    try emitConst(self,"    if (std.mem.startsWith(u8, _text, _prefix)) {\n");
    try emitFmtConst(self, "        break :removeprefix_{d} _text[_prefix.len..];\n", .{label_id});
    try emitConst(self,"    } else {\n");
    try emitFmtConst(self, "        break :removeprefix_{d} _text;\n", .{label_id});
    try emitConst(self,"    }\n");
    try emitConst(self,"}");
}

/// Generate code for text.removesuffix(suffix)
/// Returns string with suffix removed if present, otherwise original string
pub fn genRemovesuffix(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // str.removesuffix() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();
    try emitFmtConst(self, "removesuffix_{d}: {{\n", .{label_id});
    try emitConst(self,"    const _text = ");
    try self.genExpr(obj);
    try emitConst(self,";\n");
    try emitConst(self,"    const _suffix = ");
    try self.genExpr(args[0]);
    try emitConst(self,";\n");
    try emitConst(self,"    if (std.mem.endsWith(u8, _text, _suffix)) {\n");
    try emitFmtConst(self, "        break :removesuffix_{d} _text[0 .. _text.len - _suffix.len];\n", .{label_id});
    try emitConst(self,"    } else {\n");
    try emitFmtConst(self, "        break :removesuffix_{d} _text;\n", .{label_id});
    try emitConst(self,"    }\n");
    try emitConst(self,"}");
}

/// Generate code for text.rsplit([sep[, maxsplit]])
/// Like split but starts from the right
pub fn genRsplit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();
    try emitFmtConst(self, "rsplit_{d}: {{\n", .{label_id});
    try emitConst(self,"    const _text = ");
    try self.genExpr(obj);
    try emitConst(self,";\n");

    if (args.len == 0) {
        // rsplit() with no args - same as split() for now
        try emitConst(self,"    var _result = try runtime.stringSplitWhitespace(_text, __global_allocator);\n");
        try emitConst(self,"    std.mem.reverse([]const u8, _result.items);\n");
        try emitFmtConst(self, "    break :rsplit_{d} _result;\n", .{label_id});
    } else {
        try emitConst(self,"    const _sep = ");
        try self.genExpr(args[0]);
        try emitConst(self,";\n");
        try emitConst(self,"    var _result = std.ArrayListUnmanaged([]const u8){};\n");

        if (args.len >= 2) {
            try emitConst(self,"    const _maxsplit = @as(usize, @intCast(");
            try self.genExpr(args[1]);
            try emitConst(self,"));\n");
            try emitConst(self,"    var _count: usize = 0;\n");
            try emitConst(self,"    var _end = _text.len;\n");
            try emitConst(self,"    while (_count < _maxsplit) {\n");
            try emitConst(self,"        if (std.mem.lastIndexOf(u8, _text[0.._end], _sep)) |idx| {\n");
            try emitConst(self,"            try _result.insert(__global_allocator, 0, _text[idx + _sep.len .. _end]);\n");
            try emitConst(self,"            _end = idx;\n");
            try emitConst(self,"            _count += 1;\n");
            try emitConst(self,"        } else break;\n");
            try emitConst(self,"    }\n");
            try emitConst(self,"    try _result.insert(__global_allocator, 0, _text[0.._end]);\n");
        } else {
            try emitConst(self,"    var _iter = std.mem.splitSequence(u8, _text, _sep);\n");
            try emitConst(self,"    while (_iter.next()) |part| {\n");
            try emitConst(self,"        try _result.append(__global_allocator, part);\n");
            try emitConst(self,"    }\n");
        }
        try emitFmtConst(self, "    break :rsplit_{d} _result;\n", .{label_id});
    }
    try emitConst(self,"}");
}

/// Generate code for text.casefold()
/// Returns casefolded string (aggressive lowercase for caseless matching)
/// Note: For ASCII, casefold() is same as lower()
pub fn genCasefold(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();
    try emitFmtConst(self, "casefold_{d}: {{\n", .{label_id});
    try emitConst(self,"    const _text = ");
    try self.genExpr(obj);
    try emitConst(self,";\n");
    try emitConst(self,"    const _result = try __global_allocator.alloc(u8, _text.len);\n");
    try emitConst(self,"    for (_text, 0..) |c, i| {\n");
    try emitConst(self,"        _result[i] = std.ascii.toLower(c);\n");
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :casefold_{d} _result;\n", .{label_id});
    try emitConst(self,"}");
}

/// Generate code for text.format(*args, **kwargs)
/// Python new-style string formatting: "Hello {name}".format(name="World")
pub fn genFormat(self: *NativeCodegen, obj: ast.Node, args: []ast.Node, keywords: []ast.Node.KeywordArg) CodegenError!void {
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    try emitFmtConst(self, "format_{d}: {{\n", .{label_id});
    try emitConst(self,"break :format_");
    try emitFmtConst(self, "{d}", .{label_id});
    try emitConst(self," try runtime.string_utils.pyStrFormat(__global_allocator, ");
    try self.genExpr(obj);
    try emitConst(self,", .{");

    // Generate positional arguments first
    for (args, 0..) |arg, i| {
        if (i > 0) try emitConst(self,", ");
        try self.genExpr(arg);
    }

    // Generate keyword arguments as tuples: .{"name", value}
    for (keywords, 0..) |kw, i| {
        if (i > 0 or args.len > 0) try emitConst(self,", ");
        try emitConst(self,".{\"");
        try emitConst(self,kw.name);
        try emitConst(self,"\", ");
        try self.genExpr(kw.value);
        try emitConst(self,"}");
    }

    try emitConst(self,"});\n}");
}
