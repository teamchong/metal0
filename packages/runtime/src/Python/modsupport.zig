/// modsupport - Module Support Functions
/// Mirrors cpython/Python/modsupport.c
///
/// This module provides functions for building Python objects from C values
/// (Py_BuildValue) and for module initialization helpers (PyModule_Add*).
///
/// Re-exports all submodules for compatibility with existing code.

// Re-export value builder components
pub const value_builder = @import("modsupport/value_builder.zig");
pub const BuiltValue = value_builder.BuiltValue;
pub const FormatChar = value_builder.FormatChar;
pub const BuildError = value_builder.BuildError;
pub const ValueBuilder = value_builder.ValueBuilder;
pub const ArgIterator = value_builder.ArgIterator;

// Re-export module definition components
pub const module_def = @import("modsupport/module_def.zig");
pub const ModuleDef = module_def.ModuleDef;
pub const MethodDef = module_def.MethodDef;
pub const ModuleSlot = module_def.ModuleSlot;
pub const ModuleState = module_def.ModuleState;
pub const ModuleObject = module_def.ModuleObject;
pub const GILState = module_def.GILState;
pub const InitGuard = module_def.InitGuard;
pub const ensureGIL = module_def.ensureGIL;
pub const releaseGIL = module_def.releaseGIL;
pub const moduleCreate = module_def.moduleCreate;

// Re-export module operations
pub const module_ops = @import("modsupport/module_ops.zig");
pub const moduleAddObject = module_ops.moduleAddObject;
pub const moduleAddObjectRef = module_ops.moduleAddObjectRef;
pub const moduleAddIntConstant = module_ops.moduleAddIntConstant;
pub const moduleAddStringConstant = module_ops.moduleAddStringConstant;
pub const moduleAddType = module_ops.moduleAddType;
pub const moduleExecDef = module_ops.moduleExecDef;
pub const moduleGetState = module_ops.moduleGetState;
pub const moduleGetDef = module_ops.moduleGetDef;
pub const moduleGetDict = module_ops.moduleGetDict;
pub const moduleGetName = module_ops.moduleGetName;
pub const convertOptionalToSsizeT = module_ops.convertOptionalToSsizeT;
pub const convertOptionalToNonNegativeSsizeT = module_ops.convertOptionalToNonNegativeSsizeT;

// Re-export module registry
pub const module_registry = @import("modsupport/module_registry.zig");
pub const ModuleRegistry = module_registry.ModuleRegistry;
pub const getModuleRegistry = module_registry.getModuleRegistry;
pub const init = module_registry.init;
pub const fini = module_registry.fini;
