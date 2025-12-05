/// CPython Initialization Interface
///
/// Implements Python runtime initialization and finalization for C extension compatibility.
///
/// ## Implementation Status
///
/// IMPLEMENTED (functional):
/// - Py_Initialize/Py_InitializeEx: Sets initialized flag (no actual init needed for AOT)
/// - Py_Finalize/Py_FinalizeEx: Clears initialized flag
/// - Py_IsInitialized: Returns initialized status
/// - Py_GetVersion/Platform/Copyright/etc: Return version info strings
/// - Py_Exit/Py_FatalError: Process exit functions
///
/// STUB (returns defaults):
/// - Py_SetPythonHome/GetPythonHome: Path configuration (not used in AOT)
/// - Py_SetProgramName/GetProgramName: Returns "python"
/// - Py_SetPath/GetPath: Module search path (not used - compiled statically)
/// - Py_AtExit: Callback registration (not implemented)
///
/// Note: metal0 compiles Python to native code, so most "initialization" is done
/// at compile time. These functions exist for C extension compatibility.
const std = @import("std");
const cpython = @import("../include/object.zig");

// Global state
var python_initialized: bool = false;

/// Initialize the Python interpreter
/// Must be called before any Python API functions
export fn Py_Initialize() callconv(.c) void {
    Py_InitializeEx(1);
}

/// Initialize Python with optional signal handling
/// initsigs: 1 to install signal handlers, 0 to skip
/// STATUS: IMPLEMENTED - sets initialized flag (actual init done at compile time)
export fn Py_InitializeEx(initsigs: c_int) callconv(.c) void {
    if (python_initialized) return;

    // metal0 AOT compiler: all types and modules are compiled statically
    // No runtime initialization needed - just set flag for C extension compat

    if (initsigs != 0) {
        // Signal handlers could be set up here if needed
        // Currently no-op - Zig uses its own signal handling
    }

    python_initialized = true;
}

/// Finalize the Python interpreter
/// Cleans up all resources and shuts down Python
export fn Py_Finalize() callconv(.c) void {
    _ = Py_FinalizeEx();
}

/// Finalize with return code
/// Returns 0 on success, -1 if errors occurred during finalization
/// STATUS: IMPLEMENTED - clears initialized flag
export fn Py_FinalizeEx() callconv(.c) c_int {
    if (!python_initialized) return 0;

    // metal0 AOT: cleanup is handled by Zig's arena/GPA allocators
    // No special finalization needed for compiled code

    python_initialized = false;
    return 0; // Success
}

/// Check if Python is initialized
/// Returns 1 if initialized, 0 otherwise
export fn Py_IsInitialized() callconv(.c) c_int {
    return if (python_initialized) 1 else 0;
}

/// Set the Python home directory
/// Should be called before Py_Initialize()
/// STATUS: STUB - path configuration not used in AOT compilation
export fn Py_SetPythonHome(home: [*:0]const u8) callconv(.c) void {
    _ = home;
    // Not used in metal0 - modules are compiled statically
}

/// Get the Python home directory
/// Returns borrowed reference to home path string
/// STATUS: STUB - returns default path
export fn Py_GetPythonHome() callconv(.c) [*:0]const u8 {
    return "/usr/local"; // Default for compatibility
}

/// Set the program name (argv[0])
/// Should be called before Py_Initialize()
/// STATUS: STUB - not stored
export fn Py_SetProgramName(name: [*:0]const u8) callconv(.c) void {
    _ = name;
    // Not used in metal0 - executable info available via std
}

/// Get the program name
/// Returns borrowed reference to program name string
/// STATUS: STUB - returns "python"
export fn Py_GetProgramName() callconv(.c) [*:0]const u8 {
    return "python"; // Default for compatibility
}

/// Set standard module search path
/// Should be called before Py_Initialize()
/// STATUS: STUB - path not used (modules compiled statically)
export fn Py_SetPath(path: [*:0]const u8) callconv(.c) void {
    _ = path;
    // Not used in metal0 - imports resolved at compile time
}

/// Get the default module search path
/// Returns borrowed reference to path string
/// STATUS: STUB - returns default path
export fn Py_GetPath() callconv(.c) [*:0]const u8 {
    return ".:/usr/local/lib/python3.11"; // Default for compatibility
}

/// Get Python version string
/// Returns borrowed reference to version string (e.g., "3.11.0")
export fn Py_GetVersion() callconv(.c) [*:0]const u8 {
    return "3.11.0"; // Match common Python version
}

/// Get platform identifier string
/// Returns borrowed reference to platform string (e.g., "linux")
export fn Py_GetPlatform() callconv(.c) [*:0]const u8 {
    return @tagName(std.builtin.os.tag);
}

/// Get copyright string
/// Returns borrowed reference to copyright string
export fn Py_GetCopyright() callconv(.c) [*:0]const u8 {
    return "metal0 - Python AOT Compiler";
}

/// Get compiler identification string
/// Returns borrowed reference to compiler string
export fn Py_GetCompiler() callconv(.c) [*:0]const u8 {
    return "Zig " ++ @import("builtin").zig_version_string;
}

/// Get build info string
/// Returns borrowed reference to build info
export fn Py_GetBuildInfo() callconv(.c) [*:0]const u8 {
    return "metal0 compiled with Zig";
}

/// Get prefix for installed platform-independent files
/// Returns borrowed reference to prefix path
export fn Py_GetPrefix() callconv(.c) [*:0]const u8 {
    return "/usr/local";
}

/// Get prefix for installed platform-dependent files
/// Returns borrowed reference to exec prefix path
export fn Py_GetExecPrefix() callconv(.c) [*:0]const u8 {
    return "/usr/local";
}

/// Get full path to Python executable
/// Returns borrowed reference to executable path
/// STATUS: STUB - returns default path
export fn Py_GetProgramFullPath() callconv(.c) [*:0]const u8 {
    // Could use std.fs.selfExePath but requires allocation
    return "/usr/local/bin/python"; // Default for compatibility
}

// PyEval_InitThreads is in cpython_eval.zig

/// At exit handler registration
/// Registers a function to be called during finalization
/// STATUS: STUB - accepts but doesn't call (no finalization hooks)
export fn Py_AtExit(func: *const fn () callconv(.c) void) callconv(.c) c_int {
    _ = func;
    // Atexit callbacks not implemented - Zig handles cleanup
    return 0; // Success (accepts silently)
}

/// Exit Python with given status code
/// Calls finalization handlers and exits process
export fn Py_Exit(status: c_int) callconv(.c) noreturn {
    Py_Finalize();
    std.process.exit(@intCast(status));
}

/// Fatal error handler
/// Prints error message and aborts Python
export fn Py_FatalError(message: [*:0]const u8) callconv(.c) noreturn {
    _ = std.c.fprintf(std.c.stderr, "Fatal Python error: %s\n", message);
    std.process.abort();
}
