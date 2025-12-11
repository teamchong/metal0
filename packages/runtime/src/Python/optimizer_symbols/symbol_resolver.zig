/// Symbol resolver for tracking symbols across scopes
/// Manages scope entry/exit and symbol definitions/uses

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const symbol_table = @import("symbol_table.zig");

pub const Symbol = types.Symbol;
pub const SymbolKind = types.SymbolKind;
pub const ScopeType = types.ScopeType;
pub const SymbolTable = symbol_table.SymbolTable;

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
                try sym.addUse(self.allocator, site);

                // Check if it's from enclosing scope
                if (sym.scope_depth < table.depth) {
                    try table.markFree(name);
                }
            }
        }
    }
};
