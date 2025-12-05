/// Zig reserved keywords and identifier escaping
///
/// When generating Zig code from Python, we must escape identifiers
/// that collide with Zig keywords using @"name" syntax.
const std = @import("std");

/// Zig reserved keywords that cannot be used as identifiers
/// Reference: https://ziglang.org/documentation/master/#Keywords
const zig_keywords = std.StaticStringMap(void).initComptime(.{
    // Control flow
    .{ "if", {} },
    .{ "else", {} },
    .{ "while", {} },
    .{ "for", {} },
    .{ "switch", {} },
    .{ "break", {} },
    .{ "continue", {} },
    .{ "return", {} },
    .{ "defer", {} },
    .{ "errdefer", {} },

    // Functions and types
    .{ "fn", {} },
    .{ "pub", {} },
    .{ "const", {} },
    .{ "var", {} },
    .{ "struct", {} },
    .{ "enum", {} },
    .{ "union", {} },
    .{ "error", {} },
    .{ "opaque", {} },

    // Type keywords
    .{ "type", {} },
    .{ "anytype", {} },
    .{ "anyframe", {} },
    .{ "noreturn", {} },
    .{ "void", {} },
    .{ "unreachable", {} },
    .{ "null", {} },
    .{ "undefined", {} },
    .{ "true", {} },
    .{ "false", {} },

    // Memory and async
    .{ "async", {} },
    .{ "await", {} },
    .{ "suspend", {} },
    .{ "resume", {} },
    .{ "nosuspend", {} },

    // Other reserved
    .{ "and", {} },
    .{ "or", {} },
    .{ "orelse", {} },
    .{ "catch", {} },
    .{ "try", {} },
    .{ "test", {} }, // This is the one causing our issue!
    .{ "inline", {} },
    .{ "comptime", {} },
    .{ "volatile", {} },
    .{ "align", {} },
    .{ "allowzero", {} },
    .{ "linksection", {} },
    .{ "threadlocal", {} },
    .{ "export", {} },
    .{ "extern", {} },
    .{ "packed", {} },
    .{ "usingnamespace", {} },
    .{ "asm", {} },
    .{ "callconv", {} },
    .{ "noalias", {} },
    .{ "noinline", {} },
    .{ "addrspace", {} },

    // Special identifiers that require @"" syntax
    .{ "_", {} }, // Underscore for discarding values

    // Zig primitive types (name shadows primitive error)
    .{ "i0", {} },
    .{ "i1", {} },
    .{ "i2", {} },
    .{ "i3", {} },
    .{ "i4", {} },
    .{ "i5", {} },
    .{ "i6", {} },
    .{ "i7", {} },
    .{ "i8", {} },
    .{ "i16", {} },
    .{ "i32", {} },
    .{ "i64", {} },
    .{ "i128", {} },
    .{ "u0", {} },
    .{ "u1", {} },
    .{ "u2", {} },
    .{ "u3", {} },
    .{ "u4", {} },
    .{ "u5", {} },
    .{ "u6", {} },
    .{ "u7", {} },
    .{ "u8", {} },
    .{ "u16", {} },
    .{ "u32", {} },
    .{ "u64", {} },
    .{ "u128", {} },
    .{ "f16", {} },
    .{ "f32", {} },
    .{ "f64", {} },
    .{ "f128", {} },
    .{ "usize", {} },
    .{ "isize", {} },
    .{ "c_int", {} },
    .{ "c_uint", {} },
    .{ "c_long", {} },
    .{ "c_ulong", {} },
    .{ "c_longlong", {} },
    .{ "c_ulonglong", {} },
    .{ "c_short", {} },
    .{ "c_ushort", {} },
    .{ "c_char", {} },
    .{ "bool", {} },
});

/// Common method names that parameters should not shadow
/// In Zig, function parameters cannot have the same name as methods in the same struct
const shadowing_method_names = std.StaticStringMap(void).initComptime(.{
    .{ "init", {} },
    .{ "deinit", {} },
    .{ "checksum", {} },
    .{ "combine", {} },
    .{ "compress", {} },
    .{ "decompress", {} },
    .{ "flush", {} },
    .{ "copy", {} },
    .{ "hash", {} },
    .{ "update", {} },
    .{ "read", {} },
    .{ "write", {} },
    .{ "close", {} },
    .{ "open", {} },
    .{ "get", {} },
    .{ "set", {} },
    .{ "put", {} },
    .{ "pop", {} },
    .{ "push", {} },
    .{ "append", {} },
    .{ "clear", {} },
    .{ "reset", {} },
    .{ "parse", {} },
    .{ "format", {} },
    .{ "encode", {} },
    .{ "decode", {} },
});

/// Module names that parameters should not shadow
/// These are module-level imports that would cause Zig "parameter shadows declaration" errors
/// if used as function parameter names
const shadowing_module_names = std.StaticStringMap(void).initComptime(.{
    .{ "types", {} }, // Python `types` module becomes `const types = std;`
    .{ "collections", {} }, // Python `collections` module
    .{ "std", {} }, // Zig std library
    .{ "runtime", {} }, // metal0 runtime
    .{ "unittest", {} }, // unittest module
    .{ "os", {} }, // os module
    .{ "sys", {} }, // sys module
    .{ "math", {} }, // math module
    .{ "json", {} }, // json module
    .{ "re", {} }, // re module
    .{ "io", {} }, // io module
    .{ "copy", {} }, // copy module (also in method names)
    .{ "functools", {} }, // functools module
    .{ "itertools", {} }, // itertools module
    .{ "operator", {} }, // operator module
    .{ "string", {} }, // string module
    .{ "time", {} }, // time module
    .{ "random", {} }, // random module
});

/// Check if a parameter name would shadow a common method name
pub fn wouldShadowMethod(name: []const u8) bool {
    return shadowing_method_names.has(name);
}

/// Check if a parameter name would shadow a module-level import
pub fn wouldShadowModule(name: []const u8) bool {
    return shadowing_module_names.has(name);
}

/// Write parameter name, adding _arg suffix if it would shadow a method or module
pub fn writeParamName(writer: anytype, name: []const u8) !void {
    if (isZigKeyword(name)) {
        try writer.print("@\"{s}\"", .{name});
    } else if (wouldShadowMethod(name) or wouldShadowModule(name)) {
        try writer.print("{s}_arg", .{name});
    } else {
        try writer.writeAll(name);
    }
}

/// Check if identifier is a Zig reserved keyword
pub fn isZigKeyword(name: []const u8) bool {
    return zig_keywords.has(name);
}

/// Escape identifier if it's a Zig keyword or contains Unicode
/// Returns @"name" for keywords, Unicode, or bare underscore, name otherwise
/// Caller must free returned slice if it was allocated
pub fn escapeIfKeyword(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    // Handle bare underscore - Zig requires @"_" syntax for _ as an identifier
    if (name.len == 1 and name[0] == '_') {
        return "@\"_\"";
    }
    if (!isZigKeyword(name) and !containsNonAscii(name)) {
        return name;
    }
    // Escape as @"name"
    const escaped = try std.fmt.allocPrint(allocator, "@\"{s}\"", .{name});
    return escaped;
}

/// Check if name contains non-ASCII characters (Unicode)
fn containsNonAscii(name: []const u8) bool {
    for (name) |c| {
        if (c > 127) return true;
    }
    return false;
}

/// Write escaped identifier to writer
/// This avoids allocation by writing directly
pub fn writeEscapedIdent(writer: anytype, name: []const u8) !void {
    // Handle bare underscore - Zig requires @"_" syntax for _ as an identifier
    if (name.len == 1 and name[0] == '_') {
        try writer.writeAll("@\"_\"");
    } else if (isZigKeyword(name) or containsNonAscii(name)) {
        // Unicode identifiers and keywords need @"name" syntax
        try writer.print("@\"{s}\"", .{name});
    } else {
        try writer.writeAll(name);
    }
}

/// Write local variable name, renaming if it would shadow a method
/// Use this for local variable declarations and usages, NOT for method/field names
pub fn writeLocalVarName(writer: anytype, name: []const u8) !void {
    // Handle bare underscore - Zig requires @"_" syntax for _ as an identifier
    if (name.len == 1 and name[0] == '_') {
        try writer.writeAll("@\"_\"");
    } else if (isZigKeyword(name) or containsNonAscii(name)) {
        // Unicode identifiers and keywords need @"name" syntax
        try writer.print("@\"{s}\"", .{name});
    } else if (wouldShadowMethod(name)) {
        // Rename to avoid shadowing method names in struct scope
        try writer.print("{s}_", .{name});
    } else {
        try writer.writeAll(name);
    }
}

/// Write escaped module path to writer
/// Handles dotted paths like "test.support" by escaping only the first component if needed
/// Result: @"test".support
pub fn writeEscapedModulePath(writer: anytype, module_path: []const u8) !void {
    // Find the first dot (if any)
    const dot_pos = std.mem.indexOfScalar(u8, module_path, '.');
    if (dot_pos) |pos| {
        // Escape the first component and append the rest unchanged
        const first_component = module_path[0..pos];
        const rest = module_path[pos..]; // includes the dot
        try writeEscapedIdent(writer, first_component);
        try writer.writeAll(rest);
    } else {
        // No dot - just escape the whole thing if needed
        try writeEscapedIdent(writer, module_path);
    }
}

/// Convert a dotted module path to a valid Zig identifier
/// e.g., "test.support" -> "test_support", "test.support.os_helper" -> "test_support_os_helper"
pub fn dottedToIdent(module_path: []const u8) []const u8 {
    // Return as-is if no dots
    if (std.mem.indexOfScalar(u8, module_path, '.') == null) {
        return module_path;
    }
    // Has dots - caller should use dottedToIdentAlloc
    return module_path;
}

/// Convert a dotted module path to a valid Zig identifier with allocation
/// e.g., "test.support" -> "test_support"
pub fn dottedToIdentAlloc(allocator: std.mem.Allocator, module_path: []const u8) ![]const u8 {
    // Count dots
    var dot_count: usize = 0;
    for (module_path) |c| {
        if (c == '.') dot_count += 1;
    }
    if (dot_count == 0) {
        return allocator.dupe(u8, module_path);
    }

    // Replace dots with underscores
    const result = try allocator.alloc(u8, module_path.len);
    for (module_path, 0..) |c, i| {
        result[i] = if (c == '.') '_' else c;
    }
    return result;
}

/// Write a dotted module path as a Zig identifier (with dots replaced by underscores)
/// Escapes if the result is a keyword
pub fn writeEscapedDottedIdent(writer: anytype, module_path: []const u8) !void {
    // Check if first component is a keyword
    const first_end = std.mem.indexOfScalar(u8, module_path, '.') orelse module_path.len;
    const first_component = module_path[0..first_end];

    if (isZigKeyword(first_component) or std.mem.indexOfScalar(u8, module_path, '.') != null) {
        // Escape the entire name with @"" syntax, replacing dots with underscores
        try writer.writeAll("@\"");
        for (module_path) |c| {
            if (c == '.') {
                try writer.writeByte('_');
            } else {
                try writer.writeByte(c);
            }
        }
        try writer.writeAll("\"");
    } else {
        try writer.writeAll(module_path);
    }
}

test "isZigKeyword" {
    try std.testing.expect(isZigKeyword("test"));
    try std.testing.expect(isZigKeyword("fn"));
    try std.testing.expect(isZigKeyword("const"));
    try std.testing.expect(!isZigKeyword("foo"));
    try std.testing.expect(!isZigKeyword("myFunction"));
}

test "escapeIfKeyword" {
    const allocator = std.testing.allocator;

    // Non-keyword: returns original
    const foo = try escapeIfKeyword(allocator, "foo");
    try std.testing.expectEqualStrings("foo", foo);

    // Keyword: returns escaped
    const t = try escapeIfKeyword(allocator, "test");
    defer allocator.free(t);
    try std.testing.expectEqualStrings("@\"test\"", t);
}
