/// Core types for function trait analysis
/// FunctionTraits, FunctionRef, ClassTraits, and related data structures
const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const error_types = @import("error_types.zig");

/// Reference to a function (for call graph edges)
pub const FunctionRef = struct {
    module: []const u8 = "",
    name: []const u8,
    class_name: ?[]const u8 = null,
};

/// Traits computed for each function
pub const FunctionTraits = struct {
    ref: FunctionRef = .{ .name = "" },
    // Async properties
    has_await: bool = false,
    has_io: bool = false, // Has I/O operations (file, network)
    async_complexity: AsyncComplexity = .trivial,
    // Error handling
    can_error: bool = false,
    error_types: error_types.ErrorSet = .{}, // Precise error types
    // Memory requirements
    needs_allocator: bool = false,
    uses_allocator_param: bool = false, // Actually uses allocator param (not __global_allocator)
    // Optimization flags
    is_pure: bool = true, // No side effects, same inputs = same outputs
    is_tail_recursive: bool = false,
    is_generator: bool = false,
    // Global state
    modifies_globals: bool = false,
    reads_globals: bool = false,
    // Parameter analysis
    mutates_params: []bool = &.{}, // Which params are mutated
    // Call graph
    calls: []FunctionRef = &.{},
    captured_vars: []const []const u8 = &.{}, // For closures
    is_called: bool = false, // Reachability analysis
    // Escape analysis results
    escaping_params: []bool = &.{}, // Which params escape (returned, stored globally)
    escaping_locals: []const []const u8 = &.{}, // Local vars that escape
    all_locals: []const []const u8 = &.{}, // All local vars defined in function
    return_aliases_param: ?usize = null, // Return directly aliases this param index
    // Parameter usage analysis
    params_used_in_body: []bool = &.{}, // Which params are actually used
    // Block-scoped variable analysis
    escaping_block_vars: []const []const u8 = &.{}, // Vars declared in blocks used outside
    block_scoped_vars: []const []const u8 = &.{}, // Vars that stay in their block scope
    // Heterogeneous list tracking
    heterogeneous_vars: []const []const u8 = &.{}, // Vars that need PyValue due to mixed types
    list_aliases: []const ListAlias = &.{}, // List variable aliases
    builtin_subclass_instances: []const BuiltinSubclassInstance = &.{}, // Vars that are instances of builtin subclasses
    // Return type hint (from annotation or inference)
    return_type_hint: ?TypeHint = null,

    pub fn deinit(self: *FunctionTraits, allocator: std.mem.Allocator) void {
        if (self.mutates_params.len > 0) allocator.free(self.mutates_params);
        if (self.calls.len > 0) allocator.free(self.calls);
        if (self.captured_vars.len > 0) allocator.free(self.captured_vars);
        if (self.escaping_params.len > 0) allocator.free(self.escaping_params);
        if (self.escaping_locals.len > 0) allocator.free(self.escaping_locals);
        if (self.all_locals.len > 0) allocator.free(self.all_locals);
        if (self.params_used_in_body.len > 0) allocator.free(self.params_used_in_body);
        if (self.escaping_block_vars.len > 0) allocator.free(self.escaping_block_vars);
        if (self.block_scoped_vars.len > 0) allocator.free(self.block_scoped_vars);
        if (self.heterogeneous_vars.len > 0) allocator.free(self.heterogeneous_vars);
        if (self.list_aliases.len > 0) allocator.free(self.list_aliases);
        if (self.builtin_subclass_instances.len > 0) allocator.free(self.builtin_subclass_instances);
    }

    /// Check if this variable needs PyValue type (due to heterogeneous elements or aliasing)
    pub fn needsPyValueType(self: *const FunctionTraits, var_name: []const u8) bool {
        for (self.heterogeneous_vars) |het_var| {
            if (std.mem.eql(u8, het_var, var_name)) return true;
        }
        return false;
    }

    /// Check if this variable OR any alias of it needs PyValue type
    pub fn needsPyValueTypeOrAlias(self: *const FunctionTraits, var_name: []const u8) bool {
        if (self.needsPyValueType(var_name)) return true;
        // Check if any alias of this variable is in heterogeneous_vars
        for (self.list_aliases) |alias| {
            if (std.mem.eql(u8, alias.original_name, var_name)) {
                if (self.needsPyValueType(alias.alias_name)) return true;
            }
        }
        return false;
    }

    /// Alias for needsPyValueTypeOrAlias - used by codegen
    pub fn listNeedsPyValue(self: *const FunctionTraits, var_name: []const u8) bool {
        return self.needsPyValueTypeOrAlias(var_name);
    }

    /// Get the builtin base type for a variable (e.g., "tuple" for a tuple subclass instance)
    /// Returns null if variable is not an instance of a builtin subclass
    pub fn getBuiltinBase(self: *const FunctionTraits, var_name: []const u8) ?[]const u8 {
        for (self.builtin_subclass_instances) |instance| {
            if (std.mem.eql(u8, instance.var_name, var_name)) return instance.builtin_base;
        }
        return null;
    }

    /// Check if a variable needs allocator for PyValue conversion (builtin subclass with collection base)
    pub fn needsAllocForPyValue(self: *const FunctionTraits, var_name: []const u8) bool {
        if (self.getBuiltinBase(var_name)) |base| {
            // tuple, list, dict, set need fromAlloc to properly convert elements
            return std.mem.eql(u8, base, "tuple") or
                std.mem.eql(u8, base, "list") or
                std.mem.eql(u8, base, "dict") or
                std.mem.eql(u8, base, "set");
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

/// Traits computed for each class definition
pub const ClassTraits = struct {
    /// Class name
    name: []const u8,

    /// Base class name (if inheriting from builtin type)
    /// e.g., "float", "int", "str", "list", "dict", "tuple"
    builtin_base: ?[]const u8 = null,

    /// Dunder methods that are explicitly overridden in this class
    /// Used to determine if floatBuiltinCall should call __float__ vs use __base_value__
    overridden_dunders: DunderOverrides = .{},

    /// Whether this class is defined inside a function (nested class)
    is_nested: bool = false,

    /// Parent scope name (if nested) - for qualified lookup
    parent_scope: ?[]const u8 = null,

    /// Query methods
    pub fn overrides(self: *const ClassTraits, dunder: []const u8) bool {
        if (std.mem.eql(u8, dunder, "__float__")) return self.overridden_dunders.float;
        if (std.mem.eql(u8, dunder, "__int__")) return self.overridden_dunders.int;
        if (std.mem.eql(u8, dunder, "__str__")) return self.overridden_dunders.str;
        if (std.mem.eql(u8, dunder, "__repr__")) return self.overridden_dunders.repr;
        if (std.mem.eql(u8, dunder, "__bool__")) return self.overridden_dunders.bool_;
        if (std.mem.eql(u8, dunder, "__index__")) return self.overridden_dunders.index;
        if (std.mem.eql(u8, dunder, "__hash__")) return self.overridden_dunders.hash;
        if (std.mem.eql(u8, dunder, "__len__")) return self.overridden_dunders.len;
        if (std.mem.eql(u8, dunder, "__iter__")) return self.overridden_dunders.iter;
        if (std.mem.eql(u8, dunder, "__next__")) return self.overridden_dunders.next;
        if (std.mem.eql(u8, dunder, "__call__")) return self.overridden_dunders.call;
        if (std.mem.eql(u8, dunder, "__new__")) return self.overridden_dunders.new;
        if (std.mem.eql(u8, dunder, "__init__")) return self.overridden_dunders.init;
        return false;
    }

    /// Check if class inherits from a numeric builtin (float, int)
    pub fn isNumericSubclass(self: *const ClassTraits) bool {
        if (self.builtin_base) |base| {
            return std.mem.eql(u8, base, "float") or std.mem.eql(u8, base, "int");
        }
        return false;
    }

    /// Check if float() should call __float__ instead of using __base_value__
    /// True when: inherits from float AND overrides __float__
    pub fn floatCallsOverride(self: *const ClassTraits) bool {
        if (self.builtin_base) |base| {
            if (std.mem.eql(u8, base, "float")) {
                return self.overridden_dunders.float;
            }
        }
        return false;
    }
};

/// Bitfield tracking which dunder methods are overridden
pub const DunderOverrides = struct {
    float: bool = false, // __float__
    int: bool = false, // __int__
    str: bool = false, // __str__
    repr: bool = false, // __repr__
    bool_: bool = false, // __bool__
    index: bool = false, // __index__
    hash: bool = false, // __hash__
    len: bool = false, // __len__
    iter: bool = false, // __iter__
    next: bool = false, // __next__
    call: bool = false, // __call__
    new: bool = false, // __new__
    init: bool = false, // __init__
};

/// Tracks list variable aliases (T = A where A is a list)
pub const ListAlias = struct {
    alias_name: []const u8,
    original_name: []const u8,
};

/// Tracks variables that are instances of builtin subclasses
/// e.g., `u = TupleSubclass([1,2])` where TupleSubclass inherits from tuple
pub const BuiltinSubclassInstance = struct {
    var_name: []const u8, // The variable name (e.g., "u")
    class_name: []const u8, // The class name (e.g., "TupleSubclass")
    builtin_base: []const u8, // The builtin base type (e.g., "tuple")
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
