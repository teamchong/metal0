// Temporary stub for c_interop - re-exports from packages/c_interop
// This allows existing imports to work during refactoring
const c_interop_registry = @import("c_interop");

pub const ImportContext = c_interop_registry.ImportContext;
pub const MappingRegistry = c_interop_registry.MappingRegistry;
pub const FunctionMapping = c_interop_registry.FunctionMapping;
