/// Unified name generation for metal0 codegen
///
/// This module provides a centralized, conflict-free naming system.
/// All generated names use a prefix that Python identifiers cannot produce,
/// making naming conflicts impossible by construction.
///
/// Key insight: Python identifiers can't contain double underscores followed by
/// digits at the start. We use `__m{counter}_` prefix which:
/// - Is valid in Zig (alphanumeric + underscore)
/// - Is highly unlikely in Python user code (dunder + number pattern)
/// - Preserves the original name for debugging
///
/// Naming scheme:
///   User variables:     Keep original name (escaped if Zig keyword)
///   Parameters:         __m{counter}_p_{name}  (e.g., __m0_p_a, __m1_p_b)
///   Locals:             __m{counter}_l_{name}  (e.g., __m2_l_x, __m3_l_y)
///   Temps:              __m{counter}_t         (e.g., __m4_t, __m5_t)
///   Closures:           __m{counter}_c_{name}  (e.g., __m6_c_add)
///   Hoisted vars:       __m{counter}_h_{name}  (e.g., __m7_h_result)
///   Exception vars:     __m{counter}_e_{name}  (e.g., __m8_e_err)
///   Mutable copies:     __m{counter}_m_{name}  (e.g., __m9_m_count)
///   Class instances:    __m{counter}_i_{name}  (e.g., __m10_i_self)
///
/// Benefits:
/// 1. ZERO conflict checking needed - prefix pattern is impossible in user code
/// 2. Nesting-safe - counters are globally unique within codegen instance
/// 3. Debuggable - original name preserved after prefix
/// 4. Simple - one counter, one prefix system
///
const std = @import("std");
const zig_keywords = @import("utils.zig_keywords");

/// Name generator with globally unique counters
pub const NameGen = struct {
    allocator: std.mem.Allocator,
    counter: usize = 0,

    /// Scope depth for debugging (not used in naming, just for clarity)
    scope_depth: usize = 0,

    /// Generate a unique parameter name
    /// Used when a parameter would shadow outer scope
    pub fn param(self: *NameGen, original: []const u8) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_p_{s}", .{ id, original });
    }

    /// Generate a unique local variable name
    /// Used when a local would shadow outer scope
    pub fn local(self: *NameGen, original: []const u8) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_l_{s}", .{ id, original });
    }

    /// Generate a unique temporary variable name
    /// Used for tuple unpacking, intermediate results, etc.
    pub fn temp(self: *NameGen) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_t", .{id});
    }

    /// Generate a unique closure name
    pub fn closure(self: *NameGen, original: []const u8) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_c_{s}", .{ id, original });
    }

    /// Generate a unique hoisted variable name
    pub fn hoisted(self: *NameGen, original: []const u8) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_h_{s}", .{ id, original });
    }

    /// Generate a unique exception variable name
    pub fn exception(self: *NameGen, original: []const u8) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_e_{s}", .{ id, original });
    }

    /// Generate a unique mutable copy name
    /// Used when a parameter needs to be mutated
    pub fn mutable(self: *NameGen, original: []const u8) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_m_{s}", .{ id, original });
    }

    /// Generate a unique class/struct name
    pub fn class(self: *NameGen, original: []const u8) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_C_{s}", .{ id, original });
    }

    /// Generate a unique block label
    pub fn blockLabel(self: *NameGen) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_b", .{id});
    }

    /// Generate a unique try helper name
    pub fn tryHelper(self: *NameGen) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_TryHelper", .{id});
    }

    /// Generate a unique lambda name
    pub fn lambda(self: *NameGen) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_lambda", .{id});
    }

    /// Generate a unique shadow variable name
    /// Used when a local variable in nested function shadows outer scope
    pub fn shadow(self: *NameGen, original: []const u8) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_s_{s}", .{ id, original });
    }

    /// Generate a unique loop variable name
    /// Used for for-loop capture variables
    pub fn loopVar(self: *NameGen, original: []const u8) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_lv_{s}", .{ id, original });
    }

    /// Generate a unique comprehension variable name
    /// Used for list/dict/set comprehension loop variables
    pub fn compVar(self: *NameGen, original: []const u8) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_cv_{s}", .{ id, original });
    }

    /// Generate a unique comprehension result name
    pub fn compResult(self: *NameGen) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_cr", .{id});
    }

    /// Generate a unique inner loop variable name
    /// Used for inner variable bindings in for loops
    pub fn innerVar(self: *NameGen, original: []const u8) ![]const u8 {
        const id = self.counter;
        self.counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_iv_{s}", .{ id, original });
    }

    /// Check if a name is a generated name (has our prefix pattern __m{digit}_)
    pub fn isGeneratedName(name: []const u8) bool {
        if (name.len < 5) return false;
        if (!std.mem.startsWith(u8, name, "__m")) return false;
        // Check for digit after __m
        if (name.len > 3 and std.ascii.isDigit(name[3])) return true;
        return false;
    }

    /// Extract original name from generated name, or return as-is if not generated
    /// e.g., "__m0_p_foo" -> "foo", "__m123_l_bar" -> "bar", "__m5_lv_x" -> "x"
    pub fn extractOriginal(name: []const u8) []const u8 {
        if (!isGeneratedName(name)) return name;

        // Find the pattern: __m{digits}_{type}_{original}
        // Type can be: p, l, t, c, h, e, m, C, b, s, lv, cv, iv, cr
        var i: usize = 3; // Start after "__m"
        // Skip digits
        while (i < name.len and std.ascii.isDigit(name[i])) : (i += 1) {}
        // Skip underscore after digits
        if (i < name.len and name[i] == '_') i += 1;
        // Skip type chars (can be 1-2 chars like 'p', 'lv', 'cv', 'iv', 'cr')
        while (i < name.len and name[i] != '_') : (i += 1) {}
        // Skip underscore before original name
        if (i < name.len and name[i] == '_') i += 1;

        if (i < name.len) return name[i..];
        return name;
    }

    /// Enter a new scope (for debugging/tracking)
    pub fn enterScope(self: *NameGen) void {
        self.scope_depth += 1;
    }

    /// Exit a scope
    pub fn exitScope(self: *NameGen) void {
        if (self.scope_depth > 0) {
            self.scope_depth -= 1;
        }
    }
};

/// Create a new name generator
pub fn init(allocator: std.mem.Allocator) NameGen {
    return NameGen{ .allocator = allocator };
}

// Tests
test "param naming" {
    var namegen = init(std.testing.allocator);
    const p1 = try namegen.param("a");
    defer std.testing.allocator.free(p1);
    try std.testing.expectEqualStrings("__m0_p_a", p1);

    const p2 = try namegen.param("b");
    defer std.testing.allocator.free(p2);
    try std.testing.expectEqualStrings("__m1_p_b", p2);
}

test "isGeneratedName" {
    try std.testing.expect(NameGen.isGeneratedName("__m0_p_foo"));
    try std.testing.expect(NameGen.isGeneratedName("__m123_l_bar"));
    try std.testing.expect(!NameGen.isGeneratedName("foo"));
    try std.testing.expect(!NameGen.isGeneratedName("_foo"));
    try std.testing.expect(!NameGen.isGeneratedName("__foo"));
}

test "extractOriginal" {
    try std.testing.expectEqualStrings("foo", NameGen.extractOriginal("__m0_p_foo"));
    try std.testing.expectEqualStrings("bar", NameGen.extractOriginal("__m123_l_bar"));
    try std.testing.expectEqualStrings("baz", NameGen.extractOriginal("baz"));
    // Test multi-char type prefixes
    try std.testing.expectEqualStrings("x", NameGen.extractOriginal("__m5_lv_x"));
    try std.testing.expectEqualStrings("i", NameGen.extractOriginal("__m10_cv_i"));
    try std.testing.expectEqualStrings("y", NameGen.extractOriginal("__m7_iv_y"));
}

test "new naming functions" {
    var namegen = init(std.testing.allocator);

    const s1 = try namegen.shadow("rep");
    defer std.testing.allocator.free(s1);
    try std.testing.expectEqualStrings("__m0_s_rep", s1);

    const lv1 = try namegen.loopVar("i");
    defer std.testing.allocator.free(lv1);
    try std.testing.expectEqualStrings("__m1_lv_i", lv1);

    const cv1 = try namegen.compVar("x");
    defer std.testing.allocator.free(cv1);
    try std.testing.expectEqualStrings("__m2_cv_x", cv1);

    const cr1 = try namegen.compResult();
    defer std.testing.allocator.free(cr1);
    try std.testing.expectEqualStrings("__m3_cr", cr1);

    const iv1 = try namegen.innerVar("val");
    defer std.testing.allocator.free(iv1);
    try std.testing.expectEqualStrings("__m4_iv_val", iv1);
}
