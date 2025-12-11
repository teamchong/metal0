/// Symbol types and metadata structures
/// Used by the optimizer symbol table to track variable types and values

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Symbol Types
// ============================================================================

/// Symbol kind
pub const SymbolKind = enum(u8) {
    /// Local variable
    local,
    /// Cell variable (used in closures)
    cell,
    /// Free variable (from enclosing scope)
    free,
    /// Global variable
    global,
    /// Built-in name
    builtin,
    /// Constant value
    constant,
    /// Temporary (stack slot)
    temporary,
    /// Unknown
    unknown,
};

/// Symbol flags
pub const SymbolFlags = packed struct {
    /// Symbol is defined
    defined: bool = false,
    /// Symbol is referenced
    referenced: bool = false,
    /// Symbol is parameter
    is_param: bool = false,
    /// Symbol is annotated
    annotated: bool = false,
    /// Symbol is imported
    imported: bool = false,
    /// Symbol is nonlocal
    nonlocal: bool = false,
    /// Symbol is comprehension iterator
    comp_iter: bool = false,
    /// Symbol escapes to closure
    escapes: bool = false,
};

/// Symbol entry
pub const Symbol = struct {
    /// Symbol name
    name: []const u8,
    /// Symbol kind
    kind: SymbolKind,
    /// Symbol flags
    flags: SymbolFlags = .{},
    /// Scope depth where defined
    scope_depth: u32 = 0,
    /// Definition site (instruction index)
    def_site: ?u32 = null,
    /// Use sites
    use_sites: std.ArrayList(u32),
    /// Type information (from analysis)
    type_info: TypeInfo = .{},
    /// Constant value (if known)
    const_value: ?ConstValue = null,

    /// Create new symbol
    pub fn init(allocator: Allocator, name: []const u8, kind: SymbolKind) Symbol {
        return Symbol{
            .name = name,
            .kind = kind,
            .use_sites = std.ArrayList(u32).init(allocator),
        };
    }

    /// Free resources
    pub fn deinit(self: *Symbol, allocator: Allocator) void {
        self.use_sites.deinit(allocator);
    }

    /// Mark symbol as defined
    pub fn define(self: *Symbol, site: u32) void {
        self.flags.defined = true;
        self.def_site = site;
    }

    /// Add use site
    pub fn addUse(self: *Symbol, allocator: Allocator, site: u32) !void {
        self.flags.referenced = true;
        try self.use_sites.append(allocator, site);
    }

    /// Check if symbol is used
    pub fn isUsed(self: *const Symbol) bool {
        return self.flags.referenced;
    }

    /// Check if symbol is dead (defined but not used)
    pub fn isDead(self: *const Symbol) bool {
        return self.flags.defined and !self.flags.referenced;
    }
};

/// Type information for a symbol
pub const TypeInfo = struct {
    /// Inferred type
    type_id: TypeId = .unknown,
    /// Confidence (0.0 - 1.0)
    confidence: f32 = 0.0,
    /// Is type stable (monomorphic)
    is_stable: bool = false,
    /// Observed types count
    type_count: u32 = 0,
};

/// Type identifiers
pub const TypeId = enum(u8) {
    unknown,
    none_type,
    bool_type,
    int_type,
    float_type,
    str_type,
    bytes_type,
    list_type,
    tuple_type,
    dict_type,
    set_type,
    function_type,
    object_type,
};

/// Constant value
pub const ConstValue = union(enum) {
    none: void,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    str_val: []const u8,
};

/// Scope type
pub const ScopeType = enum(u8) {
    module,
    class,
    function,
    lambda,
    comprehension,
    annotation,
};
