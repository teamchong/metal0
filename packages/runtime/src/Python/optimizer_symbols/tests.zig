/// Tests for optimizer symbols module
/// Verifies symbol table, resolver, and scope management functionality

const std = @import("std");
const types = @import("types.zig");
const symbol_table = @import("symbol_table.zig");
const symbol_resolver = @import("symbol_resolver.zig");

const SymbolKind = types.SymbolKind;
const ScopeType = types.ScopeType;
const SymbolTable = symbol_table.SymbolTable;
const SymbolResolver = symbol_resolver.SymbolResolver;

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
    try used.addUse(allocator, 10);

    const unused = try table.addSymbol("unused", .local);
    unused.define(5);
    // No uses added

    try std.testing.expect(!used.isDead());
    try std.testing.expect(unused.isDead());
}
