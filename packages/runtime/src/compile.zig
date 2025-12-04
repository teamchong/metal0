const std = @import("std");
const runtime = @import("runtime.zig");

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

pub fn compile_builtin(allocator: std.mem.Allocator, source: []const u8, filename: []const u8, mode: []const u8) !*runtime.PyObject {
    _ = filename; // unused for MVP
    _ = mode; // unused for MVP

    // Check for invalid syntax: augmented assignment to tuple
    if (checkAugAssignToTuple(source)) {
        return error.SyntaxError;
    }

    // For MVP: return source string as code object
    // Full implementation would return bytecode object
    const PyString = runtime.PyString;
    return try PyString.create(allocator, source);
}
