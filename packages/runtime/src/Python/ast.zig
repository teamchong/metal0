const std = @import("std");
const runtime = @import("../runtime.zig");

/// Augmented assignment operators
const aug_assign_ops = [_][]const u8{
    "+=",  "-=",  "*=", "/=", "//=",
    "%=",  "**=", "&=", "|=", "^=",
    ">>=", "<<=", "@=",
};

/// Check if source contains augmented assignment to tuple/list (invalid syntax)
fn checkAugAssignToTuple(source: []const u8) bool {
    // Look for patterns like "x, y +=" or "(x, y) +="
    // This is a simplified check - looks for comma before aug assign op
    for (aug_assign_ops) |op| {
        if (std.mem.indexOf(u8, source, op)) |op_pos| {
            // Look backwards from op_pos for comma (excluding strings/parens)
            var i: usize = op_pos;
            var paren_depth: i32 = 0;
            var bracket_depth: i32 = 0;
            var in_string = false;
            var string_char: u8 = 0;

            while (i > 0) {
                i -= 1;
                const c = source[i];

                // Handle strings
                if (!in_string and (c == '"' or c == '\'')) {
                    in_string = true;
                    string_char = c;
                } else if (in_string and c == string_char) {
                    // Check for escape
                    if (i > 0 and source[i - 1] == '\\') {
                        continue;
                    }
                    in_string = false;
                }

                if (in_string) continue;

                // Track brackets/parens
                if (c == ')') paren_depth += 1;
                if (c == '(') paren_depth -= 1;
                if (c == ']') bracket_depth += 1;
                if (c == '[') bracket_depth -= 1;

                // If we see a comma at depth 0, this is tuple augmented assign
                if (c == ',' and paren_depth == 0 and bracket_depth == 0) {
                    return true;
                }

                // If we hit = or newline at depth 0, stop looking
                if ((c == '=' or c == '\n') and paren_depth == 0 and bracket_depth == 0) {
                    break;
                }
            }
        }
    }
    return false;
}

/// CO_FUTURE_BARRY_AS_BDFL flag value (from __future__ module)
const CO_FUTURE_BARRY_AS_BDFL: i64 = 4194304;

pub fn compile_builtin(allocator: std.mem.Allocator, source: []const u8, filename: []const u8, mode: []const u8, flags: i64) !*runtime.PyObject {
    _ = mode; // unused for MVP
    const exceptions = @import("../runtime/exceptions.zig");

    // Check for BARRY_AS_BDFL flag
    const barry_as_bdfl = (flags & CO_FUTURE_BARRY_AS_BDFL) != 0;

    // Check for invalid operators based on BARRY_AS_BDFL flag
    if (barry_as_bdfl) {
        // When BARRY_AS_BDFL is set, != is invalid, <> is valid
        if (findOperatorInSource(source, "!=")) |op_info| {
            exceptions.setSyntaxError(
                "with Barry as BDFL, use '<>' instead of '!='",
                filename,
                @intCast(op_info.lineno),
                @intCast(op_info.offset),
                op_info.line_text,
            );
            return error.SyntaxError;
        }
    } else {
        // When BARRY_AS_BDFL is NOT set, <> is invalid, != is valid
        if (findOperatorInSource(source, "<>")) |op_info| {
            exceptions.setSyntaxError(
                "invalid syntax",
                filename,
                @intCast(op_info.lineno),
                @intCast(op_info.offset),
                op_info.line_text,
            );
            return error.SyntaxError;
        }
    }

    // Check for invalid syntax: augmented assignment to tuple
    if (checkAugAssignToTuple(source)) {
        return error.SyntaxError;
    }

    // For MVP: return source string as code object
    // Full implementation would return bytecode object
    const PyString = runtime.PyString;
    return try PyString.create(allocator, source);
}

/// Information about an operator's position in source
const OperatorInfo = struct {
    lineno: usize,
    offset: usize,
    line_text: []const u8,
};

/// Find an operator in source code, avoiding strings and comments
fn findOperatorInSource(source: []const u8, operator: []const u8) ?OperatorInfo {
    var lineno: usize = 1;
    var line_start: usize = 0;
    var in_string = false;
    var string_char: u8 = 0;
    var in_triple_string = false;
    var i: usize = 0;

    while (i < source.len) {
        const c = source[i];

        // Track line numbers and line starts
        if (c == '\n') {
            lineno += 1;
            line_start = i + 1;
            in_string = false; // Reset for simplicity - strings shouldn't span lines unless triple
            if (!in_triple_string) {
                in_string = false;
                string_char = 0;
            }
            i += 1;
            continue;
        }

        // Handle comments (skip to end of line)
        if (!in_string and c == '#') {
            while (i < source.len and source[i] != '\n') {
                i += 1;
            }
            continue;
        }

        // Handle string start/end
        if (!in_string and (c == '"' or c == '\'')) {
            // Check for triple quotes
            if (i + 2 < source.len and source[i + 1] == c and source[i + 2] == c) {
                in_string = true;
                in_triple_string = true;
                string_char = c;
                i += 3;
                continue;
            }
            in_string = true;
            string_char = c;
            i += 1;
            continue;
        }

        if (in_string) {
            // Check for escape sequence
            if (c == '\\' and i + 1 < source.len) {
                i += 2;
                continue;
            }
            // Check for string end
            if (c == string_char) {
                if (in_triple_string) {
                    if (i + 2 < source.len and source[i + 1] == c and source[i + 2] == c) {
                        in_string = false;
                        in_triple_string = false;
                        string_char = 0;
                        i += 3;
                        continue;
                    }
                } else {
                    in_string = false;
                    string_char = 0;
                }
            }
            i += 1;
            continue;
        }

        // Check for operator at current position
        if (i + operator.len <= source.len) {
            if (std.mem.eql(u8, source[i .. i + operator.len], operator)) {
                // Found the operator
                // Find end of line for line_text
                var line_end = i;
                while (line_end < source.len and source[line_end] != '\n') {
                    line_end += 1;
                }
                const line_text = source[line_start..line_end];
                const offset = i - line_start + 1; // 1-based offset within line

                return OperatorInfo{
                    .lineno = lineno,
                    .offset = offset,
                    .line_text = line_text,
                };
            }
        }

        i += 1;
    }

    return null;
}
