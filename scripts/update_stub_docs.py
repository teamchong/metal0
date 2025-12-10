#!/usr/bin/env python3
"""
Update CPython stub files with documentation explaining why they're not needed.
Metal0 is an AOT compiler - many CPython stdlib modules are either:
1. Replaced by native Zig implementations (faster, no Python runtime)
2. Not applicable to AOT compilation (interpreter-specific)
3. Platform-specific and handled differently
"""

import os
import re
from pathlib import Path

# Categories of why modules aren't needed
CATEGORIES = {
    # Native Zig replacements in packages/
    "json": "//! Not needed: Native Zig JSON in packages/shared/json/ (SIMD-accelerated)",
    "http": "//! Not needed: Native Zig HTTP/2 client in packages/shared/http/h2/",
    "asyncio": "//! Not needed: Native Zig async runtime in packages/async_runtime/",
    "collections": "//! Not needed: Native Zig collections in packages/collections/",
    "concurrent": "//! Not needed: Native Zig threading in packages/threading/",
    "multiprocessing": "//! Not needed: Native Zig threading in packages/threading/ (no GIL)",
    "threading": "//! Not needed: Native Zig threading in packages/threading/ (no GIL)",
    "regex": "//! Not needed: Native Zig regex in packages/regex/",
    "re": "//! Not needed: Native Zig regex in packages/regex/",
    "websocket": "//! Not needed: Native Zig websocket in packages/websocket/",
    "compression": "//! Not needed: Native Zig compression via vendor/libdeflate/",
    "zlib": "//! Not needed: Native Zig compression via vendor/libdeflate/",
    "gzip": "//! Not needed: Native Zig compression via vendor/libdeflate/",

    # Interpreter-specific (not applicable to AOT)
    "idlelib": "//! Not needed: IDLE is CPython's IDE - AOT compilation has no REPL",
    "_pyrepl": "//! Not needed: REPL functionality - AOT compiles to native binaries",
    "code": "//! Not needed: Interactive interpreter - AOT compiles to native binaries",
    "codeop": "//! Not needed: Interactive interpreter - AOT compiles to native binaries",
    "pdb": "//! Not needed: Python debugger - use native debuggers (lldb/gdb) on AOT binaries",
    "profile": "//! Not needed: Python profiler - use native profilers on AOT binaries",
    "profiling": "//! Not needed: Python profiling - use native profilers (perf/instruments)",
    "trace": "//! Not needed: Python tracer - AOT binaries have native debug info",
    "timeit": "//! Not needed: Benchmarking - use native timing on AOT binaries",
    "dis": "//! Not needed: Bytecode disassembler - AOT produces native code, not bytecode",
    "py_compile": "//! Not needed: .pyc compiler - AOT compiles directly to native",
    "compileall": "//! Not needed: .pyc compiler - AOT compiles directly to native",
    "__pycache__": "//! Not needed: Bytecode cache - AOT has no bytecode",
    "importlib": "//! Not needed: Dynamic imports resolved at compile time in AOT",
    "ensurepip": "//! Not needed: pip installer - use `metal0 install` instead",
    "venv": "//! Not needed: Virtual environments - AOT binaries are self-contained",
    "site": "//! Not needed: Site configuration - AOT binaries are self-contained",

    # Test/development infrastructure
    "unittest": "//! Not needed: Use `metal0 test` or native test frameworks",
    "doctest": "//! Not needed: Doctests run at compile time or use native testing",
    "test": "//! Not needed: CPython test infrastructure - use `metal0 test`",
    "__phello__": "//! Not needed: CPython test module for frozen imports",

    # Platform-specific handled by Zig's cross-compilation
    "ctypes": "//! Not needed: FFI handled by Zig's native C interop (@cImport)",
    "_aix_support": "//! Not needed: Platform handled by Zig's cross-compilation",
    "_android_support": "//! Not needed: Platform handled by Zig's cross-compilation",
    "_apple_support": "//! Not needed: Platform handled by Zig's cross-compilation",
    "_ios_support": "//! Not needed: Platform handled by Zig's cross-compilation",
    "_osx_support": "//! Not needed: Platform handled by Zig's cross-compilation",
    "msvcrt": "//! Not needed: Windows runtime handled by Zig's cross-compilation",
    "winreg": "//! Not needed: Windows registry via Zig's std.os.windows",
    "posix": "//! Not needed: POSIX via Zig's std.os",
    "nt": "//! Not needed: Windows API via Zig's std.os.windows",

    # Database - use native Zig bindings
    "dbm": "//! Not needed: Use native Zig database bindings",
    "sqlite3": "//! Not needed: Use native Zig SQLite bindings",

    # GUI - not typically used in AOT CLI/server apps
    "tkinter": "//! Not needed: GUI framework - AOT targets CLI/server applications",
    "turtle": "//! Not needed: Graphics - AOT targets CLI/server applications",
    "curses": "//! Not needed: Terminal UI via Zig's std.io or native ncurses",

    # Email/MIME - use native implementations
    "email": "//! Not needed: Email parsing via native Zig implementation",
    "mailbox": "//! Not needed: Email via native Zig implementation",
    "smtplib": "//! Not needed: SMTP via native Zig HTTP/networking",
    "imaplib": "//! Not needed: IMAP via native Zig HTTP/networking",
    "poplib": "//! Not needed: POP3 via native Zig HTTP/networking",

    # Logging - compile-time or native
    "logging": "//! Not needed: Logging via Zig's std.log or compile-time elimination",

    # XML/HTML - native parsers
    "xml": "//! Not needed: XML parsing via native Zig implementation",
    "html": "//! Not needed: HTML parsing via native Zig implementation",

    # Path handling
    "pathlib": "//! Not needed: Path operations via Zig's std.fs.path",

    # Argument parsing
    "argparse": "//! Not needed: Arg parsing via Zig's std.process.args or clap",
    "getopt": "//! Not needed: Arg parsing via Zig's std.process.args",
    "optparse": "//! Not needed: Deprecated - use argparse alternative",
}

def get_reason(filepath: str) -> str:
    """Get the documentation reason for a stub file."""
    path = Path(filepath)

    # Check each category
    for key, reason in CATEGORIES.items():
        if key in str(path):
            return reason

    # Default reason for uncategorized modules
    return "//! Stub: CPython stdlib module - implement if needed for specific use case"

def update_stub_file(filepath: str) -> bool:
    """Update a stub file with proper documentation."""
    with open(filepath, 'r') as f:
        content = f.read()

    # Check if it's a stub file
    if "//! TODO: Implement from CPython" not in content:
        return False

    reason = get_reason(filepath)

    # Replace the TODO line with the proper documentation
    new_content = content.replace(
        "//! TODO: Implement from CPython Lib/",
        reason
    )

    # Also update the stub function comment if present
    new_content = new_content.replace(
        "// Stub module - not yet implemented",
        "// Stub - see module header for why this isn't needed"
    )

    if new_content != content:
        with open(filepath, 'w') as f:
            f.write(new_content)
        return True
    return False

def main():
    lib_dir = Path("packages/runtime/src/Lib")
    updated = 0

    for zig_file in lib_dir.rglob("*.zig"):
        if update_stub_file(str(zig_file)):
            print(f"Updated: {zig_file}")
            updated += 1

    print(f"\nTotal files updated: {updated}")

if __name__ == "__main__":
    main()
