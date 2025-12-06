# CPython Lib Implementation Plan for metal0

## Goal
Mirror 100% of CPython's Lib/ directory with native Zig implementations.

## Current Status
- CPython Lib: 1902 .py files
- metal0 Lib: 1902 .zig files (EXACT MATCH)
- Structure: 100% mirrors CPython Lib/ directory structure
- Implementation: ~45% functional, ~55% stubs

### Recently Implemented (Full Implementation, Not Stubs)
- `types.zig` - Type definitions (FunctionType, GeneratorType, etc.)
- `abc.zig` - ABCMeta, ABC, abstractmethod
- `functools.zig` - reduce, partial, lru_cache, wraps, total_ordering
- `operator.zig` - All comparison, math, bitwise operators
- `collections/__init__.zig` - Deque, Counter, OrderedDict, DefaultDict, namedtuple, ChainMap
- `heapq.zig` - heappush, heappop, heapify, nlargest, nsmallest
- `bisect.zig` - bisect_left, bisect_right, insort
- `queue.zig` - Queue, LifoQueue, PriorityQueue, SimpleQueue
- `enum.zig` - Enum, IntEnum, StrEnum, Flag, IntFlag
- `dataclasses.zig` - dataclass, field, fields, asdict, astuple
- `string/__init__.zig` - ascii_letters, Template, Formatter
- `textwrap.zig` - TextWrapper, wrap, fill, dedent, indent
- `random.zig` - Random class, all distributions
- `statistics.zig` - mean, median, stdev, variance, NormalDist
- `fractions.zig` - Fraction class with full arithmetic
- `json/__init__.zig` - loads, dumps, full parser/serializer
- `copy.zig` - copy, deepcopy with generic Zig support
- `contextlib.zig` - ContextManager, closing, ExitStack
- `hashlib.zig` - MD5, SHA1/256/384/512, SHA3, BLAKE2
- `struct.zig` - pack, unpack with format strings
- `calendar.zig` - Calendar, TextCalendar, HTMLCalendar
- `logging/__init__.zig` - Logger, Handler, StreamHandler, FileHandler
- `warnings.zig` - warn, filterwarnings, WarningCategory
- `traceback.zig` - print_exception, extract_tb, format_exception, FrameSummary
- `argparse.zig` - ArgumentParser, Namespace, Action, subparsers
- `threading.zig` - Thread, Lock, RLock, Condition, Semaphore, Event, Barrier
- `subprocess.zig` - Popen, run, call, check_output, PIPE
- `csv.zig` - Reader, Writer, DictReader, DictWriter, Dialect, Sniffer
- `pickle.zig` - dumps, loads, Pickler, Unpickler, protocols 0-5

### File Count Verification
```
CPython: /Users/steven_chong/Downloads/repos/cpython/Lib/ → 1902 .py files
metal0:  /Users/steven_chong/Downloads/repos/metal0/packages/runtime/src/Lib/ → 1902 .zig files
```

### Verification Command
```bash
find ~/Downloads/repos/cpython/Lib -name "*.py" | wc -l  # 1902
find packages/runtime/src/Lib -name "*.zig" | wc -l     # 1902
```

---

## Phase 1: Core Runtime (Priority: Critical)
**Timeline: Immediate**

These modules are required for basic Python compatibility:

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `builtins` | N/A | ✅ Done | Built into runtime.zig |
| `sys` | N/A | ✅ Done | sys.zig |
| `os` | N/A | ✅ Done | os.zig |
| `io` | N/A | ✅ Done | io.zig |
| `types` | 350 | ✅ Done | Type definitions - FunctionType, GeneratorType, etc. |
| `typing` | 3883 | 🔲 Stub | Type hints |
| `abc` | 200 | ✅ Done | ABCMeta, ABC, abstractmethod |
| `functools` | 1185 | ✅ Done | reduce, partial, lru_cache, wraps, total_ordering |
| `operator` | 400 | ✅ Done | lt, eq, add, sub, mul, getitem, attrgetter, etc. |
| `collections` | pkg | 🔲 Stub | Container datatypes |

---

## Phase 2: Data Structures (Priority: High)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `collections.abc` | - | 🔲 Stub | Abstract base classes for containers |
| `collections.OrderedDict` | - | 🔲 Stub | Use HashMap |
| `collections.Counter` | - | 🔲 Stub | Counting hashmap |
| `collections.deque` | - | 🔲 Stub | Double-ended queue |
| `heapq` | 600 | 🔲 Stub | Heap queue algorithm |
| `bisect` | 100 | 🔲 Stub | Binary search |
| `array` | C ext | 🔲 Stub | Efficient arrays |
| `queue` | 300 | 🔲 Stub | Synchronized queue |
| `enum` | 2192 | 🔲 Stub | Enumerations |
| `dataclasses` | 1799 | 🔲 Stub | Data classes |

---

## Phase 3: String & Text Processing (Priority: High)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `re` | N/A | ✅ Done | Regex (native Zig impl) |
| `string` | 250 | 🔲 Stub | String constants |
| `textwrap` | 500 | 🔲 Stub | Text wrapping |
| `difflib` | 2099 | 🔲 Stub | Diff utilities |
| `unicodedata` | C ext | 🔲 Stub | Unicode database |
| `codecs` | C ext | 🔲 Stub | Codec registry |
| `encodings` | pkg | 🔲 Stub | Standard encodings |

---

## Phase 4: Math & Numbers (Priority: High)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `math` | N/A | ✅ Done | Math functions |
| `decimal` | 6500 | 🔲 Stub | Decimal arithmetic |
| `fractions` | 1078 | 🔲 Stub | Rational numbers |
| `random` | 1079 | 🔲 Stub | Random generation |
| `statistics` | 1879 | 🔲 Stub | Statistical functions |
| `numbers` | 400 | 🔲 Stub | Numeric abstract base |
| `cmath` | C ext | 🔲 Stub | Complex math |

---

## Phase 5: File & I/O (Priority: High)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `pathlib` | N/A | ✅ Done | OOP file paths |
| `shutil` | N/A | ✅ Done | File operations |
| `glob` | N/A | ✅ Done | Unix glob patterns |
| `fnmatch` | 150 | 🔲 Stub | Filename matching |
| `tempfile` | 900 | 🔲 Stub | Temp files |
| `filecmp` | 300 | 🔲 Stub | File comparison |
| `stat` | 200 | 🔲 Stub | stat() results |
| `fileinput` | 400 | 🔲 Stub | File line iteration |

---

## Phase 6: Serialization (Priority: High)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `json` | N/A | ✅ Done | JSON (native Zig impl) |
| `pickle` | N/A | ✅ Done | Object serialization |
| `csv` | 500 | 🔲 Stub | CSV files |
| `configparser` | 1414 | 🔲 Stub | Config files |
| `struct` | C ext | 🔲 Stub | Binary packing |
| `base64` | N/A | ✅ Done | Base64 encoding |

---

## Phase 7: Date & Time (Priority: High)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `datetime` | N/A | ✅ Done | Date/time types |
| `time` | N/A | ✅ Done | Time access |
| `calendar` | N/A | ✅ Done | Calendar functions |
| `zoneinfo` | 600 | 🔲 Stub | IANA time zones |

---

## Phase 8: Networking (Priority: Medium)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `http` | N/A | ✅ Done | HTTP (native Zig impl) |
| `websocket` | N/A | ✅ Done | WebSocket (native Zig) |
| `socket` | C ext | 🔲 Stub | Low-level networking |
| `ssl` | C ext | 🔲 Stub | TLS/SSL wrapper |
| `urllib` | pkg | 🔲 Stub | URL handling |
| `email` | pkg | 🔲 Stub | Email handling |
| `smtplib` | 1121 | 🔲 Stub | SMTP client |
| `imaplib` | 1973 | 🔲 Stub | IMAP client |
| `ftplib` | 600 | 🔲 Stub | FTP client |
| `ipaddress` | 2427 | 🔲 Stub | IP addresses |

---

## Phase 9: Async & Concurrency (Priority: Medium)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `asyncio` | N/A | ✅ Done | Async I/O |
| `threading` | 1636 | 🔲 Stub | Thread-based parallelism |
| `multiprocessing` | pkg | 🔲 Stub | Process-based parallelism |
| `concurrent` | pkg | 🔲 Stub | Future/executor |
| `queue` | 300 | 🔲 Stub | Thread-safe queues |
| `selectors` | 600 | 🔲 Stub | I/O multiplexing |
| `signal` | C ext | 🔲 Stub | Signal handling |

---

## Phase 10: Testing (Priority: Medium)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `unittest` | N/A | ✅ Done | Unit testing |
| `doctest` | 2971 | 🔲 Stub | Test from docstrings |
| `test` | pkg | 🔲 Stub | CPython test support |
| `test.support` | - | 🔲 Stub | Test utilities |

---

## Phase 11: Compression & Archives (Priority: Medium)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `gzip` | C ext | 🔲 Stub | Gzip (use Zig std) |
| `bz2` | C ext | 🔲 Stub | Bzip2 |
| `lzma` | C ext | 🔲 Stub | LZMA |
| `zipfile` | 2300 | 🔲 Stub | ZIP archives |
| `tarfile` | 3141 | 🔲 Stub | TAR archives |

---

## Phase 12: Crypto & Hashing (Priority: Medium)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `hashlib` | C ext | 🔲 Stub | Hash algorithms (use Zig std) |
| `hmac` | 200 | 🔲 Stub | HMAC |
| `secrets` | 100 | 🔲 Stub | Secure random |

---

## Phase 13: CLI & Debugging (Priority: Low)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `argparse` | 2826 | 🔲 Stub | Argument parsing |
| `logging` | pkg | 🔲 Stub | Logging facility |
| `warnings` | 600 | 🔲 Stub | Warning control |
| `traceback` | 1796 | 🔲 Stub | Stack traces |
| `pdb` | 3669 | 🔲 Stub | Debugger |
| `inspect` | 3432 | 🔲 Stub | Introspection |
| `dis` | 1157 | 🔲 Stub | Bytecode disassembler |

---

## Phase 14: OS Integration (Priority: Low)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `subprocess` | 2229 | 🔲 Stub | Subprocess management |
| `platform` | 1447 | 🔲 Stub | Platform identification |
| `sysconfig` | 900 | 🔲 Stub | Python config |
| `locale` | 1802 | 🔲 Stub | Internationalization |
| `gettext` | 700 | 🔲 Stub | GNU gettext |

---

## Phase 15: Advanced/Rarely Used (Priority: Low)

| Module | Lines | Status | Notes |
|--------|-------|--------|-------|
| `ctypes` | pkg | 🔲 Stub | C interface (not needed in Zig) |
| `curses` | pkg | 🔲 Stub | Terminal UI |
| `tkinter` | pkg | 🔲 Stub | GUI (skip) |
| `idlelib` | pkg | 🔲 Stub | IDLE (skip) |
| `sqlite3` | C ext | 🔲 Stub | SQLite |
| `dbm` | pkg | 🔲 Stub | Database |
| `xml` | pkg | 🔲 Stub | XML processing |
| `html` | pkg | 🔲 Stub | HTML processing |

---

## Implementation Strategy

### 1. Direct Compilation (Pure Python → Zig)
For pure Python modules, use metal0 compiler:
```bash
./metal0 compile Lib/module.py --output packages/runtime/src/Lib/module.zig
```

### 2. Native Zig Implementation
For C extensions, write native Zig using std library:
- `hashlib` → `std.crypto`
- `gzip` → `std.compress.gzip`
- `json` → Already done with native impl
- `re` → Already done with native impl
- `socket` → `std.net`
- `ssl` → `std.crypto.tls`

### 3. Skip/Stub
Modules that don't make sense for AOT compilation:
- `tkinter` - GUI toolkit
- `idlelib` - Python IDE
- `ctypes` - FFI (use Zig's native C interop)
- `dbm` - Legacy database

---

## Testing Strategy

1. Run CPython's test suite for each module:
   ```bash
   ./metal0 run ~/Downloads/repos/cpython/Lib/test/test_<module>.py
   ```

2. Compare outputs with CPython:
   ```bash
   python3 -m test.test_<module> 2>&1 > expected.txt
   ./metal0 run test_<module>.py 2>&1 > actual.txt
   diff expected.txt actual.txt
   ```

3. Track coverage:
   - [ ] All functions exported
   - [ ] All classes defined
   - [ ] All constants present
   - [ ] API compatibility verified

---

## File Naming Convention

Align exactly with CPython:
```
CPython: Lib/collections/__init__.py
metal0:  packages/runtime/src/Lib/collections/__init__.zig

CPython: Lib/json/decoder.py
metal0:  packages/runtime/src/Lib/json/decoder.zig
```

---

## Progress Tracking

| Phase | Modules | Done | % |
|-------|---------|------|---|
| 1. Core Runtime | 10 | 8 | 80% |
| 2. Data Structures | 10 | 7 | 70% |
| 3. String/Text | 7 | 3 | 43% |
| 4. Math/Numbers | 7 | 4 | 57% |
| 5. File/I/O | 8 | 5 | 63% |
| 6. Serialization | 6 | 6 | 100% |
| 7. Date/Time | 4 | 3 | 75% |
| 8. Networking | 10 | 2 | 20% |
| 9. Async/Concurrency | 7 | 3 | 43% |
| 10. Testing | 4 | 1 | 25% |
| 11. Compression | 5 | 0 | 0% |
| 12. Crypto | 3 | 1 | 33% |
| 13. CLI/Debug | 7 | 4 | 57% |
| 14. OS Integration | 5 | 1 | 20% |
| 15. Advanced | 8 | 0 | 0% |
| **TOTAL** | **101** | **48** | **48%** |

---

## Next Steps

1. **Immediate**: Fix test_int.py codegen issues
2. **Week 1**: Implement Phase 1 (Core Runtime) completely
3. **Week 2**: Implement Phase 2-4 (Data structures, String, Math)
4. **Week 3**: Implement Phase 5-7 (File I/O, Serialization, DateTime)
5. **Week 4**: Implement Phase 8-10 (Networking, Async, Testing)
6. **Ongoing**: Phases 11-15 as needed

---

## Notes

- Priority modules for test_int.py: `numbers`, `functools`, `operator`
- Priority modules for test_float.py: `math`, `decimal`, `fractions`
- Skip `tkinter`, `idlelib`, `turtledemo` - GUI not needed
- Native Zig implementations preferred over Python compilation for performance
