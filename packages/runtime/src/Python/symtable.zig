/// symtable - Symbol Table Analysis
/// Mirrors cpython/Python/symtable.c
///
/// This module provides symbol table functionality for Python compilation:
/// - Name binding analysis (local, global, free, cell)
/// - Scope resolution
/// - Nested scope tracking
/// - Comprehension handling
/// - Class/function distinction

const std = @import("std");
const Allocator = std.mem.Allocator;

// Re-export submodules
pub const types = @import("symtable/types.zig");
pub const entry = @import("symtable/entry.zig");
pub const table = @import("symtable/table.zig");
pub const builder = @import("symtable/builder.zig");

// Re-export from types.zig
pub const BlockType = types.BlockType;
pub const ComprehensionType = types.ComprehensionType;
pub const SymbolFlags = types.SymbolFlags;
pub const Scope = types.Scope;
pub const SourceLocation = types.SourceLocation;
pub const FutureFeatures = types.FutureFeatures;
pub const ErrorMessages = types.ErrorMessages;

// Re-export from entry.zig
pub const SymbolTableEntry = entry.SymbolTableEntry;

// Re-export from table.zig
pub const SymbolTable = table.SymbolTable;

// Re-export from builder.zig
pub const SymbolTableBuilder = builder.SymbolTableBuilder;

// ============================================================================
// Initialization
// ============================================================================

/// Initialize symtable module
pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test {
    _ = types;
    _ = entry;
    _ = table;
    _ = builder;
}
