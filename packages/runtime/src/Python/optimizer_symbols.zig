/// optimizer_symbols - Optimizer Symbol Table
/// Mirrors cpython/Python/optimizer_symbols.c
///
/// Symbol table for the bytecode optimizer, tracking variable types,
/// definitions, and uses during optimization.

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
    pub fn deinit(self: *Symbol) void {
        self.use_sites.deinit();
    }

    /// Mark symbol as defined
    pub fn define(self: *Symbol, site: u32) void {
        self.flags.defined = true;
        self.def_site = site;
    }

    /// Add use site
    pub fn addUse(self: *Symbol, site: u32) !void {
        self.flags.referenced = true;
        try self.use_sites.append(site);
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

// ============================================================================
// Symbol Table
// ============================================================================

/// Symbol table for a scope
pub const SymbolTable = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// Symbols by name
    symbols: std.StringHashMap(*Symbol),
    /// All symbols in order
    symbol_list: std.ArrayList(*Symbol),
    /// Parent scope
    parent: ?*Self = null,
    /// Child scopes
    children: std.ArrayList(*Self),
    /// Scope name
    name: []const u8,
    /// Scope type
    scope_type: ScopeType,
    /// Scope depth
    depth: u32,
    /// Free variables (from enclosing scopes)
    freevars: std.ArrayList([]const u8),
    /// Cell variables (used by nested scopes)
    cellvars: std.ArrayList([]const u8),

    /// Create new symbol table
    pub fn init(allocator: Allocator, name: []const u8, scope_type: ScopeType, depth: u32) Self {
        return Self{
            .allocator = allocator,
            .symbols = std.StringHashMap(*Symbol).init(allocator),
            .symbol_list = std.ArrayList(*Symbol).init(allocator),
            .children = std.ArrayList(*Self).init(allocator),
            .name = name,
            .scope_type = scope_type,
            .depth = depth,
            .freevars = std.ArrayList([]const u8).init(allocator),
            .cellvars = std.ArrayList([]const u8).init(allocator),
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        for (self.symbol_list.items) |sym| {
            sym.deinit();
            self.allocator.destroy(sym);
        }
        self.symbols.deinit();
        self.symbol_list.deinit();
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();
        self.freevars.deinit();
        self.cellvars.deinit();
    }

    /// Add symbol
    pub fn addSymbol(self: *Self, name: []const u8, kind: SymbolKind) !*Symbol {
        if (self.symbols.get(name)) |existing| {
            return existing;
        }

        const sym = try self.allocator.create(Symbol);
        sym.* = Symbol.init(self.allocator, name, kind);
        sym.scope_depth = self.depth;

        try self.symbols.put(name, sym);
        try self.symbol_list.append(sym);

        return sym;
    }

    /// Look up symbol in this scope
    pub fn lookup(self: *const Self, name: []const u8) ?*Symbol {
        return self.symbols.get(name);
    }

    /// Look up symbol in this scope or parent scopes
    pub fn lookupRecursive(self: *const Self, name: []const u8) ?*Symbol {
        if (self.symbols.get(name)) |sym| {
            return sym;
        }
        if (self.parent) |parent| {
            return parent.lookupRecursive(name);
        }
        return null;
    }

    /// Create child scope
    pub fn createChild(self: *Self, name: []const u8, scope_type: ScopeType) !*Self {
        const child = try self.allocator.create(Self);
        child.* = Self.init(self.allocator, name, scope_type, self.depth + 1);
        child.parent = self;
        try self.children.append(child);
        return child;
    }

    /// Mark symbol as free variable
    pub fn markFree(self: *Self, name: []const u8) !void {
        // Add to freevars if not already present
        for (self.freevars.items) |fv| {
            if (std.mem.eql(u8, fv, name)) return;
        }
        try self.freevars.append(name);

        // Mark as cell in parent scope
        if (self.parent) |parent| {
            for (parent.cellvars.items) |cv| {
                if (std.mem.eql(u8, cv, name)) return;
            }
            try parent.cellvars.append(name);
        }
    }

    /// Get all defined symbols
    pub fn getDefinedSymbols(self: *const Self) []*Symbol {
        var defined = std.ArrayList(*Symbol).init(self.allocator);
        for (self.symbol_list.items) |sym| {
            if (sym.flags.defined) {
                defined.append(sym) catch continue;
            }
        }
        return defined.toOwnedSlice() catch &[_]*Symbol{};
    }

    /// Get all dead symbols (defined but not used)
    pub fn getDeadSymbols(self: *const Self) []*Symbol {
        var dead = std.ArrayList(*Symbol).init(self.allocator);
        for (self.symbol_list.items) |sym| {
            if (sym.isDead()) {
                dead.append(sym) catch continue;
            }
        }
        return dead.toOwnedSlice() catch &[_]*Symbol{};
    }

    /// Count symbols by kind
    pub fn countByKind(self: *const Self, kind: SymbolKind) usize {
        var count: usize = 0;
        for (self.symbol_list.items) |sym| {
            if (sym.kind == kind) count += 1;
        }
        return count;
    }
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

// ============================================================================
// Symbol Resolution
// ============================================================================

/// Symbol resolver
pub const SymbolResolver = struct {
    const Self = @This();

    allocator: Allocator,
    root_table: ?*SymbolTable = null,
    current_table: ?*SymbolTable = null,

    /// Create new resolver
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        if (self.root_table) |root| {
            root.deinit();
            self.allocator.destroy(root);
        }
    }

    /// Enter new scope
    pub fn enterScope(self: *Self, name: []const u8, scope_type: ScopeType) !void {
        if (self.current_table) |current| {
            self.current_table = try current.createChild(name, scope_type);
        } else {
            const root = try self.allocator.create(SymbolTable);
            root.* = SymbolTable.init(self.allocator, name, scope_type, 0);
            self.root_table = root;
            self.current_table = root;
        }
    }

    /// Exit current scope
    pub fn exitScope(self: *Self) void {
        if (self.current_table) |current| {
            self.current_table = current.parent;
        }
    }

    /// Define symbol in current scope
    pub fn define(self: *Self, name: []const u8, kind: SymbolKind, site: u32) !*Symbol {
        if (self.current_table) |table| {
            const sym = try table.addSymbol(name, kind);
            sym.define(site);
            return sym;
        }
        return error.NoScope;
    }

    /// Look up symbol
    pub fn lookup(self: *Self, name: []const u8) ?*Symbol {
        if (self.current_table) |table| {
            return table.lookupRecursive(name);
        }
        return null;
    }

    /// Add use of symbol
    pub fn addUse(self: *Self, name: []const u8, site: u32) !void {
        if (self.current_table) |table| {
            if (table.lookupRecursive(name)) |sym| {
                try sym.addUse(site);

                // Check if it's from enclosing scope
                if (sym.scope_depth < table.depth) {
                    try table.markFree(name);
                }
            }
        }
    }
};

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the optimizer symbols module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "symbol creation" {
    const allocator = std.testing.allocator;

    var table = SymbolTable.init(allocator, "<module>", .module, 0);
    defer table.deinit();

    const sym = try table.addSymbol("x", .local);
    sym.define(0);

    try std.testing.expectEqualStrings("x", sym.name);
    try std.testing.expectEqual(SymbolKind.local, sym.kind);
    try std.testing.expect(sym.flags.defined);
}

test "symbol lookup" {
    const allocator = std.testing.allocator;

    var table = SymbolTable.init(allocator, "<module>", .module, 0);
    defer table.deinit();

    _ = try table.addSymbol("foo", .global);

    try std.testing.expect(table.lookup("foo") != null);
    try std.testing.expect(table.lookup("bar") == null);
}

test "nested scopes" {
    const allocator = std.testing.allocator;

    var table = SymbolTable.init(allocator, "<module>", .module, 0);
    defer table.deinit();

    const outer = try table.addSymbol("outer_var", .global);
    outer.define(0);

    const child = try table.createChild("func", .function);
    _ = try child.addSymbol("inner_var", .local);

    // Should find outer_var through recursive lookup
    try std.testing.expect(child.lookupRecursive("outer_var") != null);
    try std.testing.expect(child.lookupRecursive("inner_var") != null);

    // Outer scope shouldn't see inner_var
    try std.testing.expect(table.lookup("inner_var") == null);
}

test "symbol resolver" {
    const allocator = std.testing.allocator;

    var resolver = SymbolResolver.init(allocator);
    defer resolver.deinit();

    try resolver.enterScope("<module>", .module);
    _ = try resolver.define("x", .global, 0);

    try resolver.enterScope("func", .function);
    _ = try resolver.define("y", .local, 10);

    // Can see both x and y in inner scope
    try std.testing.expect(resolver.lookup("x") != null);
    try std.testing.expect(resolver.lookup("y") != null);

    resolver.exitScope();

    // Can only see x in outer scope
    try std.testing.expect(resolver.lookup("x") != null);
    try std.testing.expect(resolver.lookup("y") == null);
}

test "free variables" {
    const allocator = std.testing.allocator;

    var table = SymbolTable.init(allocator, "<module>", .module, 0);
    defer table.deinit();

    const outer = try table.addSymbol("x", .local);
    outer.define(0);

    const inner = try table.createChild("func", .function);
    try inner.markFree("x");

    try std.testing.expectEqual(@as(usize, 1), inner.freevars.items.len);
    try std.testing.expectEqual(@as(usize, 1), table.cellvars.items.len);
}

test "dead symbol detection" {
    const allocator = std.testing.allocator;

    var table = SymbolTable.init(allocator, "<module>", .module, 0);
    defer table.deinit();

    const used = try table.addSymbol("used", .local);
    used.define(0);
    try used.addUse(10);

    const unused = try table.addSymbol("unused", .local);
    unused.define(5);
    // No uses added

    try std.testing.expect(!used.isDead());
    try std.testing.expect(unused.isDead());
}
