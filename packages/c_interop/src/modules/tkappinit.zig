/// tkappinit - Tk Application Initialization
const cpython = @import("../include/object.zig");

/// Initialize Tcl interpreter for Tk
pub export fn Tcl_AppInit(interp: ?*anyopaque) c_int {
    _ = interp;
    return 0; // TCL_OK
}
