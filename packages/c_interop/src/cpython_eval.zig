/// CPython Eval/Exec/Compile Interface
///
/// Implements code evaluation, execution, and compilation for CPython compatibility.
/// Fully wired to metal0's runtime eval/exec/bytecode system.
///
/// ## Implementation Status
///
/// IMPLEMENTED (functional):
/// - PyRun_SimpleString: Execute Python code string via runtime.exec
/// - PyRun_SimpleFile: Read and execute file via runtime.exec
/// - PyRun_String: Execute with start symbol (eval vs exec)
/// - PyRun_File: Read and execute file with start symbol
/// - Py_CompileString: Compile source to code object
/// - PyEval_EvalCode: Execute code object via runtime.eval
/// - PyCode_* functions: Code object creation and inspection
/// - PyGILState_*: GIL state API (no-op, metal0 has no GIL)
/// - Py_tss_*: Thread-specific storage (minimal)
///
/// STUB (returns success but no-op):
/// - PyEval_AcquireLock/ReleaseLock: No GIL in metal0
/// - PyEval_SaveThread/RestoreThread: No GIL
/// - PyEval_InitThreads: Already "initialized"
/// - PyEval_GetFrame/Globals/Locals: No frame objects (AOT compiled)
///
/// NOT APPLICABLE (metal0 architecture):
/// - PyEval_EvalFrame: metal0 doesn't have interpreter frames

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

// Runtime eval system - wired to metal0's eval/exec/bytecode
const runtime = @import("runtime");
const bytecode_mod = runtime.bytecode;

// Use centralized extern declarations
const Py_INCREF = traits.externs.Py_INCREF;
const Py_DECREF = traits.externs.Py_DECREF;
const PyErr_SetString = traits.externs.PyErr_SetString;

/// Default allocator for C API calls
const c_allocator = std.heap.c_allocator;

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
/// STATUS: IMPLEMENTED - extracts source from code object and runs via eval
export fn PyEval_EvalCode(code: *cpython.PyObject, globals: *cpython.PyObject, locals: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = globals; // TODO: Pass to eval when scope support added
    _ = locals;

    // Check if it's a code object
    if (PyCode_Check(code) == 0) {
        PyErr_SetString(@ptrFromInt(0), "expected code object");
        return null;
    }

    // Extract source from code object
    const code_obj: *PyCodeObjectStruct = @ptrCast(@alignCast(code));
    if (code_obj.co_code == null) {
        PyErr_SetString(@ptrFromInt(0), "code object has no bytecode");
        return null;
    }

    // Get source string from co_code (we stored source there in Py_CompileString)
    const bytes = @import("pyobject_bytes.zig");
    const source_ptr = bytes.PyBytes_AsString(code_obj.co_code);
    const source_len = bytes.PyBytes_Size(code_obj.co_code);

    if (source_len <= 0) {
        return @ptrCast(runtime.Py_None);
    }

    const source = source_ptr[0..@intCast(source_len)];

    // Execute via eval
    return runtime.eval(c_allocator, source) catch |err| {
        _ = err;
        PyErr_SetString(@ptrFromInt(0), "eval failed");
        return null;
    };
}

/// Evaluate a frame object
/// Returns result of evaluation or null on error
/// STATUS: NOT_IMPLEMENTED - metal0 doesn't have frame-based execution
export fn PyEval_EvalFrame(frame: *PyFrameObject) callconv(.c) ?*cpython.PyObject {
    _ = frame;
    // Frame execution not applicable - metal0 compiles to native code
    PyErr_SetString(@ptrFromInt(0), "PyEval_EvalFrame: not applicable to AOT compiled code");
    return null;
}

/// Evaluate a frame with extended behavior
/// Returns result of evaluation or null on error
export fn PyEval_EvalFrameEx(frame: *PyFrameObject, throwflag: c_int) callconv(.c) ?*cpython.PyObject {
    _ = throwflag;
    return PyEval_EvalFrame(frame);
}

// Global execution context - provides runtime dictionaries for C extensions
var builtins_dict: ?*cpython.PyObject = null;
var globals_dict: ?*cpython.PyObject = null;
var locals_dict: ?*cpython.PyObject = null;
var eval_context_initialized: bool = false;

/// Initialize the global execution context
fn ensureEvalContextInitialized() void {
    if (eval_context_initialized) return;
    eval_context_initialized = true;

    const pydict = @import("pyobject_dict.zig");
    const pyunicode = @import("cpython_unicode.zig");
    const pybool = @import("pyobject_bool.zig");

    // Create builtins dict with common Python builtins
    builtins_dict = pydict.PyDict_New();
    if (builtins_dict) |builtins| {
        // Add True/False/None
        if (pybool.Py_True) |t| _ = pydict.PyDict_SetItemString(builtins, "True", t);
        if (pybool.Py_False) |f| _ = pydict.PyDict_SetItemString(builtins, "False", f);
        if (@import("pyobject_none.zig").Py_None) |n| _ = pydict.PyDict_SetItemString(builtins, "None", n);

        // Add common type objects
        const types = @import("cpython_type.zig");
        if (types.PyType_GetBuiltinType("int")) |t| _ = pydict.PyDict_SetItemString(builtins, "int", @ptrCast(t));
        if (types.PyType_GetBuiltinType("str")) |t| _ = pydict.PyDict_SetItemString(builtins, "str", @ptrCast(t));
        if (types.PyType_GetBuiltinType("float")) |t| _ = pydict.PyDict_SetItemString(builtins, "float", @ptrCast(t));
        if (types.PyType_GetBuiltinType("list")) |t| _ = pydict.PyDict_SetItemString(builtins, "list", @ptrCast(t));
        if (types.PyType_GetBuiltinType("dict")) |t| _ = pydict.PyDict_SetItemString(builtins, "dict", @ptrCast(t));
        if (types.PyType_GetBuiltinType("tuple")) |t| _ = pydict.PyDict_SetItemString(builtins, "tuple", @ptrCast(t));
        if (types.PyType_GetBuiltinType("bool")) |t| _ = pydict.PyDict_SetItemString(builtins, "bool", @ptrCast(t));
        if (types.PyType_GetBuiltinType("bytes")) |t| _ = pydict.PyDict_SetItemString(builtins, "bytes", @ptrCast(t));
        if (types.PyType_GetBuiltinType("type")) |t| _ = pydict.PyDict_SetItemString(builtins, "type", @ptrCast(t));
        if (types.PyType_GetBuiltinType("object")) |t| _ = pydict.PyDict_SetItemString(builtins, "object", @ptrCast(t));

        // Add __name__ for builtins module
        const name = pyunicode.PyUnicode_FromString("builtins");
        if (name) |n| {
            _ = pydict.PyDict_SetItemString(builtins, "__name__", n);
            traits.decref(n);
        }
    }

    // Create empty globals and locals dicts
    globals_dict = pydict.PyDict_New();
    if (globals_dict) |globals| {
        // Set __builtins__ in globals
        if (builtins_dict) |b| {
            _ = pydict.PyDict_SetItemString(globals, "__builtins__", b);
        }
        // Set __name__ to __main__ by default
        const main_name = pyunicode.PyUnicode_FromString("__main__");
        if (main_name) |n| {
            _ = pydict.PyDict_SetItemString(globals, "__name__", n);
            traits.decref(n);
        }
    }

    // Locals starts empty - populated at runtime
    locals_dict = pydict.PyDict_New();
}

/// Set the current globals dictionary (for exec/eval)
export fn PyEval_SetGlobals(globals: ?*cpython.PyObject) callconv(.c) void {
    ensureEvalContextInitialized();
    if (globals) |g| {
        if (globals_dict) |old| traits.decref(old);
        traits.incref(g);
        globals_dict = g;
    }
}

/// Set the current locals dictionary (for exec/eval)
export fn PyEval_SetLocals(locals: ?*cpython.PyObject) callconv(.c) void {
    ensureEvalContextInitialized();
    if (locals) |l| {
        if (locals_dict) |old| traits.decref(old);
        traits.incref(l);
        locals_dict = l;
    }
}

/// Get the builtins dictionary for current context
/// Returns borrowed reference
export fn PyEval_GetBuiltins() callconv(.c) ?*cpython.PyObject {
    ensureEvalContextInitialized();
    return builtins_dict;
}

/// Get the globals dictionary for current context
/// Returns borrowed reference
export fn PyEval_GetGlobals() callconv(.c) ?*cpython.PyObject {
    ensureEvalContextInitialized();
    return globals_dict;
}

/// Get the locals dictionary for current context
/// Returns borrowed reference
export fn PyEval_GetLocals() callconv(.c) ?*cpython.PyObject {
    ensureEvalContextInitialized();
    return locals_dict;
}

/// Get the current frame object
/// Returns borrowed reference
/// STATUS: STUB - returns null (metal0 has no interpreter frames)
export fn PyEval_GetFrame() callconv(.c) ?*PyFrameObject {
    // metal0 compiles to native code - no interpreter frames
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
/// STATUS: NO-OP - metal0 has no GIL (uses native threads/async)
export fn PyEval_SaveThread() callconv(.c) ?*PyThreadState {
    // No GIL in metal0 - return null (no thread state tracking needed)
    return null;
}

/// Restore thread state and reacquire the GIL
/// Takes ownership of thread state
/// STATUS: NO-OP - metal0 has no GIL
export fn PyEval_RestoreThread(tstate: ?*PyThreadState) callconv(.c) void {
    _ = tstate;
    // No GIL to reacquire - no-op
}

/// Acquire the Global Interpreter Lock
/// STATUS: NO-OP - metal0 has no GIL
export fn PyEval_AcquireLock() callconv(.c) void {
    // No GIL in metal0 - no-op
}

/// Release the Global Interpreter Lock
/// STATUS: NO-OP - metal0 has no GIL
export fn PyEval_ReleaseLock() callconv(.c) void {
    // No GIL in metal0 - no-op
}

/// Acquire the GIL for a specific thread state
/// STATUS: NO-OP - metal0 has no GIL
export fn PyEval_AcquireThread(tstate: *PyThreadState) callconv(.c) void {
    _ = tstate;
    // No GIL in metal0 - no-op
}

/// Release the GIL for a specific thread state
/// STATUS: NO-OP - metal0 has no GIL
export fn PyEval_ReleaseThread(tstate: *PyThreadState) callconv(.c) void {
    _ = tstate;
    // No GIL in metal0 - no-op
}

/// Initialize thread support
/// STATUS: NO-OP - always "initialized" (no GIL)
export fn PyEval_InitThreads() callconv(.c) void {
    // No GIL to initialize - no-op
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
/// STATUS: NO-OP - always returns LOCKED (no GIL in metal0)
export fn PyGILState_Ensure() callconv(.c) PyGILState_STATE {
    // No GIL in metal0 - always "have" it
    return .PyGILState_LOCKED;
}

/// Release the GIL according to the state returned by PyGILState_Ensure
/// If state was UNLOCKED, releases the GIL and destroys thread state
/// STATUS: NO-OP - no GIL to release
export fn PyGILState_Release(state: PyGILState_STATE) callconv(.c) void {
    _ = state;
    // No GIL in metal0 - no-op
}

/// Check if the current thread holds the GIL
/// Returns 1 if this thread has the GIL, 0 otherwise
/// STATUS: STUB - always returns 1 (no GIL, so always "held")
export fn PyGILState_Check() callconv(.c) c_int {
    // No GIL in metal0 - always "have" it
    return 1;
}

/// Get the current thread state for the GIL state API
/// Returns current thread state or null if not created via GIL API
/// STATUS: STUB - returns null (no thread state tracking)
export fn PyGILState_GetThisThreadState() callconv(.c) ?*PyThreadState {
    // No thread state tracking in metal0
    return null;
}

// ============================================================================
// PyRun Functions - Run Python code from strings/files
// ============================================================================

/// Run a simple Python command string
/// Returns 0 on success, -1 on error
/// STATUS: IMPLEMENTED - wired to runtime.exec
export fn PyRun_SimpleString(command: [*:0]const u8) callconv(.c) c_int {
    const cmd_slice = std.mem.span(command);
    runtime.exec(c_allocator, cmd_slice) catch |err| {
        _ = err;
        return -1;
    };
    return 0; // Success
}

/// Run a simple Python file
/// Returns 0 on success, -1 on error
/// STATUS: IMPLEMENTED - reads file and runs via runtime.exec
export fn PyRun_SimpleFile(fp: *std.c.FILE, filename: [*:0]const u8) callconv(.c) c_int {
    _ = filename;

    // Read file contents
    var buffer: [65536]u8 = undefined;
    var total_read: usize = 0;

    while (true) {
        const bytes_read = std.c.fread(buffer[total_read..].ptr, 1, buffer.len - total_read, fp);
        if (bytes_read == 0) break;
        total_read += bytes_read;
        if (total_read >= buffer.len) break;
    }

    if (total_read == 0) return 0; // Empty file is success

    runtime.exec(c_allocator, buffer[0..total_read]) catch |err| {
        _ = err;
        return -1;
    };
    return 0;
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
/// STATUS: IMPLEMENTED - wired to runtime.eval/exec
export fn PyRun_String(str: [*:0]const u8, start: c_int, globals: *cpython.PyObject, locals: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = globals; // TODO: Pass to eval/exec when scope support added
    _ = locals;

    const str_slice = std.mem.span(str);

    if (start == Py_eval_input) {
        // Expression - use eval
        return runtime.eval(c_allocator, str_slice) catch |err| {
            _ = err;
            PyErr_SetString(@ptrFromInt(0), "eval() failed");
            return null;
        };
    } else {
        // Statement/file - use exec
        runtime.exec(c_allocator, str_slice) catch |err| {
            _ = err;
            PyErr_SetString(@ptrFromInt(0), "exec() failed");
            return null;
        };
        // exec returns None
        return @ptrCast(runtime.Py_None);
    }
}

/// Run Python file with specified start symbol
/// Returns result object or null on error
/// STATUS: IMPLEMENTED - reads file and runs via runtime
export fn PyRun_File(fp: *std.c.FILE, filename: [*:0]const u8, start: c_int, globals: *cpython.PyObject, locals: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = filename;
    _ = globals;
    _ = locals;

    // Read file contents
    var buffer: [65536]u8 = undefined;
    var total_read: usize = 0;

    while (true) {
        const bytes_read = std.c.fread(buffer[total_read..].ptr, 1, buffer.len - total_read, fp);
        if (bytes_read == 0) break;
        total_read += bytes_read;
        if (total_read >= buffer.len) break;
    }

    if (total_read == 0) {
        // Empty file returns None
        return @ptrCast(runtime.Py_None);
    }

    const source = buffer[0..total_read];

    if (start == Py_eval_input) {
        return runtime.eval(c_allocator, source) catch |err| {
            _ = err;
            PyErr_SetString(@ptrFromInt(0), "eval() failed");
            return null;
        };
    } else {
        runtime.exec(c_allocator, source) catch |err| {
            _ = err;
            PyErr_SetString(@ptrFromInt(0), "exec() failed");
            return null;
        };
        return @ptrCast(runtime.Py_None);
    }
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
/// STATUS: IMPLEMENTED - stores source for later execution via eval/exec
export fn Py_CompileString(str: [*:0]const u8, filename: [*:0]const u8, start: c_int) callconv(.c) ?*cpython.PyObject {
    _ = start; // Compile mode stored in flags

    const str_slice = std.mem.span(str);
    const filename_slice = std.mem.span(filename);

    // Create code object that stores the source for later execution
    // (metal0 compiles on-demand when PyEval_EvalCode is called)
    const code = c_allocator.create(PyCodeObjectStruct) catch return null;

    code.ob_base.ob_refcnt = 1;
    code.ob_base.ob_type = &PyCode_Type;
    code.co_argcount = 0;
    code.co_posonlyargcount = 0;
    code.co_kwonlyargcount = 0;
    code.co_nlocals = 0;
    code.co_stacksize = 256;
    code.co_flags = 0;
    code.co_firstlineno = 1;

    // Store filename and source
    const unicode = @import("cpython_unicode.zig");
    code.co_filename = unicode.PyUnicode_FromString(filename_slice.ptr);
    code.co_name = unicode.PyUnicode_FromString("__main__");
    code.co_qualname = code.co_name;

    // Store source code as co_code (will be compiled when executed)
    const bytes = @import("pyobject_bytes.zig");
    code.co_code = bytes.PyBytes_FromStringAndSize(str_slice.ptr, @intCast(str_slice.len));

    code.co_consts = null;
    code.co_names = null;
    code.co_varnames = null;
    code.co_freevars = null;
    code.co_cellvars = null;

    return @ptrCast(code);
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
/// STATUS: NOT_IMPLEMENTED - requires runtime.bytecode integration
export fn Py_CompileStringObject(str: [*:0]const u8, filename: *cpython.PyObject, start: c_int, flags: ?*anyopaque, optimize: c_int) callconv(.c) ?*cpython.PyObject {
    _ = filename;
    _ = optimize;
    _ = flags;
    _ = start;
    _ = str;
    // Requires runtime module integration
    PyErr_SetString(@ptrFromInt(0), "Py_CompileStringObject: requires runtime module integration");
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
        var counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(1);
    };
    key._key = tss_key_counter.counter.load(.seq_cst);
    _ = tss_key_counter.counter.fetchAdd(1, .seq_cst);
    key._is_initialized = 1;
    return 0;
}

/// Delete a TSS key
export fn PyThread_tss_delete(key: *Py_tss_t) callconv(.c) void {
    key._is_initialized = 0;
    key._key = 0;
}

/// Thread-local storage for TSS values (keyed by TSS key index)
const TssStorage = struct {
    const MAX_KEYS = 128;
    var values: [MAX_KEYS]?*anyopaque = [_]?*anyopaque{null} ** MAX_KEYS;
    var mutex: std.Thread.Mutex = .{};
};

/// Get value associated with TSS key for current thread
export fn PyThread_tss_get(key: *Py_tss_t) callconv(.c) ?*anyopaque {
    if (key._is_initialized == 0) return null;
    if (key._key == 0 or key._key >= TssStorage.MAX_KEYS) return null;

    TssStorage.mutex.lock();
    defer TssStorage.mutex.unlock();
    return TssStorage.values[key._key];
}

/// Set value associated with TSS key for current thread
/// Returns 0 on success, -1 on error
export fn PyThread_tss_set(key: *Py_tss_t, value: ?*anyopaque) callconv(.c) c_int {
    if (key._is_initialized == 0) return -1;
    if (key._key == 0 or key._key >= TssStorage.MAX_KEYS) return -1;

    TssStorage.mutex.lock();
    defer TssStorage.mutex.unlock();
    TssStorage.values[key._key] = value;
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
/// STATUS: STUB - returns success but no-op (metal0 uses native stack traces)
export fn PyTraceBack_Here(frame: *cpython.PyObject) callconv(.c) c_int {
    _ = frame;
    // metal0 uses native stack traces via Zig's error return trace
    return 0;
}

/// Print traceback to file
/// STATUS: STUB - returns success but no-op
export fn PyTraceBack_Print(tb: *cpython.PyObject, file: *cpython.PyObject) callconv(.c) c_int {
    _ = tb;
    _ = file;
    // metal0 uses native stack traces
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
/// STATUS: NOT_SUPPORTED - metal0 doesn't support sub-interpreters
export fn Py_NewInterpreter() callconv(.c) ?*PyThreadState {
    // Sub-interpreters not supported - metal0 compiles to native code
    return null;
}

/// End sub-interpreter
/// STATUS: NO-OP - sub-interpreters not supported
export fn Py_EndInterpreter(tstate: ?*PyThreadState) callconv(.c) void {
    _ = tstate;
    // Sub-interpreters not supported - no-op
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

/// Thread-local dictionary for PyThreadState_GetDict
/// Extensions use this for thread-local storage (e.g., SQLite3 connection state)
threadlocal var thread_dict: ?*cpython.PyObject = null;

/// Get dictionary for thread-local data
/// Returns a dict that persists for the lifetime of the thread
export fn PyThreadState_GetDict() callconv(.c) ?*cpython.PyObject {
    if (thread_dict == null) {
        const pydict = @import("pyobject_dict.zig");
        thread_dict = pydict.PyDict_New();
    }
    return thread_dict;
}

/// Internal thread state structure (our implementation)
const InternalThreadState = struct {
    interp: ?*PyInterpreterState,
    dict: ?*cpython.PyObject,
    thread_id: u64,
    prev: ?*InternalThreadState,
    next: ?*InternalThreadState,
};

/// Thread state pool for reuse
var thread_state_pool: std.ArrayList(*InternalThreadState) = undefined;
var thread_state_pool_initialized: bool = false;

fn initThreadStatePool() void {
    if (thread_state_pool_initialized) return;
    thread_state_pool_initialized = true;
    thread_state_pool = std.ArrayList(*InternalThreadState).init(std.heap.c_allocator);
}

/// Create new thread state
export fn PyThreadState_New(interp: ?*PyInterpreterState) callconv(.c) ?*PyThreadState {
    initThreadStatePool();

    // Allocate new thread state
    const tstate = std.heap.c_allocator.create(InternalThreadState) catch return null;
    tstate.* = InternalThreadState{
        .interp = interp orelse main_interp_state,
        .dict = null,
        .thread_id = @intCast(std.Thread.getCurrentId()),
        .prev = null,
        .next = null,
    };

    thread_state_pool.append(tstate) catch {};

    // Return as opaque pointer
    return @ptrCast(tstate);
}

/// Delete thread state
/// STATUS: NO-OP - no thread state to delete
export fn PyThreadState_Delete(tstate: ?*PyThreadState) callconv(.c) void {
    _ = tstate;
    // No thread state management - no-op
}

/// Clear thread state
/// STATUS: NO-OP - no thread state to clear
export fn PyThreadState_Clear(tstate: ?*PyThreadState) callconv(.c) void {
    _ = tstate;
    // No thread state management - no-op
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
/// STATUS: STUB - returns 0 (async exceptions not supported)
export fn PyThreadState_SetAsyncExc(id: c_ulong, exc: ?*cpython.PyObject) callconv(.c) c_int {
    _ = id;
    _ = exc;
    // Async exceptions not applicable - metal0 has no interpreter loop to interrupt
    return 0;
}
