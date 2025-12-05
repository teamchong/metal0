/// Source Map Module
///
/// Re-exports debug_info types for source mapping.
/// This is a convenience wrapper - the actual implementation is in debug_info.zig
///
/// Usage:
///   const source_map = @import("source_map");
///   var writer = source_map.DebugInfoWriter.init(allocator, "file.py", source);
///
const debug_info = @import("debug_info.zig");

// Re-export main types
pub const SourceLoc = debug_info.SourceLoc;
pub const Symbol = debug_info.Symbol;
pub const SymbolKind = debug_info.SymbolKind;
pub const StmtLoc = debug_info.StmtLoc;
pub const CodeMapping = debug_info.CodeMapping;
pub const DebugInfo = debug_info.DebugInfo;
pub const DebugInfoWriter = debug_info.DebugInfoWriter;
pub const DebugInfoReader = debug_info.DebugInfoReader;

// For backwards compatibility during migration
pub const SourceMapCollector = debug_info.DebugInfoWriter;
