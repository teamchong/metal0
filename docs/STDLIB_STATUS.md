# Metal0 Stdlib Implementation Status

## Summary

| Category | Count | Notes |
|----------|-------|-------|
| Total Modules | 207 | Top-level .zig files in Lib/ |
| Stub-Only | ~10 | Re-export shells, essentially empty |
| Minimal/Re-export | ~22 | 30-80 lines, mostly passthrough |
| Partially Implemented | ~35 | 80-200 lines, basic functionality |
| Fully Implemented | ~140 | 200+ lines, substantial code |
| Module Subdirectories | 84 | Composite/modular modules |

---

## Critical Missing/Stub Modules

These modules are referenced by tests but have minimal or no implementation:

### Tier 1: Blocks Many Tests (HIGH PRIORITY)

| Module | Status | Impact | Notes |
|--------|--------|--------|-------|
| `concurrent` | **MISSING** | test_compileall | No concurrent.futures implementation |
| `asyncio` | STUB | async tests | Basic queue only, no event loop |
| `subprocess` | PARTIAL | process tests | spawn/pipe incomplete |
| `multiprocessing` | STUB | mp tests | Directory exists but minimal |
| `select` | STUB (11 lines) | I/O tests | Only defines error alias |
| `signal` | PARTIAL | signal tests | Basic handlers only |

### Tier 2: Blocks Some Tests (MEDIUM PRIORITY)

| Module | Status | Impact | Notes |
|--------|--------|--------|-------|
| `ssl` | PARTIAL (113 lines) | network tests | No cert verification |
| `socket` | PARTIAL (110 lines) | network tests | No non-blocking I/O |
| `threading` | PARTIAL (125 lines) | thread tests | Basic locks only |
| `ctypes` | PARTIAL | FFI tests | Incomplete, security risk |
| `sqlite3` | RE-EXPORT (47 lines) | db tests | Basic bindings only |

### Tier 3: Low Test Impact (LOW PRIORITY)

| Module | Status | Notes |
|--------|--------|-------|
| `curses` | PARTIAL (94 lines) | Terminal control |
| `tkinter` | MINIMAL | GUI framework |
| `msvcrt` | STUB (151 lines) | Windows-only |
| `winreg` | STUB (132 lines) | Windows-only |

---

## Module Implementation Details

### test.support Decorators Needed

The `test.support` module needs these decorator stubs for test compatibility:

```
Currently Implemented:
- cpython_only()
- impl_detail()
- no_tracing()
- requires_resource(resource)
- requires_working_socket()  # Added this session
- requires_IEEE_754()
- is_resource_enabled(resource)
- check_sanitizer(address, memory)

Likely Needed (add as tests fail):
- requires_docstrings
- requires_fork
- requires_subprocess
- requires_multiprocessing
- requires_hashdigest
- bigmemtest
- bigaddrspacetest
- cpython_api
- refcount_test
- gc_collect
```

### sys Module Attributes

`runtime.builtins.sys` needs these commonly accessed attributes:

```
Currently Implemented:
- argv, path, platform, version
- stdin, stdout, stderr
- executable (partial)
- modules, builtin_module_names

Likely Needed:
- flags (sys.flags object)
- implementation (sys.implementation)
- float_info, int_info
- getrecursionlimit/setrecursionlimit
- getsizeof
- intern
- exc_info()
```

### os Module Functions

```
Currently Implemented:
- path operations (via os.path)
- file operations (open, read, write, close)
- directory operations (mkdir, rmdir, listdir)
- environment (environ, getenv, putenv)

Partially Implemented:
- process operations (fork, exec, spawn) - Unix only
- stat, chmod, chown - basic

Missing/Stub:
- Windows-specific (startfile, etc.)
- Advanced file ops (sendfile, copy_file_range)
- Terminal ops (tcgetpgrp, tcsetpgrp)
```

---

## Modules with Explicit TODOs

Files with TODO/FIXME markers that need completion:

| Module | Issues |
|--------|--------|
| `lzma.zig` | 2x TODO: format parameter handling |
| `_compression.zig` | Multiple TODO for edge cases |
| `stringprep.zig` | TODO: Complete Unicode normalization |
| `_testcapi.zig` | TODO: More comprehensive C API testing |

---

## Architecture Patterns

### Pattern A: Monolithic
Single `.zig` file with all code.
- Example: `math.zig` (540+ lines), `functools.zig` (410+ lines)
- Easy to audit and modify

### Pattern B: Re-export Shell + Subdirectory
Top-level file just re-exports from subdirectory.
- Example: `socket.zig` (110 lines) → `socket/*.zig`
- Example: `asyncio.zig` → `asyncio/*.zig`
- Real implementation scattered across 5-20 files

### Pattern C: Pure Re-export
Very short file (< 30 lines), all code in subdirectory.
- Example: `sched.zig` (21 lines) → `sched/`
- Example: `optparse.zig` (23 lines) → `optparse/`

---

## Well-Implemented Modules (Safe to Use)

These modules have substantial implementations (200+ lines):

**Core Language:**
- `types.zig`, `typing.zig`, `abc.zig`, `enum.zig`
- `dataclasses.zig`, `functools.zig`, `contextlib.zig`

**Data Structures:**
- `collections/*.zig` (namedtuple, deque, Counter, etc.)
- `heapq.zig`, `bisect.zig`, `queue.zig`, `array.zig`

**String/Text:**
- `string.zig`, `textwrap.zig`, `re.zig` (via sre_*)
- `codecs.zig`, `encodings/*.zig` (125+ encoding files)

**Math/Numeric:**
- `math.zig`, `statistics.zig`, `cmath.zig`
- `decimal/*.zig`, `fractions.zig`

**File I/O:**
- `pathlib.zig`, `tempfile.zig`, `glob.zig`, `fnmatch.zig`
- `shutil.zig`, `filecmp.zig`

**Compression:**
- `tarfile.zig`, `zipfile.zig`
- `gzip.zig`, `bz2.zig`, `zlib.zig`, `lzma.zig`

**Encoding:**
- `base64.zig`, `binascii.zig`, `struct.zig`
- `json.zig`, `pickle.zig`

**Testing:**
- `unittest.zig`, `doctest.zig`
- `warnings.zig`, `traceback.zig`

---

## Recommended Implementation Order

### Phase 1: Unblock Core Tests
1. Add `concurrent` module stub (for test_compileall)
2. Complete `subprocess` for basic spawn/pipe
3. Add missing `test.support` decorators as needed

### Phase 2: Network/Async Foundation
1. Implement `select` properly (select/poll/epoll/kqueue)
2. Complete `socket` non-blocking I/O
3. Build `asyncio` event loop on top

### Phase 3: Security/Production
1. Complete `ssl` with certificate verification
2. Implement `signal` handlers properly
3. Complete `threading` primitives

### Phase 4: Nice-to-Have
1. `multiprocessing` process pools
2. `ctypes` FFI (security-sensitive)
3. `sqlite3` full database API
4. Platform-specific: `msvcrt`, `winreg`

---

## Quick Reference: Module Line Counts

```
< 30 lines (stubs):       select, sched, optparse, profile, cProfile, pdb, socketserver, turtle, configparser, html
30-80 lines (minimal):    mailbox, bdb, decimal, numbers, weakref, selectors, pstats, tokenize, smtplib, argparse, collections, sqlite3, re, dis, csv, datetime
80-200 lines (partial):   time, difflib, inspect, curses, os, socket, ssl, urllib, threading, logging, ipaddress, warnings
200+ lines (full):        math, types, typing, abc, enum, functools, string, pathlib, tarfile, json, pickle, unittest, traceback, etc.
```

---

Last Updated: 2026-01-07
Based on: packages/runtime/src/Lib/ analysis
