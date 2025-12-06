/// getbuildinfo - Build Information
const cpython = @import("../include/object.zig");

/// Get build info string
pub export fn Py_GetBuildInfo() [*:0]const u8 {
    return "metal0 dev";
}

/// Get compiler string
pub export fn Py_GetCompiler() [*:0]const u8 {
    return "Zig";
}

/// Get build number
pub export fn Py_GetBuildNumber() c_int {
    return 0;
}
