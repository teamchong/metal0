/// CPython-Compatible Object Layout
///
/// This file defines ALL PyObject types with EXACT CPython binary layout
/// so external C extensions (numpy, pandas, etc.) can use them.
///
/// Supports: Python 3.10, 3.11, 3.12, 3.13
/// Reference: cpython/Include/object.h, cpython/Include/cpython/*.h

const std = @import("std");
const version = @import("version.zig");

/// Current Python version for struct layouts
pub const PYTHON_VERSION = version.PYTHON_VERSION;

/// ============================================================================
/// CPYTHON 3.12+ OBJECT LAYOUT (Binary Compatible - 64-bit little-endian)
/// ============================================================================

/// PyObject - The base object type (16 bytes on 64-bit)
///
/// CPython 3.12 layout (non-GIL-disabled build, 64-bit):
/// ```c
/// struct _object {
///     union {
///         Py_ssize_t ob_refcnt;  // 8 bytes (Py_ssize_t = ssize_t = int64)
///         // Actually a union with ob_refcnt_full containing:
///         // uint32_t ob_refcnt, uint16_t ob_overflow, uint16_t ob_flags
///     };
///     PyTypeObject *ob_type;     // 8 bytes (pointer)
/// };
/// ```
pub const PyObject = extern struct {
    ob_refcnt: isize, // Py_ssize_t = ssize_t = 8 bytes on 64-bit
    ob_type: *PyTypeObject,
};

/// PyVarObject - Variable-size object (24 bytes on 64-bit)
/// Used for lists, tuples, strings, etc.
pub const PyVarObject = extern struct {
    ob_base: PyObject, // 16 bytes
    ob_size: isize, // 8 bytes - number of items
};

/// ============================================================================
/// TYPE DEFINITIONS (Function pointer types)
/// ============================================================================

pub const destructor = ?*const fn (*PyObject) callconv(.c) void;
pub const getattrfunc = ?*const fn (*PyObject, [*:0]u8) callconv(.c) ?*PyObject;
pub const setattrfunc = ?*const fn (*PyObject, [*:0]u8, ?*PyObject) callconv(.c) c_int;
pub const reprfunc = ?*const fn (*PyObject) callconv(.c) ?*PyObject;
pub const hashfunc = ?*const fn (*PyObject) callconv(.c) isize;
pub const ternaryfunc = ?*const fn (*PyObject, *PyObject, ?*PyObject) callconv(.c) ?*PyObject;
pub const getattrofunc = ?*const fn (*PyObject, *PyObject) callconv(.c) ?*PyObject;
pub const setattrofunc = ?*const fn (*PyObject, *PyObject, ?*PyObject) callconv(.c) c_int;
pub const traverseproc = ?*const fn (*PyObject, visitproc, ?*anyopaque) callconv(.c) c_int;
pub const visitproc = ?*const fn (*PyObject, ?*anyopaque) callconv(.c) c_int;
pub const inquiry = ?*const fn (*PyObject) callconv(.c) c_int;
pub const richcmpfunc = ?*const fn (*PyObject, *PyObject, c_int) callconv(.c) ?*PyObject;
pub const getiterfunc = ?*const fn (*PyObject) callconv(.c) ?*PyObject;
pub const iternextfunc = ?*const fn (*PyObject) callconv(.c) ?*PyObject;
pub const descrgetfunc = ?*const fn (*PyObject, ?*PyObject, ?*PyObject) callconv(.c) ?*PyObject;
pub const descrsetfunc = ?*const fn (*PyObject, *PyObject, ?*PyObject) callconv(.c) c_int;
pub const initproc = ?*const fn (*PyObject, *PyObject, ?*PyObject) callconv(.c) c_int;
pub const allocfunc = ?*const fn (*PyTypeObject, isize) callconv(.c) ?*PyObject;
pub const newfunc = ?*const fn (*PyTypeObject, *PyObject, ?*PyObject) callconv(.c) ?*PyObject;
pub const freefunc = ?*const fn (?*anyopaque) callconv(.c) void;
pub const vectorcallfunc = ?*const fn (*PyObject, [*]const *PyObject, usize, ?*PyObject) callconv(.c) ?*PyObject;

/// Binary function (a + b, etc.)
pub const binaryfunc = ?*const fn (*PyObject, *PyObject) callconv(.c) ?*PyObject;
/// Unary function (-a, etc.)
pub const unaryfunc = ?*const fn (*PyObject) callconv(.c) ?*PyObject;
/// Coercion function
pub const coercion = ?*const fn (**PyObject, **PyObject) callconv(.c) c_int;
/// Sequence length function
pub const lenfunc = ?*const fn (*PyObject) callconv(.c) isize;
/// Sequence item getter
pub const ssizeargfunc = ?*const fn (*PyObject, isize) callconv(.c) ?*PyObject;
/// Sequence item setter
pub const ssizeobjargproc = ?*const fn (*PyObject, isize, ?*PyObject) callconv(.c) c_int;
/// Mapping subscript getter
pub const objobjargproc = ?*const fn (*PyObject, *PyObject, ?*PyObject) callconv(.c) c_int;
/// Object contains check
pub const objobjproc = ?*const fn (*PyObject, *PyObject) callconv(.c) c_int;

/// ============================================================================
/// PROTOCOL STRUCTURES (Number, Sequence, Mapping)
/// ============================================================================

/// PyNumberMethods - Numeric operations
pub const PyNumberMethods = extern struct {
    nb_add: binaryfunc = null,
    nb_subtract: binaryfunc = null,
    nb_multiply: binaryfunc = null,
    nb_remainder: binaryfunc = null,
    nb_divmod: binaryfunc = null,
    nb_power: ternaryfunc = null,
    nb_negative: unaryfunc = null,
    nb_positive: unaryfunc = null,
    nb_absolute: unaryfunc = null,
    nb_bool: inquiry = null,
    nb_invert: unaryfunc = null,
    nb_lshift: binaryfunc = null,
    nb_rshift: binaryfunc = null,
    nb_and: binaryfunc = null,
    nb_xor: binaryfunc = null,
    nb_or: binaryfunc = null,
    nb_int: unaryfunc = null,
    nb_reserved: ?*anyopaque = null, // formerly nb_long
    nb_float: unaryfunc = null,
    nb_inplace_add: binaryfunc = null,
    nb_inplace_subtract: binaryfunc = null,
    nb_inplace_multiply: binaryfunc = null,
    nb_inplace_remainder: binaryfunc = null,
    nb_inplace_power: ternaryfunc = null,
    nb_inplace_lshift: binaryfunc = null,
    nb_inplace_rshift: binaryfunc = null,
    nb_inplace_and: binaryfunc = null,
    nb_inplace_xor: binaryfunc = null,
    nb_inplace_or: binaryfunc = null,
    nb_floor_divide: binaryfunc = null,
    nb_true_divide: binaryfunc = null,
    nb_inplace_floor_divide: binaryfunc = null,
    nb_inplace_true_divide: binaryfunc = null,
    nb_index: unaryfunc = null,
    nb_matrix_multiply: binaryfunc = null,
    nb_inplace_matrix_multiply: binaryfunc = null,
};

/// PySequenceMethods - Sequence operations
pub const PySequenceMethods = extern struct {
    sq_length: lenfunc = null,
    sq_concat: binaryfunc = null,
    sq_repeat: ssizeargfunc = null,
    sq_item: ssizeargfunc = null,
    was_sq_slice: ?*anyopaque = null, // deprecated
    sq_ass_item: ssizeobjargproc = null,
    was_sq_ass_slice: ?*anyopaque = null, // deprecated
    sq_contains: objobjproc = null,
    sq_inplace_concat: binaryfunc = null,
    sq_inplace_repeat: ssizeargfunc = null,
};

/// PyMappingMethods - Mapping operations
pub const PyMappingMethods = extern struct {
    mp_length: lenfunc = null,
    mp_subscript: binaryfunc = null,
    mp_ass_subscript: objobjargproc = null,
};

/// PyAsyncMethods - Async/await operations
pub const PyAsyncMethods = extern struct {
    am_await: unaryfunc = null,
    am_aiter: unaryfunc = null,
    am_anext: unaryfunc = null,
    am_send: binaryfunc = null,
};

/// PyBufferProcs - Buffer protocol
pub const PyBufferProcs = extern struct {
    bf_getbuffer: ?*const fn (*PyObject, *Py_buffer, c_int) callconv(.c) c_int = null,
    bf_releasebuffer: ?*const fn (*PyObject, *Py_buffer) callconv(.c) void = null,
};

/// Buffer protocol flags
pub const PyBUF_SIMPLE: c_int = 0;
pub const PyBUF_WRITABLE: c_int = 0x0001;
pub const PyBUF_FORMAT: c_int = 0x0004;
pub const PyBUF_ND: c_int = 0x0008;
pub const PyBUF_STRIDES: c_int = 0x0010 | PyBUF_ND;
pub const PyBUF_C_CONTIGUOUS: c_int = 0x0020 | PyBUF_STRIDES;
pub const PyBUF_F_CONTIGUOUS: c_int = 0x0040 | PyBUF_STRIDES;
pub const PyBUF_ANY_CONTIGUOUS: c_int = 0x0080 | PyBUF_STRIDES;
pub const PyBUF_INDIRECT: c_int = 0x0100 | PyBUF_STRIDES;

/// Py_buffer - Buffer view structure
pub const Py_buffer = extern struct {
    buf: ?*anyopaque = null,
    obj: ?*PyObject = null,
    len: isize = 0,
    itemsize: isize = 0,
    readonly: c_int = 0,
    ndim: c_int = 0,
    format: ?[*:0]u8 = null,
    shape: ?[*]isize = null,
    strides: ?[*]isize = null,
    suboffsets: ?[*]isize = null,
    internal: ?*anyopaque = null,
};

/// PyMethodDef - Method descriptor
pub const PyMethodDef = extern struct {
    ml_name: ?[*:0]const u8 = null,
    ml_meth: ?*anyopaque = null, // PyCFunction or PyCFunctionWithKeywords
    ml_flags: c_int = 0,
    ml_doc: ?[*:0]const u8 = null,
};

/// PyMemberDef - Member descriptor
pub const PyMemberDef = extern struct {
    name: ?[*:0]const u8 = null,
    @"type": c_int = 0,
    offset: isize = 0,
    flags: c_int = 0,
    doc: ?[*:0]const u8 = null,
};

/// PyGetSetDef - Property descriptor
pub const PyGetSetDef = extern struct {
    name: ?[*:0]const u8 = null,
    get: ?*anyopaque = null, // getter
    set: ?*anyopaque = null, // setter
    doc: ?[*:0]const u8 = null,
    closure: ?*anyopaque = null,
};

/// ============================================================================
/// PYTYPEOBJECT - EXACT CPYTHON 3.12 LAYOUT
/// ============================================================================

/// Type flags
pub const Py_TPFLAGS_DEFAULT: c_ulong = 0;
pub const Py_TPFLAGS_BASETYPE: c_ulong = 1 << 10;
pub const Py_TPFLAGS_HEAPTYPE: c_ulong = 1 << 9;
pub const Py_TPFLAGS_HAVE_GC: c_ulong = 1 << 14;
pub const Py_TPFLAGS_LONG_SUBCLASS: c_ulong = 1 << 24;
pub const Py_TPFLAGS_LIST_SUBCLASS: c_ulong = 1 << 25;
pub const Py_TPFLAGS_TUPLE_SUBCLASS: c_ulong = 1 << 26;
pub const Py_TPFLAGS_BYTES_SUBCLASS: c_ulong = 1 << 27;
pub const Py_TPFLAGS_UNICODE_SUBCLASS: c_ulong = 1 << 28;
pub const Py_TPFLAGS_DICT_SUBCLASS: c_ulong = 1 << 29;
pub const Py_TPFLAGS_BASE_EXC_SUBCLASS: c_ulong = 1 << 30;
pub const Py_TPFLAGS_TYPE_SUBCLASS: c_ulong = 1 << 31;

/// PyTypeObject - Version-specific layout
/// - 3.12+: Has tp_watched and tp_versions_used fields
/// - 3.10-3.11: Ends at tp_vectorcall
pub const PyTypeObject = extern struct {
    // PyObject_VAR_HEAD
    ob_base: PyVarObject, // 24 bytes

    tp_name: ?[*:0]const u8, // For printing
    tp_basicsize: isize,
    tp_itemsize: isize,

    // Methods to implement standard operations
    tp_dealloc: destructor,
    tp_vectorcall_offset: isize,
    tp_getattr: getattrfunc,
    tp_setattr: setattrfunc,
    tp_as_async: ?*PyAsyncMethods,
    tp_repr: reprfunc,

    // Method suites for standard classes
    tp_as_number: ?*PyNumberMethods,
    tp_as_sequence: ?*PySequenceMethods,
    tp_as_mapping: ?*PyMappingMethods,

    // More standard operations
    tp_hash: hashfunc,
    tp_call: ternaryfunc,
    tp_str: reprfunc,
    tp_getattro: getattrofunc,
    tp_setattro: setattrofunc,

    // Functions to access object as input/output buffer
    tp_as_buffer: ?*PyBufferProcs,

    // Flags
    tp_flags: c_ulong,

    // Documentation string
    tp_doc: ?[*:0]const u8,

    // Traversal and clearing for GC
    tp_traverse: traverseproc,
    tp_clear: inquiry,

    // Rich comparisons
    tp_richcompare: richcmpfunc,

    // Weak reference enabler
    tp_weaklistoffset: isize,

    // Iterators
    tp_iter: getiterfunc,
    tp_iternext: iternextfunc,

    // Attribute descriptor and subclassing stuff
    tp_methods: ?[*]PyMethodDef,
    tp_members: ?[*]PyMemberDef,
    tp_getset: ?[*]PyGetSetDef,
    tp_base: ?*PyTypeObject,
    tp_dict: ?*PyObject,
    tp_descr_get: descrgetfunc,
    tp_descr_set: descrsetfunc,
    tp_dictoffset: isize,
    tp_init: initproc,
    tp_alloc: allocfunc,
    tp_new: newfunc,
    tp_free: freefunc,
    tp_is_gc: inquiry,
    tp_bases: ?*PyObject,
    tp_mro: ?*PyObject,
    tp_cache: ?*PyObject,
    tp_subclasses: ?*anyopaque,
    tp_weaklist: ?*PyObject,
    tp_del: destructor,

    // Type attribute cache version tag
    tp_version_tag: c_uint,

    tp_finalize: destructor,
    tp_vectorcall: vectorcallfunc,

    // Added in 3.12 - conditional fields
    // For 3.10-3.11 compatibility, these are always present but ignored
    tp_watched: u8 = 0,
    tp_versions_used: u16 = 0,
};

/// ============================================================================
/// PYMODULEDEF - EXACT CPYTHON 3.12 LAYOUT
/// ============================================================================

/// PyModuleDef_Base - module definition base
pub const PyModuleDef_Base = extern struct {
    ob_base: PyObject,
    m_init: ?*const fn () callconv(.c) ?*PyObject,
    m_index: isize,
    m_copy: ?*PyObject,
};

/// PyModuleDef_Slot - module slot
pub const PyModuleDef_Slot = extern struct {
    slot: c_int,
    value: ?*anyopaque,
};

/// PyModuleDef - module definition
pub const PyModuleDef = extern struct {
    m_base: PyModuleDef_Base,
    m_name: ?[*:0]const u8,
    m_doc: ?[*:0]const u8,
    m_size: isize,
    m_methods: ?[*]PyMethodDef,
    m_slots: ?[*]PyModuleDef_Slot,
    m_traverse: traverseproc,
    m_clear: inquiry,
    m_free: freefunc,
};

/// ============================================================================
/// PYLONGOBJECT - Version-specific layouts
/// ============================================================================
///
/// Python 3.12+: Uses lv_tag encoding (sign + digit count packed)
/// Python 3.10-3.11: Uses ob_size in PyVarObject header
///
/// Layout from cpython/Include/cpython/longintrepr.h

/// digit type for bigint - 30 bits per digit on 64-bit platforms
pub const digit = u32;
pub const sdigit = i32;
pub const twodigits = u64;
pub const stwodigits = i64;

pub const PyLong_SHIFT: u5 = 30;
pub const PyLong_BASE: digit = 1 << PyLong_SHIFT;
pub const PyLong_MASK: digit = PyLong_BASE - 1;

pub const _PyLong_SIGN_MASK: usize = 3;
pub const _PyLong_NON_SIZE_BITS: u5 = 3;

/// _PyLongValue - Internal long value structure (3.12+ only)
pub const _PyLongValue = extern struct {
    lv_tag: usize, // Number of digits, sign and flags
    ob_digit: [1]digit, // Flexible array member - at least 1 digit always allocated
};

/// PyLongObject - Python int (arbitrary precision)
/// Version-specific layout:
/// - 3.12+: PyObject + _PyLongValue (lv_tag encoding)
/// - 3.10-3.11: PyVarObject + ob_digit (ob_size encoding)
pub const PyLongObject = if (version.hasLvTag(PYTHON_VERSION))
    // Python 3.12+ layout
    extern struct {
        ob_base: PyObject, // 16 bytes
        long_value: _PyLongValue, // lv_tag + ob_digit[1]

        // 3.12+ helpers
        pub fn isNegative(self: *const @This()) bool {
            return (self.long_value.lv_tag & _PyLong_SIGN_MASK) == 2;
        }
        pub fn isZero(self: *const @This()) bool {
            return (self.long_value.lv_tag & _PyLong_SIGN_MASK) == 1;
        }
        pub fn digitCount(self: *const @This()) usize {
            return self.long_value.lv_tag >> _PyLong_NON_SIZE_BITS;
        }
    }
else
    // Python 3.10-3.11 layout
    extern struct {
        ob_base: PyVarObject, // 24 bytes (includes ob_size for digit count + sign)
        ob_digit: [1]digit, // Flexible array

        // 3.10-3.11 helpers (ob_size encodes sign + count)
        pub fn isNegative(self: *const @This()) bool {
            return self.ob_base.ob_size < 0;
        }
        pub fn isZero(self: *const @This()) bool {
            return self.ob_base.ob_size == 0;
        }
        pub fn digitCount(self: *const @This()) usize {
            const size = self.ob_base.ob_size;
            return @intCast(if (size < 0) -size else size);
        }
    };

/// Unified PyLongObject access (works across versions)
pub const PyLongObject_312 = extern struct {
    ob_base: PyObject,
    long_value: _PyLongValue,
};
pub const PyLongObject_310 = extern struct {
    ob_base: PyVarObject,
    ob_digit: [1]digit,
};

/// ============================================================================
/// PYUNICODEOBJECT - EXACT CPYTHON 3.12 LAYOUT (String)
/// ============================================================================
///
/// CPython 3.12 has 3 forms of unicode strings:
/// 1. Compact ASCII (PyASCIIObject) - ASCII-only, data follows struct
/// 2. Compact (PyCompactUnicodeObject) - Non-ASCII, data follows struct
/// 3. Legacy (PyUnicodeObject) - Subclasses, separate data buffer
///
/// Layout from cpython/Include/cpython/unicodeobject.h

/// Unicode string kinds
pub const PyUnicode_1BYTE_KIND: c_uint = 1;
pub const PyUnicode_2BYTE_KIND: c_uint = 2;
pub const PyUnicode_4BYTE_KIND: c_uint = 4;

/// Interning state
pub const SSTATE_NOT_INTERNED: c_uint = 0;
pub const SSTATE_INTERNED_MORTAL: c_uint = 1;
pub const SSTATE_INTERNED_IMMORTAL: c_uint = 2;
pub const SSTATE_INTERNED_IMMORTAL_STATIC: c_uint = 3;

/// _PyUnicodeObject_state - bit fields for unicode state
/// Note: In C this is a bitfield struct. We pack it into a u32.
pub const _PyUnicodeObject_state = extern struct {
    /// Packed state: interned(2) | kind(3) | compact(1) | ascii(1) | statically_allocated(1) | padding(24)
    _packed: u32,
};

/// PyASCIIObject - Base for ASCII-only strings
/// Data immediately follows this struct
pub const PyASCIIObject = extern struct {
    ob_base: PyObject, // 16 bytes
    length: isize, // Number of code points
    hash: isize, // Cached hash, -1 if not computed
    state: _PyUnicodeObject_state, // 4 bytes packed state
};

/// PyCompactUnicodeObject - Non-ASCII compact strings
/// Data immediately follows this struct
pub const PyCompactUnicodeObject = extern struct {
    _base: PyASCIIObject,
    utf8_length: isize, // UTF-8 length excluding \0
    utf8: ?[*:0]u8, // UTF-8 representation (null-terminated)
};

/// PyUnicodeObject - Full unicode object (for subclasses)
pub const PyUnicodeObject = extern struct {
    _base: PyCompactUnicodeObject,
    data: extern union {
        any: ?*anyopaque,
        latin1: ?[*]u8,
        ucs2: ?[*]u16,
        ucs4: ?[*]u32,
    },
};

/// ============================================================================
/// PYLISTOBJECT - EXACT CPYTHON 3.12 LAYOUT
/// ============================================================================
///
/// Layout from cpython/Include/cpython/listobject.h:
/// ```c
/// typedef struct {
///     PyObject_VAR_HEAD
///     PyObject **ob_item;
///     Py_ssize_t allocated;
/// } PyListObject;
/// ```

pub const PyListObject = extern struct {
    ob_base: PyVarObject, // 24 bytes (includes ob_size = current length)
    ob_item: ?[*]*PyObject, // Array of pointers to elements
    allocated: isize, // Allocated capacity
};

/// ============================================================================
/// PYTUPLEOBJECT - EXACT CPYTHON 3.12 LAYOUT
/// ============================================================================
///
/// Layout from cpython/Include/cpython/tupleobject.h:
/// ```c
/// typedef struct {
///     PyObject_VAR_HEAD
///     Py_hash_t ob_hash;
///     PyObject *ob_item[1];
/// } PyTupleObject;
/// ```

pub const PyTupleObject = extern struct {
    ob_base: PyVarObject, // 24 bytes
    ob_hash: isize, // Cached hash, initially -1
    ob_item: [1]*PyObject, // Flexible array - space for ob_size elements
};

/// ============================================================================
/// PYDICTOBJECT - EXACT CPYTHON 3.12 LAYOUT
/// ============================================================================
///
/// Layout from cpython/Include/cpython/dictobject.h:
/// ```c
/// typedef struct {
///     PyObject_HEAD
///     Py_ssize_t ma_used;
///     uint64_t _ma_watcher_tag;
///     PyDictKeysObject *ma_keys;
///     PyDictValues *ma_values;
/// } PyDictObject;
/// ```

/// Forward declarations for dict internals
pub const PyDictKeysObject = opaque {};
pub const PyDictValues = opaque {};

/// PyDictObject - Version-specific layout
/// - 3.12+: Has _ma_watcher_tag field (48 bytes)
/// - 3.10-3.11: No watcher tag (40 bytes)
pub const PyDictObject = if (version.hasDictWatcher(PYTHON_VERSION))
    // Python 3.12+ layout with watcher tag
    extern struct {
        ob_base: PyObject, // 16 bytes (NOT PyVarObject!)
        ma_used: isize, // Number of items in dictionary
        _ma_watcher_tag: u64, // Internal: watchers, mutation counter, unique id
        ma_keys: ?*PyDictKeysObject, // Keys storage
        ma_values: ?*PyDictValues, // Values storage (NULL for combined table)
    }
else
    // Python 3.10-3.11 layout without watcher tag
    extern struct {
        ob_base: PyObject, // 16 bytes
        ma_used: isize, // Number of items in dictionary
        ma_keys: ?*PyDictKeysObject, // Keys storage
        ma_values: ?*PyDictValues, // Values storage (NULL for combined table)
    };

/// Explicit versioned types for cross-version access
pub const PyDictObject_312 = extern struct {
    ob_base: PyObject,
    ma_used: isize,
    _ma_watcher_tag: u64,
    ma_keys: ?*PyDictKeysObject,
    ma_values: ?*PyDictValues,
};
pub const PyDictObject_310 = extern struct {
    ob_base: PyObject,
    ma_used: isize,
    ma_keys: ?*PyDictKeysObject,
    ma_values: ?*PyDictValues,
};

/// ============================================================================
/// PYBYTESOBJECT - EXACT CPYTHON 3.12 LAYOUT
/// ============================================================================
///
/// Layout from cpython/Include/cpython/bytesobject.h:
/// ```c
/// typedef struct {
///     PyObject_VAR_HEAD
///     Py_hash_t ob_shash;
///     char ob_sval[1];
/// } PyBytesObject;
/// ```

pub const PyBytesObject = extern struct {
    ob_base: PyVarObject, // 24 bytes
    ob_shash: isize, // Cached hash, -1 if not computed
    ob_sval: [1]u8, // Flexible array - space for ob_size+1 bytes (includes \0)
};

/// ============================================================================
/// PYSETOBJECT - EXACT CPYTHON 3.12 LAYOUT
/// ============================================================================
///
/// Layout from cpython/Include/cpython/setobject.h:
/// ```c
/// #define PySet_MINSIZE 8
/// typedef struct { PyObject *key; Py_hash_t hash; } setentry;
/// typedef struct {
///     PyObject_HEAD
///     Py_ssize_t fill;
///     Py_ssize_t used;
///     Py_ssize_t mask;
///     setentry *table;
///     Py_hash_t hash;
///     Py_ssize_t finger;
///     setentry smalltable[PySet_MINSIZE];
///     PyObject *weakreflist;
/// } PySetObject;
/// ```

pub const PySet_MINSIZE: usize = 8;

pub const setentry = extern struct {
    key: ?*PyObject,
    hash: isize, // Cached hash of key
};

pub const PySetObject = extern struct {
    ob_base: PyObject, // 16 bytes
    fill: isize, // Number of active + dummy entries
    used: isize, // Number of active entries
    mask: isize, // Table size - 1 (always power of 2 - 1)
    table: ?*setentry, // Points to smalltable or malloc'd memory
    hash: isize, // Only used by frozenset, -1 for set
    finger: isize, // Search finger for pop()
    smalltable: [PySet_MINSIZE]setentry, // Inline storage for small sets
    weakreflist: ?*PyObject, // List of weak references
};

/// ============================================================================
/// PYFLOATOBJECT - EXACT CPYTHON LAYOUT
/// ============================================================================
///
/// Layout:
/// ```c
/// typedef struct {
///     PyObject_HEAD
///     double ob_fval;
/// } PyFloatObject;
/// ```

pub const PyFloatObject = extern struct {
    ob_base: PyObject, // 16 bytes
    ob_fval: f64, // 8 bytes
};

/// ============================================================================
/// PYCOMPLEXOBJECT - EXACT CPYTHON LAYOUT
/// ============================================================================

pub const Py_complex = extern struct {
    real: f64,
    imag: f64,
};

pub const PyComplexObject = extern struct {
    ob_base: PyObject, // 16 bytes
    cval: Py_complex, // 16 bytes
};

/// ============================================================================
/// TYPE SPEC STRUCTURES (for PyType_FromSpec)
/// ============================================================================

/// PyType_Slot - Slot definition for PyType_FromSpec
/// CPython: typedef struct { int slot; void *pfunc; } PyType_Slot;
pub const PyType_Slot = extern struct {
    slot: c_int,
    pfunc: ?*anyopaque,
};

/// PyType_Spec - Type specification for PyType_FromSpec
/// CPython: typedef struct { const char *name; int basicsize; int itemsize; unsigned int flags; PyType_Slot *slots; } PyType_Spec;
pub const PyType_Spec = extern struct {
    name: ?[*:0]const u8,
    basicsize: c_int,
    itemsize: c_int,
    flags: c_uint,
    slots: ?[*]const PyType_Slot,
};

/// Slot IDs (from CPython's typeslots.h)
pub const Py_tp_alloc: c_int = 47;
pub const Py_tp_base: c_int = 48;
pub const Py_tp_bases: c_int = 49;
pub const Py_tp_call: c_int = 50;
pub const Py_tp_clear: c_int = 51;
pub const Py_tp_dealloc: c_int = 52;
pub const Py_tp_del: c_int = 53;
pub const Py_tp_descr_get: c_int = 54;
pub const Py_tp_descr_set: c_int = 55;
pub const Py_tp_doc: c_int = 56;
pub const Py_tp_getattr: c_int = 57;
pub const Py_tp_getattro: c_int = 58;
pub const Py_tp_hash: c_int = 59;
pub const Py_tp_init: c_int = 60;
pub const Py_tp_is_gc: c_int = 61;
pub const Py_tp_iter: c_int = 62;
pub const Py_tp_iternext: c_int = 63;
pub const Py_tp_methods: c_int = 64;
pub const Py_tp_new: c_int = 65;
pub const Py_tp_repr: c_int = 66;
pub const Py_tp_richcompare: c_int = 67;
pub const Py_tp_setattr: c_int = 68;
pub const Py_tp_setattro: c_int = 69;
pub const Py_tp_str: c_int = 70;
pub const Py_tp_traverse: c_int = 71;
pub const Py_tp_members: c_int = 72;
pub const Py_tp_getset: c_int = 73;
pub const Py_tp_free: c_int = 74;
pub const Py_tp_finalize: c_int = 75;
pub const Py_nb_add: c_int = 7;
pub const Py_nb_subtract: c_int = 8;
pub const Py_nb_multiply: c_int = 9;
pub const Py_nb_remainder: c_int = 10;
pub const Py_nb_divmod: c_int = 11;
pub const Py_nb_power: c_int = 12;
pub const Py_nb_negative: c_int = 13;
pub const Py_nb_positive: c_int = 14;
pub const Py_nb_absolute: c_int = 15;
pub const Py_nb_bool: c_int = 16;
pub const Py_nb_invert: c_int = 17;
pub const Py_nb_lshift: c_int = 18;
pub const Py_nb_rshift: c_int = 19;
pub const Py_nb_and: c_int = 20;
pub const Py_nb_xor: c_int = 21;
pub const Py_nb_or: c_int = 22;
pub const Py_nb_int: c_int = 23;
pub const Py_nb_float: c_int = 25;
pub const Py_nb_inplace_add: c_int = 26;
pub const Py_nb_inplace_subtract: c_int = 27;
pub const Py_nb_inplace_multiply: c_int = 28;
pub const Py_nb_inplace_remainder: c_int = 29;
pub const Py_nb_inplace_power: c_int = 30;
pub const Py_nb_inplace_lshift: c_int = 31;
pub const Py_nb_inplace_rshift: c_int = 32;
pub const Py_nb_inplace_and: c_int = 33;
pub const Py_nb_inplace_xor: c_int = 34;
pub const Py_nb_inplace_or: c_int = 35;
pub const Py_nb_floor_divide: c_int = 36;
pub const Py_nb_true_divide: c_int = 37;
pub const Py_nb_inplace_floor_divide: c_int = 38;
pub const Py_nb_inplace_true_divide: c_int = 39;
pub const Py_nb_index: c_int = 40;
pub const Py_nb_matrix_multiply: c_int = 41;
pub const Py_nb_inplace_matrix_multiply: c_int = 42;
pub const Py_sq_length: c_int = 1;
pub const Py_sq_concat: c_int = 2;
pub const Py_sq_repeat: c_int = 3;
pub const Py_sq_item: c_int = 4;
pub const Py_sq_ass_item: c_int = 6;
pub const Py_sq_contains: c_int = 43;
pub const Py_sq_inplace_concat: c_int = 44;
pub const Py_sq_inplace_repeat: c_int = 45;
pub const Py_mp_length: c_int = 76;
pub const Py_mp_subscript: c_int = 77;
pub const Py_mp_ass_subscript: c_int = 78;
pub const Py_bf_getbuffer: c_int = 79;
pub const Py_bf_releasebuffer: c_int = 80;

/// ============================================================================
/// HELPER MACROS/FUNCTIONS
/// ============================================================================

/// Get type of object
pub inline fn Py_TYPE(ob: *PyObject) *PyTypeObject {
    return ob.ob_type;
}

/// Get refcount
pub inline fn Py_REFCNT(ob: *PyObject) isize {
    return ob.ob_refcnt;
}

/// Get size for variable-size objects
pub inline fn Py_SIZE(ob: *PyVarObject) isize {
    return ob.ob_size;
}

/// PyLong helpers - version-aware
/// These use the struct's built-in methods which are version-specific
pub inline fn _PyLong_IsCompact(op: *const PyLongObject) bool {
    if (version.hasLvTag(PYTHON_VERSION)) {
        return op.long_value.lv_tag < (2 << _PyLong_NON_SIZE_BITS);
    } else {
        // 3.10-3.11: compact if |ob_size| <= 1
        const size = op.ob_base.ob_size;
        return size >= -1 and size <= 1;
    }
}

pub inline fn _PyLong_IsNegative(op: *const PyLongObject) bool {
    return op.isNegative();
}

pub inline fn _PyLong_IsZero(op: *const PyLongObject) bool {
    return op.isZero();
}

pub inline fn _PyLong_DigitCount(op: *const PyLongObject) usize {
    return op.digitCount();
}

// ============================================================================
// COMPILE-TIME LAYOUT VERIFICATION
// ============================================================================

comptime {
    // Verify sizes match CPython on 64-bit
    if (@sizeOf(PyObject) != 16) {
        @compileError("PyObject size mismatch! Expected 16 bytes");
    }
    if (@sizeOf(PyVarObject) != 24) {
        @compileError("PyVarObject size mismatch! Expected 24 bytes");
    }
    if (@sizeOf(PyFloatObject) != 24) {
        @compileError("PyFloatObject size mismatch! Expected 24 bytes");
    }
    // PyListObject: ob_base(24) + ob_item(8) + allocated(8) = 40 bytes
    if (@sizeOf(PyListObject) != 40) {
        @compileError("PyListObject size mismatch! Expected 40 bytes");
    }
    // PyDictObject: version-specific
    // - 3.12+: ob_base(16) + ma_used(8) + _ma_watcher_tag(8) + ma_keys(8) + ma_values(8) = 48 bytes
    // - 3.10-3.11: ob_base(16) + ma_used(8) + ma_keys(8) + ma_values(8) = 40 bytes
    const expected_dict_size: usize = if (version.hasDictWatcher(PYTHON_VERSION)) 48 else 40;
    if (@sizeOf(PyDictObject) != expected_dict_size) {
        @compileError("PyDictObject size mismatch!");
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "PyObject layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PyObject, "ob_refcnt"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(PyObject, "ob_type"));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(PyObject));
}

test "PyVarObject layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PyVarObject, "ob_base"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyVarObject, "ob_size"));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(PyVarObject));
}

test "PyListObject layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PyListObject, "ob_base"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyListObject, "ob_item"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(PyListObject, "allocated"));
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(PyListObject));
}

test "PyDictObject layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PyDictObject, "ob_base"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyDictObject, "ma_used"));
    if (version.hasDictWatcher(PYTHON_VERSION)) {
        // 3.12+ layout with watcher tag
        try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyDictObject, "_ma_watcher_tag"));
        try std.testing.expectEqual(@as(usize, 32), @offsetOf(PyDictObject, "ma_keys"));
        try std.testing.expectEqual(@as(usize, 40), @offsetOf(PyDictObject, "ma_values"));
        try std.testing.expectEqual(@as(usize, 48), @sizeOf(PyDictObject));
    } else {
        // 3.10-3.11 layout without watcher tag
        try std.testing.expectEqual(@as(usize, 24), @offsetOf(PyDictObject, "ma_keys"));
        try std.testing.expectEqual(@as(usize, 32), @offsetOf(PyDictObject, "ma_values"));
        try std.testing.expectEqual(@as(usize, 40), @sizeOf(PyDictObject));
    }
}

test "PyFloatObject layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(PyFloatObject, "ob_base"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(PyFloatObject, "ob_fval"));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(PyFloatObject));
}
