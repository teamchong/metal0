/// CPython Import System
///
/// Implements PyImport_* functions for loading Python modules and C extensions.
/// This is the key to loading NumPy and other C extension modules.

const std = @import("std");
const cpython = @import("cpython_object.zig");
const cpython_module = @import("cpython_module.zig");

const allocator = std.heap.c_allocator;

/// ============================================================================
/// MODULE REGISTRY
/// ============================================================================

/// Module registry - stores loaded modules (sys.modules equivalent)
var module_dict: ?*cpython.PyObject = null;
var registry_initialized = false;

/// Built-in module table
const BuiltinModule = struct {
    name: []const u8,
    init_func: *const fn () callconv(.c) ?*cpython.PyObject,
};

var builtin_modules: std.ArrayList(BuiltinModule) = undefined;
var builtin_modules_initialized = false;

/// Initialize module system
fn initModuleSystem() void {
    if (registry_initialized) return;

    // Create sys.modules dict
    module_dict = PyDict_New();

    registry_initialized = true;
}

/// Initialize builtin module table
fn initBuiltinModules() void {
    if (builtin_modules_initialized) return;

    builtin_modules = std.ArrayList(BuiltinModule).init(allocator);
    builtin_modules_initialized = true;
}

/// ============================================================================
/// IMPORT FUNCTIONS
/// ============================================================================

/// Import module by name (simple version)
///
/// CPython: PyObject* PyImport_ImportModule(const char *name)
export fn PyImport_ImportModule(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    initModuleSystem();

    const name_str = std.mem.span(name);

    // Check sys.modules first
    if (module_dict) |mod_dict| {
        const existing = PyDict_GetItemString(mod_dict, name);
        if (existing) |module| {
            Py_INCREF(module);
            return module;
        }
    }

    // Check built-in modules
    if (builtin_modules_initialized) {
        for (builtin_modules.items) |builtin| {
            if (std.mem.eql(u8, builtin.name, name_str)) {
                const module = builtin.init_func();
                if (module) |m| {
                    // Add to sys.modules
                    if (module_dict) |mod_dict| {
                        _ = PyDict_SetItemString(mod_dict, name, m);
                    }
                    return m;
                }
            }
        }
    }

    // Try loading extension module (.so/.dylib/.dll)
    return loadExtensionModule(name_str);
}

/// Import module without blocking (same as regular import for now)
///
/// CPython: PyObject* PyImport_ImportModuleNoBlock(const char *name)
export fn PyImport_ImportModuleNoBlock(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    return PyImport_ImportModule(name);
}

/// Import module with level (for relative imports)
///
/// CPython: PyObject* PyImport_ImportModuleLevel(const char *name, PyObject *globals,
///                                                PyObject *locals, PyObject *fromlist, int level)
export fn PyImport_ImportModuleLevel(
    name: [*:0]const u8,
    globals: ?*cpython.PyObject,
    locals: ?*cpython.PyObject,
    fromlist: ?*cpython.PyObject,
    level: c_int,
) callconv(.c) ?*cpython.PyObject {
    _ = globals;
    _ = locals;
    _ = fromlist;
    _ = level; // TODO: Handle relative imports

    return PyImport_ImportModule(name);
}

/// Import using __import__ protocol
///
/// CPython: PyObject* PyImport_Import(PyObject *name)
export fn PyImport_Import(name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const name_str = PyUnicode_AsUTF8(name);
    if (name_str == null) return null;

    return PyImport_ImportModule(name_str.?);
}

/// Reload module
///
/// CPython: PyObject* PyImport_ReloadModule(PyObject *module)
export fn PyImport_ReloadModule(module: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // For now, just return the module unchanged
    // TODO: Implement proper reloading
    Py_INCREF(module);
    return module;
}

/// Add module to sys.modules
///
/// CPython: PyObject* PyImport_AddModule(const char *name)
export fn PyImport_AddModule(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    initModuleSystem();

    // Check if module already exists
    if (module_dict) |mod_dict| {
        const existing = PyDict_GetItemString(mod_dict, name);
        if (existing) |module| {
            Py_INCREF(module);
            return module;
        }
    }

    // Create new module
    var module_def = cpython_module.PyModuleDef{
        .m_base = undefined,
        .m_name = name,
        .m_doc = null,
        .m_size = -1,
        .m_methods = null,
        .m_slots = null,
        .m_traverse = null,
        .m_clear = null,
        .m_free = null,
    };

    const module = PyModule_Create2(&module_def, 0);
    if (module) |m| {
        // Add to sys.modules
        if (module_dict) |mod_dict| {
            _ = PyDict_SetItemString(mod_dict, name, m);
        }
        return m;
    }

    return null;
}

/// Add module object to sys.modules
///
/// CPython: PyObject* PyImport_AddModuleObject(PyObject *name)
export fn PyImport_AddModuleObject(name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const name_str = PyUnicode_AsUTF8(name);
    if (name_str == null) return null;

    return PyImport_AddModule(name_str.?);
}

/// Execute code as module
///
/// CPython: PyObject* PyImport_ExecCodeModule(const char *name, PyObject *co)
export fn PyImport_ExecCodeModule(name: [*:0]const u8, co: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = co; // TODO: Execute code object

    // For now, just create empty module
    return PyImport_AddModule(name);
}

/// Execute code as module with pathname
///
/// CPython: PyObject* PyImport_ExecCodeModuleEx(const char *name, PyObject *co, const char *pathname)
export fn PyImport_ExecCodeModuleEx(name: [*:0]const u8, co: *cpython.PyObject, pathname: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = pathname; // TODO: Set __file__ attribute

    return PyImport_ExecCodeModule(name, co);
}

/// Get sys.modules dict
///
/// CPython: PyObject* PyImport_GetModuleDict(void)
export fn PyImport_GetModuleDict() callconv(.c) ?*cpython.PyObject {
    initModuleSystem();
    return module_dict;
}

/// Get module from sys.modules
///
/// CPython: PyObject* PyImport_GetModule(PyObject *name)
export fn PyImport_GetModule(name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    initModuleSystem();

    const name_str = PyUnicode_AsUTF8(name);
    if (name_str == null) return null;

    if (module_dict) |mod_dict| {
        const module = PyDict_GetItemString(mod_dict, name_str.?);
        if (module) |m| {
            Py_INCREF(m);
            return m;
        }
    }

    return null;
}

/// Add built-in module to inittab
///
/// CPython: int PyImport_AppendInittab(const char *name, PyObject* (*initfunc)(void))
export fn PyImport_AppendInittab(
    name: [*:0]const u8,
    initfunc: *const fn () callconv(.c) ?*cpython.PyObject,
) callconv(.c) c_int {
    initBuiltinModules();

    const name_copy = allocator.dupeZ(u8, std.mem.span(name)) catch return -1;

    builtin_modules.append(.{
        .name = name_copy,
        .init_func = initfunc,
    }) catch {
        allocator.free(name_copy);
        return -1;
    };

    return 0;
}

/// Inittab entry
pub const PyImport_Inittab = extern struct {
    name: [*:0]const u8,
    initfunc: *const fn () callconv(.c) ?*cpython.PyObject,
};

/// Extend inittab with table of entries
///
/// CPython: int PyImport_ExtendInittab(struct _inittab *newtab)
export fn PyImport_ExtendInittab(newtab: [*]PyImport_Inittab) callconv(.c) c_int {
    initBuiltinModules();

    var i: usize = 0;
    while (newtab[i].initfunc != null) : (i += 1) {
        const result = PyImport_AppendInittab(newtab[i].name, newtab[i].initfunc);
        if (result != 0) return result;
    }

    return 0;
}

/// ============================================================================
/// EXTENSION MODULE LOADING
/// ============================================================================

/// Load C extension module from .so/.dylib/.dll file
fn loadExtensionModule(name: []const u8) ?*cpython.PyObject {
    // Try various extension search paths
    const search_paths = [_][]const u8{
        "./",
        "/usr/local/lib/python3.11/site-packages/",
        "/usr/lib/python3.11/site-packages/",
        "/opt/homebrew/lib/python3.11/site-packages/", // macOS Homebrew
    };

    for (search_paths) |path| {
        if (tryLoadExtension(path, name)) |module| {
            return module;
        }
    }

    return null;
}

/// Try loading extension from specific path
fn tryLoadExtension(base_path: []const u8, name: []const u8) ?*cpython.PyObject {
    // Try different extensions based on platform
    const extensions = if (std.builtin.os.tag == .macos)
        [_][]const u8{ ".so", ".dylib" }
    else if (std.builtin.os.tag == .windows)
        [_][]const u8{".pyd"}
    else
        [_][]const u8{".so"};

    for (extensions) |ext| {
        var path_buf: [1024]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, "{s}{s}{s}", .{ base_path, name, ext }) catch continue;

        if (loadSharedLibrary(path, name)) |module| {
            return module;
        }
    }

    return null;
}

/// Load shared library and call init function
fn loadSharedLibrary(path: [:0]const u8, name: []const u8) ?*cpython.PyObject {
    // Try to open the shared library
    const handle = std.c.dlopen(path, std.c.RTLD.NOW) orelse return null;

    // Build init function name: PyInit_{name}
    var init_name_buf: [256]u8 = undefined;
    const init_name = std.fmt.bufPrintZ(&init_name_buf, "PyInit_{s}", .{name}) catch {
        _ = std.c.dlclose(handle);
        return null;
    };

    // Get init function pointer
    const init_func_ptr = std.c.dlsym(handle, init_name) orelse {
        _ = std.c.dlclose(handle);
        return null;
    };

    // Cast to proper function type
    const init_func: *const fn () callconv(.c) ?*cpython.PyObject = @ptrCast(init_func_ptr);

    // Call init function
    const module = init_func();

    if (module) |m| {
        // Add to sys.modules
        initModuleSystem();
        if (module_dict) |mod_dict| {
            const name_z = allocator.dupeZ(u8, name) catch {
                Py_DECREF(m);
                _ = std.c.dlclose(handle);
                return null;
            };
            defer allocator.free(name_z);

            _ = PyDict_SetItemString(mod_dict, name_z, m);
        }

        return m;
    }

    _ = std.c.dlclose(handle);
    return null;
}

/// ============================================================================
/// HELPER FUNCTIONS (External dependencies)
/// ============================================================================

extern fn PyDict_New() callconv(.c) ?*cpython.PyObject;
extern fn PyDict_GetItemString(*cpython.PyObject, [*:0]const u8) callconv(.c) ?*cpython.PyObject;
extern fn PyDict_SetItemString(*cpython.PyObject, [*:0]const u8, *cpython.PyObject) callconv(.c) c_int;
extern fn PyUnicode_AsUTF8(*cpython.PyObject) callconv(.c) ?[*:0]const u8;
extern fn PyModule_Create2(*cpython_module.PyModuleDef, c_int) callconv(.c) ?*cpython.PyObject;
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;

/// ============================================================================
/// TESTS
/// ============================================================================

test "module registry initialization" {
    initModuleSystem();
    try std.testing.expect(registry_initialized);
    try std.testing.expect(module_dict != null);
}

test "builtin module registration" {
    initBuiltinModules();
    try std.testing.expect(builtin_modules_initialized);
}
