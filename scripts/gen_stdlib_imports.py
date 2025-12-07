#!/usr/bin/env python3
"""
Unified stdlib/import generator for metal0

Scans all Zig module directories and generates:
1. stdlib_modules_gen.zig - Complete list of available modules
2. Auto-registers discovered modules in import_registry.zig

Usage:
    python3 scripts/gen_stdlib_imports.py
    # Or via Makefile:
    make gen-stdlib
"""

import os
import re
from pathlib import Path
from typing import Set, Dict, List, Tuple

# Root directory
ROOT = Path(__file__).parent.parent

# Directories to scan for auto-discovery
SCAN_DIRS = [
    # Primary Lib/ directory (CPython stdlib)
    ("packages/runtime/src/Lib", ""),
    # Modules directory (CPython Modules/)
    ("packages/runtime/src/Modules", ""),
    # Objects directory (CPython Objects/)
    ("packages/runtime/src/Objects", "_objects."),
    # Python directory (CPython Python/)
    ("packages/runtime/src/Python", "_python."),
    # c_interop objects (CPython Objects/ mirror)
    ("packages/c_interop/src/objects", "_c_objects."),
    # c_interop modules (CPython Modules/ mirror)
    ("packages/c_interop/src/modules", "_c_modules."),
]

# Files/patterns to exclude (internal implementation details)
EXCLUDE_PATTERNS = [
    r"^_impl$",       # Internal implementation modules
    r"_impl/",        # Implementation subdirectories
    r"/utils/",       # Utility subdirectories
    r"test_",         # Test files
    r"benchmark",     # Benchmark files
    r"\.test\.zig$",  # Test files
    r"mimalloc/",     # mimalloc allocator internals
    r"prim/",         # Platform primitives
]

# Modules that MUST NOT be auto-registered (need special handling)
MANUAL_REGISTRY_MODULES = {
    # Core modules with special function metadata
    "json", "http", "http.client", "requests", "asyncio", "re", "sys", "time", "math",
    "unittest", "sqlite3", "zlib", "ssl", "hashlib", "io", "struct", "base64",
    "pickle", "hmac", "socket", "os", "random", "collections", "collections.abc",
    "functools", "itertools", "logging", "threading", "queue", "copy", "operator",
    "typing", "ast", "contextlib", "string", "_string", "_testcapi", "_testbuffer",
    "shutil", "glob", "fnmatch", "secrets", "csv", "configparser", "argparse",
    "zipfile", "gzip", "textwrap", "uuid", "tempfile", "subprocess", "heapq",
    "bisect", "statistics", "decimal", "fractions", "cmath", "html", "xml", "email",
    "signal", "multiprocessing", "array", "weakref", "types", "abc", "inspect",
    "dataclasses", "enum", "atexit", "warnings", "traceback", "pprint", "ctypes",
    "_ctypes", "platform", "locale", "codecs", "calendar", "binascii", "errno", "gc",
    "builtins", "metal0", "metal0.tokenizer",
}


def should_exclude(filepath: str) -> bool:
    """Check if file should be excluded from discovery."""
    for pattern in EXCLUDE_PATTERNS:
        if re.search(pattern, filepath):
            return True
    return False


def scan_directory(base_dir: Path, prefix: str) -> Set[str]:
    """Recursively scan directory for .zig files and return module names."""
    modules = set()

    if not base_dir.exists():
        return modules

    for root, dirs, files in os.walk(base_dir):
        # Skip hidden directories
        dirs[:] = [d for d in dirs if not d.startswith('.')]

        for file in files:
            if not file.endswith('.zig'):
                continue

            filepath = os.path.join(root, file)
            relpath = os.path.relpath(filepath, base_dir)

            # Check exclusions
            if should_exclude(relpath):
                continue

            # Convert path to module name
            # foo/bar/baz.zig -> foo.bar.baz
            module_name = relpath.replace('/', '.').replace('\\', '.')
            module_name = module_name[:-4]  # Remove .zig

            # Apply prefix for non-Lib directories
            if prefix:
                module_name = prefix + module_name

            modules.add(module_name)

    return modules


def discover_all_modules() -> Tuple[Set[str], Dict[str, str]]:
    """
    Discover all modules from all scan directories.

    Returns:
        (all_modules, source_map) where source_map maps module -> source directory
    """
    all_modules = set()
    source_map = {}

    for scan_dir, prefix in SCAN_DIRS:
        dir_path = ROOT / scan_dir
        modules = scan_directory(dir_path, prefix)

        for mod in modules:
            if mod not in all_modules:
                all_modules.add(mod)
                source_map[mod] = scan_dir

    return all_modules, source_map


def generate_stdlib_modules_gen(modules: Set[str], source_map: Dict[str, str]) -> str:
    """Generate the stdlib_modules_gen.zig file content."""
    sorted_modules = sorted(modules)

    # Build module list with categories
    lib_modules = []
    objects_modules = []
    python_modules = []
    c_interop_modules = []

    for mod in sorted_modules:
        source = source_map.get(mod, "")
        if "c_interop" in source:
            c_interop_modules.append(mod)
        elif "Objects" in source or mod.startswith("_objects."):
            objects_modules.append(mod)
        elif "Python" in source or mod.startswith("_python."):
            python_modules.append(mod)
        else:
            lib_modules.append(mod)

    lines = [
        '//! Auto-generated stdlib module list - DO NOT EDIT',
        '//! Generated by: python3 scripts/gen_stdlib_imports.py',
        '//!',
        '//! Sources:',
        '//!   - packages/runtime/src/Lib/*.zig (stdlib)',
        '//!   - packages/runtime/src/Modules/*.zig (C extension modules)',
        '//!   - packages/runtime/src/Objects/*.zig (object implementations)',
        '//!   - packages/runtime/src/Python/*.zig (interpreter internals)',
        '//!   - packages/c_interop/src/objects/*.zig (CPython object mirrors)',
        '//!   - packages/c_interop/src/modules/*.zig (CPython module mirrors)',
        '',
        'const std = @import("std");',
        '',
        '/// List of all discovered stdlib module files',
        '/// Format: module_name (derived from filename without .zig)',
        'pub const stdlib_module_names = [_][]const u8{',
    ]

    # Add modules grouped by category
    if lib_modules:
        lines.append('    // === Lib/ (stdlib) ===')
        for mod in lib_modules:
            lines.append(f'    "{mod}",')

    if objects_modules:
        lines.append('    // === Objects/ ===')
        for mod in objects_modules:
            lines.append(f'    "{mod}",')

    if python_modules:
        lines.append('    // === Python/ (interpreter) ===')
        for mod in python_modules:
            lines.append(f'    "{mod}",')

    if c_interop_modules:
        lines.append('    // === c_interop/ ===')
        for mod in c_interop_modules:
            lines.append(f'    "{mod}",')

    lines.extend([
        '};',
        '',
        f'/// Number of discovered stdlib modules',
        f'pub const stdlib_module_count: usize = {len(sorted_modules)};',
        '',
        '/// Check if a module name exists in stdlib',
        'pub fn hasModule(name: []const u8) bool {',
        '    for (stdlib_module_names) |mod| {',
        '        if (std.mem.eql(u8, name, mod)) return true;',
        '    }',
        '    return false;',
        '}',
        '',
        '/// Get modules that can be auto-registered (not in manual registry)',
        '/// These are modules that have Zig implementations but don\'t need special handling',
        'pub const auto_registrable_modules = [_][]const u8{',
    ])

    # Add auto-registrable modules (those NOT in MANUAL_REGISTRY_MODULES)
    auto_modules = [m for m in sorted_modules if m not in MANUAL_REGISTRY_MODULES]
    for mod in auto_modules:
        lines.append(f'    "{mod}",')

    lines.extend([
        '};',
        '',
        f'pub const auto_registrable_count: usize = {len(auto_modules)};',
        '',
    ])

    return '\n'.join(lines)


def main():
    print("Discovering modules...")
    all_modules, source_map = discover_all_modules()
    print(f"Found {len(all_modules)} modules")

    # Generate stdlib_modules_gen.zig
    output_path = ROOT / "src/codegen/native/stdlib_modules_gen.zig"
    content = generate_stdlib_modules_gen(all_modules, source_map)

    print(f"Writing {output_path}...")
    output_path.write_text(content)

    # Print summary by category
    lib_count = sum(1 for m in all_modules if not any(
        m.startswith(p) for p in ["_objects.", "_python.", "_c_objects.", "_c_modules."]
    ))
    objects_count = sum(1 for m in all_modules if m.startswith("_objects."))
    python_count = sum(1 for m in all_modules if m.startswith("_python."))
    c_interop_count = sum(1 for m in all_modules if m.startswith("_c_objects.") or m.startswith("_c_modules."))

    print(f"\nSummary:")
    print(f"  Lib/ (stdlib):     {lib_count}")
    print(f"  Objects/:          {objects_count}")
    print(f"  Python/:           {python_count}")
    print(f"  c_interop/:        {c_interop_count}")
    print(f"  Total:             {len(all_modules)}")

    auto_count = len([m for m in all_modules if m not in MANUAL_REGISTRY_MODULES])
    print(f"\nAuto-registrable: {auto_count} (not needing special handling)")
    print(f"Manual registry:  {len(MANUAL_REGISTRY_MODULES)} (with special metadata)")

    print("\nDone!")


if __name__ == "__main__":
    main()
