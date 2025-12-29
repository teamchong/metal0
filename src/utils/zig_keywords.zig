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
    .{ "take", {} },      // runtime.take iterator function
    .{ "compare", {} },   // comparison functions
    .{ "stop", {} },      // iterator stop
});

/// Module names that parameters should not shadow
/// These are module-level imports that would cause Zig "parameter shadows declaration" errors
/// if used as function parameter names
const shadowing_module_names = std.StaticStringMap(void).initComptime(.{
    .{ "types", {} }, // Python `types` module becomes `const types = std;`
    .{ "collections", {} }, // Python `collections` module
    .{ "std", {} }, // Zig std library
    .{ "runtime", {} }, // metal0 runtime
    .{ "c_interop", {} }, // metal0 c_interop for numpy/external libs
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
    .{ "main", {} }, // Entry point function - can't shadow pub fn main()
});

/// Check if a parameter name would shadow a common method name
pub fn wouldShadowMethod(name: []const u8) bool {
    return shadowing_method_names.has(name);
}

/// Check if a parameter name would shadow a module-level import
pub fn wouldShadowModule(name: []const u8) bool {
    return shadowing_module_names.has(name);
}

/// Write parameter name, adding _ suffix if it would shadow a method or module
/// Uses same suffix as writeLocalVarName for consistency between declaration and usage
pub fn writeParamName(writer: anytype, name: []const u8) !void {
    if (isZigKeyword(name)) {
        try writer.print("@\"{s}\"", .{name});
    } else if (wouldShadowMethod(name) or wouldShadowModule(name)) {
        try writer.print("{s}_", .{name});
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

/// Check if a string is a valid Zig identifier that can be emitted directly
/// Returns false if the name needs @"" escaping or contains invalid chars
/// Use this to validate dynamic strings (e.g., from ctypes, CDLL) before emitting
pub fn isValidZigIdent(name: []const u8) bool {
    if (name.len == 0) return false;

    // Cannot start with digit
    const first = name[0];
    if (first >= '0' and first <= '9') return false;

    // Check for keywords and non-ASCII
    if (isZigKeyword(name) or containsNonAscii(name)) return false;

    // Bare underscore requires escaping
    if (name.len == 1 and name[0] == '_') return false;

    // Check for special characters that require escaping
    for (name) |c| {
        // Valid Zig identifier chars: a-z, A-Z, 0-9, _
        const is_alpha = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
        const is_digit = (c >= '0' and c <= '9');
        const is_underscore = (c == '_');
        if (!is_alpha and !is_digit and !is_underscore) {
            return false;
        }
    }
    return true;
}

/// Write escaped identifier to writer
/// Check if identifier contains characters that require quoting (dots, dashes, etc.)
fn containsSpecialChars(name: []const u8) bool {
    for (name) |c| {
        if (c == '.' or c == '-' or c == ' ') return true;
    }
    return false;
}

/// This avoids allocation by writing directly
pub fn writeEscapedIdent(writer: anytype, name: []const u8) !void {
    // Handle pointer dereference expressions (e.g., "p_a_1.*" from try-except hoisting)
    // The ".*" suffix is NOT part of the identifier - it's the dereference operator
    // Emit base part with normal escaping, then ".*" literally
    if (std.mem.endsWith(u8, name, ".*")) {
        const base = name[0 .. name.len - 2];
        try writeEscapedIdent(writer, base);
        try writer.writeAll(".*");
        return;
    }

    // Handle bare underscore - Zig requires @"_" syntax for _ as an identifier
    if (name.len == 1 and name[0] == '_') {
        try writer.writeAll("@\"_\"");
    } else if (isZigKeyword(name) or containsNonAscii(name) or containsSpecialChars(name)) {
        // Unicode identifiers, keywords, and special chars need @"name" syntax
        try writer.print("@\"{s}\"", .{name});
    } else {
        try writer.writeAll(name);
    }
}

/// Write local variable name, renaming if it would shadow a method or module import
/// Use this for local variable declarations and usages, NOT for method/field names
pub fn writeLocalVarName(writer: anytype, name: []const u8) !void {
    // Handle pointer dereference expressions (e.g., "p_a_1.*" from try-except hoisting)
    // The ".*" suffix is NOT part of the identifier - it's the dereference operator
    // Emit base part with normal escaping, then ".*" literally
    if (std.mem.endsWith(u8, name, ".*")) {
        const base = name[0 .. name.len - 2];
        try writeLocalVarName(writer, base);
        try writer.writeAll(".*");
        return;
    }

    // Handle bare underscore - Zig requires @"_" syntax for _ as an identifier
    if (name.len == 1 and name[0] == '_') {
        try writer.writeAll("@\"_\"");
    } else if (isZigKeyword(name) or containsNonAscii(name) or containsSpecialChars(name)) {
        // Unicode identifiers, keywords, and special chars need @"name" syntax
        try writer.print("@\"{s}\"", .{name});
    } else if (wouldShadowMethod(name) or wouldShadowModule(name)) {
        // Rename to avoid shadowing method names in struct scope or module-level imports
        // e.g., `std = np.std(...)` becomes `std_ = ...` to not shadow `const std = @import("std")`
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

/// Write import path with escaped last segment if it's a keyword
/// Used for import paths like "runtime.Lib.enum" -> "runtime.Lib.@\"enum\""
/// Unlike writeEscapedModulePath which escapes the first segment,
/// this escapes the LAST segment (the module name after runtime.Lib.)
pub fn writeEscapedImportPath(writer: anytype, import_path: []const u8) !void {
    // Find the last dot
    if (std.mem.lastIndexOfScalar(u8, import_path, '.')) |last_dot| {
        const prefix = import_path[0 .. last_dot + 1]; // includes the dot
        const last_segment = import_path[last_dot + 1 ..];
        try writer.writeAll(prefix);
        try writeEscapedIdent(writer, last_segment);
    } else {
        // No dot - escape whole thing if keyword
        try writeEscapedIdent(writer, import_path);
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

// =============================================================================
// CENTRALIZED PARAMETER NAMING
// =============================================================================
// This is the SINGLE SOURCE OF TRUTH for how Python parameter names are
// transformed to Zig parameter names. All code that generates parameter
// declarations or references should use these types and functions.
// =============================================================================

/// Describes how a parameter name was transformed
pub const ParamSuffix = enum {
    /// No transformation (original name used as-is)
    none,
    /// Name suffixed with "_" (shadows method/module name)
    underscore,
    /// Name suffixed with "_param" (has default value, becomes optional)
    param,
    /// Name wrapped with @"" (Zig keyword or Unicode)
    escaped,
};

/// Result of parameter name transformation
pub const ZigParamName = struct {
    /// The Zig-compatible parameter name (may be allocated)
    name: []const u8,
    /// What type of suffix was applied
    suffix: ParamSuffix,
    /// Whether the name was allocated (caller must free if true)
    allocated: bool,

    /// Get the Python name that would produce this Zig name
    /// For searching in generated code, we need to know what to look for
    pub fn getSearchNames(self: ZigParamName, python_name: []const u8) struct { primary: []const u8, secondary: ?[]const u8 } {
        return switch (self.suffix) {
            .none => .{ .primary = python_name, .secondary = null },
            .underscore => .{ .primary = self.name, .secondary = python_name },
            .param => .{ .primary = self.name, .secondary = null },
            .escaped => .{ .primary = python_name, .secondary = null },
        };
    }
};

/// CENTRALIZED FUNCTION: Get the Zig name for a Python parameter
///
/// This is the SINGLE SOURCE OF TRUTH for parameter naming. Use this function
/// whenever you need to determine what Zig name a Python parameter should have.
///
/// Priority order:
/// 1. Parameters with defaults -> "_param" suffix (becomes optional ?T)
/// 2. Parameters that shadow methods/modules -> "_" suffix
/// 3. Parameters that are Zig keywords -> @"name" escaping
/// 4. All other parameters -> use as-is
///
/// Examples:
///   getZigParamName(alloc, "x", false)     -> { "x", .none }
///   getZigParamName(alloc, "x", true)      -> { "x_param", .param }
///   getZigParamName(alloc, "stop", false)  -> { "stop_", .underscore }
///   getZigParamName(alloc, "test", false)  -> { "@\"test\"", .escaped }
pub fn getZigParamName(
    allocator: std.mem.Allocator,
    python_name: []const u8,
    has_default: bool,
) !ZigParamName {
    // Priority 1: Optional parameters (have defaults) use _param suffix
    if (has_default) {
        const name = try std.fmt.allocPrint(allocator, "{s}_param", .{python_name});
        return .{ .name = name, .suffix = .param, .allocated = true };
    }

    // Priority 2: Names that shadow methods or modules use _ suffix
    if (wouldShadowMethod(python_name) or wouldShadowModule(python_name)) {
        const name = try std.fmt.allocPrint(allocator, "{s}_", .{python_name});
        return .{ .name = name, .suffix = .underscore, .allocated = true };
    }

    // Priority 3: Zig keywords and special identifiers need @"" escaping
    if (isZigKeyword(python_name) or containsNonAscii(python_name)) {
        const name = try std.fmt.allocPrint(allocator, "@\"{s}\"", .{python_name});
        return .{ .name = name, .suffix = .escaped, .allocated = true };
    }

    // Handle bare underscore
    if (python_name.len == 1 and python_name[0] == '_') {
        return .{ .name = "@\"_\"", .suffix = .escaped, .allocated = false };
    }

    // Priority 4: Use original name as-is
    return .{ .name = python_name, .suffix = .none, .allocated = false };
}

/// Write parameter name using the centralized naming logic
/// Convenience function that combines getZigParamName + writer output
pub fn writeZigParamName(writer: anytype, allocator: std.mem.Allocator, python_name: []const u8, has_default: bool) !ZigParamName {
    const result = try getZigParamName(allocator, python_name, has_default);
    try writer.writeAll(result.name);
    return result;
}

/// Check if a Python parameter name would be transformed
/// Useful for deciding whether to track renames
pub fn wouldTransformParam(python_name: []const u8, has_default: bool) bool {
    if (has_default) return true;
    if (wouldShadowMethod(python_name)) return true;
    if (wouldShadowModule(python_name)) return true;
    if (isZigKeyword(python_name)) return true;
    if (containsNonAscii(python_name)) return true;
    if (python_name.len == 1 and python_name[0] == '_') return true;
    return false;
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

test "getZigParamName - regular parameter" {
    const allocator = std.testing.allocator;

    // Regular parameter - no transformation
    const x = try getZigParamName(allocator, "x", false);
    try std.testing.expectEqualStrings("x", x.name);
    try std.testing.expect(x.suffix == .none);
    try std.testing.expect(!x.allocated);
}

test "getZigParamName - parameter with default" {
    const allocator = std.testing.allocator;

    // Parameter with default - gets _param suffix
    const x = try getZigParamName(allocator, "x", true);
    defer allocator.free(x.name);
    try std.testing.expectEqualStrings("x_param", x.name);
    try std.testing.expect(x.suffix == .param);
    try std.testing.expect(x.allocated);
}

test "getZigParamName - shadows method" {
    const allocator = std.testing.allocator;

    // Parameter that shadows method - gets _ suffix
    const stop = try getZigParamName(allocator, "stop", false);
    defer allocator.free(stop.name);
    try std.testing.expectEqualStrings("stop_", stop.name);
    try std.testing.expect(stop.suffix == .underscore);
    try std.testing.expect(stop.allocated);
}

test "getZigParamName - Zig keyword" {
    const allocator = std.testing.allocator;

    // Zig keyword - gets @"" escaping
    const t = try getZigParamName(allocator, "test", false);
    defer allocator.free(t.name);
    try std.testing.expectEqualStrings("@\"test\"", t.name);
    try std.testing.expect(t.suffix == .escaped);
    try std.testing.expect(t.allocated);
}

test "getZigParamName - default takes priority over shadowing" {
    const allocator = std.testing.allocator;

    // Parameter "stop" with default - _param takes priority over _
    const stop = try getZigParamName(allocator, "stop", true);
    defer allocator.free(stop.name);
    try std.testing.expectEqualStrings("stop_param", stop.name);
    try std.testing.expect(stop.suffix == .param);
}

test "isValidZigIdent" {
    // Valid identifiers
    try std.testing.expect(isValidZigIdent("foo"));
    try std.testing.expect(isValidZigIdent("myFunction"));
    try std.testing.expect(isValidZigIdent("some_var"));
    try std.testing.expect(isValidZigIdent("CamelCase"));
    try std.testing.expect(isValidZigIdent("_private"));
    try std.testing.expect(isValidZigIdent("var123"));

    // Invalid - empty
    try std.testing.expect(!isValidZigIdent(""));

    // Invalid - starts with digit
    try std.testing.expect(!isValidZigIdent("123abc"));
    try std.testing.expect(!isValidZigIdent("0x"));

    // Invalid - Zig keywords
    try std.testing.expect(!isValidZigIdent("test"));
    try std.testing.expect(!isValidZigIdent("fn"));
    try std.testing.expect(!isValidZigIdent("const"));

    // Invalid - bare underscore
    try std.testing.expect(!isValidZigIdent("_"));

    // Invalid - special characters
    try std.testing.expect(!isValidZigIdent("foo-bar"));
    try std.testing.expect(!isValidZigIdent("foo.bar"));
    try std.testing.expect(!isValidZigIdent("foo bar"));
    try std.testing.expect(!isValidZigIdent("foo@bar"));
    try std.testing.expect(!isValidZigIdent("foo!"));
}
