/// optimizer_symbols - Optimizer Symbol Table
/// Mirrors cpython/Python/optimizer_symbols.c
///
/// Symbol table for the bytecode optimizer, tracking variable types,
/// definitions, and uses during optimization.

// Re-export all types
pub const types = @import("optimizer_symbols/types.zig");
pub const SymbolKind = types.SymbolKind;
pub const SymbolFlags = types.SymbolFlags;
pub const Symbol = types.Symbol;
pub const TypeInfo = types.TypeInfo;
pub const TypeId = types.TypeId;
pub const ConstValue = types.ConstValue;
pub const ScopeType = types.ScopeType;

// Re-export symbol table
pub const symbol_table = @import("optimizer_symbols/symbol_table.zig");
pub const SymbolTable = symbol_table.SymbolTable;

// Re-export symbol resolver
pub const symbol_resolver = @import("optimizer_symbols/symbol_resolver.zig");
pub const SymbolResolver = symbol_resolver.SymbolResolver;

// Re-export initialization functions
pub const init_module = @import("optimizer_symbols/init.zig");
pub const init = init_module.init;
pub const reset = init_module.reset;

// Re-export tests
pub const tests = @import("optimizer_symbols/tests.zig");

// Convenience test export
test {
    @import("std").testing.refAllDecls(@This());
}
