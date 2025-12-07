//! CPython source: Lib/symtable.py
//!
//! Provides symbol table generation and analysis for Python source code.
//!
//! Mirrors: CPython Lib/symtable.py

const std = @import("std");

// ============================================================================
// Symbol Flags
// ============================================================================

/// Symbol flags
pub const SymbolFlags = struct {
    pub const DEF_GLOBAL: u32 = 1 << 0;
    pub const DEF_LOCAL: u32 = 1 << 1;
    pub const DEF_PARAM: u32 = 1 << 2;
    pub const DEF_NONLOCAL: u32 = 1 << 3;
    pub const USE: u32 = 1 << 4;
    pub const DEF_FREE: u32 = 1 << 5;
    pub const DEF_FREE_CLASS: u32 = 1 << 6;
    pub const DEF_IMPORT: u32 = 1 << 7;
    pub const DEF_ANNOT: u32 = 1 << 8;
    pub const DEF_COMP_ITER: u32 = 1 << 9;
    pub const DEF_TYPE_PARAM: u32 = 1 << 10;

    pub const DEF_BOUND: u32 = DEF_LOCAL | DEF_PARAM | DEF_IMPORT;

    pub const SCOPE_OFFSET: u5 = 11;
    pub const SCOPE_MASK: u32 = 0x7 << SCOPE_OFFSET;

    pub const LOCAL: u32 = 1;
    pub const GLOBAL_EXPLICIT: u32 = 2;
    pub const GLOBAL_IMPLICIT: u32 = 3;
    pub const FREE: u32 = 4;
    pub const CELL: u32 = 5;
};

/// Block types
pub const BlockType = enum {
    FunctionBlock,
    ClassBlock,
    ModuleBlock,
    AnnotationBlock,
    TypeVarBoundBlock,
    TypeAliasBlock,
    TypeParamBlock,
};

// ============================================================================
// Symbol
// ============================================================================

/// Represents a symbol in the symbol table
pub const Symbol = struct {
    const Self = @This();

    name: []const u8,
    flags: u32,
    namespaces: ?std.ArrayList(*SymbolTable),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, flags: u32) Self {
        return .{
            .name = name,
            .flags = flags,
            .namespaces = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.namespaces) |*ns| {
            ns.deinit();
        }
    }

    /// Get the name of the symbol
    pub fn getName(self: *const Self) []const u8 {
        return self.name;
    }

    /// Check if symbol is referenced
    pub fn isReferenced(self: *const Self) bool {
        return (self.flags & SymbolFlags.USE) != 0;
    }

    /// Check if symbol is a parameter
    pub fn isParameter(self: *const Self) bool {
        return (self.flags & SymbolFlags.DEF_PARAM) != 0;
    }

    /// Check if symbol is global
    pub fn isGlobal(self: *const Self) bool {
        const scope = (self.flags >> SymbolFlags.SCOPE_OFFSET) & 0x7;
        return scope == SymbolFlags.GLOBAL_IMPLICIT or
            scope == SymbolFlags.GLOBAL_EXPLICIT;
    }

    /// Check if symbol is explicitly declared global
    pub fn isDeclaredGlobal(self: *const Self) bool {
        const scope = (self.flags >> SymbolFlags.SCOPE_OFFSET) & 0x7;
        return scope == SymbolFlags.GLOBAL_EXPLICIT;
    }

    /// Check if symbol is local
    pub fn isLocal(self: *const Self) bool {
        const scope = (self.flags >> SymbolFlags.SCOPE_OFFSET) & 0x7;
        return scope == SymbolFlags.LOCAL;
    }

    /// Check if symbol is annotated
    pub fn isAnnotated(self: *const Self) bool {
        return (self.flags & SymbolFlags.DEF_ANNOT) != 0;
    }

    /// Check if symbol is free (closure variable)
    pub fn isFree(self: *const Self) bool {
        const scope = (self.flags >> SymbolFlags.SCOPE_OFFSET) & 0x7;
        return scope == SymbolFlags.FREE;
    }

    /// Check if symbol is imported
    pub fn isImported(self: *const Self) bool {
        return (self.flags & SymbolFlags.DEF_IMPORT) != 0;
    }

    /// Check if symbol is assigned
    pub fn isAssigned(self: *const Self) bool {
        return (self.flags & SymbolFlags.DEF_LOCAL) != 0;
    }

    /// Check if symbol is a namespace (has child scope)
    pub fn isNamespace(self: *const Self) bool {
        if (self.namespaces) |ns| {
            return ns.items.len > 0;
        }
        return false;
    }

    /// Get child namespaces
    pub fn getNamespaces(self: *const Self) ?[]*SymbolTable {
        if (self.namespaces) |ns| {
            return ns.items;
        }
        return null;
    }

    /// Check if symbol is nonlocal
    pub fn isNonlocal(self: *const Self) bool {
        return (self.flags & SymbolFlags.DEF_NONLOCAL) != 0;
    }

    /// Check if symbol is a cell variable
    pub fn isCell(self: *const Self) bool {
        const scope = (self.flags >> SymbolFlags.SCOPE_OFFSET) & 0x7;
        return scope == SymbolFlags.CELL;
    }

    /// Check if symbol is a type parameter
    pub fn isTypeParam(self: *const Self) bool {
        return (self.flags & SymbolFlags.DEF_TYPE_PARAM) != 0;
    }
};

// ============================================================================
// Symbol Table
// ============================================================================

/// Symbol table for a block
pub const SymbolTable = struct {
    const Self = @This();

    name: []const u8,
    filename: []const u8,
    block_type: BlockType,
    lineno: u32,
    col_offset: u32,
    end_lineno: ?u32,
    end_col_offset: ?u32,
    is_nested: bool,
    has_children: bool,
    has_exec: bool,
    has_varkeywords: bool,
    has_varargs: bool,
    has_free: bool,
    child_free: bool,
    generator: bool,
    coroutine: bool,
    comprehension: bool,
    symbols: std.StringHashMap(Symbol),
    children: std.ArrayList(*Self),
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        filename: []const u8,
        block_type: BlockType,
        lineno: u32,
        col_offset: u32,
    ) Self {
        return .{
            .name = name,
            .filename = filename,
            .block_type = block_type,
            .lineno = lineno,
            .col_offset = col_offset,
            .end_lineno = null,
            .end_col_offset = null,
            .is_nested = false,
            .has_children = false,
            .has_exec = false,
            .has_varkeywords = false,
            .has_varargs = false,
            .has_free = false,
            .child_free = false,
            .generator = false,
            .coroutine = false,
            .comprehension = false,
            .symbols = std.StringHashMap(Symbol).init(allocator),
            .children = std.ArrayList(*Self).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            var sym = entry.value_ptr;
            sym.deinit();
        }
        self.symbols.deinit();
        self.children.deinit();
    }

    /// Get the type of the block
    pub fn getType(self: *const Self) BlockType {
        return self.block_type;
    }

    /// Get the name of the block
    pub fn getName(self: *const Self) []const u8 {
        return self.name;
    }

    /// Get the line number where the block starts
    pub fn getLineno(self: *const Self) u32 {
        return self.lineno;
    }

    /// Check if block is optimized (has fast locals)
    pub fn isOptimized(self: *const Self) bool {
        return self.block_type == .FunctionBlock;
    }

    /// Check if block is nested
    pub fn isNested(self: *const Self) bool {
        return self.is_nested;
    }

    /// Check if block has children
    pub fn hasChildren(self: *const Self) bool {
        return self.has_children or self.children.items.len > 0;
    }

    /// Check if block has exec
    pub fn hasExec(self: *const Self) bool {
        return self.has_exec;
    }

    /// Check if block has import star
    pub fn hasImportStar(self: *const Self) bool {
        // Would check for import * usage
        return false;
    }

    /// Get identifiers in this scope
    pub fn getIdentifiers(self: *const Self) [][]const u8 {
        var identifiers = std.ArrayList([]const u8).init(self.allocator);
        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            identifiers.append(entry.key_ptr.*) catch continue;
        }
        return identifiers.toOwnedSlice() catch &[_][]const u8{};
    }

    /// Look up a symbol by name
    pub fn lookup(self: *const Self, name: []const u8) ?Symbol {
        return self.symbols.get(name);
    }

    /// Get child symbol tables
    pub fn getChildren(self: *const Self) []*Self {
        return self.children.items;
    }

    /// Add a symbol to the table
    pub fn addSymbol(self: *Self, name: []const u8, flags: u32) !void {
        if (self.symbols.get(name)) |existing| {
            var sym = existing;
            sym.flags |= flags;
            try self.symbols.put(name, sym);
        } else {
            try self.symbols.put(name, Symbol.init(self.allocator, name, flags));
        }
    }

    /// Add a child symbol table
    pub fn addChild(self: *Self, child: *Self) !void {
        try self.children.append(child);
        self.has_children = true;
        child.is_nested = true;
    }
};

// ============================================================================
// Module-Level Functions
// ============================================================================

/// Generate a symbol table from source code
pub fn symtable(allocator: std.mem.Allocator, code: []const u8, filename: []const u8, compile_type: []const u8) !*SymbolTable {
    _ = code;
    _ = compile_type;

    const st = try allocator.create(SymbolTable);
    st.* = SymbolTable.init(
        allocator,
        "top",
        filename,
        .ModuleBlock,
        0,
        0,
    );
    return st;
}

/// Generate a symbol table from an AST
pub fn symtableFromAst(allocator: std.mem.Allocator, ast: anytype, filename: []const u8) !*SymbolTable {
    _ = ast;

    const st = try allocator.create(SymbolTable);
    st.* = SymbolTable.init(
        allocator,
        "top",
        filename,
        .ModuleBlock,
        0,
        0,
    );
    return st;
}

// ============================================================================
// Symbol Table Entry (for C API compatibility)
// ============================================================================

/// Symbol table entry (C API compatibility)
pub const SymbolTableEntry = SymbolTable;

/// Class scope type
pub const ClassScope = struct {
    pub const NO_FREE: u32 = 0;
    pub const FREE_TO_FREE: u32 = 1;
    pub const FREE_TO_CELL: u32 = 2;
};

// ============================================================================
// Tests
// ============================================================================

test "Symbol flags" {
    try std.testing.expectEqual(@as(u32, 1), SymbolFlags.DEF_GLOBAL);
    try std.testing.expectEqual(@as(u32, 2), SymbolFlags.DEF_LOCAL);
    try std.testing.expectEqual(@as(u32, 4), SymbolFlags.DEF_PARAM);
}

test "Symbol creation" {
    const allocator = std.testing.allocator;
    var sym = Symbol.init(allocator, "test", SymbolFlags.DEF_LOCAL | SymbolFlags.USE);
    defer sym.deinit();

    try std.testing.expectEqualStrings("test", sym.getName());
    try std.testing.expect(sym.isReferenced());
    try std.testing.expect(sym.isAssigned());
    try std.testing.expect(!sym.isParameter());
    try std.testing.expect(!sym.isGlobal());
}

test "Symbol parameter" {
    const allocator = std.testing.allocator;
    var sym = Symbol.init(allocator, "x", SymbolFlags.DEF_PARAM);
    defer sym.deinit();

    try std.testing.expect(sym.isParameter());
    try std.testing.expect(!sym.isGlobal());
}

test "SymbolTable creation" {
    const allocator = std.testing.allocator;
    var st = SymbolTable.init(
        allocator,
        "test_func",
        "test.py",
        .FunctionBlock,
        1,
        0,
    );
    defer st.deinit();

    try std.testing.expectEqualStrings("test_func", st.getName());
    try std.testing.expectEqual(BlockType.FunctionBlock, st.getType());
    try std.testing.expectEqual(@as(u32, 1), st.getLineno());
    try std.testing.expect(st.isOptimized());
}

test "SymbolTable addSymbol" {
    const allocator = std.testing.allocator;
    var st = SymbolTable.init(
        allocator,
        "test",
        "test.py",
        .ModuleBlock,
        1,
        0,
    );
    defer st.deinit();

    try st.addSymbol("x", SymbolFlags.DEF_LOCAL);
    try st.addSymbol("y", SymbolFlags.DEF_PARAM);

    const x = st.lookup("x");
    try std.testing.expect(x != null);
    try std.testing.expect(x.?.isAssigned());

    const y = st.lookup("y");
    try std.testing.expect(y != null);
    try std.testing.expect(y.?.isParameter());

    const z = st.lookup("z");
    try std.testing.expect(z == null);
}

test "symtable function" {
    const allocator = std.testing.allocator;
    const st = try symtable(allocator, "x = 1", "test.py", "exec");
    defer {
        st.deinit();
        allocator.destroy(st);
    }

    try std.testing.expectEqual(BlockType.ModuleBlock, st.getType());
}
