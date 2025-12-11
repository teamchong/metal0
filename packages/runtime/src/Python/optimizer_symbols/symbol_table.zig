/// Symbol table for tracking symbols within a scope
/// Supports nested scopes with parent/child relationships

const std = @import("std");
const Allocator = std.mem.Allocator;
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");

pub const Symbol = types.Symbol;
pub const SymbolKind = types.SymbolKind;
pub const ScopeType = types.ScopeType;

// ============================================================================
// Symbol Table
// ============================================================================

/// Symbol table for a scope
pub const SymbolTable = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// Symbols by name
    symbols: hashmap_helper.StringHashMap(*Symbol),
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
            .symbols = hashmap_helper.StringHashMap(*Symbol).init(allocator),
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
            sym.deinit(self.allocator);
            self.allocator.destroy(sym);
        }
        self.symbols.deinit();
        self.symbol_list.deinit(self.allocator);
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit(self.allocator);
        self.freevars.deinit(self.allocator);
        self.cellvars.deinit(self.allocator);
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
        try self.symbol_list.append(self.allocator, sym);

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
        try self.children.append(self.allocator, child);
        return child;
    }

    /// Mark symbol as free variable
    pub fn markFree(self: *Self, name: []const u8) !void {
        // Add to freevars if not already present
        for (self.freevars.items) |fv| {
            if (std.mem.eql(u8, fv, name)) return;
        }
        try self.freevars.append(self.allocator, name);

        // Mark as cell in parent scope
        if (self.parent) |parent| {
            for (parent.cellvars.items) |cv| {
                if (std.mem.eql(u8, cv, name)) return;
            }
            try parent.cellvars.append(self.allocator, name);
        }
    }

    /// Get all defined symbols
    pub fn getDefinedSymbols(self: *const Self) []*Symbol {
        var defined = std.ArrayList(*Symbol).init(self.allocator);
        for (self.symbol_list.items) |sym| {
            if (sym.flags.defined) {
                defined.append(self.allocator, sym) catch continue;
            }
        }
        return defined.toOwnedSlice(self.allocator) catch &[_]*Symbol{};
    }

    /// Get all dead symbols (defined but not used)
    pub fn getDeadSymbols(self: *const Self) []*Symbol {
        var dead = std.ArrayList(*Symbol).init(self.allocator);
        for (self.symbol_list.items) |sym| {
            if (sym.isDead()) {
                dead.append(self.allocator, sym) catch continue;
            }
        }
        return dead.toOwnedSlice(self.allocator) catch &[_]*Symbol{};
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
