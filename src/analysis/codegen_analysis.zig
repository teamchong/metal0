/// Codegen Analysis Framework
/// Unified analysis for common codegen patterns that cause repeated issues.
///
/// Solves these recurring problems:
/// | Problem                    | Solution                                    |
/// |----------------------------|---------------------------------------------|
/// | Pointless discard errors   | shouldEmitDiscard() - track variable usage  |
/// | Type cast chains           | getCastStrategy() - unified casting         |
/// | Variable shadowing         | getShadowRename() - systematic renaming     |
/// | Error handling inconsist.  | getErrorStrategy() - unified error handling |
/// | Unused unpacking vars      | isUnpackedVarUsed() - tuple var tracking    |
///
/// INTEGRATION EXAMPLE:
/// ```zig
/// // In NativeCodegen or similar:
/// const codegen_analysis = @import("analysis").codegen_analysis;
///
/// // 1. Create analyzer at start of function/scope
/// var analyzer = codegen_analysis.CodegenAnalyzer.init(self.allocator);
/// defer analyzer.deinit();
///
/// // 2. During analysis phase, register variables
/// const scope = codegen_analysis.ScopeId.function("my_func");
/// try analyzer.registerVariable(scope, "x", line_number);
///
/// // 3. When variable is used, mark it
/// analyzer.markUsed(scope, "x", line_number);
///
/// // 4. During codegen, query before emitting discards
/// if (analyzer.shouldEmitDiscard(scope, "x")) {
///     try self.emit("_ = x;");  // Only if truly unused
/// }
///
/// // 5. For casts, use the helper
/// const strategy = analyzer.getCastStrategy(.signed_int, .unsigned_int);
/// try codegen_analysis.emitCast(self.writer, strategy, struct {
///     fn emit(w: anytype) !void { try w.writeAll("my_value"); }
/// }.emit);
///
/// // 6. For shadowing, get renamed variable
/// const name = analyzer.getShadowRename(scope, "x") orelse "x";
/// try self.emit(name);
/// ```
///
/// PHILOSOPHY: Analyze once, query many times. No string-based detection.

const std = @import("std");
const ast = @import("ast");

// ============================================================================
// TYPES
// ============================================================================

/// Scope identifier for tracking variable usage per scope
pub const ScopeId = struct {
    function_name: []const u8,
    depth: u32, // 0 = module level, 1+ = nested scopes

    pub fn module() ScopeId {
        return .{ .function_name = "", .depth = 0 };
    }

    pub fn function(name: []const u8) ScopeId {
        return .{ .function_name = name, .depth = 1 };
    }

    pub fn nested(parent: ScopeId, name: []const u8) ScopeId {
        _ = name;
        return .{ .function_name = parent.function_name, .depth = parent.depth + 1 };
    }
};

/// Cast strategy to emit
pub const CastStrategy = enum {
    none, // No cast needed
    int_cast, // @intCast
    float_cast, // @floatCast
    ptr_cast, // @ptrCast
    ptr_align_cast, // @ptrCast(@alignCast(...))
    truncate, // @truncate
    as_i64, // @as(i64, @intCast(...))
    as_usize, // @as(usize, @intCast(...))
    as_f64, // @as(f64, @floatCast(...))
};

/// Error handling strategy
pub const ErrorStrategy = enum {
    return_null, // orelse return null
    return_error, // orelse return error.X
    catch_block, // catch |err| { ... }
    catch_continue, // catch continue
    unwrap_or_default, // orelse default_value
};

/// Variable usage info
pub const VarUsage = struct {
    name: []const u8,
    declared_at: usize, // Line/position of declaration
    used_after_decl: bool, // Whether variable is used after declaration
    assigned_to: bool, // Whether variable is target of assignment
    captured: bool, // Whether captured by inner closure
    shadows_outer: bool, // Whether shadows an outer scope variable
    shadow_rename: ?[]const u8, // Renamed name if shadowing
};

/// Analysis result for a scope
pub const ScopeAnalysis = struct {
    scope: ScopeId,
    variables: std.StringHashMap(VarUsage),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, scope: ScopeId) ScopeAnalysis {
        return .{
            .scope = scope,
            .variables = std.StringHashMap(VarUsage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ScopeAnalysis) void {
        self.variables.deinit();
    }
};

// ============================================================================
// MAIN ANALYZER
// ============================================================================

pub const CodegenAnalyzer = struct {
    allocator: std.mem.Allocator,
    scope_analyses: std.StringHashMap(ScopeAnalysis),
    outer_scope_vars: std.StringHashMap(ScopeId), // var_name -> declaring scope
    shadow_counter: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .scope_analyses = std.StringHashMap(ScopeAnalysis).init(allocator),
            .outer_scope_vars = std.StringHashMap(ScopeId).init(allocator),
            .shadow_counter = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free shadow rename strings
        var scope_it = self.scope_analyses.valueIterator();
        while (scope_it.next()) |analysis| {
            var var_it = analysis.variables.valueIterator();
            while (var_it.next()) |usage| {
                if (usage.shadow_rename) |rename| {
                    self.allocator.free(rename);
                }
            }
            @constCast(analysis).deinit();
        }
        self.scope_analyses.deinit();
        self.outer_scope_vars.deinit();
    }

    // ========================================================================
    // QUERY API - Call these during codegen
    // ========================================================================

    /// Should we emit `_ = varname;` for this variable?
    /// Returns false if variable is used later (would cause "pointless discard")
    pub fn shouldEmitDiscard(self: *Self, scope: ScopeId, var_name: []const u8) bool {
        const key = scopeKey(scope);
        if (self.scope_analyses.get(key)) |analysis| {
            if (analysis.variables.get(var_name)) |usage| {
                // Only discard if NOT used after declaration
                return !usage.used_after_decl;
            }
        }
        // Default: don't emit discard (safer - avoids pointless discard error)
        return false;
    }

    /// Get renamed variable name if it shadows an outer scope variable
    pub fn getShadowRename(self: *Self, scope: ScopeId, var_name: []const u8) ?[]const u8 {
        const key = scopeKey(scope);
        if (self.scope_analyses.get(key)) |analysis| {
            if (analysis.variables.get(var_name)) |usage| {
                return usage.shadow_rename;
            }
        }
        return null;
    }

    /// Check if variable shadows an outer scope variable
    pub fn doesShadow(self: *Self, scope: ScopeId, var_name: []const u8) bool {
        // Check if this var exists in any outer scope
        if (self.outer_scope_vars.get(var_name)) |declaring_scope| {
            // Shadows if declared at lower depth than current
            return declaring_scope.depth < scope.depth;
        }
        return false;
    }

    /// Get cast strategy for converting between types
    pub fn getCastStrategy(_: *Self, from_type: TypeCategory, to_type: TypeCategory) CastStrategy {
        return switch (from_type) {
            .signed_int => switch (to_type) {
                .signed_int => .none,
                .unsigned_int => .as_usize,
                .float => .as_f64,
                .pointer => .ptr_cast,
                else => .none,
            },
            .unsigned_int => switch (to_type) {
                .signed_int => .as_i64,
                .unsigned_int => .none,
                .float => .as_f64,
                .pointer => .ptr_cast,
                else => .none,
            },
            .float => switch (to_type) {
                .signed_int => .truncate,
                .unsigned_int => .truncate,
                .float => .none,
                else => .none,
            },
            .pointer => switch (to_type) {
                .pointer => .ptr_align_cast,
                else => .none,
            },
            else => .none,
        };
    }

    /// Get error handling strategy for an expression
    pub fn getErrorStrategy(_: *Self, in_loop: bool, returns_optional: bool) ErrorStrategy {
        if (in_loop) {
            return .catch_continue;
        }
        if (returns_optional) {
            return .return_null;
        }
        return .return_error;
    }

    /// Check if a variable from tuple unpacking is used
    pub fn isUnpackedVarUsed(self: *Self, scope: ScopeId, var_name: []const u8) bool {
        const key = scopeKey(scope);
        if (self.scope_analyses.get(key)) |analysis| {
            if (analysis.variables.get(var_name)) |usage| {
                return usage.used_after_decl;
            }
        }
        // Default: assume used (safer - generates working code)
        return true;
    }

    // ========================================================================
    // ANALYSIS API - Call these during analysis phase
    // ========================================================================

    /// Register a variable declaration in a scope
    pub fn registerVariable(self: *Self, scope: ScopeId, var_name: []const u8, position: usize) !void {
        const key = scopeKey(scope);

        // Ensure scope analysis exists
        if (!self.scope_analyses.contains(key)) {
            try self.scope_analyses.put(key, ScopeAnalysis.init(self.allocator, scope));
        }

        var analysis = self.scope_analyses.getPtr(key).?;

        // Check for shadowing
        const shadows = self.doesShadow(scope, var_name);
        var shadow_rename: ?[]const u8 = null;

        if (shadows) {
            // Generate unique shadow name
            self.shadow_counter += 1;
            const rename = try std.fmt.allocPrint(self.allocator, "__shadow_{s}_{d}", .{ var_name, self.shadow_counter });
            shadow_rename = rename;
        }

        try analysis.variables.put(var_name, .{
            .name = var_name,
            .declared_at = position,
            .used_after_decl = false,
            .assigned_to = true,
            .captured = false,
            .shadows_outer = shadows,
            .shadow_rename = shadow_rename,
        });

        // Register in outer scope tracker
        try self.outer_scope_vars.put(var_name, scope);
    }

    /// Mark a variable as used (called when variable is referenced)
    pub fn markUsed(self: *Self, scope: ScopeId, var_name: []const u8, position: usize) void {
        const key = scopeKey(scope);
        if (self.scope_analyses.getPtr(key)) |analysis| {
            if (analysis.variables.getPtr(var_name)) |usage| {
                // Mark as used if reference is after declaration
                if (position > usage.declared_at) {
                    usage.used_after_decl = true;
                }
            }
        }
    }

    /// Mark a variable as captured by a closure
    pub fn markCaptured(self: *Self, scope: ScopeId, var_name: []const u8) void {
        const key = scopeKey(scope);
        if (self.scope_analyses.getPtr(key)) |analysis| {
            if (analysis.variables.getPtr(var_name)) |usage| {
                usage.captured = true;
            }
        }
    }

    // ========================================================================
    // HELPERS
    // ========================================================================

    fn scopeKey(scope: ScopeId) []const u8 {
        // For now, just use function name. Could be improved with depth.
        return scope.function_name;
    }
};

/// Type categories for cast decisions
pub const TypeCategory = enum {
    signed_int,
    unsigned_int,
    float,
    pointer,
    string,
    boolean,
    other,

    pub fn fromZigType(type_str: []const u8) TypeCategory {
        if (std.mem.eql(u8, type_str, "i64") or
            std.mem.eql(u8, type_str, "i32") or
            std.mem.eql(u8, type_str, "isize"))
        {
            return .signed_int;
        }
        if (std.mem.eql(u8, type_str, "u64") or
            std.mem.eql(u8, type_str, "u32") or
            std.mem.eql(u8, type_str, "usize"))
        {
            return .unsigned_int;
        }
        if (std.mem.eql(u8, type_str, "f64") or std.mem.eql(u8, type_str, "f32")) {
            return .float;
        }
        if (std.mem.startsWith(u8, type_str, "*") or std.mem.startsWith(u8, type_str, "[*")) {
            return .pointer;
        }
        if (std.mem.eql(u8, type_str, "bool")) {
            return .boolean;
        }
        if (std.mem.eql(u8, type_str, "[]const u8") or std.mem.eql(u8, type_str, "[]u8")) {
            return .string;
        }
        return .other;
    }
};

// ============================================================================
// CAST HELPERS - Emit functions for common casts
// ============================================================================

/// Emit a cast based on strategy
pub fn emitCast(writer: anytype, strategy: CastStrategy, value_emitter: anytype) !void {
    switch (strategy) {
        .none => try value_emitter(writer),
        .int_cast => {
            try writer.writeAll("@intCast(");
            try value_emitter(writer);
            try writer.writeAll(")");
        },
        .float_cast => {
            try writer.writeAll("@floatCast(");
            try value_emitter(writer);
            try writer.writeAll(")");
        },
        .ptr_cast => {
            try writer.writeAll("@ptrCast(");
            try value_emitter(writer);
            try writer.writeAll(")");
        },
        .ptr_align_cast => {
            try writer.writeAll("@ptrCast(@alignCast(");
            try value_emitter(writer);
            try writer.writeAll("))");
        },
        .truncate => {
            try writer.writeAll("@truncate(");
            try value_emitter(writer);
            try writer.writeAll(")");
        },
        .as_i64 => {
            try writer.writeAll("@as(i64, @intCast(");
            try value_emitter(writer);
            try writer.writeAll("))");
        },
        .as_usize => {
            try writer.writeAll("@as(usize, @intCast(");
            try value_emitter(writer);
            try writer.writeAll("))");
        },
        .as_f64 => {
            try writer.writeAll("@as(f64, @floatCast(");
            try value_emitter(writer);
            try writer.writeAll("))");
        },
    }
}

/// Emit error handling based on strategy
pub fn emitErrorHandler(writer: anytype, strategy: ErrorStrategy, error_name: ?[]const u8) !void {
    switch (strategy) {
        .return_null => try writer.writeAll(" orelse return null"),
        .return_error => {
            try writer.writeAll(" orelse return error.");
            try writer.writeAll(error_name orelse "OperationFailed");
        },
        .catch_block => {
            try writer.writeAll(" catch |err| { _ = err; return null; }");
        },
        .catch_continue => try writer.writeAll(" catch continue"),
        .unwrap_or_default => try writer.writeAll(" orelse .{}"),
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "CodegenAnalyzer basic usage" {
    const allocator = std.testing.allocator;
    var analyzer = CodegenAnalyzer.init(allocator);
    defer analyzer.deinit();

    const scope = ScopeId.function("test_func");

    // Register variable
    try analyzer.registerVariable(scope, "x", 10);

    // Mark as used at position after declaration
    analyzer.markUsed(scope, "x", 20);

    // After use, should NOT emit discard (would be pointless)
    try std.testing.expect(!analyzer.shouldEmitDiscard(scope, "x"));

    // Register an unused variable
    try analyzer.registerVariable(scope, "unused_y", 30);
    // Don't mark as used

    // Unused variable SHOULD be discardable
    try std.testing.expect(analyzer.shouldEmitDiscard(scope, "unused_y"));
}

test "CastStrategy selection" {
    const allocator = std.testing.allocator;
    var analyzer = CodegenAnalyzer.init(allocator);
    defer analyzer.deinit();

    // i64 -> usize should use as_usize
    const strategy = analyzer.getCastStrategy(.signed_int, .unsigned_int);
    try std.testing.expectEqual(CastStrategy.as_usize, strategy);

    // usize -> i64 should use as_i64
    const strategy2 = analyzer.getCastStrategy(.unsigned_int, .signed_int);
    try std.testing.expectEqual(CastStrategy.as_i64, strategy2);
}

test "Shadow detection" {
    const allocator = std.testing.allocator;
    var analyzer = CodegenAnalyzer.init(allocator);
    defer analyzer.deinit();

    // Register at module level
    const module_scope = ScopeId.module();
    try analyzer.registerVariable(module_scope, "x", 0);

    // Register same name in function - should shadow
    const func_scope = ScopeId.function("test_func");
    try analyzer.registerVariable(func_scope, "x", 10);

    // Should have shadow rename
    const rename = analyzer.getShadowRename(func_scope, "x");
    try std.testing.expect(rename != null);
    try std.testing.expect(std.mem.startsWith(u8, rename.?, "__shadow_x_"));
}
