/// _ctypes/ctypes - Core ctypes definitions
///
/// Implements CPython's Modules/_ctypes/ctypes.h
/// Provides base types and structures for ctypes module
///
/// Reference: cpython/Modules/_ctypes/ctypes.h
const std = @import("std");
const cpython = @import("../../include/object.zig");

pub const allocator = std.heap.c_allocator;

// ============================================================================
// CONSTANTS
// ============================================================================

/// Max number of arguments for function calls
pub const CTYPES_MAX_ARGCOUNT: usize = 1024;

/// Parameter flags
pub const PARAMFLAG_FIN: c_int = 0x1;
pub const PARAMFLAG_FOUT: c_int = 0x2;
pub const PARAMFLAG_FLCID: c_int = 0x4;

// ============================================================================
// UNION VALUE - Default buffer for small C types
// ============================================================================

/// Union value for small C types (16 bytes)
/// Matches CPython's union value exactly
pub const UnionValue = extern union {
    c: [16]u8,
    s: c_short,
    i: c_int,
    l: c_long,
    f: f32,
    d: f64,
    ll: c_longlong,
    D: c_longdouble,
};

// ============================================================================
// CDATA OBJECT - Base for all ctypes data objects
// ============================================================================

/// CDataObject - Base type for all ctypes data
/// Matches CPython's struct tagCDataObject exactly
pub const CDataObject = extern struct {
    ob_base: cpython.PyObject,
    b_ptr: ?[*]u8, // pointer to memory block
    b_needsfree: c_int, // do we need to free the memory?
    b_base: ?*CDataObject, // pointer to base object or NULL
    b_size: isize, // size of memory block in bytes
    b_length: isize, // number of references we need
    b_index: isize, // index of this object into base's b_object list
    b_objects: ?*cpython.PyObject, // dictionary of references or Py_None
    b_value: UnionValue, // default buffer for small C types
};

// ============================================================================
// PCARG OBJECT - Argument object for function calls
// ============================================================================

/// PyCArgObject - Represents a C argument
/// Matches CPython's struct tagPyCArgObject
pub const PyCArgObject = extern struct {
    ob_base: cpython.PyObject,
    pffi_type: ?*anyopaque, // ffi_type pointer
    tag: u8, // Type tag
    value: UnionValue, // The value
    obj: ?*cpython.PyObject, // Keep-alive reference
    size: isize, // Size in bytes
};

// ============================================================================
// STGDICT - Storage dictionary for ctypes types
// ============================================================================

/// StgDictObject - Extended dictionary for ctypes type information
/// Matches CPython's StgDictObject
pub const StgDictObject = extern struct {
    dict: cpython.PyDictObject, // Base dictionary
    size: isize, // Size of the C type
    align_val: isize, // Alignment requirement
    length: isize, // Number of elements (for arrays)
    ffi_type_pointer: ?*anyopaque, // ffi_type for this type
    proto: ?*cpython.PyObject, // Protocol object
    setfunc: ?*const fn (?*anyopaque, ?*cpython.PyObject, isize) callconv(.c) ?*cpython.PyObject,
    getfunc: ?*const fn (?*anyopaque, isize) callconv(.c) ?*cpython.PyObject,
    paramfunc: ?*anyopaque,
    argtypes: ?*cpython.PyObject, // Tuple of argument types
    converters: ?*cpython.PyObject, // Tuple of converter functions
    restype: ?*cpython.PyObject, // Result type
    checker: ?*cpython.PyObject, // Result checker
    flags: c_int, // Various flags
    format: ?[*:0]const u8, // Struct format string
    ndim: c_int, // Number of dimensions
    shape: ?[*]isize, // Shape for arrays
};

// ============================================================================
// CFIELD - Structure field descriptor
// ============================================================================

/// CFieldObject - Represents a field in a Structure/Union
/// Matches CPython's CFieldObject
pub const CFieldObject = extern struct {
    ob_base: cpython.PyObject,
    offset: isize, // Field offset in bytes
    size: isize, // Field size in bytes
    index: isize, // Field index
    proto: ?*cpython.PyObject, // Type prototype
    getfunc: ?*const fn (?*anyopaque, isize) callconv(.c) ?*cpython.PyObject,
    setfunc: ?*const fn (?*anyopaque, ?*cpython.PyObject, isize) callconv(.c) ?*cpython.PyObject,
    anonymous: c_int, // Is anonymous field?
};

// ============================================================================
// CTHUNK - Callback thunk object
// ============================================================================

/// CThunkObject - Callback thunk for Python callbacks called from C
/// Matches CPython's CThunkObject
pub const CThunkObject = extern struct {
    ob_base: cpython.PyVarObject,
    pcl_write: ?*anyopaque, // Writable closure pointer
    pcl_exec: ?*anyopaque, // Executable closure pointer
    cif: [32]u8, // ffi_cif structure (opaque)
    flags: c_int,
    converters: ?*cpython.PyObject,
    callable: ?*cpython.PyObject,
    restype: ?*cpython.PyObject,
    setfunc: ?*anyopaque,
    ffi_restype: ?*anyopaque,
    atypes: [1]?*anyopaque, // Variable length array
};

// ============================================================================
// CFUNCPTR - C function pointer type
// ============================================================================

/// CFuncPtrObject - Represents a C function pointer
/// Matches CPython's PyCFuncPtrObject
pub const CFuncPtrObject = extern struct {
    base: CDataObject,
    callable: ?*cpython.PyObject, // Python callable for callbacks
    converters: ?*cpython.PyObject, // Argument converters
    argtypes: ?*cpython.PyObject, // Argument types tuple
    restype: ?*cpython.PyObject, // Result type
    checker: ?*cpython.PyObject, // Result checker
    errcheck: ?*cpython.PyObject, // Error check function
    index: c_int, // COM method index
    iid: ?*anyopaque, // COM interface ID
    thunk: ?*CThunkObject, // Callback thunk
    paramflags: ?*cpython.PyObject, // Parameter flags
};

// ============================================================================
// CARRAY - C array type
// ============================================================================

/// CArrayObject - Represents a C array
/// Matches CPython's Array_Type instances
pub const CArrayObject = extern struct {
    base: CDataObject,
    // Array data follows in b_ptr
};

// ============================================================================
// CPOINTER - C pointer type
// ============================================================================

/// CPointerObject - Represents a C pointer
/// Matches CPython's Pointer_Type instances
pub const CPointerObject = extern struct {
    base: CDataObject,
    // Pointer value in b_ptr
};

// ============================================================================
// SIMPLE - Simple C type (c_int, c_char, etc.)
// ============================================================================

/// SimpleObject - Represents a simple C type
/// Matches CPython's Simple_Type instances
pub const SimpleObject = extern struct {
    base: CDataObject,
    // Value stored in b_value
};

// ============================================================================
// MODULE STATE
// ============================================================================

/// ctypes_state - Module state structure
/// Matches CPython's ctypes_state
pub const ctypes_state = extern struct {
    DictRemover_Type: ?*cpython.PyTypeObject,
    PyCArg_Type: ?*cpython.PyTypeObject,
    PyCField_Type: ?*cpython.PyTypeObject,
    PyCThunk_Type: ?*cpython.PyTypeObject,
    StructParam_Type: ?*cpython.PyTypeObject,
    PyCType_Type: ?*cpython.PyTypeObject,
    PyCStructType_Type: ?*cpython.PyTypeObject,
    UnionType_Type: ?*cpython.PyTypeObject,
    PyCPointerType_Type: ?*cpython.PyTypeObject,
    PyCArrayType_Type: ?*cpython.PyTypeObject,
    PyCSimpleType_Type: ?*cpython.PyTypeObject,
    PyCFuncPtrType_Type: ?*cpython.PyTypeObject,
    PyCData_Type: ?*cpython.PyTypeObject,
    Struct_Type: ?*cpython.PyTypeObject,
    Union_Type: ?*cpython.PyTypeObject,
    PyCArray_Type: ?*cpython.PyTypeObject,
    Simple_Type: ?*cpython.PyTypeObject,
    PyCPointer_Type: ?*cpython.PyTypeObject,
    PyCFuncPtr_Type: ?*cpython.PyTypeObject,
    _unpickle: ?*cpython.PyObject,
    array_cache: ?*cpython.PyObject,
    error_object_name: ?*cpython.PyObject,
    PyExc_ArgError: ?*cpython.PyObject,
    swapped_suffix: ?*cpython.PyObject,
};

/// Global module state
pub var _ctypes_state: ctypes_state = .{
    .DictRemover_Type = null,
    .PyCArg_Type = null,
    .PyCField_Type = null,
    .PyCThunk_Type = null,
    .StructParam_Type = null,
    .PyCType_Type = null,
    .PyCStructType_Type = null,
    .UnionType_Type = null,
    .PyCPointerType_Type = null,
    .PyCArrayType_Type = null,
    .PyCSimpleType_Type = null,
    .PyCFuncPtrType_Type = null,
    .PyCData_Type = null,
    .Struct_Type = null,
    .Union_Type = null,
    .PyCArray_Type = null,
    .Simple_Type = null,
    .PyCPointer_Type = null,
    .PyCFuncPtr_Type = null,
    ._unpickle = null,
    .array_cache = null,
    .error_object_name = null,
    .PyExc_ArgError = null,
    .swapped_suffix = null,
};
