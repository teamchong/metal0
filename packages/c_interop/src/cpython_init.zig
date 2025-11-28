/// CPython Initialization Interface
///
/// Implements Python runtime initialization and finalization.
const std = @import("std");
const cpython = @import("cpython_object.zig");

// Global state
var python_initialized: bool = false;

/// Initialize the Python interpreter
/// Must be called before any Python API functions
export fn Py_Initialize() callconv(.c) void {
    Py_InitializeEx(1);
}

/// Initialize Python with optional signal handling
/// initsigs: 1 to install signal handlers, 0 to skip
export fn Py_InitializeEx(initsigs: c_int) callconv(.c) void {
    if (python_initialized) return;

    // TODO: Initialize interpreter subsystems:
    // - Thread state and GIL
    // - Built-in types (int, str, list, dict, etc.)
    // - Built-in modules (sys, builtins, _io, etc.)
    // - Import system
    // - Signal handlers (if initsigs != 0)
    // - Standard I/O streams (sys.stdin, stdout, stderr)

    if (initsigs != 0) {
        // Initialize signal handlers
        // TODO: Set up SIGINT, SIGTERM handlers
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
export fn Py_FinalizeEx() callconv(.c) c_int {
    if (!python_initialized) return 0;

    // TODO: Clean up interpreter subsystems:
    // - Run pending calls
    // - Call sys.exitfunc if set
    // - Call atexit callbacks
    // - Flush I/O buffers
    // - Clean up thread state
    // - Free all allocated objects
    // - Free type objects
    // - Free modules
    // - Release GIL

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
export fn Py_SetPythonHome(home: [*:0]const u8) callconv(.c) void {
    _ = home;
    // TODO: Store Python home path for module/library discovery
    // This affects sys.prefix, sys.exec_prefix
}

/// Get the Python home directory
/// Returns borrowed reference to home path string
export fn Py_GetPythonHome() callconv(.c) [*:0]const u8 {
    // TODO: Return stored Python home path
    return "/usr/local"; // Default
}

/// Set the program name (argv[0])
/// Should be called before Py_Initialize()
export fn Py_SetProgramName(name: [*:0]const u8) callconv(.c) void {
    _ = name;
    // TODO: Store program name for sys.executable, error messages
}

/// Get the program name
/// Returns borrowed reference to program name string
export fn Py_GetProgramName() callconv(.c) [*:0]const u8 {
    // TODO: Return stored program name
    return "python"; // Default
}

/// Set standard module search path
/// Should be called before Py_Initialize()
export fn Py_SetPath(path: [*:0]const u8) callconv(.c) void {
    _ = path;
    // TODO: Override default sys.path with given path
    // Path should be colon-separated on Unix, semicolon on Windows
}

/// Get the default module search path
/// Returns borrowed reference to path string
export fn Py_GetPath() callconv(.c) [*:0]const u8 {
    // TODO: Return module search path (sys.path as colon/semicolon string)
    return ".:/usr/local/lib/python3.11"; // Default
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
export fn Py_GetProgramFullPath() callconv(.c) [*:0]const u8 {
    // TODO: Return full path to current executable
    return "/usr/local/bin/python"; // Default
}

/// Initialize and acquire the GIL
/// Prepares Python for multi-threaded use
export fn PyEval_InitThreads() callconv(.c) void {
    // TODO: Initialize GIL if not already initialized
}

/// At exit handler registration
/// Registers a function to be called during finalization
export fn Py_AtExit(func: *const fn () callconv(.c) void) callconv(.c) c_int {
    _ = func;
    // TODO: Add function to atexit callback list
    return 0; // Success
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
