/// String validation methods - isdigit(), isalpha(), isalnum(), isspace(), etc.
const std = @import("std");
const ast = @import("../../../../ast.zig");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Generate code for text.isdigit()
/// Returns true if all characters are digits (0-9)
pub fn genIsdigit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // SIMD-optimized digit validation using @Vector
    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    if (_text.len == 0) break :blk false;\n");
    try self.emit("    const vec_size = 16;\n");
    try self.emit("    const zero: @Vector(vec_size, u8) = @splat('0');\n");
    try self.emit("    const nine: @Vector(vec_size, u8) = @splat('9');\n");
    try self.emit("    var i: usize = 0;\n");
    try self.emit("    while (i + vec_size <= _text.len) : (i += vec_size) {\n");
    try self.emit("        const chunk: @Vector(vec_size, u8) = _text[i..][0..vec_size].*;\n");
    try self.emit("        const ge_zero = chunk >= zero;\n");
    try self.emit("        const le_nine = chunk <= nine;\n");
    try self.emit("        const is_digit = ge_zero & le_nine;\n");
    try self.emit("        if (!@reduce(.And, is_digit)) break :blk false;\n");
    try self.emit("    }\n");
    try self.emit("    while (i < _text.len) : (i += 1) {\n");
    try self.emit("        if (!std.ascii.isDigit(_text[i])) break :blk false;\n");
    try self.emit("    }\n");
    try self.emit("    break :blk true;\n");
    try self.emit("}");
}

/// Generate code for text.isalpha()
/// Returns true if all characters are alphabetic
pub fn genIsalpha(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    if (_text.len == 0) break :blk false;\n");
    try self.emit("    for (_text) |c| {\n");
    try self.emit("        if (!std.ascii.isAlphabetic(c)) break :blk false;\n");
    try self.emit("    }\n");
    try self.emit("    break :blk true;\n");
    try self.emit("}");
}

/// Generate code for text.isalnum()
/// Returns true if all characters are alphanumeric
pub fn genIsalnum(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    if (_text.len == 0) break :blk false;\n");
    try self.emit("    for (_text) |c| {\n");
    try self.emit("        if (!std.ascii.isAlphanumeric(c)) break :blk false;\n");
    try self.emit("    }\n");
    try self.emit("    break :blk true;\n");
    try self.emit("}");
}

/// Generate code for text.isspace()
/// Returns true if all characters are whitespace
pub fn genIsspace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    if (_text.len == 0) break :blk false;\n");
    try self.emit("    for (_text) |c| {\n");
    try self.emit("        if (!std.ascii.isWhitespace(c)) break :blk false;\n");
    try self.emit("    }\n");
    try self.emit("    break :blk true;\n");
    try self.emit("}");
}

/// Generate code for text.islower()
/// Returns true if all cased characters are lowercase
pub fn genIslower(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    if (_text.len == 0) break :blk false;\n");
    try self.emit("    var has_cased = false;\n");
    try self.emit("    for (_text) |c| {\n");
    try self.emit("        if (std.ascii.isUpper(c)) break :blk false;\n");
    try self.emit("        if (std.ascii.isLower(c)) has_cased = true;\n");
    try self.emit("    }\n");
    try self.emit("    break :blk has_cased;\n");
    try self.emit("}");
}

/// Generate code for text.isupper()
/// Returns true if all cased characters are uppercase
pub fn genIsupper(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    if (_text.len == 0) break :blk false;\n");
    try self.emit("    var has_cased = false;\n");
    try self.emit("    for (_text) |c| {\n");
    try self.emit("        if (std.ascii.isLower(c)) break :blk false;\n");
    try self.emit("        if (std.ascii.isUpper(c)) has_cased = true;\n");
    try self.emit("    }\n");
    try self.emit("    break :blk has_cased;\n");
    try self.emit("}");
}

/// Generate code for text.isascii()
/// Returns true if all characters are ASCII
pub fn genIsascii(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    if (_text.len == 0) break :blk true;\n");
    try self.emit("    for (_text) |c| {\n");
    try self.emit("        if (!std.ascii.isASCII(c)) break :blk false;\n");
    try self.emit("    }\n");
    try self.emit("    break :blk true;\n");
    try self.emit("}");
}

/// Generate code for text.istitle()
/// Returns true if string is titlecased
pub fn genIstitle(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    if (_text.len == 0) break :blk false;\n");
    try self.emit("    var in_word = false;\n");
    try self.emit("    var has_title = false;\n");
    try self.emit("    for (_text) |c| {\n");
    try self.emit("        if (std.ascii.isAlphabetic(c)) {\n");
    try self.emit("            if (!in_word) {\n");
    try self.emit("                if (!std.ascii.isUpper(c)) break :blk false;\n");
    try self.emit("                has_title = true;\n");
    try self.emit("                in_word = true;\n");
    try self.emit("            } else {\n");
    try self.emit("                if (!std.ascii.isLower(c)) break :blk false;\n");
    try self.emit("            }\n");
    try self.emit("        } else {\n");
    try self.emit("            in_word = false;\n");
    try self.emit("        }\n");
    try self.emit("    }\n");
    try self.emit("    break :blk has_title;\n");
    try self.emit("}");
}

/// Generate code for text.isprintable()
/// Returns true if all characters are printable
pub fn genIsprintable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("blk: {\n");
    try self.emit("    const _text = ");
    try self.genExpr(obj);
    try self.emit(";\n");
    try self.emit("    if (_text.len == 0) break :blk true;\n");
    try self.emit("    for (_text) |c| {\n");
    try self.emit("        if (!std.ascii.isPrint(c)) break :blk false;\n");
    try self.emit("    }\n");
    try self.emit("    break :blk true;\n");
    try self.emit("}");
}
