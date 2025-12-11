/// import - Python Import System
/// Mirrors cpython/Python/import.c
///
/// Implements the core import machinery:
/// - Module loading and caching (sys.modules)
/// - Module definition handling
/// - Built-in and frozen module support
/// - Extension module loading
/// - Import hooks (finders, loaders)
/// - Package initialization

const std = @import("std");

// Submodule imports
const types_mod = @import("import/types.zig");
const state_mod = @import("import/state.zig");
const builtins_mod = @import("import/builtins.zig");
const lock_mod = @import("import/lock.zig");
const modules_mod = @import("import/modules.zig");
const loader_mod = @import("import/loader.zig");

// ============================================================================
// Re-exports from types.zig
// ============================================================================
pub const ModuleDef = types_mod.ModuleDef;
pub const ModuleDefBase = types_mod.ModuleDefBase;
pub const MethodDef = types_mod.MethodDef;
pub const ModuleDefSlotId = types_mod.ModuleDefSlotId;
pub const ModuleDefSlot = types_mod.ModuleDefSlot;
pub const InitFunc = types_mod.InitFunc;
pub const TraverseFunc = types_mod.TraverseFunc;
pub const ClearFunc = types_mod.ClearFunc;
pub const FreeFunc = types_mod.FreeFunc;
pub const InittabEntry = types_mod.InittabEntry;
pub const FrozenModule = types_mod.FrozenModule;

// ============================================================================
// Re-exports from state.zig
// ============================================================================
pub const ImportState = state_mod.ImportState;
pub const init = state_mod.init;
pub const fini = state_mod.fini;
pub const initModuleTables = state_mod.initModuleTables;

// ============================================================================
// Re-exports from lock.zig
// ============================================================================
pub const acquireLock = lock_mod.acquireLock;
pub const releaseLock = lock_mod.releaseLock;
pub const lockHeld = lock_mod.lockHeld;

// ============================================================================
// Re-exports from modules.zig
// ============================================================================
pub const ImportError = modules_mod.ImportError;
pub const initModules = modules_mod.initModules;
pub const getModuleDict = modules_mod.getModuleDict;
pub const getModule = modules_mod.getModule;
pub const setModule = modules_mod.setModule;
pub const removeModule = modules_mod.removeModule;
pub const clearModules = modules_mod.clearModules;
pub const findBuiltin = modules_mod.findBuiltin;
pub const findFrozen = modules_mod.findFrozen;
pub const isBuiltin = modules_mod.isBuiltin;
pub const isFrozen = modules_mod.isFrozen;

// ============================================================================
// Re-exports from loader.zig
// ============================================================================
pub const ModuleObject = loader_mod.ModuleObject;
pub const importModule = loader_mod.importModule;
pub const importModuleEx = loader_mod.importModuleEx;
pub const importModuleLevel = loader_mod.importModuleLevel;
pub const loadFrozenModule = loader_mod.loadFrozenModule;
pub const addModule = loader_mod.addModule;
pub const reloadModule = loader_mod.reloadModule;
pub const getNextModuleIndex = loader_mod.getNextModuleIndex;
pub const getModuleByIndex = loader_mod.getModuleByIndex;
pub const setModuleByIndex = loader_mod.setModuleByIndex;
pub const moduleCreate = loader_mod.moduleCreate;
pub const moduleCreate2 = loader_mod.moduleCreate2;
pub const moduleDefInit = loader_mod.moduleDefInit;
pub const FileTab = loader_mod.FileTab;
pub const import_filetab = loader_mod.import_filetab;
