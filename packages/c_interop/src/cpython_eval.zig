/// CPython Eval/Exec/Compile Interface
///
/// Implements code evaluation, execution, and compilation for CPython compatibility.

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

// Use centralized extern declarations
const Py_INCREF = traits.externs.Py_INCREF;
const Py_DECREF = traits.externs.Py_DECREF;
const PyErr_SetString = traits.externs.PyErr_SetString;

// Start symbols for parsing
pub const Py_eval_input: c_int = 256; // Expression
pub const Py_file_input: c_int = 257; // File/module
pub const Py_single_input: c_int = 258; // Single interactive statement

/// Thread state structure (opaque)
pub const PyThreadState = opaque {};

/// Frame object structure (opaque)
pub const PyFrameObject = opaque {};

/// Code object structure (opaque)
pub const PyCodeObject = opaque {};

// ============================================================================
// PyEval Functions - Evaluation and execution
// ============================================================================

/// Evaluate a code object with given globals and locals
/// Returns result of evaluation or null on error
export fn PyEval_EvalCode(code: *cpython.PyObject, globals: *cpython.PyObject, locals: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = code;
    _ = globals;
    _ = locals;
    // TODO: Execute code object and return result
    PyErr_SetString(@ptrFromInt(0), "PyEval_EvalCode not implemented");
    return null;
}

/// Evaluate a frame object
/// Returns result of evaluation or null on error
export fn PyEval_EvalFrame(frame: *PyFrameObject) callconv(.c) ?*cpython.PyObject {
    _ = frame;
    // TODO: Execute frame and return result
    PyErr_SetString(@ptrFromInt(0), "PyEval_EvalFrame not implemented");
    return null;
}

/// Evaluate a frame with extended behavior
/// Returns result of evaluation or null on error
export fn PyEval_EvalFrameEx(frame: *PyFrameObject, throwflag: c_int) callconv(.c) ?*cpython.PyObject {
    _ = throwflag;
    return PyEval_EvalFrame(frame);
}

/// Get the builtins dictionary for current context
/// Returns borrowed reference
export fn PyEval_GetBuiltins() callconv(.c) ?*cpython.PyObject {
    // TODO: Return builtins dict from current thread state
    return null;
}

/// Get the globals dictionary for current context
/// Returns borrowed reference
export fn PyEval_GetGlobals() callconv(.c) ?*cpython.PyObject {
    // TODO: Return globals dict from current frame
    return null;
}

/// Get the locals dictionary for current context
/// Returns borrowed reference
export fn PyEval_GetLocals() callconv(.c) ?*cpython.PyObject {
    // TODO: Return locals dict from current frame
    return null;
}

/// Get the current frame object
/// Returns borrowed reference
export fn PyEval_GetFrame() callconv(.c) ?*PyFrameObject {
    // TODO: Return current frame from thread state
    return null;
}

/// Get the name of the current function
/// Returns borrowed reference to function name string
export fn PyEval_GetFuncName(func: *cpython.PyObject) callconv(.c) [*:0]const u8 {
    _ = func;
    return "?"; // Unknown function
}

/// Get the description of the current function
/// Returns borrowed reference to function description string
export fn PyEval_GetFuncDesc(func: *cpython.PyObject) callconv(.c) [*:0]const u8 {
    _ = func;
    return ""; // Empty description
}

// ============================================================================
// Thread State Management
// ============================================================================

/// Save the current thread state and release the GIL
/// Returns the saved thread state
export fn PyEval_SaveThread() callconv(.c) ?*PyThreadState {
    // TODO: Release GIL and return current thread state
    return null;
}

/// Restore thread state and reacquire the GIL
/// Takes ownership of thread state
export fn PyEval_RestoreThread(tstate: ?*PyThreadState) callconv(.c) void {
    _ = tstate;
    // TODO: Reacquire GIL and restore thread state
}

/// Acquire the Global Interpreter Lock
export fn PyEval_AcquireLock() callconv(.c) void {
    // TODO: Acquire GIL
}

/// Release the Global Interpreter Lock
export fn PyEval_ReleaseLock() callconv(.c) void {
    // TODO: Release GIL
}

/// Acquire the GIL for a specific thread state
export fn PyEval_AcquireThread(tstate: *PyThreadState) callconv(.c) void {
    _ = tstate;
    // TODO: Acquire GIL and set as current thread
}

/// Release the GIL for a specific thread state
export fn PyEval_ReleaseThread(tstate: *PyThreadState) callconv(.c) void {
    _ = tstate;
    // TODO: Release GIL and clear current thread
}

/// Initialize thread support
export fn PyEval_InitThreads() callconv(.c) void {
    // TODO: Initialize GIL and thread support
}

/// Check if thread support is initialized
/// Returns 1 if initialized, 0 otherwise
export fn PyEval_ThreadsInitialized() callconv(.c) c_int {
    return 1; // Assume initialized
}

// ============================================================================
// GIL State API - For C extensions managing the GIL
// ============================================================================

/// GIL state enum - used by PyGILState_Ensure/Release
pub const PyGILState_STATE = enum(c_int) {
    PyGILState_LOCKED = 0,
    PyGILState_UNLOCKED = 1,
};

/// Ensure the current thread holds the GIL
/// If the thread doesn't have a Python thread state, one is created
/// Returns state to pass to PyGILState_Release
export fn PyGILState_Ensure() callconv(.c) PyGILState_STATE {
    // TODO: Check if current thread has thread state
    // If not, create one and acquire GIL
    // For now, return LOCKED (we always "have" the GIL in single-threaded mode)
    return .PyGILState_LOCKED;
}

/// Release the GIL according to the state returned by PyGILState_Ensure
/// If state was UNLOCKED, releases the GIL and destroys thread state
export fn PyGILState_Release(state: PyGILState_STATE) callconv(.c) void {
    _ = state;
    // TODO: If state was UNLOCKED, release GIL and destroy temp thread state
    // For now, no-op in single-threaded mode
}

/// Check if the current thread holds the GIL
/// Returns 1 if this thread has the GIL, 0 otherwise
export fn PyGILState_Check() callconv(.c) c_int {
    // TODO: Check if current thread is the one holding the GIL
    // For now, assume we always have the GIL
    return 1;
}

/// Get the current thread state for the GIL state API
/// Returns current thread state or null if not created via GIL API
export fn PyGILState_GetThisThreadState() callconv(.c) ?*PyThreadState {
    // TODO: Return thread state created by GIL state API
    return null;
}

// ============================================================================
// PyRun Functions - Run Python code from strings/files
// ============================================================================

/// Run a simple Python command string
/// Returns 0 on success, -1 on error
export fn PyRun_SimpleString(command: [*:0]const u8) callconv(.c) c_int {
    _ = command;
    // TODO: Parse and execute command string
    // This is the simplest interface - just run code, no return value
    return 0; // Success
}

/// Run a simple Python file
/// Returns 0 on success, -1 on error
export fn PyRun_SimpleFile(fp: *std.c.FILE, filename: [*:0]const u8) callconv(.c) c_int {
    _ = fp;
    _ = filename;
    // TODO: Read file and execute as Python code
    return 0; // Success
}

/// Run a simple Python file with explicit close flag
/// Returns 0 on success, -1 on error
export fn PyRun_SimpleFileEx(fp: *std.c.FILE, filename: [*:0]const u8, closeit: c_int) callconv(.c) c_int {
    const result = PyRun_SimpleFile(fp, filename);

    if (closeit != 0) {
        _ = std.c.fclose(fp);
    }

    return result;
}

/// Run Python string with specified start symbol
/// Returns result object or null on error
export fn PyRun_String(str: [*:0]const u8, start: c_int, globals: *cpython.PyObject, locals: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = str;
    _ = start;
    _ = globals;
    _ = locals;
    // TODO: Parse string and execute with given start symbol
    // start is Py_eval_input, Py_file_input, or Py_single_input
    PyErr_SetString(@ptrFromInt(0), "PyRun_String not implemented");
    return null;
}

/// Run Python file with specified start symbol
/// Returns result object or null on error
export fn PyRun_File(fp: *std.c.FILE, filename: [*:0]const u8, start: c_int, globals: *cpython.PyObject, locals: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = fp;
    _ = filename;
    _ = start;
    _ = globals;
    _ = locals;
    // TODO: Read file, parse and execute with given start symbol
    PyErr_SetString(@ptrFromInt(0), "PyRun_File not implemented");
    return null;
}

/// Run Python file with explicit close flag
/// Returns result object or null on error
export fn PyRun_FileEx(fp: *std.c.FILE, filename: [*:0]const u8, start: c_int, globals: *cpython.PyObject, locals: *cpython.PyObject, closeit: c_int) callconv(.c) ?*cpython.PyObject {
    const result = PyRun_File(fp, filename, start, globals, locals);

    if (closeit != 0) {
        _ = std.c.fclose(fp);
    }

    return result;
}

/// Run Python file with flags
/// Returns result object or null on error
export fn PyRun_FileFlags(fp: *std.c.FILE, filename: [*:0]const u8, start: c_int, globals: *cpython.PyObject, locals: *cpython.PyObject, flags: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    _ = flags;
    return PyRun_File(fp, filename, start, globals, locals);
}

// ============================================================================
// Py_Compile Functions - Compile Python code to code objects
// ============================================================================

/// Compile a Python source string into a code object
/// Returns code object or null on error
export fn Py_CompileString(str: [*:0]const u8, filename: [*:0]const u8, start: c_int) callconv(.c) ?*cpython.PyObject {
    _ = str;
    _ = filename;
    _ = start;
    // TODO: Parse string and compile to code object
    // start is Py_eval_input, Py_file_input, or Py_single_input
    PyErr_SetString(@ptrFromInt(0), "Py_CompileString not implemented");
    return null;
}

/// Compile with compiler flags
/// Returns code object or null on error
export fn Py_CompileStringFlags(str: [*:0]const u8, filename: [*:0]const u8, start: c_int, flags: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    _ = flags;
    return Py_CompileString(str, filename, start);
}

/// Compile with explicit flags structure
/// Returns code object or null on error
export fn Py_CompileStringExFlags(str: [*:0]const u8, filename: [*:0]const u8, start: c_int, flags: ?*anyopaque, optimize: c_int) callconv(.c) ?*cpython.PyObject {
    _ = optimize;
    return Py_CompileStringFlags(str, filename, start, flags);
}

/// Compile with object filename
/// Returns code object or null on error
export fn Py_CompileStringObject(str: [*:0]const u8, filename: *cpython.PyObject, start: c_int, flags: ?*anyopaque, optimize: c_int) callconv(.c) ?*cpython.PyObject {
    _ = filename;
    _ = optimize;
    _ = flags;
    _ = start;
    _ = str;
    // TODO: Use filename object instead of string
    PyErr_SetString(@ptrFromInt(0), "Py_CompileStringObject not implemented");
    return null;
}

// ============================================================================
// Thread-Specific Storage (TSS) API - Replaces deprecated TLS API
// ============================================================================

/// TSS key structure - opaque type for thread-specific storage
pub const Py_tss_t = extern struct {
    _is_initialized: c_int,
    _key: usize, // Platform-specific key (pthread_key_t on POSIX)
};

/// Undefined TSS key value
pub const Py_tss_NEEDS_INIT: Py_tss_t = .{ ._is_initialized = 0, ._key = 0 };

/// Check if TSS key is created
export fn PyThread_tss_is_created(key: *Py_tss_t) callconv(.c) c_int {
    return key._is_initialized;
}

/// Create a TSS key
/// Returns 0 on success, -1 on error
export fn PyThread_tss_create(key: *Py_tss_t) callconv(.c) c_int {
    if (key._is_initialized != 0) return 0; // Already created

    // Use simple counter as key (in real impl would use pthread_key_create)
    const tss_key_counter = struct {
        var counter: usize = 1;
    };
    key._key = @atomicLoad(&tss_key_counter.counter, .seq_cst);
    _ = @atomicRmw(&tss_key_counter.counter, .Add, 1, .seq_cst);
    key._is_initialized = 1;
    return 0;
}

/// Delete a TSS key
export fn PyThread_tss_delete(key: *Py_tss_t) callconv(.c) void {
    key._is_initialized = 0;
    key._key = 0;
}

/// Get value associated with TSS key for current thread
export fn PyThread_tss_get(key: *Py_tss_t) callconv(.c) ?*anyopaque {
    if (key._is_initialized == 0) return null;
    // TODO: Use pthread_getspecific or platform equivalent
    // For now, return null (single-threaded mode)
    return null;
}

/// Set value associated with TSS key for current thread
/// Returns 0 on success, -1 on error
export fn PyThread_tss_set(key: *Py_tss_t, value: ?*anyopaque) callconv(.c) c_int {
    if (key._is_initialized == 0) return -1;
    _ = value;
    // TODO: Use pthread_setspecific or platform equivalent
    // For now, no-op (single-threaded mode)
    return 0;
}

/// Allocate a TSS key on the heap
export fn PyThread_tss_alloc() callconv(.c) ?*Py_tss_t {
    const allocator = std.heap.c_allocator;
    const key = allocator.create(Py_tss_t) catch return null;
    key.* = Py_tss_NEEDS_INIT;
    return key;
}

/// Free a heap-allocated TSS key
export fn PyThread_tss_free(key: ?*Py_tss_t) callconv(.c) void {
    if (key) |k| {
        PyThread_tss_delete(k);
        const allocator = std.heap.c_allocator;
        allocator.destroy(k);
    }
}

// ============================================================================
// PyCode_* - Code Object Functions
// ============================================================================

/// Code object type
pub var PyCode_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "code",
    .tp_basicsize = @sizeOf(PyCodeObjectStruct),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
};

/// Internal code object structure (simplified)
pub const PyCodeObjectStruct = extern struct {
    ob_base: cpython.PyObject,
    co_argcount: c_int, // #arguments, except *args
    co_posonlyargcount: c_int, // #positional only arguments
    co_kwonlyargcount: c_int, // #keyword only arguments
    co_nlocals: c_int, // #local variables
    co_stacksize: c_int, // #entries needed for evaluation stack
    co_flags: c_int, // CO_..., see below
    co_firstlineno: c_int, // first source line number
    co_code: ?*cpython.PyObject, // instruction opcodes
    co_consts: ?*cpython.PyObject, // list of constants
    co_names: ?*cpython.PyObject, // list of strings (names used)
    co_varnames: ?*cpython.PyObject, // tuple of strings (local variable names)
    co_freevars: ?*cpython.PyObject, // tuple of strings (free variable names)
    co_cellvars: ?*cpython.PyObject, // tuple of strings (cell variable names)
    co_filename: ?*cpython.PyObject, // unicode (where it was loaded from)
    co_name: ?*cpython.PyObject, // unicode (name, for reference)
    co_qualname: ?*cpython.PyObject, // unicode (qualified name)
};

/// Check if object is a code object
export fn PyCode_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyCode_Type) 1 else 0;
}

/// Get number of free variables in code object
export fn PyCode_GetNumFree(code: *cpython.PyObject) callconv(.c) isize {
    const co: *PyCodeObjectStruct = @ptrCast(@alignCast(code));
    if (co.co_freevars) |freevars| {
        const pytuple = @import("pyobject_tuple.zig");
        return pytuple.PyTuple_Size(freevars);
    }
    return 0;
}

/// Create new code object (simplified - full version has many more args)
export fn PyCode_New(
    argcount: c_int,
    kwonlyargcount: c_int,
    nlocals: c_int,
    stacksize: c_int,
    flags: c_int,
    code: *cpython.PyObject,
    consts: *cpython.PyObject,
    names: *cpython.PyObject,
    varnames: *cpython.PyObject,
    freevars: *cpython.PyObject,
    cellvars: *cpython.PyObject,
    filename: *cpython.PyObject,
    name: *cpython.PyObject,
    firstlineno: c_int,
    lnotab: *cpython.PyObject,
) callconv(.c) ?*cpython.PyObject {
    _ = lnotab;
    const allocator = std.heap.c_allocator;
    const co = allocator.create(PyCodeObjectStruct) catch return null;

    co.ob_base.ob_refcnt = 1;
    co.ob_base.ob_type = &PyCode_Type;
    co.co_argcount = argcount;
    co.co_posonlyargcount = 0;
    co.co_kwonlyargcount = kwonlyargcount;
    co.co_nlocals = nlocals;
    co.co_stacksize = stacksize;
    co.co_flags = flags;
    co.co_firstlineno = firstlineno;
    co.co_code = code;
    co.co_consts = consts;
    co.co_names = names;
    co.co_varnames = varnames;
    co.co_freevars = freevars;
    co.co_cellvars = cellvars;
    co.co_filename = filename;
    co.co_name = name;
    co.co_qualname = name;

    // INCREF all object references
    _ = traits.incref(code);
    _ = traits.incref(consts);
    _ = traits.incref(names);
    _ = traits.incref(varnames);
    _ = traits.incref(freevars);
    _ = traits.incref(cellvars);
    _ = traits.incref(filename);
    _ = traits.incref(name);

    return @ptrCast(&co.ob_base);
}

/// Create empty code object (for modules)
export fn PyCode_NewEmpty(filename: [*:0]const u8, funcname: [*:0]const u8, firstlineno: c_int) callconv(.c) ?*cpython.PyObject {
    const pyunicode = @import("cpython_unicode.zig");
    const pytuple = @import("pyobject_tuple.zig");
    const pybytes = @import("pyobject_bytes.zig");

    // Create empty objects
    const empty_tuple = pytuple.PyTuple_New(0) orelse return null;
    const empty_bytes = pybytes.PyBytes_FromStringAndSize(null, 0) orelse {
        traits.decref(empty_tuple);
        return null;
    };
    const filename_obj = pyunicode.PyUnicode_FromString(filename) orelse {
        traits.decref(empty_tuple);
        traits.decref(empty_bytes);
        return null;
    };
    const name_obj = pyunicode.PyUnicode_FromString(funcname) orelse {
        traits.decref(empty_tuple);
        traits.decref(empty_bytes);
        traits.decref(filename_obj);
        return null;
    };

    return PyCode_New(
        0, // argcount
        0, // kwonlyargcount
        0, // nlocals
        1, // stacksize
        0, // flags
        empty_bytes,
        empty_tuple,
        empty_tuple,
        empty_tuple,
        empty_tuple,
        empty_tuple,
        filename_obj,
        name_obj,
        firstlineno,
        empty_bytes,
    );
}

// ============================================================================
// PyTraceBack_* - Traceback Functions
// ============================================================================

/// Traceback object structure (simplified)
pub const PyTracebackObject = extern struct {
    ob_base: cpython.PyObject,
    tb_next: ?*PyTracebackObject,
    tb_frame: ?*cpython.PyObject, // PyFrameObject
    tb_lasti: c_int,
    tb_lineno: c_int,
};

pub var PyTraceBack_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "traceback",
    .tp_basicsize = @sizeOf(PyTracebackObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
};

/// Add traceback entry
export fn PyTraceBack_Here(frame: *cpython.PyObject) callconv(.c) c_int {
    _ = frame;
    // TODO: Create new traceback entry and link to current exception
    return 0;
}

/// Print traceback to file
export fn PyTraceBack_Print(tb: *cpython.PyObject, file: *cpython.PyObject) callconv(.c) c_int {
    _ = tb;
    _ = file;
    // TODO: Format and print traceback
    return 0;
}

// ============================================================================
// PyInterpreterState_* - Interpreter State Functions
// ============================================================================

/// Interpreter state (opaque)
pub const PyInterpreterState = opaque {};

/// Global main interpreter state
var main_interp_state: ?*PyInterpreterState = null;

/// Get the main interpreter state
export fn PyInterpreterState_Main() callconv(.c) ?*PyInterpreterState {
    return main_interp_state;
}

/// Get the current interpreter state
export fn PyInterpreterState_Get() callconv(.c) ?*PyInterpreterState {
    return main_interp_state;
}

/// Get the head interpreter state
export fn PyInterpreterState_Head() callconv(.c) ?*PyInterpreterState {
    return main_interp_state;
}

/// Get next interpreter state (for iteration)
export fn PyInterpreterState_Next(interp: ?*PyInterpreterState) callconv(.c) ?*PyInterpreterState {
    _ = interp;
    return null; // Single interpreter for now
}

/// Create new sub-interpreter
export fn Py_NewInterpreter() callconv(.c) ?*PyThreadState {
    // TODO: Create new interpreter
    return null;
}

/// End sub-interpreter
export fn Py_EndInterpreter(tstate: ?*PyThreadState) callconv(.c) void {
    _ = tstate;
    // TODO: Clean up interpreter
}

// ============================================================================
// PyThreadState_* - Thread State Functions
// ============================================================================

/// Global current thread state
var current_thread_state: ?*PyThreadState = null;

/// Get current thread state
export fn PyThreadState_Get() callconv(.c) ?*PyThreadState {
    return current_thread_state;
}

/// Get current thread state (may be null)
export fn _PyThreadState_UncheckedGet() callconv(.c) ?*PyThreadState {
    return current_thread_state;
}

/// Set current thread state
export fn PyThreadState_Swap(new_tstate: ?*PyThreadState) callconv(.c) ?*PyThreadState {
    const old = current_thread_state;
    current_thread_state = new_tstate;
    return old;
}

/// Get dictionary for thread-local data
export fn PyThreadState_GetDict() callconv(.c) ?*cpython.PyObject {
    // TODO: Return thread state dict
    return null;
}

/// Create new thread state
export fn PyThreadState_New(interp: ?*PyInterpreterState) callconv(.c) ?*PyThreadState {
    _ = interp;
    // TODO: Create new thread state
    return null;
}

/// Delete thread state
export fn PyThreadState_Delete(tstate: ?*PyThreadState) callconv(.c) void {
    _ = tstate;
    // TODO: Free thread state
}

/// Clear thread state
export fn PyThreadState_Clear(tstate: ?*PyThreadState) callconv(.c) void {
    _ = tstate;
    // TODO: Clear thread state
}

/// Get interpreter from thread state
export fn PyThreadState_GetInterpreter(tstate: ?*PyThreadState) callconv(.c) ?*PyInterpreterState {
    _ = tstate;
    return main_interp_state;
}

/// Get frame from thread state
export fn PyThreadState_GetFrame(tstate: ?*PyThreadState) callconv(.c) ?*cpython.PyObject {
    _ = tstate;
    return null;
}

/// Get thread ID from thread state
export fn PyThreadState_GetID(tstate: ?*PyThreadState) callconv(.c) u64 {
    _ = tstate;
    // Return some unique identifier
    return 1;
}

/// Set async exception on thread
export fn PyThreadState_SetAsyncExc(id: c_ulong, exc: ?*cpython.PyObject) callconv(.c) c_int {
    _ = id;
    _ = exc;
    // TODO: Set async exception
    return 0;
}
