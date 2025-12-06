/// getpath - Path Configuration
const cpython = @import("../include/object.zig");

/// Get Python home directory
pub export fn Py_GetPythonHome() ?[*:0]const u8 {
    return null;
}

/// Get program name
pub export fn Py_GetProgramName() [*:0]const u8 {
    return "python";
}

/// Get program full path
pub export fn Py_GetProgramFullPath() [*:0]const u8 {
    return "/usr/bin/python";
}

/// Get prefix
pub export fn Py_GetPrefix() [*:0]const u8 {
    return "/usr";
}

/// Get exec prefix
pub export fn Py_GetExecPrefix() [*:0]const u8 {
    return "/usr";
}

/// Get path
pub export fn Py_GetPath() [*:0]const u8 {
    return "";
}
