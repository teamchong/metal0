//! CPython source: Lib/pkgutil.py
//!
//! Utilities to support packages (finding, importing, iterating).
//!
//! Mirrors: CPython Lib/pkgutil.py
//!
//! This module provides a modular pkgutil implementation split into focused submodules.

// Re-export core types
pub const types = @import("pkgutil/types.zig");
pub const ModuleInfo = types.ModuleInfo;
pub const Importer = types.Importer;
pub const LoaderResult = types.LoaderResult;

// Re-export iterator functionality
pub const iterator = @import("pkgutil/iterator.zig");
pub const ModuleIterator = iterator.ModuleIterator;
pub const iter_modules = iterator.iter_modules;

// Re-export walker functionality
pub const walker = @import("pkgutil/walker.zig");
pub const walk_packages = walker.walk_packages;

// Re-export loader functionality
pub const loader = @import("pkgutil/loader.zig");
pub const get_importer = loader.get_importer;
pub const find_loader = loader.find_loader;
pub const get_loader = loader.get_loader;

// Re-export resolver functionality
pub const resolver = @import("pkgutil/resolver.zig");
pub const resolve_name = resolver.resolve_name;

// Re-export path utilities
pub const path_utils = @import("pkgutil/path_utils.zig");
pub const get_data = path_utils.get_data;
pub const extend_path = path_utils.extend_path;

// Re-export module initialization
pub const module_init = @import("pkgutil/init.zig");
pub const init = module_init.init;
pub const reset = module_init.reset;
