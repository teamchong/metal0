//! metal0 Package Manager
//!
//! Compile-time package management for metal0.
//! Auto-installs dependencies, supports PyPI + multi-language registries.
//!
//! ## Architecture
//! ```
//! pkg/
//! ├── parse/      # Format parsers (PEP 440, 508, requirements.txt, METADATA)
//! ├── resolve/    # Dependency resolution (PubGrub, cache, installed packages)
//! ├── fetch/      # Download (PyPI API, wheel selection, parallel)
//! ├── install/    # Extract & verify (wheel, tarball)
//! ├── link/       # Native linking (.so/.dylib/.dll tree-shaking)
//! └── analyze/    # Import scanning, usage analysis
//! ```

const std = @import("std");

// Phase 1: Parsers
pub const pep440 = @import("parse/pep440.zig");
pub const pep508 = @import("parse/pep508.zig");
pub const requirements = @import("parse/requirements.zig");
pub const metadata = @import("parse/metadata.zig");
pub const record = @import("parse/record.zig");
pub const toml = @import("parse/toml.zig");
pub const pyproject = @import("parse/pyproject.zig");

// Phase 2: Fetchers
pub const pypi = @import("fetch/pypi.zig");
pub const wheel = @import("fetch/wheel.zig");
pub const cache = @import("fetch/cache.zig");
pub const scheduler = @import("fetch/scheduler.zig");

// Phase 3: Resolver
pub const resolver = @import("resolve/resolver.zig");

// Phase 4: Installer
pub const installer = @import("install/installer.zig");

// Conformance tests (from Python packaging library)
pub const pep440_conformance = @import("parse/pep440_conformance.zig");
pub const pep508_conformance = @import("parse/pep508_conformance.zig");

// Re-export main types - Parsers
pub const Version = pep440.Version;
pub const VersionSpec = pep440.VersionSpec;
pub const Dependency = pep508.Dependency;
pub const Requirement = requirements.Requirement;
pub const PackageMetadata = metadata.PackageMetadata;
pub const InstalledFile = record.InstalledFile;
pub const TomlTable = toml.Table;
pub const PyProject = pyproject.PyProject;

// Re-export main types - Fetchers
pub const PyPIClient = pypi.PyPIClient;
pub const WheelSelector = wheel.WheelSelector;
pub const WheelInfo = wheel.WheelInfo;
pub const Platform = wheel.Platform;
pub const Cache = cache.Cache;
pub const MemoryCache = cache.MemoryCache;
pub const FetchScheduler = scheduler.FetchScheduler;

// Re-export main types - Resolver
pub const Resolver = resolver.Resolver;
pub const Resolution = resolver.Resolution;

// Re-export main types - Installer
pub const Installer = installer.Installer;
pub const PackageInfo = installer.PackageInfo;
pub const InstallResult = installer.InstallResult;

test {
    std.testing.refAllDecls(@This());
}
