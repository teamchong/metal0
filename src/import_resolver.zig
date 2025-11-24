/// Import resolution for multi-file Python projects
const std = @import("std");

// Import submodules
const discovery = @import("import_resolver/discovery.zig");
const resolution = @import("import_resolver/resolution.zig");
const helpers = @import("import_resolver/helpers.zig");

// Re-export main functions for backward compatibility
pub const discoverSitePackages = discovery.discoverSitePackages;
pub const discoverStdlib = discovery.discoverStdlib;

pub const findInSitePackages = resolution.findInSitePackages;
pub const resolveImportSource = resolution.resolveImportSource;
pub const resolveImport = resolution.resolveImport;
pub const isLocalModule = resolution.isLocalModule;
pub const isCExtension = resolution.isCExtension;

pub const getFileDirectory = helpers.getFileDirectory;
pub const analyzePackage = helpers.analyzePackage;
pub const PackageInfo = helpers.PackageInfo;
