/// String validation methods - isdigit(), isalpha(), isalnum(), isspace(), etc.
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

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


/// Check if a string expression is uncertain (needs PyValue operations)
/// Two-Flow: routes uncertain strings to PyValue extraction via .asString()
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
        return false;
    }
    return false;
}

/// Helper to emit string expression, extracting from PyValue if uncertain
fn emitStringExpr(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    if (isStringUncertain(self, obj)) {
        // Extract string from PyValue using .asString()
        try self.genExpr(obj);
        try emitConst(self,".asString()");
    } else {
        try self.genExpr(obj);
    }
}

/// Generate code for text.isdigit()
/// Returns true if all characters are digits (0-9)
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIsdigit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // SIMD-optimized digit validation using @Vector
    const label = self.nextLabelId();
    try emitFmtConst(self, "isdigit_{d}: {{\n", .{label});
    try emitConst(self,"    const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,";\n");
    try emitFmtConst(self, "    if (_text.len == 0) break :isdigit_{d} false;\n", .{label});
    try emitConst(self,"    const vec_size = 16;\n");
    try emitConst(self,"    const zero: @Vector(vec_size, u8) = @splat('0');\n");
    try emitConst(self,"    const nine: @Vector(vec_size, u8) = @splat('9');\n");
    try emitConst(self,"    var i: usize = 0;\n");
    try emitConst(self,"    while (i + vec_size <= _text.len) : (i += vec_size) {\n");
    try emitConst(self,"        const chunk: @Vector(vec_size, u8) = _text[i..][0..vec_size].*;\n");
    try emitConst(self,"        const ge_zero = chunk >= zero;\n");
    try emitConst(self,"        const le_nine = chunk <= nine;\n");
    try emitConst(self,"        const is_digit = ge_zero & le_nine;\n");
    try emitFmtConst(self, "        if (!@reduce(.And, is_digit)) break :isdigit_{d} false;\n", .{label});
    try emitConst(self,"    }\n");
    try emitConst(self,"    while (i < _text.len) : (i += 1) {\n");
    try emitFmtConst(self, "        if (!std.ascii.isDigit(_text[i])) break :isdigit_{d} false;\n", .{label});
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :isdigit_{d} true;\n", .{label});
    try emitConst(self,"}");
}

/// Generate code for text.isalpha()
/// Returns true if all characters are alphabetic
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIsalpha(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = self.nextLabelId();
    try emitFmtConst(self, "isalpha_{d}: {{\n", .{label});
    try emitConst(self,"    const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,";\n");
    try emitFmtConst(self, "    if (_text.len == 0) break :isalpha_{d} false;\n", .{label});
    try emitConst(self,"    for (_text) |c| {\n");
    try emitFmtConst(self, "        if (!std.ascii.isAlphabetic(c)) break :isalpha_{d} false;\n", .{label});
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :isalpha_{d} true;\n", .{label});
    try emitConst(self,"}");
}

/// Generate code for text.isalnum()
/// Returns true if all characters are alphanumeric
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIsalnum(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = self.nextLabelId();
    try emitFmtConst(self, "isalnum_{d}: {{\n", .{label});
    try emitConst(self,"    const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,";\n");
    try emitFmtConst(self, "    if (_text.len == 0) break :isalnum_{d} false;\n", .{label});
    try emitConst(self,"    for (_text) |c| {\n");
    try emitFmtConst(self, "        if (!std.ascii.isAlphanumeric(c)) break :isalnum_{d} false;\n", .{label});
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :isalnum_{d} true;\n", .{label});
    try emitConst(self,"}");
}

/// Generate code for text.isspace()
/// Returns true if all characters are whitespace (including Unicode whitespace)
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIsspace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Use runtime function that handles Unicode properly
    try emitConst(self,"runtime.isStringAllWhitespace(");
    try emitStringExpr(self, obj);
    try emitConst(self,")");
}

/// Generate code for text.islower()
/// Returns true if all cased characters are lowercase
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIslower(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = self.nextLabelId();
    try emitFmtConst(self, "islower_{d}: {{\n", .{label});
    try emitConst(self,"    const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,";\n");
    try emitFmtConst(self, "    if (_text.len == 0) break :islower_{d} false;\n", .{label});
    try emitConst(self,"    var has_cased = false;\n");
    try emitConst(self,"    for (_text) |c| {\n");
    try emitFmtConst(self, "        if (std.ascii.isUpper(c)) break :islower_{d} false;\n", .{label});
    try emitConst(self,"        if (std.ascii.isLower(c)) has_cased = true;\n");
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :islower_{d} has_cased;\n", .{label});
    try emitConst(self,"}");
}

/// Generate code for text.isupper()
/// Returns true if all cased characters are uppercase
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIsupper(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = self.nextLabelId();
    try emitFmtConst(self, "isupper_{d}: {{\n", .{label});
    try emitConst(self,"    const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,";\n");
    try emitFmtConst(self, "    if (_text.len == 0) break :isupper_{d} false;\n", .{label});
    try emitConst(self,"    var has_cased = false;\n");
    try emitConst(self,"    for (_text) |c| {\n");
    try emitFmtConst(self, "        if (std.ascii.isLower(c)) break :isupper_{d} false;\n", .{label});
    try emitConst(self,"        if (std.ascii.isUpper(c)) has_cased = true;\n");
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :isupper_{d} has_cased;\n", .{label});
    try emitConst(self,"}");
}

/// Generate code for text.isascii()
/// Returns true if all characters are ASCII
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIsascii(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = self.nextLabelId();
    try emitFmtConst(self, "isascii_{d}: {{\n", .{label});
    try emitConst(self,"    const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,";\n");
    try emitFmtConst(self, "    if (_text.len == 0) break :isascii_{d} true;\n", .{label});
    try emitConst(self,"    for (_text) |c| {\n");
    try emitFmtConst(self, "        if (!std.ascii.isASCII(c)) break :isascii_{d} false;\n", .{label});
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :isascii_{d} true;\n", .{label});
    try emitConst(self,"}");
}

/// Generate code for text.istitle()
/// Returns true if string is titlecased
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIstitle(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = self.nextLabelId();
    try emitFmtConst(self, "istitle_{d}: {{\n", .{label});
    try emitConst(self,"    const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,";\n");
    try emitFmtConst(self, "    if (_text.len == 0) break :istitle_{d} false;\n", .{label});
    try emitConst(self,"    var in_word = false;\n");
    try emitConst(self,"    var has_title = false;\n");
    try emitConst(self,"    for (_text) |c| {\n");
    try emitConst(self,"        if (std.ascii.isAlphabetic(c)) {\n");
    try emitConst(self,"            if (!in_word) {\n");
    try emitFmtConst(self, "                if (!std.ascii.isUpper(c)) break :istitle_{d} false;\n", .{label});
    try emitConst(self,"                has_title = true;\n");
    try emitConst(self,"                in_word = true;\n");
    try emitConst(self,"            } else {\n");
    try emitFmtConst(self, "                if (!std.ascii.isLower(c)) break :istitle_{d} false;\n", .{label});
    try emitConst(self,"            }\n");
    try emitConst(self,"        } else {\n");
    try emitConst(self,"            in_word = false;\n");
    try emitConst(self,"        }\n");
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :istitle_{d} has_title;\n", .{label});
    try emitConst(self,"}");
}

/// Generate code for text.isprintable()
/// Returns true if all characters are printable
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIsprintable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = self.nextLabelId();
    try emitFmtConst(self, "isprint_{d}: {{\n", .{label});
    try emitConst(self,"    const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,";\n");
    try emitFmtConst(self, "    if (_text.len == 0) break :isprint_{d} true;\n", .{label});
    try emitConst(self,"    for (_text) |c| {\n");
    try emitFmtConst(self, "        if (!std.ascii.isPrint(c)) break :isprint_{d} false;\n", .{label});
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :isprint_{d} true;\n", .{label});
    try emitConst(self,"}");
}

/// Generate code for text.isdecimal()
/// Returns true if all characters are decimal characters (0-9)
/// In Python, isdecimal is more restrictive than isdigit - only matches 0-9
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIsdecimal(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = self.nextLabelId();
    try emitFmtConst(self, "isdec_{d}: {{\n", .{label});
    try emitConst(self,"    const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,";\n");
    try emitFmtConst(self, "    if (_text.len == 0) break :isdec_{d} false;\n", .{label});
    try emitConst(self,"    for (_text) |c| {\n");
    try emitFmtConst(self, "        if (c < '0' or c > '9') break :isdec_{d} false;\n", .{label});
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :isdec_{d} true;\n", .{label});
    try emitConst(self,"}");
}

/// Generate code for text.isnumeric()
/// Returns true if all characters are numeric
/// For ASCII-only, this is same as isdigit (0-9)
/// Two-Flow: Extracts string from PyValue if uncertain
pub fn genIsnumeric(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    const label = self.nextLabelId();
    try emitFmtConst(self, "isnum_{d}: {{\n", .{label});
    try emitConst(self,"    const _text = ");
    try emitStringExpr(self, obj);
    try emitConst(self,";\n");
    try emitFmtConst(self, "    if (_text.len == 0) break :isnum_{d} false;\n", .{label});
    try emitConst(self,"    for (_text) |c| {\n");
    try emitFmtConst(self, "        if (!std.ascii.isDigit(c)) break :isnum_{d} false;\n", .{label});
    try emitConst(self,"    }\n");
    try emitFmtConst(self, "    break :isnum_{d} true;\n", .{label});
    try emitConst(self,"}");
}
