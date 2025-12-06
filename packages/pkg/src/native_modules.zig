//! Native Modules - PyPI packages with Zig implementations
//!
//! This file re-exports the auto-generated native_modules_gen.zig
//! which is built from packages/*/package.json
//!
//! To add a new PyPI override:
//!   1. Create packages/{name}/package.json with "pypi": ["pypi-name"]
//!   2. Run: python3 scripts/gen_packages.py
//!
//! See: .claude/CLAUDE.md for full documentation

pub usingnamespace @import("native_modules_gen.zig");
