/// Unified function traits analysis framework
/// Build call graph once, query for multiple codegen decisions
///
/// One analysis, many uses:
/// | Trait                  | Used For                                      |
/// |------------------------|-----------------------------------------------|
/// | has_io_await           | Async strategy (state machine vs thread pool) |
/// | mutates_params         | var vs const parameters                       |
/// | can_error              | !T vs T return type                           |
/// | needs_allocator        | Pass allocator or not                         |
/// | is_pure                | Memoization / comptime eval                   |
/// | is_tail_recursive      | Tail call optimization                        |
/// | captures_vars          | Closure generation                            |
/// | is_generator           | Generator state machine                       |
/// | calls                  | Call graph edges for dead code elimination    |
const std = @import("std");
const ast = @import("ast");
const hashmap_helper = @import("hashmap_helper");

/// Reference to a function (module-qualified name)
pub const FunctionRef = struct {
    module: []const u8, // Empty string for current module
    name: []const u8,
    class_name: ?[]const u8 = null, // For methods

    pub fn format(self: FunctionRef, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.module.len > 0) {
            try writer.print("{s}.", .{self.module});
        }
        if (self.class_name) |cls| {
            try writer.print("{s}.", .{cls});
        }
        try writer.print("{s}", .{self.name});
    }

    pub fn eql(self: FunctionRef, other: FunctionRef) bool {
        return std.mem.eql(u8, self.module, other.module) and
            std.mem.eql(u8, self.name, other.name) and
            ((self.class_name == null and other.class_name == null) or
            (self.class_name != null and other.class_name != null and
            std.mem.eql(u8, self.class_name.?, other.class_name.?)));
    }
};

/// Traits computed for each function
pub const FunctionTraits = struct {
    /// Function reference
    ref: FunctionRef,

    /// Whether function contains await expressions
    has_await: bool = false,

    /// Whether function contains I/O operations (file, network, print)
    has_io: bool = false,

    /// Which parameters are mutated (indexed by param position)
    mutates_params: []bool = &.{},

    /// Whether function can raise/return an error
    can_error: bool = false,

    /// Whether function needs an allocator parameter (for error union return)
    needs_allocator: bool = false,

    /// Whether function actually uses the allocator param (vs __global_allocator)
    uses_allocator_param: bool = false,

    /// Whether function is pure (no I/O, no side effects)
    is_pure: bool = true,

    /// Whether function is tail-recursive
    is_tail_recursive: bool = false,

    /// Whether function is a generator (contains yield)
    is_generator: bool = false,

    /// Variables captured from outer scope (for closures)
    captured_vars: []const []const u8 = &.{},

    /// Functions called directly by this function
    calls: []FunctionRef = &.{},

    /// Whether this function is called by anyone (for DCE)
    is_called: bool = false,

    /// Whether function modifies global state
    modifies_globals: bool = false,

    /// Whether function reads global state
    reads_globals: bool = false,

    /// Async complexity classification
    async_complexity: AsyncComplexity = .trivial,

    /// Return type hint (if determinable)
    return_type_hint: ?TypeHint = null,

    // ========== PARAMETER USAGE ANALYSIS ==========
    /// Which parameters are actually used in the function body (indexed by param position)
    /// Used to determine if a parameter should be anonymous (_: type) in Zig signature
    params_used_in_body: []bool = &.{},

    // ========== BLOCK-SCOPED VARIABLE ANALYSIS ==========
    /// Variables declared inside block scopes (for/if/try/with) that are NOT used outside
    /// These variables should NOT get function-level discards (they're truly block-scoped in Zig)
    block_scoped_vars: []const []const u8 = &.{},

    /// Variables declared inside block scopes that ARE used outside (need hoisting)
    /// These need to be hoisted to function level with var declaration
    escaping_block_vars: []const []const u8 = &.{},

    // ========== ESCAPE ANALYSIS ==========
    /// Which parameters escape this function (returned, stored globally, passed to escaping call)
    escaping_params: []bool = &.{},
    /// Local variables that escape (by name)
    escaping_locals: []const []const u8 = &.{},
    /// If return value aliases a parameter, which one? (for ownership tracking)
    return_aliases_param: ?usize = null,

    // ========== PRECISE ERROR TYPES ==========
    /// Precise error types this function can raise (KeyError, IndexError, etc.)
    /// Use getErrorSet() to query, toZigErrorSet() to generate code
    error_types: ErrorSet = .{},

    // ========== HETEROGENEOUS CONTAINER ANALYSIS ==========
    /// Variables that need PyValue type (assigned different types, heterogeneous lists)
    /// These should be declared as ArrayList(PyValue) instead of ArrayList(T)
    heterogeneous_vars: []const []const u8 = &.{},

    /// Variables that are list aliases (T = A where A is a list)
    /// Maps alias name -> original list name
    list_aliases: []const ListAlias = &.{},

    pub fn deinit(self: *FunctionTraits, allocator: std.mem.Allocator) void {
        if (self.mutates_params.len > 0) allocator.free(self.mutates_params);
        if (self.captured_vars.len > 0) allocator.free(self.captured_vars);
        if (self.calls.len > 0) allocator.free(self.calls);
        if (self.escaping_params.len > 0) allocator.free(self.escaping_params);
        if (self.escaping_locals.len > 0) allocator.free(self.escaping_locals);
        if (self.params_used_in_body.len > 0) allocator.free(self.params_used_in_body);
        if (self.block_scoped_vars.len > 0) allocator.free(self.block_scoped_vars);
        if (self.escaping_block_vars.len > 0) allocator.free(self.escaping_block_vars);
    }

    // ========== QUERY METHODS ==========

    /// Check if a parameter at the given index is used in the function body
    pub fn isParamUsed(self: *const FunctionTraits, param_index: usize) bool {
        if (param_index >= self.params_used_in_body.len) return true; // Assume used if not analyzed
        return self.params_used_in_body[param_index];
    }

    /// Check if a variable is block-scoped (declared in for/if/try, not used outside)
    pub fn isBlockScoped(self: *const FunctionTraits, var_name: []const u8) bool {
        for (self.block_scoped_vars) |v| {
            if (std.mem.eql(u8, v, var_name)) return true;
        }
        return false;
    }

    /// Check if a variable needs hoisting (declared in block, used outside)
    pub fn needsHoisting(self: *const FunctionTraits, var_name: []const u8) bool {
        for (self.escaping_block_vars) |v| {
            if (std.mem.eql(u8, v, var_name)) return true;
        }
        return false;
    }

    /// Check if a variable needs PyValue type (heterogeneous assignments)
    pub fn needsPyValueType(self: *const FunctionTraits, var_name: []const u8) bool {
        for (self.heterogeneous_vars) |v| {
            if (std.mem.eql(u8, v, var_name)) return true;
        }
        return false;
    }

    /// Check if a variable is an alias to another list
    pub fn getListAliasTarget(self: *const FunctionTraits, var_name: []const u8) ?[]const u8 {
        for (self.list_aliases) |alias| {
            if (std.mem.eql(u8, alias.alias_name, var_name)) return alias.original_name;
        }
        return null;
    }

    /// Check if the original list variable needs PyValue (because alias adds heterogeneous types)
    pub fn listNeedsPyValue(self: *const FunctionTraits, var_name: []const u8) bool {
        // Check if this variable is in heterogeneous_vars
        if (self.needsPyValueType(var_name)) return true;
        // Check if any alias of this variable is in heterogeneous_vars
        for (self.list_aliases) |alias| {
            if (std.mem.eql(u8, alias.original_name, var_name)) {
                if (self.needsPyValueType(alias.alias_name)) return true;
            }
        }
        return false;
    }
};

pub const AsyncComplexity = enum {
    trivial, // Single expression, no calls - inline always
    simple, // Few operations, no loops - prefer inline
    moderate, // Has loops or multiple awaits - generate both
    complex, // Recursive or many awaits - spawn only
};

/// Tracks list variable aliases (T = A where A is a list)
pub const ListAlias = struct {
    alias_name: []const u8,
    original_name: []const u8,
};

pub const TypeHint = enum {
    void,
    int,
    float,
    bool,
    string,
    list,
    dict,
    tuple,
    none,
    object,
    any,
};

// ============================================================================
// Runtime Type Categories - For generating comptime type checks
// ============================================================================
// These categories help codegen emit proper comptime checks when the exact
// type isn't known (e.g., closure parameters with anytype).

/// Categories of runtime types that need special handling in codegen
pub const RuntimeTypeCategory = enum {
    /// Standard slice/array - use direct indexing and .len
    slice,
    /// ArrayList - use .items for indexing and .items.len for length
    array_list,
    /// BigInt - needs .toInt() conversion
    big_int,
    /// PyValue union - needs accessor methods or switch
    py_value,
    /// HashMap/AutoHashMap - use .get()/.put()/.count()
    hash_map,
    /// Iterator - has .next() method
    iterator,
    /// Standard integer - direct arithmetic
    integer,
    /// Unknown - need full comptime dispatch
    unknown,
};

/// Helper to generate comptime type check code for a given category
/// Returns Zig code that evaluates to true if the type matches
pub fn comptimeTypeCheck(category: RuntimeTypeCategory) []const u8 {
    return switch (category) {
        .slice => "@typeInfo(@TypeOf(__val)) == .pointer and @typeInfo(@TypeOf(__val)).pointer.size == .slice",
        .array_list => "@typeInfo(@TypeOf(__val)) == .@\"struct\" and @hasField(@TypeOf(__val), \"items\") and @hasField(@TypeOf(__val), \"capacity\")",
        .big_int => "@TypeOf(__val) == bigint.BigInt",
        .py_value => "@TypeOf(__val) == runtime.PyValue",
        .hash_map => "@typeInfo(@TypeOf(__val)) == .@\"struct\" and @hasDecl(@TypeOf(__val), \"count\")",
        .iterator => "@typeInfo(@TypeOf(__val)) == .@\"struct\" and @hasDecl(@TypeOf(__val), \"next\")",
        .integer => "@typeInfo(@TypeOf(__val)) == .int or @typeInfo(@TypeOf(__val)) == .comptime_int",
        .unknown => "true",
    };
}

/// Generate a comptime dispatch expression that handles multiple type categories
/// Usage: genComptimeDispatch("my_var", &.{.array_list, .slice}, &.{".items[idx]", "[idx]"})
/// Returns code like: if (comptime is_arraylist) __val.items[idx] else __val[idx]
pub fn genComptimeDispatch(
    allocator: std.mem.Allocator,
    var_name: []const u8,
    categories: []const RuntimeTypeCategory,
    expressions: []const []const u8,
) ![]const u8 {
    if (categories.len != expressions.len) return error.InvalidArgument;
    if (categories.len == 0) return "";
    if (categories.len == 1) {
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ var_name, expressions[0] });
    }

    var result = std.ArrayList(u8).init(allocator);
    const writer = result.writer();

    // Generate nested if-else chain
    try writer.print("blk: {{ const __val = {s}; break :blk ", .{var_name});

    for (categories[0 .. categories.len - 1], expressions[0 .. expressions.len - 1], 0..) |cat, expr, i| {
        if (i > 0) try writer.writeAll(" else ");
        try writer.print("if ({s}) __val{s}", .{ comptimeTypeCheck(cat), expr });
    }

    // Final else case
    try writer.print(" else __val{s}; }}", .{expressions[expressions.len - 1]});

    return result.toOwnedSlice();
}

/// Standard comptime patterns for common operations
pub const ComptimePatterns = struct {
    /// Get length of a value (handles slice, ArrayList, HashMap, PyValue)
    pub const length =
        \\blk: { const __t = @TypeOf(__val); break :blk if (@typeInfo(__t) == .@"struct" and @hasField(__t, "items")) __val.items.len else if (@typeInfo(__t) == .@"struct" and @hasDecl(__t, "count")) __val.count() else if (__t == runtime.PyValue) __val.pyLen() else __val.len; }
    ;

    /// Index into a value (handles slice, ArrayList, PyValue)
    pub const index =
        \\blk: { const __t = @TypeOf(__val); break :blk if (@typeInfo(__t) == .@"struct" and @hasField(__t, "items")) __val.items[__idx] else if (__t == runtime.PyValue) __val.pyAt(__idx) else __val[__idx]; }
    ;

    /// Convert to i64 (handles int, BigInt, PyValue)
    pub const to_int =
        \\blk: { const __t = @TypeOf(__val); break :blk if (__t == bigint.BigInt) __val.toInt() else if (__t == runtime.PyValue) __val.asInt() else @as(i64, @intCast(__val)); }
    ;

    /// Convert to f64 (handles float, int, BigInt, PyValue)
    pub const to_float =
        \\blk: { const __t = @TypeOf(__val); break :blk if (__t == bigint.BigInt) __val.toFloat() else if (__t == runtime.PyValue) __val.asFloat() else if (@typeInfo(__t) == .int) @as(f64, @floatFromInt(__val)) else @as(f64, @floatCast(__val)); }
    ;

    /// Safe shift amount (converts i64 to u6 for bit shifts)
    pub const shift_amount =
        \\@as(u6, @intCast(@mod(__val, 64)))
    ;

    /// Iterator slice (handles ArrayList vs slice)
    pub const iter_slice =
        \\blk: { const __t = @TypeOf(__val); break :blk if (@typeInfo(__t) == .@"struct" and @hasField(__t, "items")) __val.items else __val; }
    ;
};

// ============================================================================
// Primitive Type Method Dispatch - Python methods on Zig primitives
// ============================================================================
// Python has methods on primitive types (int, float, str) that don't exist
// on Zig's native types. This maps them to runtime helper functions.

/// Methods available on Python float that need runtime dispatch
pub const FloatMethods = std.StaticStringMap([]const u8).initComptime(.{
    // Float representation methods
    .{ "as_integer_ratio", "runtime.float_ops.asIntegerRatio" },
    .{ "is_integer", "runtime.float_ops.isInteger" },
    .{ "hex", "runtime.float_ops.toHex" },
    .{ "fromhex", "runtime.float_ops.fromHex" },

    // Magic methods for math module
    .{ "__floor__", "runtime.float_ops.floor" },
    .{ "__ceil__", "runtime.float_ops.ceil" },
    .{ "__trunc__", "runtime.float_ops.trunc" },
    .{ "__round__", "runtime.float_ops.round" },
    .{ "__abs__", "runtime.float_ops.abs" },
    .{ "__neg__", "runtime.float_ops.neg" },
    .{ "__pos__", "runtime.float_ops.pos" },

    // Comparison magic methods
    .{ "__eq__", "runtime.float_ops.eq" },
    .{ "__ne__", "runtime.float_ops.ne" },
    .{ "__lt__", "runtime.float_ops.lt" },
    .{ "__le__", "runtime.float_ops.le" },
    .{ "__gt__", "runtime.float_ops.gt" },
    .{ "__ge__", "runtime.float_ops.ge" },

    // String conversion
    .{ "__repr__", "runtime.float_ops.repr" },
    .{ "__str__", "runtime.float_ops.str" },
    .{ "__format__", "runtime.float_ops.format" },

    // Hash and bool
    .{ "__hash__", "runtime.float_ops.hash" },
    .{ "__bool__", "runtime.float_ops.toBool" },

    // Type conversion
    .{ "__int__", "runtime.float_ops.toInt" },
    .{ "__float__", "runtime.float_ops.toFloat" },

    // Conjugate (for complex compat)
    .{ "conjugate", "runtime.float_ops.conjugate" },
    .{ "real", "runtime.float_ops.real" },
    .{ "imag", "runtime.float_ops.imag" },
});

/// Methods available on Python int that need runtime dispatch
pub const IntMethods = std.StaticStringMap([]const u8).initComptime(.{
    // Bit operations
    .{ "bit_length", "runtime.int_ops.bitLength" },
    .{ "bit_count", "runtime.int_ops.bitCount" },
    .{ "to_bytes", "runtime.int_ops.toBytes" },
    .{ "from_bytes", "runtime.int_ops.fromBytes" },

    // Type conversion
    .{ "as_integer_ratio", "runtime.int_ops.asIntegerRatio" },
    .{ "__index__", "runtime.int_ops.index" },
    .{ "__int__", "runtime.int_ops.toInt" },
    .{ "__float__", "runtime.int_ops.toFloat" },

    // Math magic methods
    .{ "__floor__", "runtime.int_ops.floor" },
    .{ "__ceil__", "runtime.int_ops.ceil" },
    .{ "__trunc__", "runtime.int_ops.trunc" },
    .{ "__round__", "runtime.int_ops.round" },
    .{ "__abs__", "runtime.int_ops.abs" },

    // String conversion
    .{ "__repr__", "runtime.int_ops.repr" },
    .{ "__str__", "runtime.int_ops.str" },
    .{ "__format__", "runtime.int_ops.format" },

    // Hash and bool
    .{ "__hash__", "runtime.int_ops.hash" },
    .{ "__bool__", "runtime.int_ops.toBool" },

    // Conjugate (for complex compat)
    .{ "conjugate", "runtime.int_ops.conjugate" },
    .{ "real", "runtime.int_ops.real" },
    .{ "imag", "runtime.int_ops.imag" },

    // Numerator/denominator (for rational compat)
    .{ "numerator", "runtime.int_ops.numerator" },
    .{ "denominator", "runtime.int_ops.denominator" },
});

/// Methods available on Python dict that need runtime dispatch
/// Dict in Zig uses ArrayHashMap which has different method names
pub const DictMethods = std.StaticStringMap([]const u8).initComptime(.{
    // Mutating methods
    .{ "update", "runtime.dict_ops.update" },
    .{ "clear", "runtime.dict_ops.clear" },
    .{ "pop", "runtime.dict_ops.pop" },
    .{ "popitem", "runtime.dict_ops.popitem" },
    .{ "setdefault", "runtime.dict_ops.setdefault" },

    // Non-mutating methods
    .{ "get", "runtime.dict_ops.get" },
    .{ "keys", "runtime.dict_ops.keys" },
    .{ "values", "runtime.dict_ops.values" },
    .{ "items", "runtime.dict_ops.items" },
    .{ "copy", "runtime.dict_ops.copy" },

    // Comparison/membership
    .{ "__contains__", "runtime.dict_ops.contains" },
    .{ "__eq__", "runtime.dict_ops.eq" },
    .{ "__ne__", "runtime.dict_ops.ne" },

    // OrderedDict methods
    .{ "move_to_end", "runtime.dict_ops.moveToEnd" },

    // String conversion
    .{ "__repr__", "runtime.dict_ops.repr" },
    .{ "__str__", "runtime.dict_ops.str" },

    // Length
    .{ "__len__", "runtime.dict_ops.len" },
});

/// Methods available on Python list that need runtime dispatch
pub const ListMethods = std.StaticStringMap([]const u8).initComptime(.{
    // Mutating methods
    .{ "append", "runtime.list_ops.append" },
    .{ "extend", "runtime.list_ops.extend" },
    .{ "insert", "runtime.list_ops.insert" },
    .{ "remove", "runtime.list_ops.remove" },
    .{ "pop", "runtime.list_ops.pop" },
    .{ "clear", "runtime.list_ops.clear" },
    .{ "reverse", "runtime.list_ops.reverse" },
    .{ "sort", "runtime.list_ops.sort" },

    // Non-mutating methods
    .{ "index", "runtime.list_ops.index" },
    .{ "count", "runtime.list_ops.count" },
    .{ "copy", "runtime.list_ops.copy" },

    // String conversion
    .{ "__repr__", "runtime.list_ops.repr" },
    .{ "__str__", "runtime.list_ops.str" },

    // Length/comparison
    .{ "__len__", "runtime.list_ops.len" },
    .{ "__eq__", "runtime.list_ops.eq" },
    .{ "__contains__", "runtime.list_ops.contains" },
});

/// Check if a method name is a Python primitive method that needs dispatch
pub fn isPrimitiveMethod(method_name: []const u8) bool {
    return FloatMethods.has(method_name) or IntMethods.has(method_name);
}

/// Check if a method name is a Python dict method that needs dispatch
pub fn isDictMethod(method_name: []const u8) bool {
    return DictMethods.has(method_name);
}

/// Check if a method name is a Python list method that needs dispatch
pub fn isListMethod(method_name: []const u8) bool {
    return ListMethods.has(method_name);
}

/// Get the runtime function for a float method
pub fn getFloatMethod(method_name: []const u8) ?[]const u8 {
    return FloatMethods.get(method_name);
}

/// Get the runtime function for an int method
pub fn getIntMethod(method_name: []const u8) ?[]const u8 {
    return IntMethods.get(method_name);
}

/// Get the runtime function for a dict method
pub fn getDictMethod(method_name: []const u8) ?[]const u8 {
    return DictMethods.get(method_name);
}

/// Get the runtime function for a list method
pub fn getListMethod(method_name: []const u8) ?[]const u8 {
    return ListMethods.get(method_name);
}

// ============================================================================
// Closure Return Type Analysis - Infer proper return types for nested functions
// ============================================================================
// Closures/nested functions need proper return type inference. Common patterns:
// - Returns context manager (assertRaises, open, etc.) -> ContextManager type
// - Returns self method call -> method's return type
// - Returns literal -> literal type
// - Returns nothing -> void

/// Known methods that return context managers (for `with` statement usage)
pub const ContextManagerMethods = std.StaticStringMap([]const u8).initComptime(.{
    // unittest assertion context managers
    .{ "assertRaises", "runtime.unittest.AssertRaisesContext" },
    .{ "assertRaisesRegex", "runtime.unittest.AssertRaisesContext" },
    .{ "assertWarns", "runtime.unittest.AssertWarnsContext" },
    .{ "assertWarnsRegex", "runtime.unittest.AssertWarnsContext" },
    .{ "assertLogs", "runtime.unittest.AssertLogsContext" },
    .{ "assertNoLogs", "runtime.unittest.AssertLogsContext" },

    // File/IO context managers
    .{ "open", "runtime.io.File" },

    // Threading context managers
    .{ "Lock", "runtime.threading.Lock" },
    .{ "RLock", "runtime.threading.RLock" },

    // Contextlib
    .{ "contextmanager", "runtime.contextlib.ContextManager" },
    .{ "nullcontext", "runtime.contextlib.NullContext" },
    .{ "suppress", "runtime.contextlib.SuppressContext" },
    .{ "redirect_stdout", "runtime.contextlib.RedirectContext" },
    .{ "redirect_stderr", "runtime.contextlib.RedirectContext" },

    // Decimal context
    .{ "localcontext", "runtime.decimal.LocalContext" },

    // Warnings
    .{ "catch_warnings", "runtime.warnings.CatchWarningsContext" },
});

/// Closure return type categories
pub const ClosureReturnType = enum {
    void, // No return or return without value
    context_manager, // Returns a context manager (for with statements)
    integer, // Returns int literal or int expression
    float, // Returns float
    string, // Returns string
    boolean, // Returns bool
    list, // Returns list
    dict, // Returns dict
    tuple, // Returns tuple
    callable, // Returns another function/lambda
    self_type, // Returns self (for method chaining)
    unknown, // Can't determine - use anytype or PyValue
};

/// Analyze a nested function's return type from its AST
/// Returns the inferred return type category
pub fn analyzeClosureReturnType(func_body: []const ast.Node) ClosureReturnType {
    // First pass: collect variable types from assignments
    var var_types: [32]VarTypeEntry = undefined;
    var var_count: usize = 0;
    collectVarTypes(func_body, &var_types, &var_count);

    // Second pass: find return statements and infer type
    for (func_body) |stmt| {
        if (stmt == .return_stmt) {
            const ret = stmt.return_stmt;
            if (ret.value) |val_ptr| {
                return inferExprReturnTypeWithVars(val_ptr.*, var_types[0..var_count]);
            } else {
                return .void;
            }
        }
    }
    // No explicit return found
    return .void;
}

/// Entry for tracking variable types
const VarTypeEntry = struct {
    name: []const u8,
    var_type: ClosureReturnType,
};

/// Collect variable types from assignments in function body
fn collectVarTypes(body: []const ast.Node, var_types: *[32]VarTypeEntry, count: *usize) void {
    for (body) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                // Get the assigned value type
                const value_type = inferExprReturnType(assign.value.*);
                // Track all target variables
                for (assign.targets) |target| {
                    if (target == .name) {
                        const name = target.name.id;
                        if (count.* < 32) {
                            var_types[count.*] = .{ .name = name, .var_type = value_type };
                            count.* += 1;
                        }
                    }
                }
            },
            .aug_assign => |aug| {
                // Augmented assignment (+=, -= etc) preserves or promotes type
                // For now, assume it keeps the type based on the operand
                const value_type = inferExprReturnType(aug.value.*);
                if (aug.target.* == .name) {
                    const name = aug.target.name.id;
                    // Update existing or add new
                    for (var_types[0..count.*]) |*entry| {
                        if (std.mem.eql(u8, entry.name, name)) {
                            // Keep existing type or promote to unknown if different
                            if (entry.var_type != value_type and value_type != .unknown) {
                                entry.var_type = .unknown;
                            }
                            return;
                        }
                    }
                    // Add new entry
                    if (count.* < 32) {
                        var_types[count.*] = .{ .name = name, .var_type = value_type };
                        count.* += 1;
                    }
                }
            },
            .for_stmt => |for_stmt| {
                // Recurse into for body
                collectVarTypes(for_stmt.body, var_types, count);
                if (for_stmt.orelse_body) |orelse_body| {
                    collectVarTypes(orelse_body, var_types, count);
                }
            },
            .while_stmt => |while_stmt| {
                collectVarTypes(while_stmt.body, var_types, count);
                if (while_stmt.orelse_body) |orelse_body| {
                    collectVarTypes(orelse_body, var_types, count);
                }
            },
            .if_stmt => |if_stmt| {
                collectVarTypes(if_stmt.body, var_types, count);
                collectVarTypes(if_stmt.else_body, var_types, count);
            },
            .try_stmt => |try_stmt| {
                collectVarTypes(try_stmt.body, var_types, count);
                collectVarTypes(try_stmt.else_body, var_types, count);
                collectVarTypes(try_stmt.finalbody, var_types, count);
            },
            .with_stmt => |with_stmt| {
                collectVarTypes(with_stmt.body, var_types, count);
            },
            else => {},
        }
    }
}

/// Infer return type with variable type lookup
fn inferExprReturnTypeWithVars(expr: ast.Node, var_types: []const VarTypeEntry) ClosureReturnType {
    return switch (expr) {
        .name => |n| {
            if (std.mem.eql(u8, n.id, "self")) return .self_type;
            if (std.mem.eql(u8, n.id, "True") or std.mem.eql(u8, n.id, "False")) return .boolean;
            if (std.mem.eql(u8, n.id, "None")) return .void;
            // Look up variable type
            for (var_types) |entry| {
                if (std.mem.eql(u8, entry.name, n.id)) {
                    return entry.var_type;
                }
            }
            return .unknown;
        },
        else => inferExprReturnType(expr),
    };
}

/// Infer return type from an expression
fn inferExprReturnType(expr: ast.Node) ClosureReturnType {
    return switch (expr) {
        .constant => |c| switch (c.value) {
            .int => .integer,
            .float => .float,
            .string => .string,
            .bool => .boolean,
            .none => .void,
            else => .unknown,
        },
        .list => .list,
        .dict => .dict,
        .tuple => .tuple,
        .set => .unknown, // Set type
        .name => |n| {
            if (std.mem.eql(u8, n.id, "self")) return .self_type;
            if (std.mem.eql(u8, n.id, "True") or std.mem.eql(u8, n.id, "False")) return .boolean;
            if (std.mem.eql(u8, n.id, "None")) return .void;
            return .unknown;
        },
        .call => |call| {
            // Check if calling a known context manager method
            if (call.func.* == .attribute) {
                const attr = call.func.attribute;
                if (ContextManagerMethods.has(attr.attr)) {
                    return .context_manager;
                }
            }
            // Check if calling a known context manager function
            if (call.func.* == .name) {
                if (ContextManagerMethods.has(call.func.name.id)) {
                    return .context_manager;
                }
            }
            return .unknown;
        },
        .lambda => .callable,
        .binop => |op| {
            // Arithmetic ops typically return numeric
            return switch (op.op) {
                .Add, .Sub, .Mult, .Div, .FloorDiv, .Mod, .Pow => .unknown, // Could be int or float
                .BitOr, .BitXor, .BitAnd, .LShift, .RShift => .integer,
                else => .unknown,
            };
        },
        .compare => .boolean,
        .boolop => .boolean,
        .unaryop => |op| {
            if (op.op == .Not) return .boolean;
            return .unknown;
        },
        else => .unknown,
    };
}

/// Get the Zig type string for a closure return type
/// NOTE: anytype cannot be used as return type in Zig - use concrete types or PyValue
pub fn closureReturnTypeToZig(ret_type: ClosureReturnType) []const u8 {
    return switch (ret_type) {
        .void => "void",
        .context_manager => "runtime.PyValue", // Context managers resolved separately
        .integer => "i64",
        .float => "f64",
        .string => "[]const u8",
        .boolean => "bool",
        .list => "runtime.PyValue", // List element type varies
        .dict => "runtime.PyValue", // Dict key/value types vary
        .tuple => "runtime.PyValue", // Tuple field types vary
        .callable => "runtime.PyValue", // Function types vary
        .self_type => "runtime.PyValue", // Self type varies by class
        .unknown => "runtime.PyValue", // Fallback to dynamic type
    };
}

/// Check if a method name returns a context manager
pub fn isContextManagerMethod(method_name: []const u8) bool {
    return ContextManagerMethods.has(method_name);
}

/// Get the Zig type for a context manager method
pub fn getContextManagerType(method_name: []const u8) ?[]const u8 {
    return ContextManagerMethods.get(method_name);
}

// ============================================================================
// Variable Mutation Analysis - Determine var vs const for local variables
// ============================================================================
// Zig 0.15 requires `const` for variables that are never mutated.
// A variable needs `var` if:
// 1. It's reassigned after initial declaration (multiple assignments)
// 2. It's used in augmented assignment (+=, -=, etc.)
// 3. It's an iterator (mutated by .next() calls)
//
// Note: Dict/list method calls (.put(), .append()) don't require `var` -
// these methods take *Self and mutate through the pointer.

/// Analyze a function body for variable mutations
/// Returns a set of variable names that are mutated (need `var`)
pub fn analyzeMutatedVars(body: []const ast.Node) MutatedVarSet {
    var result = MutatedVarSet{};
    collectMutatedVars(body, &result, null);
    return result;
}

/// Set of mutated variable names (up to 64 variables)
pub const MutatedVarSet = struct {
    names: [64][]const u8 = undefined,
    count: usize = 0,

    pub fn add(self: *MutatedVarSet, name: []const u8) void {
        // Don't add duplicates
        for (self.names[0..self.count]) |existing| {
            if (std.mem.eql(u8, existing, name)) return;
        }
        if (self.count < 64) {
            self.names[self.count] = name;
            self.count += 1;
        }
    }

    pub fn contains(self: *const MutatedVarSet, name: []const u8) bool {
        for (self.names[0..self.count]) |existing| {
            if (std.mem.eql(u8, existing, name)) return true;
        }
        return false;
    }
};

/// Collect mutated variables from function body
/// first_assign tracks which variables have been seen (for detecting reassignment)
fn collectMutatedVars(body: []const ast.Node, result: *MutatedVarSet, first_assign: ?*MutatedVarSet) void {
    var seen = if (first_assign) |fa| fa.* else MutatedVarSet{};

    for (body) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                // Check for reassignment (variable assigned more than once)
                for (assign.targets) |target| {
                    if (target == .name) {
                        const name = target.name.id;
                        if (seen.contains(name)) {
                            // Reassigned - needs var
                            result.add(name);
                        } else {
                            seen.add(name);
                        }
                    }
                }
            },
            .aug_assign => |aug| {
                // Augmented assignment always needs var
                if (aug.target.* == .name) {
                    result.add(aug.target.name.id);
                }
            },
            .for_stmt => |for_stmt| {
                // Loop variable is reassigned each iteration
                if (for_stmt.target.* == .name) {
                    result.add(for_stmt.target.name.id);
                }
                // Recurse into body with current seen state
                collectMutatedVars(for_stmt.body, result, &seen);
                if (for_stmt.orelse_body) |orelse_body| {
                    collectMutatedVars(orelse_body, result, &seen);
                }
            },
            .while_stmt => |while_stmt| {
                collectMutatedVars(while_stmt.body, result, &seen);
                if (while_stmt.orelse_body) |orelse_body| {
                    collectMutatedVars(orelse_body, result, &seen);
                }
            },
            .if_stmt => |if_stmt| {
                collectMutatedVars(if_stmt.body, result, &seen);
                collectMutatedVars(if_stmt.else_body, result, &seen);
            },
            .try_stmt => |try_stmt| {
                collectMutatedVars(try_stmt.body, result, &seen);
                collectMutatedVars(try_stmt.else_body, result, &seen);
                collectMutatedVars(try_stmt.finalbody, result, &seen);
            },
            .with_stmt => |with_stmt| {
                collectMutatedVars(with_stmt.body, result, &seen);
            },
            .function_def => {
                // Don't recurse into nested function definitions -
                // they have their own scope
            },
            .class_def => {
                // Don't recurse into class definitions
            },
            else => {},
        }
    }
}

/// Check if a variable is mutated in a function body
pub fn isVarMutatedInBody(body: []const ast.Node, var_name: []const u8) bool {
    const mutated = analyzeMutatedVars(body);
    return mutated.contains(var_name);
}

// ============================================================================
// Precise Error Types - Generate error{KeyError,IndexError}!T not anyerror!T
// ============================================================================

/// Python exception types mapped to Zig error enum values
pub const PreciseError = enum {
    // Lookup errors
    KeyError, // dict[missing_key]
    IndexError, // list[out_of_bounds]
    AttributeError, // obj.missing_attr

    // Type errors
    TypeError, // type mismatch
    ValueError, // invalid value (e.g., int("abc"))

    // Arithmetic errors
    ZeroDivisionError, // x / 0
    OverflowError, // integer overflow

    // I/O errors
    FileNotFoundError, // open() missing file
    PermissionError, // access denied
    IOError, // general I/O

    // Runtime errors
    RuntimeError, // generic
    StopIteration, // iterator exhausted
    AssertionError, // assert failed
    NotImplementedError, // abstract method

    /// Generate Zig error set string from a slice of errors
    pub fn toErrorSet(errors: []const PreciseError) []const u8 {
        if (errors.len == 0) return "error{}";
        // For now, return a static representation
        // In practice, we'd build this dynamically
        return switch (errors[0]) {
            .KeyError => "error{KeyError}",
            .IndexError => "error{IndexError}",
            .ValueError => "error{ValueError}",
            .TypeError => "error{TypeError}",
            .ZeroDivisionError => "error{DivisionByZero}",
            .OverflowError => "error{Overflow}",
            .FileNotFoundError => "error{FileNotFound}",
            .AssertionError => "error{AssertionFailed}",
            else => "error{RuntimeError}",
        };
    }
};

/// Packed error set using bit flags for efficient storage (16 errors = 16 bits)
pub const ErrorSet = packed struct {
    KeyError: bool = false,
    IndexError: bool = false,
    AttributeError: bool = false,
    TypeError: bool = false,
    ValueError: bool = false,
    ZeroDivisionError: bool = false,
    OverflowError: bool = false,
    FileNotFoundError: bool = false,
    PermissionError: bool = false,
    IOError: bool = false,
    RuntimeError: bool = false,
    StopIteration: bool = false,
    AssertionError: bool = false,
    NotImplementedError: bool = false,
    _padding: u2 = 0,

    pub fn isEmpty(self: ErrorSet) bool {
        return @as(u16, @bitCast(self)) == 0;
    }

    pub fn merge(self: ErrorSet, other: ErrorSet) ErrorSet {
        return @bitCast(@as(u16, @bitCast(self)) | @as(u16, @bitCast(other)));
    }

    /// Generate Zig error set string like "error{KeyError,IndexError}"
    pub fn toZigErrorSet(self: ErrorSet, buf: []u8) []const u8 {
        if (self.isEmpty()) return "error{}";
        var pos: usize = 0;
        const prefix = "error{";
        @memcpy(buf[pos..][0..prefix.len], prefix);
        pos += prefix.len;

        var first = true;
        if (self.KeyError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "KeyError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.IndexError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "IndexError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.ValueError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "ValueError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.TypeError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "TypeError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.ZeroDivisionError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "DivisionByZero";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.FileNotFoundError or self.IOError or self.PermissionError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "IoError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.AssertionError) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "AssertionFailed";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        if (self.RuntimeError or self.NotImplementedError or self.AttributeError or self.OverflowError or self.StopIteration) {
            if (!first) {
                buf[pos] = ',';
                pos += 1;
            }
            const s = "RuntimeError";
            @memcpy(buf[pos..][0..s.len], s);
            pos += s.len;
            first = false;
        }
        buf[pos] = '}';
        pos += 1;
        return buf[0..pos];
    }
};

// ============================================================================
// SIMD Vectorization Analysis
// ============================================================================

/// SIMD vectorization info for list comprehensions
pub const SimdInfo = struct {
    /// Can this comprehension be vectorized?
    vectorizable: bool = false,
    /// Element type (i64, f64)
    element_type: SimdElementType = .i64,
    /// The vectorizable operation
    op: SimdOp = .none,
    /// Vector width to use (4, 8, 16)
    vector_width: u8 = 8,
    /// Is the source a contiguous range?
    is_range: bool = false,
    /// Static range bounds (if known)
    range_start: ?i64 = null,
    range_end: ?i64 = null,
};

pub const SimdElementType = enum { i64, f64, i32, f32 };

pub const SimdOp = enum {
    none,
    // Arithmetic
    add, // x + c or c + x
    sub, // x - c or c - x
    mul, // x * c or c * x
    div, // x / c
    neg, // -x
    // Bitwise
    bit_and,
    bit_or,
    bit_xor,
    shl, // x << c
    shr, // x >> c
    // Compound
    mul_add, // x * a + b (FMA)
    square, // x * x
};

/// Analyze a list comprehension for SIMD vectorization potential
pub fn analyzeListCompForSimd(listcomp: ast.Node.ListComp) SimdInfo {
    var info = SimdInfo{};

    // Must have exactly one generator with no conditions
    if (listcomp.generators.len != 1) return info;
    const gen = listcomp.generators[0];
    if (gen.ifs.len > 0) return info; // Conditionals break vectorization

    // Check if iterating over range()
    if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
        if (std.mem.eql(u8, gen.iter.call.func.name.id, "range")) {
            info.is_range = true;
            const args = gen.iter.call.args;
            // Extract static bounds if possible
            if (args.len >= 1 and args[0] == .constant and args[0].constant.value == .int) {
                if (args.len == 1) {
                    info.range_start = 0;
                    info.range_end = args[0].constant.value.int;
                } else if (args.len >= 2 and args[1] == .constant and args[1].constant.value == .int) {
                    info.range_start = args[0].constant.value.int;
                    info.range_end = args[1].constant.value.int;
                }
            }
        }
    }

    // Target must be a simple name
    if (gen.target.* != .name) return info;
    const loop_var = gen.target.name.id;

    // Analyze the element expression
    const elt = listcomp.elt.*;
    const op_info = analyzeSimdExpr(elt, loop_var);
    if (op_info.op == .none) return info;

    info.vectorizable = true;
    info.op = op_info.op;
    info.element_type = op_info.element_type;

    // Choose vector width based on element type
    info.vector_width = switch (info.element_type) {
        .i64, .f64 => 4, // 256-bit vectors / 64-bit = 4 elements
        .i32, .f32 => 8, // 256-bit vectors / 32-bit = 8 elements
    };

    return info;
}

const SimdExprInfo = struct {
    op: SimdOp = .none,
    element_type: SimdElementType = .i64,
    constant: ?i64 = null,
};

/// Analyze expression to determine if it's a simple vectorizable op
fn analyzeSimdExpr(expr: ast.Node, loop_var: []const u8) SimdExprInfo {
    var info = SimdExprInfo{};

    switch (expr) {
        .name => |n| {
            // Just the loop variable: identity (can still vectorize as copy)
            if (std.mem.eql(u8, n.id, loop_var)) {
                info.op = .add; // x + 0 is identity
                info.constant = 0;
                return info;
            }
        },
        .binop => |b| {
            // Check for simple patterns: x op const, const op x
            const left_is_var = b.left.* == .name and std.mem.eql(u8, b.left.name.id, loop_var);
            const right_is_var = b.right.* == .name and std.mem.eql(u8, b.right.name.id, loop_var);
            const left_is_const = b.left.* == .constant and b.left.constant.value == .int;
            const right_is_const = b.right.* == .constant and b.right.constant.value == .int;

            // x * x pattern (square)
            if (left_is_var and right_is_var and b.op == .Mult) {
                info.op = .square;
                return info;
            }

            // x op const or const op x
            if ((left_is_var and right_is_const) or (left_is_const and right_is_var)) {
                const c = if (right_is_const) b.right.constant.value.int else b.left.constant.value.int;
                info.constant = c;

                info.op = switch (b.op) {
                    .Add => .add,
                    .Sub => if (left_is_var) .sub else .none, // const - x not simple
                    .Mult => .mul,
                    .Div, .FloorDiv => if (left_is_var) .div else .none,
                    .BitOr => .bit_or,
                    .BitAnd => .bit_and,
                    .BitXor => .bit_xor,
                    .LShift => if (left_is_var) .shl else .none,
                    .RShift => if (left_is_var) .shr else .none,
                    else => .none,
                };
                return info;
            }
        },
        .unaryop => |u| {
            // -x pattern
            if (u.op == .USub and u.operand.* == .name and std.mem.eql(u8, u.operand.name.id, loop_var)) {
                info.op = .neg;
                return info;
            }
        },
        else => {},
    }

    return info;
}

// ============================================================================
// Parallelization Analysis
// ============================================================================

/// Info about whether a list comprehension can be parallelized
pub const ParallelInfo = struct {
    /// Can this be safely parallelized?
    parallelizable: bool = false,
    /// Is it a large enough workload to benefit from parallelization?
    worth_parallelizing: bool = false,
    /// Minimum threshold for parallel (smaller runs sequentially)
    min_parallel_size: usize = 1024,
    /// Operation type (for runtime.parallel)
    op: SimdOp = .none,
};

/// Check if a list comprehension can be safely parallelized
/// Requires: pure element expression, no loop-carried dependencies
pub fn analyzeListCompForParallel(listcomp: ast.Node.ListComp) ParallelInfo {
    var info = ParallelInfo{};

    // Must have exactly one generator
    if (listcomp.generators.len != 1) return info;
    const gen = listcomp.generators[0];

    // Conditionals make parallelization complex (varying output size)
    if (gen.ifs.len > 0) return info;

    // Target must be simple name
    if (gen.target.* != .name) return info;
    const loop_var = gen.target.name.id;

    // Check if element expression is pure and parallelizable
    if (!isParallelizableExpr(listcomp.elt.*, loop_var)) return info;

    // Check for large range (worth parallelizing)
    if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
        if (std.mem.eql(u8, gen.iter.call.func.name.id, "range")) {
            const args = gen.iter.call.args;
            if (args.len >= 1 and args[0] == .constant and args[0].constant.value == .int) {
                const end_val = if (args.len == 1)
                    args[0].constant.value.int
                else if (args.len >= 2 and args[1] == .constant and args[1].constant.value == .int)
                    args[1].constant.value.int
                else
                    0;
                const start_val: i64 = if (args.len >= 2 and args[0] == .constant and args[0].constant.value == .int)
                    args[0].constant.value.int
                else
                    0;

                const size = end_val - start_val;
                info.worth_parallelizing = size >= info.min_parallel_size;
            }
        }
    }

    // Get the operation type
    const simd_info = analyzeSimdExpr(listcomp.elt.*, loop_var);
    info.op = simd_info.op;
    info.parallelizable = simd_info.op != .none;

    return info;
}

/// Check if expression is safe to parallelize (no side effects, no shared state)
fn isParallelizableExpr(expr: ast.Node, loop_var: []const u8) bool {
    return switch (expr) {
        .name => |n| std.mem.eql(u8, n.id, loop_var), // Only loop var is safe
        .constant => true,
        .binop => |b| isParallelizableExpr(b.left.*, loop_var) and isParallelizableExpr(b.right.*, loop_var),
        .unaryop => |u| isParallelizableExpr(u.operand.*, loop_var),
        // Function calls are NOT parallelizable (might have side effects)
        .call => false,
        // Attribute access might access shared state
        .attribute => false,
        // Subscript might access shared state
        .subscript => false,
        else => false,
    };
}

/// Call graph built from module analysis
pub const CallGraph = struct {
    /// Map from function name to its traits
    functions: hashmap_helper.StringHashMap(FunctionTraits),
    /// Map from class name to its methods
    classes: hashmap_helper.StringHashMap([]const []const u8),
    /// Global variables that are modified
    modified_globals: hashmap_helper.StringHashMap(void),
    /// Allocator for internal storage
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CallGraph {
        return .{
            .functions = hashmap_helper.StringHashMap(FunctionTraits).init(allocator),
            .classes = hashmap_helper.StringHashMap([]const []const u8).init(allocator),
            .modified_globals = hashmap_helper.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CallGraph) void {
        var it = self.functions.iterator();
        while (it.next()) |entry| {
            var traits = entry.value_ptr.*;
            traits.deinit(self.allocator);
        }
        self.functions.deinit();

        var class_it = self.classes.iterator();
        while (class_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.classes.deinit();

        self.modified_globals.deinit();
    }

    /// Get traits for a function
    pub fn getTraits(self: *const CallGraph, name: []const u8) ?FunctionTraits {
        return self.functions.get(name);
    }

    /// Check if a function is reachable from entry points
    pub fn isReachable(self: *const CallGraph, name: []const u8) bool {
        if (self.functions.get(name)) |traits| {
            return traits.is_called;
        }
        return false;
    }

    /// Get all functions called by a function (transitive)
    pub fn getTransitiveCalls(self: *const CallGraph, name: []const u8, allocator: std.mem.Allocator) ![]FunctionRef {
        var visited = hashmap_helper.StringHashMap(void).init(allocator);
        defer visited.deinit();

        var result = std.ArrayList(FunctionRef){};
        errdefer result.deinit(allocator);

        try self.collectTransitiveCalls(name, &visited, &result, allocator);

        return result.toOwnedSlice(allocator);
    }

    fn collectTransitiveCalls(
        self: *const CallGraph,
        name: []const u8,
        visited: *hashmap_helper.StringHashMap(void),
        result: *std.ArrayList(FunctionRef),
        allocator: std.mem.Allocator,
    ) !void {
        if (visited.contains(name)) return;
        try visited.put(name, {});

        if (self.functions.get(name)) |traits| {
            for (traits.calls) |call| {
                try result.append(allocator, call);
                try self.collectTransitiveCalls(call.name, visited, result, allocator);
            }
        }
    }
};

/// Analyzer context for building traits
const AnalyzerContext = struct {
    allocator: std.mem.Allocator,
    current_func: ?[]const u8 = null,
    current_class: ?[]const u8 = null,
    current_module: []const u8 = "",
    scope_vars: hashmap_helper.StringHashMap(void),
    param_names: []const []const u8 = &.{},
    param_mutations: std.ArrayList(bool),
    calls: std.ArrayList(FunctionRef),
    captured: std.ArrayList([]const u8),

    // Trait flags
    has_await: bool = false,
    has_io: bool = false,
    can_error: bool = false,
    needs_allocator: bool = false,
    is_pure: bool = true,
    is_tail_recursive: bool = false,
    is_generator: bool = false,
    modifies_globals: bool = false,
    reads_globals: bool = false,
    op_count: usize = 0,
    await_count: usize = 0,
    has_loops: bool = false,

    // Escape analysis
    escaping_params: std.ArrayList(bool),
    escaping_locals: std.ArrayList([]const u8),
    local_vars: hashmap_helper.StringHashMap(void), // Track locally defined vars
    return_aliases_param: ?usize = null,

    // Precise error types
    error_types: ErrorSet = .{},

    // ========== PARAMETER USAGE ANALYSIS ==========
    /// Track which parameters are actually used in the body
    params_used: std.ArrayList(bool),

    // ========== BLOCK-SCOPED VARIABLE ANALYSIS ==========
    /// Current block scope depth (0 = function level, >0 = inside for/if/try/with)
    block_scope_depth: usize = 0,
    /// Variables declared at each scope depth (for tracking block-scoped vars)
    vars_at_depth: hashmap_helper.StringHashMap(usize),
    /// Variables declared in blocks that are used outside their declaring block
    escaping_block_vars: std.ArrayList([]const u8),
    /// Variables declared in blocks that are NOT used outside (truly block-scoped)
    block_scoped_vars: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) AnalyzerContext {
        return .{
            .allocator = allocator,
            .scope_vars = hashmap_helper.StringHashMap(void).init(allocator),
            .param_mutations = std.ArrayList(bool){},
            .calls = std.ArrayList(FunctionRef){},
            .captured = std.ArrayList([]const u8){},
            .escaping_params = std.ArrayList(bool){},
            .escaping_locals = std.ArrayList([]const u8){},
            .local_vars = hashmap_helper.StringHashMap(void).init(allocator),
            .params_used = std.ArrayList(bool){},
            .vars_at_depth = hashmap_helper.StringHashMap(usize).init(allocator),
            .escaping_block_vars = std.ArrayList([]const u8){},
            .block_scoped_vars = std.ArrayList([]const u8){},
        };
    }

    pub fn deinit(self: *AnalyzerContext) void {
        self.scope_vars.deinit();
        self.param_mutations.deinit(self.allocator);
        self.calls.deinit(self.allocator);
        self.captured.deinit(self.allocator);
        self.escaping_params.deinit(self.allocator);
        self.escaping_locals.deinit(self.allocator);
        self.local_vars.deinit();
        self.params_used.deinit(self.allocator);
        self.vars_at_depth.deinit();
        self.escaping_block_vars.deinit(self.allocator);
        self.block_scoped_vars.deinit(self.allocator);
    }

    pub fn reset(self: *AnalyzerContext) void {
        self.scope_vars.clearRetainingCapacity();
        self.param_mutations.clearRetainingCapacity();
        self.calls.clearRetainingCapacity();
        self.captured.clearRetainingCapacity();
        self.escaping_params.clearRetainingCapacity();
        self.escaping_locals.clearRetainingCapacity();
        self.local_vars.clearRetainingCapacity();
        self.params_used.clearRetainingCapacity();
        self.vars_at_depth.clearRetainingCapacity();
        self.escaping_block_vars.clearRetainingCapacity();
        self.block_scoped_vars.clearRetainingCapacity();
        self.has_await = false;
        self.has_io = false;
        self.can_error = false;
        self.needs_allocator = false;
        self.is_pure = true;
        self.is_tail_recursive = false;
        self.is_generator = false;
        self.modifies_globals = false;
        self.reads_globals = false;
        self.op_count = 0;
        self.await_count = 0;
        self.has_loops = false;
        self.return_aliases_param = null;
        self.error_types = .{};
        self.block_scope_depth = 0;
    }

    /// Mark a parameter as used
    pub fn markParamUsed(self: *AnalyzerContext, param_name: []const u8) !void {
        for (self.param_names, 0..) |name, i| {
            if (std.mem.eql(u8, name, param_name)) {
                // Ensure params_used array is large enough
                while (self.params_used.items.len <= i) {
                    try self.params_used.append(self.allocator, false);
                }
                self.params_used.items[i] = true;
                return;
            }
        }
    }

    /// Declare a variable at current block depth
    pub fn declareVarAtDepth(self: *AnalyzerContext, var_name: []const u8) !void {
        try self.vars_at_depth.put(var_name, self.block_scope_depth);
    }

    /// Check if a variable use escapes its declaring block
    pub fn checkVarEscape(self: *AnalyzerContext, var_name: []const u8) !void {
        if (self.vars_at_depth.get(var_name)) |decl_depth| {
            // Variable was declared in a block
            if (decl_depth > 0 and self.block_scope_depth < decl_depth) {
                // Used at a shallower depth than declared = escape
                // Add to escaping_block_vars if not already there
                for (self.escaping_block_vars.items) |v| {
                    if (std.mem.eql(u8, v, var_name)) return;
                }
                try self.escaping_block_vars.append(self.allocator, var_name);
            }
        }
    }

    /// Enter a block scope (for/if/try/with)
    pub fn enterBlockScope(self: *AnalyzerContext) void {
        self.block_scope_depth += 1;
    }

    /// Exit a block scope
    pub fn exitBlockScope(self: *AnalyzerContext) void {
        if (self.block_scope_depth > 0) {
            self.block_scope_depth -= 1;
        }
    }
};

/// I/O function names that trigger state machine async (actual async I/O operations)
/// NOTE: Excludes print (sync), includes only operations that benefit from kqueue/epoll
const IoFunctions = std.StaticStringMap(void).initComptime(.{
    // File I/O (async benefits from OS-level polling)
    .{ "input", {} },  // stdin waits for user input
    .{ "open", {} },
    .{ "read", {} },
    .{ "write", {} },
    .{ "close", {} },
    // Network/HTTP
    .{ "get", {} },
    .{ "post", {} },
    .{ "put", {} },
    .{ "delete", {} },
    .{ "patch", {} },
    .{ "request", {} },
    .{ "fetch", {} },
    .{ "connect", {} },
    .{ "send", {} },
    .{ "recv", {} },
    .{ "sendall", {} },
    .{ "recvfrom", {} },
    .{ "sendto", {} },
    // Async I/O (actual I/O operations, not coordination primitives)
    .{ "sleep", {} },  // Timer I/O via kqueue/epoll
    // Subprocess
    .{ "call", {} },
    .{ "check_call", {} },
    .{ "check_output", {} },
    .{ "communicate", {} },
    .{ "Popen", {} },
});

/// I/O method names (additional methods not in IoFunctions)
const IoMethods = std.StaticStringMap(void).initComptime(.{
    .{ "flush", {} },
    .{ "readline", {} },
    .{ "readlines", {} },
    .{ "writelines", {} },
    .{ "json", {} }, // response.json()
    .{ "text", {} }, // response.text()
});

/// List mutation methods (make function impure)
const ListMutationMethods = std.StaticStringMap(void).initComptime(.{
    .{ "append", {} },
    .{ "extend", {} },
    .{ "insert", {} },
    .{ "pop", {} },
    .{ "remove", {} },
    .{ "clear", {} },
    .{ "sort", {} },
    .{ "reverse", {} },
});

/// Functions that can raise errors - maps to specific error types for precise error unions
const ErrorFunctions = std.StaticStringMap(ErrorSet).initComptime(.{
    .{ "raise", ErrorSet{ .RuntimeError = true } }, // Generic raise
    .{ "assert", ErrorSet{ .AssertionError = true } },
    .{ "open", ErrorSet{ .FileNotFoundError = true, .PermissionError = true, .IOError = true } },
    .{ "int", ErrorSet{ .ValueError = true } }, // int("abc") raises ValueError
    .{ "float", ErrorSet{ .ValueError = true } },
    .{ "eval", ErrorSet{ .RuntimeError = true } },
    .{ "exec", ErrorSet{ .RuntimeError = true } },
    .{ "next", ErrorSet{ .StopIteration = true } },
    .{ "getattr", ErrorSet{ .AttributeError = true } },
});

/// Functions that require allocator
const AllocatorFunctions = std.StaticStringMap(void).initComptime(.{
    .{ "list", {} },
    .{ "dict", {} },
    .{ "set", {} },
    .{ "str", {} },
    .{ "bytes", {} },
    .{ "bytearray", {} },
    .{ "range", {} },
    .{ "map", {} },
    .{ "filter", {} },
    .{ "sorted", {} },
    .{ "reversed", {} },
    .{ "enumerate", {} },
    .{ "zip", {} },
});

/// Build call graph from a module
pub fn buildCallGraph(module: ast.Node.Module, allocator: std.mem.Allocator) !CallGraph {
    var graph = CallGraph.init(allocator);
    errdefer graph.deinit();

    var ctx = AnalyzerContext.init(allocator);
    defer ctx.deinit();

    // First pass: collect all function definitions
    for (module.body) |stmt| {
        try collectDefinitions(stmt, &graph, &ctx);
    }

    // Second pass: analyze each function's traits
    for (module.body) |stmt| {
        try analyzeStatement(stmt, &graph, &ctx);
    }

    // Third pass: mark reachable functions from entry points
    try markReachable(&graph, allocator);

    return graph;
}

/// Collect function and class definitions
fn collectDefinitions(stmt: ast.Node, graph: *CallGraph, ctx: *AnalyzerContext) !void {
    switch (stmt) {
        .function_def => |func| {
            const ref = FunctionRef{
                .module = ctx.current_module,
                .name = func.name,
                .class_name = ctx.current_class,
            };
            try graph.functions.put(func.name, FunctionTraits{ .ref = ref });
        },
        .class_def => |class| {
            var methods = std.ArrayList([]const u8){};
            errdefer methods.deinit(ctx.allocator);

            const old_class = ctx.current_class;
            ctx.current_class = class.name;
            defer ctx.current_class = old_class;

            for (class.body) |body_stmt| {
                if (body_stmt == .function_def) {
                    try methods.append(ctx.allocator, body_stmt.function_def.name);
                    try collectDefinitions(body_stmt, graph, ctx);
                }
            }

            try graph.classes.put(class.name, try methods.toOwnedSlice(ctx.allocator));
        },
        else => {},
    }
}

/// Analyze a statement for traits
fn analyzeStatement(stmt: ast.Node, graph: *CallGraph, ctx: *AnalyzerContext) !void {
    switch (stmt) {
        .function_def => |func| {
            ctx.reset();
            ctx.current_func = func.name;

            // Set up parameter tracking
            var param_names = std.ArrayList([]const u8){};
            defer param_names.deinit(ctx.allocator);

            for (func.args) |arg| {
                try param_names.append(ctx.allocator, arg.name);
                try ctx.scope_vars.put(arg.name, {});
                try ctx.param_mutations.append(ctx.allocator, false);
                try ctx.escaping_params.append(ctx.allocator, false); // Initialize escape tracking
            }
            ctx.param_names = param_names.items;

            // Analyze function body
            for (func.body) |body_stmt| {
                try analyzeStmtForTraits(body_stmt, ctx);
            }

            // Check for tail recursion (last statement is return with recursive call)
            if (func.body.len > 0) {
                ctx.is_tail_recursive = isTailRecursive(func.body[func.body.len - 1], func.name);
            }

            // Build traits
            var traits = graph.functions.get(func.name) orelse FunctionTraits{
                .ref = .{ .module = ctx.current_module, .name = func.name, .class_name = ctx.current_class },
            };

            traits.has_await = ctx.has_await;
            traits.has_io = ctx.has_io;
            traits.can_error = ctx.can_error;
            traits.needs_allocator = ctx.needs_allocator;
            traits.is_pure = ctx.is_pure and !ctx.has_io and !ctx.modifies_globals;
            traits.is_tail_recursive = ctx.is_tail_recursive;
            traits.is_generator = ctx.is_generator;
            traits.modifies_globals = ctx.modifies_globals;
            traits.reads_globals = ctx.reads_globals;
            traits.async_complexity = computeAsyncComplexity(ctx);

            // Copy mutation info
            if (ctx.param_mutations.items.len > 0) {
                traits.mutates_params = try ctx.allocator.dupe(bool, ctx.param_mutations.items);
            }

            // Copy calls
            if (ctx.calls.items.len > 0) {
                traits.calls = try ctx.allocator.dupe(FunctionRef, ctx.calls.items);
            }

            // Copy captured vars
            if (ctx.captured.items.len > 0) {
                traits.captured_vars = try ctx.allocator.dupe([]const u8, ctx.captured.items);
            }

            // Copy escape analysis results
            if (ctx.escaping_params.items.len > 0) {
                traits.escaping_params = try ctx.allocator.dupe(bool, ctx.escaping_params.items);
            }
            if (ctx.escaping_locals.items.len > 0) {
                traits.escaping_locals = try ctx.allocator.dupe([]const u8, ctx.escaping_locals.items);
            }
            traits.return_aliases_param = ctx.return_aliases_param;

            // Copy precise error types
            traits.error_types = ctx.error_types;

            // Copy parameter usage analysis
            if (ctx.params_used.items.len > 0) {
                traits.params_used_in_body = try ctx.allocator.dupe(bool, ctx.params_used.items);
            }

            // Copy block-scoped variable analysis
            if (ctx.escaping_block_vars.items.len > 0) {
                traits.escaping_block_vars = try ctx.allocator.dupe([]const u8, ctx.escaping_block_vars.items);
            }
            if (ctx.block_scoped_vars.items.len > 0) {
                traits.block_scoped_vars = try ctx.allocator.dupe([]const u8, ctx.block_scoped_vars.items);
            }

            // Analyze heterogeneous list patterns
            const het_analysis = analyzeHeterogeneousLists(ctx.allocator, func.body);
            traits.heterogeneous_vars = het_analysis.heterogeneous_vars;
            traits.list_aliases = het_analysis.list_aliases;

            try graph.functions.put(func.name, traits);
        },
        .class_def => |class| {
            const old_class = ctx.current_class;
            ctx.current_class = class.name;
            defer ctx.current_class = old_class;

            for (class.body) |body_stmt| {
                try analyzeStatement(body_stmt, graph, ctx);
            }
        },
        .assign => |assign| {
            // Track global modifications at module level
            if (ctx.current_func == null) {
                for (assign.targets) |target| {
                    if (target == .name) {
                        try graph.modified_globals.put(target.name.id, {});
                    }
                }
            }
        },
        else => {},
    }
}

/// Analyze a statement for trait flags
fn analyzeStmtForTraits(stmt: ast.Node, ctx: *AnalyzerContext) !void {
    switch (stmt) {
        .expr_stmt => |expr| {
            try analyzeExprForTraits(expr.value.*, ctx);
        },
        .assign => |assign| {
            // Check for parameter mutation via attribute/subscript assignment
            for (assign.targets) |target| {
                try checkMutation(target, ctx);
                // Track local variable definitions with block scope depth
                if (target == .name) {
                    try ctx.local_vars.put(target.name.id, {});
                    try ctx.declareVarAtDepth(target.name.id);
                }
                // Check if storing param into global (escape)
                if (target == .name and !ctx.scope_vars.contains(target.name.id)) {
                    // Global assignment - check if value is a param
                    try markEscapingExpr(assign.value.*, ctx);
                }
            }
            try analyzeExprForTraits(assign.value.*, ctx);
            ctx.op_count += 1;
        },
        .aug_assign => |aug| {
            try checkMutation(aug.target.*, ctx);
            try analyzeExprForTraits(aug.value.*, ctx);
            ctx.op_count += 1;
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                try analyzeExprForTraits(val.*, ctx);
                // Mark returned values as escaping
                try markEscapingExpr(val.*, ctx);
                // Check if return directly aliases a param
                if (val.* == .name) {
                    for (ctx.param_names, 0..) |param, i| {
                        if (std.mem.eql(u8, param, val.name.id)) {
                            ctx.return_aliases_param = i;
                            break;
                        }
                    }
                }
            }
            ctx.op_count += 1;
        },
        .raise_stmt => {
            ctx.can_error = true;
            ctx.error_types.RuntimeError = true; // Default, could be refined by analyzing raised exception
            ctx.is_pure = false;
        },
        .if_stmt => |if_stmt| {
            try analyzeExprForTraits(if_stmt.condition.*, ctx);
            ctx.enterBlockScope();
            for (if_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            ctx.enterBlockScope();
            for (if_stmt.else_body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            ctx.op_count += 2;
        },
        .while_stmt => |while_stmt| {
            ctx.has_loops = true;
            try analyzeExprForTraits(while_stmt.condition.*, ctx);
            ctx.enterBlockScope();
            for (while_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            ctx.op_count += 5;
        },
        .for_stmt => |for_stmt| {
            ctx.has_loops = true;
            try analyzeExprForTraits(for_stmt.iter.*, ctx);
            ctx.enterBlockScope();
            // Track loop variable at block scope
            if (for_stmt.target.* == .name) {
                try ctx.declareVarAtDepth(for_stmt.target.name.id);
            }
            for (for_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            ctx.op_count += 5;
        },
        .try_stmt => |try_stmt| {
            ctx.can_error = true;
            ctx.enterBlockScope();
            for (try_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            for (try_stmt.handlers) |h| {
                ctx.enterBlockScope();
                for (h.body) |s| try analyzeStmtForTraits(s, ctx);
                ctx.exitBlockScope();
            }
            ctx.enterBlockScope();
            for (try_stmt.else_body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
            ctx.enterBlockScope();
            for (try_stmt.finalbody) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
        },
        .with_stmt => |with_stmt| {
            try analyzeExprForTraits(with_stmt.context_expr.*, ctx);
            ctx.enterBlockScope();
            for (with_stmt.body) |s| try analyzeStmtForTraits(s, ctx);
            ctx.exitBlockScope();
        },
        .function_def => {
            // Nested function - check for captures
            // This is handled separately
        },
        .yield_stmt, .yield_from_stmt => {
            ctx.is_generator = true;
        },
        else => {
            ctx.op_count += 1;
        },
    }
}

/// Analyze an expression for trait flags
fn analyzeExprForTraits(expr: ast.Node, ctx: *AnalyzerContext) error{OutOfMemory}!void {
    switch (expr) {
        .await_expr => |await_expr| {
            ctx.has_await = true;
            ctx.await_count += 1;
            try analyzeExprForTraits(await_expr.value.*, ctx);
        },
        .yield_stmt => {
            ctx.is_generator = true;
        },
        .yield_from_stmt => {
            ctx.is_generator = true;
        },
        .call => |call| {
            // Check function name for traits
            if (call.func.* == .name) {
                const func_name = call.func.name.id;

                // Check if it's a recursive call
                if (ctx.current_func != null and std.mem.eql(u8, func_name, ctx.current_func.?)) {
                    // Self-recursive call
                }

                // I/O functions
                if (IoFunctions.has(func_name)) {
                    ctx.has_io = true;
                    ctx.is_pure = false;
                }

                // Error-raising functions with precise error types
                if (ErrorFunctions.get(func_name)) |errors| {
                    ctx.can_error = true;
                    ctx.error_types = ctx.error_types.merge(errors);
                }

                // Allocator-requiring functions
                if (AllocatorFunctions.has(func_name)) {
                    ctx.needs_allocator = true;
                }

                // Record call
                try ctx.calls.append(ctx.allocator, .{
                    .module = "",
                    .name = func_name,
                    .class_name = null,
                });
            } else if (call.func.* == .attribute) {
                const attr = call.func.attribute;
                const method_name = attr.attr;

                // I/O methods (check both IoFunctions and IoMethods)
                if (IoFunctions.has(method_name) or IoMethods.has(method_name)) {
                    ctx.has_io = true;
                    ctx.is_pure = false;
                }

                // Mutating list methods
                if (ListMutationMethods.has(method_name)) {
                    ctx.is_pure = false;
                    // Check if mutating a parameter
                    if (attr.value.* == .name) {
                        try checkParamMutation(attr.value.name.id, ctx);
                    }
                }

                try analyzeExprForTraits(attr.value.*, ctx);
            }

            // Analyze arguments
            for (call.args) |arg| {
                try analyzeExprForTraits(arg, ctx);
            }
            ctx.op_count += 2;
        },
        .name => |n| {
            // Track parameter usage
            try ctx.markParamUsed(n.id);

            // Check if variable escapes its declaring block
            try ctx.checkVarEscape(n.id);

            // Check if accessing variable from outer scope (closure capture)
            if (!ctx.scope_vars.contains(n.id)) {
                // Could be a captured variable or global
                try ctx.captured.append(ctx.allocator, n.id);
                ctx.reads_globals = true;
            }
        },
        .binop => |binop| {
            try analyzeExprForTraits(binop.left.*, ctx);
            try analyzeExprForTraits(binop.right.*, ctx);
            ctx.op_count += 1;
        },
        .unaryop => |unary| {
            try analyzeExprForTraits(unary.operand.*, ctx);
            ctx.op_count += 1;
        },
        .compare => |comp| {
            try analyzeExprForTraits(comp.left.*, ctx);
            for (comp.comparators) |c| {
                try analyzeExprForTraits(c, ctx);
            }
            ctx.op_count += 1;
        },
        .boolop => |boolop| {
            for (boolop.values) |val| {
                try analyzeExprForTraits(val, ctx);
            }
        },
        .subscript => |sub| {
            try analyzeExprForTraits(sub.value.*, ctx);
            switch (sub.slice) {
                .index => |idx| {
                    try analyzeExprForTraits(idx.*, ctx);
                    // Subscript with index can raise KeyError (dict) or IndexError (list)
                    // We conservatively mark both since we don't track types here
                    ctx.can_error = true;
                    ctx.error_types.KeyError = true;
                    ctx.error_types.IndexError = true;
                },
                .slice => |rng| {
                    if (rng.lower) |l| try analyzeExprForTraits(l.*, ctx);
                    if (rng.upper) |u| try analyzeExprForTraits(u.*, ctx);
                    if (rng.step) |st| try analyzeExprForTraits(st.*, ctx);
                    // Slice can raise IndexError for invalid ranges
                    ctx.can_error = true;
                    ctx.error_types.IndexError = true;
                },
            }
            ctx.op_count += 1;
        },
        .attribute => |attr| {
            try analyzeExprForTraits(attr.value.*, ctx);
            ctx.op_count += 1;
        },
        .list => |list| {
            ctx.needs_allocator = true;
            for (list.elts) |elt| {
                try analyzeExprForTraits(elt, ctx);
            }
            ctx.op_count += 1;
        },
        .dict => |dict| {
            ctx.needs_allocator = true;
            for (dict.keys) |key| {
                try analyzeExprForTraits(key, ctx);
            }
            for (dict.values) |val| {
                try analyzeExprForTraits(val, ctx);
            }
            ctx.op_count += 1;
        },
        .tuple => |tuple| {
            for (tuple.elts) |elt| {
                try analyzeExprForTraits(elt, ctx);
            }
        },
        .if_expr => |tern| {
            try analyzeExprForTraits(tern.condition.*, ctx);
            try analyzeExprForTraits(tern.body.*, ctx);
            try analyzeExprForTraits(tern.orelse_value.*, ctx);
        },
        .listcomp, .dictcomp, .genexp => {
            ctx.needs_allocator = true;
            ctx.has_loops = true;
        },
        .lambda => |lam| {
            try analyzeExprForTraits(lam.body.*, ctx);
        },
        else => {},
    }
}

/// Check if a target expression mutates a parameter
fn checkMutation(target: ast.Node, ctx: *AnalyzerContext) !void {
    switch (target) {
        .attribute => |attr| {
            if (attr.value.* == .name) {
                try checkParamMutation(attr.value.name.id, ctx);
            }
        },
        .subscript => |sub| {
            if (sub.value.* == .name) {
                try checkParamMutation(sub.value.name.id, ctx);
            }
        },
        .name => |n| {
            // Direct reassignment of parameter
            try checkParamMutation(n.id, ctx);
        },
        else => {},
    }
}

/// Check if name is a parameter and mark it as mutated
fn checkParamMutation(name: []const u8, ctx: *AnalyzerContext) !void {
    for (ctx.param_names, 0..) |param, i| {
        if (std.mem.eql(u8, param, name)) {
            if (i < ctx.param_mutations.items.len) {
                ctx.param_mutations.items[i] = true;
            }
            ctx.is_pure = false;
            return;
        }
    }
}

/// Mark expression as escaping (returned, stored globally, passed to external func)
fn markEscapingExpr(expr: ast.Node, ctx: *AnalyzerContext) !void {
    switch (expr) {
        .name => |n| {
            // Check if it's a param
            for (ctx.param_names, 0..) |param, i| {
                if (std.mem.eql(u8, param, n.id)) {
                    if (i < ctx.escaping_params.items.len) {
                        ctx.escaping_params.items[i] = true;
                    }
                    return;
                }
            }
            // Check if it's a local var
            if (ctx.local_vars.contains(n.id)) {
                // Check if already marked
                for (ctx.escaping_locals.items) |local| {
                    if (std.mem.eql(u8, local, n.id)) return;
                }
                try ctx.escaping_locals.append(ctx.allocator, n.id);
            }
        },
        .tuple => |t| {
            for (t.elts) |elt| try markEscapingExpr(elt, ctx);
        },
        .list => |l| {
            for (l.elts) |elt| try markEscapingExpr(elt, ctx);
        },
        .subscript => |sub| {
            // x[i] escapes → x escapes
            try markEscapingExpr(sub.value.*, ctx);
        },
        .attribute => |attr| {
            // x.attr escapes → x escapes
            try markEscapingExpr(attr.value.*, ctx);
        },
        .call => |call| {
            // Function call result can escape - args passed to external func escape
            for (call.args) |arg| {
                try markEscapingExpr(arg, ctx);
            }
        },
        .if_expr => |tern| {
            try markEscapingExpr(tern.body.*, ctx);
            try markEscapingExpr(tern.orelse_value.*, ctx);
        },
        else => {},
    }
}

/// Check if a statement is a tail-recursive return
fn isTailRecursive(stmt: ast.Node, func_name: []const u8) bool {
    if (stmt != .return_stmt) return false;
    const ret = stmt.return_stmt;
    if (ret.value == null) return false;

    const val = ret.value.?.*;
    if (val != .call) return false;

    const call = val.call;
    if (call.func.* != .name) return false;

    return std.mem.eql(u8, call.func.name.id, func_name);
}

/// Compute async complexity from context
fn computeAsyncComplexity(ctx: *const AnalyzerContext) AsyncComplexity {
    if (ctx.op_count <= 5 and ctx.await_count == 0 and !ctx.has_loops) {
        return .trivial;
    }
    if (ctx.op_count <= 20 and ctx.await_count <= 1 and !ctx.has_loops and !ctx.is_tail_recursive) {
        return .simple;
    }
    if (ctx.await_count <= 5) {
        return .moderate;
    }
    return .complex;
}

/// Mark functions reachable from entry points
fn markReachable(graph: *CallGraph, allocator: std.mem.Allocator) !void {
    var worklist = std.ArrayList([]const u8){};
    defer worklist.deinit(allocator);

    // Entry points: module-level code, main, test functions
    var it = graph.functions.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        // Mark test functions and main as entry points
        if (std.mem.startsWith(u8, name, "test_") or
            std.mem.eql(u8, name, "main") or
            std.mem.eql(u8, name, "__init__") or
            std.mem.eql(u8, name, "__new__"))
        {
            entry.value_ptr.is_called = true;
            try worklist.append(allocator, name);
        }
    }

    // Propagate reachability
    while (worklist.items.len > 0) {
        const name = worklist.pop() orelse break;
        if (graph.functions.get(name)) |traits| {
            for (traits.calls) |call| {
                if (graph.functions.getPtr(call.name)) |callee_ptr| {
                    if (!callee_ptr.is_called) {
                        callee_ptr.is_called = true;
                        try worklist.append(allocator, call.name);
                    }
                }
            }
        }
    }
}

// ============================================================================
// Query API - Use these in codegen
// ============================================================================

/// Check if function should use state machine async (has I/O await)
pub fn shouldUseStateMachineAsync(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.has_await and traits.has_io;
    }
    return false;
}

/// Check if ANY async function in module has I/O
/// Used to ensure all async functions use same interface (for gather compatibility)
pub fn anyAsyncHasIO(graph: *const CallGraph) bool {
    var it = graph.functions.iterator();
    while (it.next()) |entry| {
        const traits = entry.value_ptr.*;
        if (traits.has_await and traits.has_io) return true;
    }
    return false;
}

/// Check if parameter should be `var` (mutated) vs `const`
pub fn isParamMutated(graph: *const CallGraph, func_name: []const u8, param_idx: usize) bool {
    if (graph.functions.get(func_name)) |traits| {
        if (param_idx < traits.mutates_params.len) {
            return traits.mutates_params[param_idx];
        }
    }
    return false;
}

/// Check if function needs error union return type
pub fn needsErrorUnion(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.can_error;
    }
    return false;
}

/// Get precise error types for a function (for generating error{X,Y}!T instead of anyerror!T)
pub fn getErrorSet(graph: *const CallGraph, name: []const u8) ErrorSet {
    if (graph.functions.get(name)) |traits| {
        return traits.error_types;
    }
    return .{};
}

/// Check if function needs allocator parameter (for error union return type)
pub fn needsAllocator(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.needs_allocator;
    }
    return false;
}

/// Check if function actually uses allocator param (not just __global_allocator)
pub fn usesAllocatorParam(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.uses_allocator_param;
    }
    return false;
}

/// Check if function is pure (can be memoized/comptime evaluated)
pub fn isPure(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.is_pure;
    }
    return false;
}

/// Check if function can use tail call optimization
pub fn canUseTCO(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.is_tail_recursive;
    }
    return false;
}

/// Check if function is a generator
pub fn isGenerator(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return traits.is_generator;
    }
    return false;
}

/// Get captured variables for closure generation
pub fn getCapturedVars(graph: *const CallGraph, name: []const u8) []const []const u8 {
    if (graph.functions.get(name)) |traits| {
        return traits.captured_vars;
    }
    return &.{};
}

/// Check if function is dead code (not reachable)
pub fn isDeadCode(graph: *const CallGraph, name: []const u8) bool {
    if (graph.functions.get(name)) |traits| {
        return !traits.is_called;
    }
    return true;
}

/// Get async complexity for optimization decisions
pub fn getAsyncComplexity(graph: *const CallGraph, name: []const u8) AsyncComplexity {
    if (graph.functions.get(name)) |traits| {
        return traits.async_complexity;
    }
    return .trivial;
}

// ============================================================================
// Escape Analysis Query API
// ============================================================================

/// Check if a parameter escapes its function (returned, stored globally, etc.)
/// If param doesn't escape → can stack allocate caller's argument
pub fn paramEscapes(graph: *const CallGraph, func_name: []const u8, param_idx: usize) bool {
    if (graph.functions.get(func_name)) |traits| {
        if (param_idx < traits.escaping_params.len) {
            return traits.escaping_params[param_idx];
        }
    }
    return true; // Conservative: assume escapes if unknown
}

/// Check if a local variable can be stack allocated (doesn't escape)
pub fn canStackAllocate(graph: *const CallGraph, func_name: []const u8, var_name: []const u8) bool {
    if (graph.functions.get(func_name)) |traits| {
        // If in escaping_locals list, can't stack allocate
        for (traits.escaping_locals) |local| {
            if (std.mem.eql(u8, local, var_name)) return false;
        }
        return true; // Not in escaping list → safe for stack
    }
    return false; // Conservative: heap allocate if unknown
}

/// Get which parameter the return value aliases (if any)
/// Useful for ownership tracking and avoiding copies
pub fn getReturnAliasParam(graph: *const CallGraph, func_name: []const u8) ?usize {
    if (graph.functions.get(func_name)) |traits| {
        return traits.return_aliases_param;
    }
    return null;
}

/// Get all non-escaping locals in a function (candidates for stack allocation)
pub fn getNonEscapingLocals(graph: *const CallGraph, func_name: []const u8) []const []const u8 {
    _ = graph;
    _ = func_name;
    // TODO: Return inverse of escaping_locals once we track all locals
    return &.{};
}

// ============================================================================
// Static AST Analysis (no CallGraph needed)
// ============================================================================

/// Methods that use allocator param
const AllocatorMethods = std.StaticStringMap(void).initComptime(.{
    .{ "upper", {} }, .{ "lower", {} }, .{ "strip", {} }, .{ "split", {} },
    .{ "replace", {} }, .{ "join", {} }, .{ "write", {} }, .{ "getvalue", {} },
});

/// Methods using __global_allocator (need error union but not allocator param)
const GlobalAllocMethods = std.StaticStringMap(void).initComptime(.{
    .{ "hexdigest", {} }, .{ "digest", {} }, .{ "append", {} },
    .{ "extend", {} }, .{ "insert", {} }, .{ "appendleft", {} }, .{ "extendleft", {} },
});

/// Builtins needing allocator
const AllocBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "str", {} }, .{ "list", {} }, .{ "dict", {} }, .{ "input", {} },
    .{ "StringIO", {} }, .{ "BytesIO", {} }, .{ "int", {} }, .{ "float", {} },
    .{ "Counter", {} }, .{ "deque", {} }, .{ "defaultdict", {} }, .{ "OrderedDict", {} },
});

/// Builtins using __global_allocator
const GlobalAllocBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "str", {} }, .{ "list", {} }, .{ "dict", {} }, .{ "print", {} },
    .{ "eval", {} }, .{ "exec", {} }, .{ "compile", {} },
});

/// Module functions using allocator param
const ModuleAllocFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "dumps", {} }, .{ "loads", {} }, .{ "match", {} }, .{ "search", {} },
    .{ "findall", {} }, .{ "sub", {} }, .{ "split", {} }, .{ "compile", {} },
    .{ "compress", {} }, .{ "decompress", {} },
});

/// Constructors using allocator
const AllocConstructors = std.StaticStringMap(void).initComptime(.{
    .{ "Counter", {} }, .{ "deque", {} }, .{ "defaultdict", {} },
    .{ "OrderedDict", {} }, .{ "StringIO", {} }, .{ "BytesIO", {} },
});

/// Dunder methods that return primitive values and should NEVER need allocator
/// The runtime calls these directly without passing allocator, so the generated
/// code must match the expected signature: self -> primitive_type
const NoAllocatorDunderMethods = std.StaticStringMap(void).initComptime(.{
    .{ "__float__", {} }, // Returns f64
    .{ "__int__", {} }, // Returns i64
    .{ "__bool__", {} }, // Returns bool (error is allowed, not allocator)
    .{ "__hash__", {} }, // Returns i64
    .{ "__index__", {} }, // Returns i64
    .{ "__sizeof__", {} }, // Returns i64
    .{ "__len__", {} }, // Returns i64 (error is allowed, not allocator)
    .{ "__eq__", {} }, // Returns bool
    .{ "__ne__", {} }, // Returns bool
    .{ "__lt__", {} }, // Returns bool
    .{ "__le__", {} }, // Returns bool
    .{ "__gt__", {} }, // Returns bool
    .{ "__ge__", {} }, // Returns bool
    .{ "__contains__", {} }, // Returns bool
});

/// Analyze function AST to determine if it needs allocator (for error union)
pub fn analyzeNeedsAllocator(func: ast.Node.FunctionDef, class_name: ?[]const u8) bool {
    // Dunder methods that return primitive values should NEVER need allocator
    // The runtime calls these without allocator, so we must match that signature
    if (NoAllocatorDunderMethods.has(func.name)) return false;

    // Check for nested class instantiation
    var nested: [32][]const u8 = undefined;
    var count: usize = 0;
    collectNestedClasses(func.body, &nested, &count);
    if (class_name) |cn| if (count < 32) { nested[count] = cn; count += 1; };
    if (count > 0 and hasNestedClassCalls(func.body, nested[0..count])) return true;

    for (func.body) |stmt| if (stmtNeedsAlloc(stmt)) return true;
    return false;
}

/// Analyze if function actually uses allocator param (not __global_allocator)
pub fn analyzeUsesAllocatorParam(func: ast.Node.FunctionDef, class_name: ?[]const u8) bool {
    _ = class_name; // Same-class calls use __global_allocator
    var nested: [32][]const u8 = undefined;
    var count: usize = 0;
    collectNestedClasses(func.body, &nested, &count);

    for (func.body) |stmt| if (stmtUsesAllocParam(stmt, func.name, nested[0..count])) return true;
    return false;
}

fn collectNestedClasses(stmts: []ast.Node, names: *[32][]const u8, count: *usize) void {
    for (stmts) |stmt| switch (stmt) {
        .class_def => |c| if (count.* < 32) { names[count.*] = c.name; count.* += 1; },
        .if_stmt => |i| { collectNestedClasses(i.body, names, count); collectNestedClasses(i.else_body, names, count); },
        .for_stmt => |f| collectNestedClasses(f.body, names, count),
        .while_stmt => |w| collectNestedClasses(w.body, names, count),
        .try_stmt => |t| { collectNestedClasses(t.body, names, count); for (t.handlers) |h| collectNestedClasses(h.body, names, count); },
        .with_stmt => |w| collectNestedClasses(w.body, names, count),
        else => {},
    };
}

fn hasNestedClassCalls(stmts: []ast.Node, nested: []const []const u8) bool {
    for (stmts) |stmt| if (stmtHasNestedCall(stmt, nested)) return true;
    return false;
}

fn stmtHasNestedCall(stmt: ast.Node, nested: []const []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprHasNestedCall(e.value.*, nested),
        .assign => |a| exprHasNestedCall(a.value.*, nested),
        .return_stmt => |r| if (r.value) |v| exprHasNestedCall(v.*, nested) else false,
        .if_stmt => |i| exprHasNestedCall(i.condition.*, nested) or hasNestedClassCalls(i.body, nested) or hasNestedClassCalls(i.else_body, nested),
        .while_stmt => |w| exprHasNestedCall(w.condition.*, nested) or hasNestedClassCalls(w.body, nested),
        .for_stmt => |f| exprHasNestedCall(f.iter.*, nested) or hasNestedClassCalls(f.body, nested),
        .try_stmt => |t| blk: { if (hasNestedClassCalls(t.body, nested)) break :blk true; for (t.handlers) |h| if (hasNestedClassCalls(h.body, nested)) break :blk true; break :blk false; },
        .with_stmt => |w| exprHasNestedCall(w.context_expr.*, nested) or hasNestedClassCalls(w.body, nested),
        else => false,
    };
}

fn exprHasNestedCall(expr: ast.Node, nested: []const []const u8) bool {
    return switch (expr) {
        .call => |c| blk: {
            if (c.func.* == .name) for (nested) |n| if (std.mem.eql(u8, c.func.name.id, n)) break :blk true;
            for (c.args) |a| if (exprHasNestedCall(a, nested)) break :blk true;
            break :blk exprHasNestedCall(c.func.*, nested);
        },
        .binop => |b| exprHasNestedCall(b.left.*, nested) or exprHasNestedCall(b.right.*, nested),
        .unaryop => |u| exprHasNestedCall(u.operand.*, nested),
        .attribute => |a| exprHasNestedCall(a.value.*, nested),
        .subscript => |s| exprHasNestedCall(s.value.*, nested) or switch (s.slice) {
            .index => |i| exprHasNestedCall(i.*, nested),
            .slice => |r| (if (r.lower) |l| exprHasNestedCall(l.*, nested) else false) or (if (r.upper) |u| exprHasNestedCall(u.*, nested) else false),
        },
        .tuple => |t| blk: { for (t.elts) |e| if (exprHasNestedCall(e, nested)) break :blk true; break :blk false; },
        .list => |l| blk: { for (l.elts) |e| if (exprHasNestedCall(e, nested)) break :blk true; break :blk false; },
        .compare => |co| blk: { if (exprHasNestedCall(co.left.*, nested)) break :blk true; for (co.comparators) |c| if (exprHasNestedCall(c, nested)) break :blk true; break :blk false; },
        else => false,
    };
}

fn stmtNeedsAlloc(stmt: ast.Node) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprNeedsAlloc(e.value.*),
        .assign => |a| blk: {
            for (a.targets) |t| if (t == .attribute and t.attribute.value.* == .name and std.mem.eql(u8, t.attribute.value.name.id, "self")) break :blk true;
            break :blk exprNeedsAlloc(a.value.*);
        },
        .aug_assign => |a| exprNeedsAlloc(a.value.*),
        .return_stmt => |r| if (r.value) |v| exprNeedsAlloc(v.*) else false,
        .if_stmt => |i| exprNeedsAlloc(i.condition.*) or blk: { for (i.body) |s| if (stmtNeedsAlloc(s)) break :blk true; for (i.else_body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        .while_stmt => |w| exprNeedsAlloc(w.condition.*) or blk: { for (w.body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        .for_stmt => |f| exprNeedsAlloc(f.iter.*) or blk: { for (f.body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        .try_stmt => |t| blk: { for (t.body) |s| if (stmtNeedsAlloc(s)) break :blk true; for (t.handlers) |h| for (h.body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        .class_def => |c| blk: { for (c.body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        .function_def => true, // Nested functions need allocator for closure
        .with_stmt => |w| exprNeedsAlloc(w.context_expr.*) or blk: { for (w.body) |s| if (stmtNeedsAlloc(s)) break :blk true; break :blk false; },
        else => false,
    };
}

fn exprNeedsAlloc(expr: ast.Node) bool {
    return switch (expr) {
        .binop => |b| (b.op == .Add and (mightBeStr(b.left.*) or mightBeStr(b.right.*))) or
            b.op == .Div or b.op == .FloorDiv or b.op == .Mod or exprNeedsAlloc(b.left.*) or exprNeedsAlloc(b.right.*),
        .call => |c| callNeedsAlloc(c),
        .fstring, .listcomp, .dictcomp, .dict => true,
        .list => |l| l.elts.len > 0 or blk: { for (l.elts) |e| if (exprNeedsAlloc(e)) break :blk true; break :blk false; },
        .tuple => |t| blk: { for (t.elts) |e| if (exprNeedsAlloc(e)) break :blk true; break :blk false; },
        .subscript => |s| exprNeedsAlloc(s.value.*) or switch (s.slice) { .index => |i| exprNeedsAlloc(i.*), .slice => |r| (if (r.lower) |l| exprNeedsAlloc(l.*) else false) or (if (r.upper) |u| exprNeedsAlloc(u.*) else false) },
        .attribute => |a| exprNeedsAlloc(a.value.*),
        .compare => |c| exprNeedsAlloc(c.left.*) or blk: { for (c.comparators) |x| if (exprNeedsAlloc(x)) break :blk true; break :blk false; },
        .boolop => |b| blk: { for (b.values) |v| if (exprNeedsAlloc(v)) break :blk true; break :blk false; },
        .unaryop => |u| exprNeedsAlloc(u.operand.*),
        else => false,
    };
}

fn callNeedsAlloc(call: ast.Node.Call) bool {
    for (call.args) |a| if (exprNeedsAlloc(a)) return true;
    if (call.func.* == .attribute) {
        const m = call.func.attribute.attr;
        if (AllocatorMethods.has(m) or GlobalAllocMethods.has(m)) return true;
        if (call.func.attribute.value.* == .call and exprNeedsAlloc(call.func.attribute.value.*)) return true;
        if (call.func.attribute.value.* == .name) {
            const obj = call.func.attribute.value.name.id;
            if (std.mem.eql(u8, obj, "self")) return true;
            if (ModuleAllocFuncs.has(m)) return true;
        }
    }
    if (call.func.* == .name and AllocBuiltins.has(call.func.name.id)) return true;
    return false;
}

fn mightBeStr(expr: ast.Node) bool {
    return switch (expr) {
        .constant => |c| c.value == .string,
        .fstring => true,
        .call => |c| (c.func.* == .name and (std.mem.eql(u8, c.func.name.id, "str") or std.mem.eql(u8, c.func.name.id, "input"))) or
            (c.func.* == .attribute and (std.mem.eql(u8, c.func.attribute.attr, "upper") or std.mem.eql(u8, c.func.attribute.attr, "lower"))),
        .binop => |b| b.op == .Add and (mightBeStr(b.left.*) or mightBeStr(b.right.*)),
        else => false,
    };
}

fn stmtUsesAllocParam(stmt: ast.Node, func_name: []const u8, nested: []const []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprUsesAllocParam(e.value.*, func_name, nested),
        .assign => |a| exprUsesAllocParam(a.value.*, func_name, nested),
        .aug_assign => |a| exprUsesAllocParam(a.value.*, func_name, nested),
        .return_stmt => |r| if (r.value) |v| exprUsesAllocParam(v.*, func_name, nested) else false,
        .if_stmt => |i| exprUsesAllocParam(i.condition.*, func_name, nested) or blk: { for (i.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; for (i.else_body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        .while_stmt => |w| exprUsesAllocParam(w.condition.*, func_name, nested) or blk: { for (w.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        .for_stmt => |f| exprUsesAllocParam(f.iter.*, func_name, nested) or blk: { for (f.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        .try_stmt => |t| blk: { for (t.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; for (t.handlers) |h| for (h.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        .class_def => |c| blk: { for (c.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        .with_stmt => |w| exprUsesAllocParam(w.context_expr.*, func_name, nested) or blk: { for (w.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true; break :blk false; },
        else => false,
    };
}

fn exprUsesAllocParam(expr: ast.Node, func_name: []const u8, nested: []const []const u8) bool {
    return switch (expr) {
        .binop => |b| exprUsesAllocParam(b.left.*, func_name, nested) or exprUsesAllocParam(b.right.*, func_name, nested),
        .call => |c| callUsesAllocParam(c, func_name, nested),
        .listcomp, .dictcomp => true,
        .list => |l| blk: { for (l.elts) |e| if (exprUsesAllocParam(e, func_name, nested)) break :blk true; break :blk false; },
        .tuple => |t| blk: { for (t.elts) |e| if (exprUsesAllocParam(e, func_name, nested)) break :blk true; break :blk false; },
        .subscript => |s| exprUsesAllocParam(s.value.*, func_name, nested) or switch (s.slice) { .index => |i| exprUsesAllocParam(i.*, func_name, nested), .slice => |r| (if (r.lower) |l| exprUsesAllocParam(l.*, func_name, nested) else false) or (if (r.upper) |u| exprUsesAllocParam(u.*, func_name, nested) else false) },
        .attribute => |a| exprUsesAllocParam(a.value.*, func_name, nested),
        .compare => |co| exprUsesAllocParam(co.left.*, func_name, nested) or blk: { for (co.comparators) |x| if (exprUsesAllocParam(x, func_name, nested)) break :blk true; break :blk false; },
        .boolop => |b| blk: { for (b.values) |v| if (exprUsesAllocParam(v, func_name, nested)) break :blk true; break :blk false; },
        .unaryop => |u| exprUsesAllocParam(u.operand.*, func_name, nested),
        .name => |n| std.mem.eql(u8, n.id, "allocator"),
        .if_expr => |ie| exprUsesAllocParam(ie.body.*, func_name, nested) or exprUsesAllocParam(ie.orelse_value.*, func_name, nested),
        else => false,
    };
}

fn callUsesAllocParam(call: ast.Node.Call, func_name: []const u8, nested: []const []const u8) bool {
    for (call.args) |a| if (exprUsesAllocParam(a, func_name, nested)) return true;
    if (call.func.* == .attribute) {
        if (AllocatorMethods.has(call.func.attribute.attr)) return true;
        if (call.func.attribute.value.* == .name) {
            const obj = call.func.attribute.value.name.id;
            if (ModuleAllocFuncs.has(call.func.attribute.attr) and !std.mem.eql(u8, obj, "self")) return true;
        }
    }
    if (call.func.* == .name) {
        const n = call.func.name.id;
        if (GlobalAllocBuiltins.has(n)) return false;
        if (std.mem.eql(u8, n, func_name)) return true; // Recursive call
        if (AllocBuiltins.has(n)) return true;
        if (AllocConstructors.has(n)) return true;
        for (nested) |c| if (std.mem.eql(u8, n, c)) return true;
    }
    return false;
}

// ============================================================================
// Comptime Patterns for Runtime Type Handling
// ============================================================================

// ============================================================================
// Heterogeneous List Analysis
// ============================================================================
// Detects when variables need PyValue type due to:
// 1. List aliases that get heterogeneous items appended (T = A; T += [(x,)])
// 2. Variables assigned different types in different branches
// 3. List comprehensions producing mixed types

/// Analyze a function body for heterogeneous list patterns
/// Returns lists of variables that need special handling
pub fn analyzeHeterogeneousLists(
    allocator: std.mem.Allocator,
    body: []const ast.Node,
) struct { heterogeneous_vars: [][]const u8, list_aliases: []ListAlias } {
    var heterogeneous_vars = std.ArrayList([]const u8){};
    var list_aliases_list = std.ArrayList(ListAlias){};
    var list_vars = hashmap_helper.StringHashMap(TypeHint).init(allocator);
    defer list_vars.deinit();

    // Two-pass analysis:
    // Pass 1: Find all list variables and aliases
    // Pass 2: Check augmented assignments for type mismatches
    for (body) |stmt| {
        analyzeStmtForLists(stmt, &list_vars, &list_aliases_list, allocator);
    }

    // Pass 2: Check for heterogeneous augmented assignments
    for (body) |stmt| {
        checkHeterogeneousAugAssign(stmt, &list_vars, &heterogeneous_vars, allocator);
    }

    return .{
        .heterogeneous_vars = heterogeneous_vars.toOwnedSlice(allocator) catch &.{},
        .list_aliases = list_aliases_list.toOwnedSlice(allocator) catch &.{},
    };
}

fn analyzeStmtForLists(
    stmt: ast.Node,
    list_vars: *hashmap_helper.StringHashMap(TypeHint),
    list_aliases: *std.ArrayList(ListAlias),
    allocator: std.mem.Allocator,
) void {
    switch (stmt) {
        .assign => |assign| {
            // Check if this is a list assignment
            for (assign.targets) |target| {
                if (target == .name) {
                    const var_name = target.name.id;
                    // Check RHS type
                    const rhs_type = inferSimpleType(assign.value.*);
                    if (rhs_type == .list) {
                        list_vars.put(allocator.dupe(u8, var_name) catch var_name, .list) catch {};
                    } else if (assign.value.* == .name) {
                        // Potential alias: T = A
                        const rhs_name = assign.value.name.id;
                        if (list_vars.contains(rhs_name)) {
                            list_aliases.append(allocator, .{
                                .alias_name = allocator.dupe(u8, var_name) catch var_name,
                                .original_name = allocator.dupe(u8, rhs_name) catch rhs_name,
                            }) catch {};
                            list_vars.put(allocator.dupe(u8, var_name) catch var_name, .list) catch {};
                        }
                    }
                }
            }
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            if (for_stmt.orelse_body) |else_body| {
                for (else_body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            if (while_stmt.orelse_body) |else_body| {
                for (else_body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
            for (if_stmt.else_body) |s| analyzeStmtForLists(s, list_vars, list_aliases, allocator);
        },
        else => {},
    }
}

fn checkHeterogeneousAugAssign(
    stmt: ast.Node,
    list_vars: *hashmap_helper.StringHashMap(TypeHint),
    heterogeneous_vars: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) void {
    switch (stmt) {
        .aug_assign => |aug| {
            if (aug.op == .Add and aug.target.* == .name) {
                const var_name = aug.target.name.id;
                if (list_vars.contains(var_name)) {
                    // Check if RHS produces different type
                    const rhs_type = inferSimpleType(aug.value.*);
                    // List + tuple/product = heterogeneous
                    if (rhs_type == .tuple or rhs_type == .list) {
                        // Check if it's a comprehension producing tuples
                        if (aug.value.* == .listcomp) {
                            const comp = aug.value.listcomp;
                            const elem_type = inferSimpleType(comp.elt.*);
                            if (elem_type == .tuple) {
                                // This list will have heterogeneous elements
                                heterogeneous_vars.append(allocator, allocator.dupe(u8, var_name) catch var_name) catch {};
                            }
                        } else if (aug.value.* == .call) {
                            // Check if it's a product() call
                            if (aug.value.call.func.* == .name) {
                                const fn_name = aug.value.call.func.name.id;
                                if (std.mem.eql(u8, fn_name, "product")) {
                                    heterogeneous_vars.append(allocator, allocator.dupe(u8, var_name) catch var_name) catch {};
                                }
                            }
                        }
                    }
                }
            }
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            if (for_stmt.orelse_body) |else_body| {
                for (else_body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            if (while_stmt.orelse_body) |else_body| {
                for (else_body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
            for (if_stmt.else_body) |s| checkHeterogeneousAugAssign(s, list_vars, heterogeneous_vars, allocator);
        },
        else => {},
    }
}

fn inferSimpleType(expr: ast.Node) TypeHint {
    return switch (expr) {
        .list => .list,
        .tuple => .tuple,
        .listcomp => .list,
        .dict, .dictcomp => .dict,
        .constant => |c| switch (c.value) {
            .int => .int,
            .float => .float,
            .bool => .bool,
            .string, .bytes => .string,
            .none => .none,
            else => .any,
        },
        .call => .any, // Could be anything
        else => .any,
    };
}

// ============================================================================
// Bound Method Reference Analysis
// ============================================================================

/// Check if a function body contains bound method references (self.method used as value)
/// Returns a list of (target_field, method_name) pairs for field assignments like:
///   self.callback = self.handler
/// where handler is a method name
pub fn findBoundMethodRefs(body: []const ast.Node, class_methods: []const []const u8) BoundMethodRefs {
    var result = BoundMethodRefs{};
    for (body) |stmt| {
        collectBoundMethodRefs(stmt, class_methods, &result);
    }
    return result;
}

pub const BoundMethodRef = struct {
    field_name: []const u8, // Target field (e.g., "default_factory")
    method_name: []const u8, // Bound method (e.g., "_factory")
};

pub const BoundMethodRefs = struct {
    refs: [16]BoundMethodRef = undefined,
    count: usize = 0,

    pub fn add(self: *BoundMethodRefs, ref: BoundMethodRef) void {
        if (self.count < 16) {
            self.refs[self.count] = ref;
            self.count += 1;
        }
    }

    pub fn contains(self: *const BoundMethodRefs, field_name: []const u8) bool {
        for (self.refs[0..self.count]) |ref| {
            if (std.mem.eql(u8, ref.field_name, field_name)) return true;
        }
        return false;
    }

    pub fn getMethod(self: *const BoundMethodRefs, field_name: []const u8) ?[]const u8 {
        for (self.refs[0..self.count]) |ref| {
            if (std.mem.eql(u8, ref.field_name, field_name)) return ref.method_name;
        }
        return null;
    }
};

fn collectBoundMethodRefs(stmt: ast.Node, class_methods: []const []const u8, result: *BoundMethodRefs) void {
    switch (stmt) {
        .assign => |assign| {
            // Look for: self.field = self.method
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const target_attr = assign.targets[0].attribute;
                if (target_attr.value.* == .name and std.mem.eql(u8, target_attr.value.name.id, "self")) {
                    // Target is self.field - check if value is self.method
                    if (assign.value.* == .attribute) {
                        const value_attr = assign.value.attribute;
                        if (value_attr.value.* == .name and std.mem.eql(u8, value_attr.value.name.id, "self")) {
                            // Check if attr is a method name
                            for (class_methods) |method| {
                                if (std.mem.eql(u8, value_attr.attr, method)) {
                                    result.add(.{
                                        .field_name = target_attr.attr,
                                        .method_name = value_attr.attr,
                                    });
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |s| collectBoundMethodRefs(s, class_methods, result);
            for (if_stmt.else_body) |s| collectBoundMethodRefs(s, class_methods, result);
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |s| collectBoundMethodRefs(s, class_methods, result);
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |s| collectBoundMethodRefs(s, class_methods, result);
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |s| collectBoundMethodRefs(s, class_methods, result);
            for (try_stmt.handlers) |handler| {
                for (handler.body) |s| collectBoundMethodRefs(s, class_methods, result);
            }
        },
        else => {},
    }
}

/// Get all method names from a class definition
pub fn getClassMethods(class_def: ast.Node.ClassDef) [64][]const u8 {
    var methods: [64][]const u8 = undefined;
    var count: usize = 0;

    for (class_def.body) |stmt| {
        if (stmt == .function_def) {
            if (count < 64) {
                methods[count] = stmt.function_def.name;
                count += 1;
            }
        }
    }

    // Null terminate
    if (count < 64) {
        methods[count] = "";
    }

    return methods;
}

// ============================================================================
// Variable Usage Analysis
// ============================================================================

/// Track which variables are actually used (read) in a function body
/// This is for determining if `_ = var;` discard is needed
pub const UsedVarsSet = struct {
    names: [128][]const u8 = undefined,
    count: usize = 0,

    pub fn add(self: *UsedVarsSet, name: []const u8) void {
        if (!self.contains(name) and self.count < 128) {
            self.names[self.count] = name;
            self.count += 1;
        }
    }

    pub fn contains(self: *const UsedVarsSet, name: []const u8) bool {
        for (self.names[0..self.count]) |n| {
            if (std.mem.eql(u8, n, name)) return true;
        }
        return false;
    }
};

/// Analyze which variables are actually read (used) in a function body
/// Excludes LHS of assignments (those are writes, not reads)
pub fn analyzeUsedVars(body: []const ast.Node) UsedVarsSet {
    var result = UsedVarsSet{};
    for (body) |stmt| {
        collectUsedVars(stmt, &result);
    }
    return result;
}

fn collectUsedVars(node: ast.Node, result: *UsedVarsSet) void {
    switch (node) {
        .name => |name| result.add(name.id),
        .attribute => |attr| collectUsedVars(attr.value.*, result),
        .subscript => |sub| {
            collectUsedVars(sub.value.*, result);
            collectUsedVars(sub.slice.*, result);
        },
        .call => |call| {
            collectUsedVars(call.func.*, result);
            for (call.args) |arg| collectUsedVars(arg, result);
            for (call.keywords) |kw| {
                if (kw.value) |v| collectUsedVars(v.*, result);
            }
        },
        .binop => |binop| {
            collectUsedVars(binop.left.*, result);
            collectUsedVars(binop.right.*, result);
        },
        .unaryop => |unary| collectUsedVars(unary.operand.*, result),
        .compare => |cmp| {
            collectUsedVars(cmp.left.*, result);
            for (cmp.comparators) |c| collectUsedVars(c, result);
        },
        .boolop => |boolop| {
            for (boolop.values) |v| collectUsedVars(v, result);
        },
        .ifexp => |ifexp| {
            collectUsedVars(ifexp.condition.*, result);
            collectUsedVars(ifexp.body.*, result);
            collectUsedVars(ifexp.@"orelse".*, result);
        },
        .list => |list| {
            for (list.elts) |e| collectUsedVars(e, result);
        },
        .tuple => |tuple| {
            for (tuple.elts) |e| collectUsedVars(e, result);
        },
        .dict => |dict| {
            for (dict.keys) |k| collectUsedVars(k, result);
            for (dict.values) |v| collectUsedVars(v, result);
        },
        .set => |set| {
            for (set.elts) |e| collectUsedVars(e, result);
        },
        .listcomp => |lc| {
            collectUsedVars(lc.elt.*, result);
            for (lc.generators) |gen| {
                collectUsedVars(gen.iter.*, result);
                for (gen.ifs) |cond| collectUsedVars(cond, result);
            }
        },
        .dictcomp => |dc| {
            collectUsedVars(dc.key.*, result);
            collectUsedVars(dc.value.*, result);
            for (dc.generators) |gen| {
                collectUsedVars(gen.iter.*, result);
                for (gen.ifs) |cond| collectUsedVars(cond, result);
            }
        },
        .setcomp => |sc| {
            collectUsedVars(sc.elt.*, result);
            for (sc.generators) |gen| {
                collectUsedVars(gen.iter.*, result);
                for (gen.ifs) |cond| collectUsedVars(cond, result);
            }
        },
        .genexp => |ge| {
            collectUsedVars(ge.elt.*, result);
            for (ge.generators) |gen| {
                collectUsedVars(gen.iter.*, result);
                for (gen.ifs) |cond| collectUsedVars(cond, result);
            }
        },
        .lambda => |lambda| collectUsedVars(lambda.body.*, result),
        .slice => |slice| {
            if (slice.lower) |l| collectUsedVars(l.*, result);
            if (slice.upper) |u| collectUsedVars(u.*, result);
            if (slice.step) |s| collectUsedVars(s.*, result);
        },
        .starred => |starred| collectUsedVars(starred.value.*, result),
        .await_expr => |await_e| collectUsedVars(await_e.value.*, result),
        .joined_str => |js| {
            for (js.values) |v| collectUsedVars(v, result);
        },
        .formatted_value => |fv| collectUsedVars(fv.value.*, result),
        // Statements - recurse into their expression parts
        .assign => |assign| {
            // Only collect from RHS (value), not LHS (targets)
            collectUsedVars(assign.value.*, result);
        },
        .ann_assign => |ann| {
            if (ann.value) |v| collectUsedVars(v.*, result);
        },
        .aug_assign => |aug| {
            // Both target and value are used for aug_assign (target is read AND written)
            collectUsedVars(aug.target.*, result);
            collectUsedVars(aug.value.*, result);
        },
        .expr_stmt => |expr| collectUsedVars(expr.value.*, result),
        .return_stmt => |ret| {
            if (ret.value) |v| collectUsedVars(v.*, result);
        },
        .delete_stmt => |del| {
            for (del.targets) |t| collectUsedVars(t, result);
        },
        .raise_stmt => |raise| {
            if (raise.exc) |e| collectUsedVars(e.*, result);
            if (raise.cause) |c| collectUsedVars(c.*, result);
        },
        .assert_stmt => |assert| {
            collectUsedVars(assert.@"test".*, result);
            if (assert.msg) |m| collectUsedVars(m.*, result);
        },
        .if_stmt => |if_stmt| {
            collectUsedVars(if_stmt.condition.*, result);
            for (if_stmt.body) |s| collectUsedVars(s, result);
            for (if_stmt.else_body) |s| collectUsedVars(s, result);
        },
        .while_stmt => |while_stmt| {
            collectUsedVars(while_stmt.condition.*, result);
            for (while_stmt.body) |s| collectUsedVars(s, result);
            if (while_stmt.orelse_body) |else_body| {
                for (else_body) |s| collectUsedVars(s, result);
            }
        },
        .for_stmt => |for_stmt| {
            collectUsedVars(for_stmt.iter.*, result);
            for (for_stmt.body) |s| collectUsedVars(s, result);
            if (for_stmt.orelse_body) |else_body| {
                for (else_body) |s| collectUsedVars(s, result);
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |s| collectUsedVars(s, result);
            for (try_stmt.handlers) |handler| {
                for (handler.body) |s| collectUsedVars(s, result);
            }
            for (try_stmt.else_body) |s| collectUsedVars(s, result);
            for (try_stmt.finalbody) |s| collectUsedVars(s, result);
        },
        .with_stmt => |with_stmt| {
            collectUsedVars(with_stmt.context_expr.*, result);
            for (with_stmt.body) |s| collectUsedVars(s, result);
        },
        .match_stmt => |match_stmt| {
            collectUsedVars(match_stmt.subject.*, result);
            for (match_stmt.cases) |case| {
                for (case.body) |s| collectUsedVars(s, result);
            }
        },
        else => {},
    }
}

/// Check if a variable is actually used (read) in a body after being assigned
/// This helps avoid "pointless discard" errors
pub fn isVarActuallyUsed(body: []const ast.Node, var_name: []const u8) bool {
    const used = analyzeUsedVars(body);
    return used.contains(var_name);
}

// ============================================================================
// Tests
// ============================================================================

test "build call graph from simple function" {
    const allocator = std.testing.allocator;
    _ = allocator;
}
