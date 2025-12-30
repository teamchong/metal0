/// CPython Import System
///
/// Implements PyImport_* functions for loading Python modules and C extensions.
/// This is the key to loading NumPy and other C extension modules.
const std = @import("std");
const builtin = @import("builtin");
const cpython = @import("object.zig");
const cpython_module = @import("moduleobject.zig");
const traits = @import("../objects/typetraits.zig");

const allocator = std.heap.c_allocator;

// Use centralized extern declarations
const Py_INCREF = traits.externs.Py_INCREF;
const Py_DECREF = traits.externs.Py_DECREF;
const PyDict_New = traits.externs.PyDict_New;
const PyDict_GetItemString = traits.externs.PyDict_GetItemString;
const PyDict_SetItemString = traits.externs.PyDict_SetItemString;
const PyUnicode_AsUTF8 = traits.externs.PyUnicode_AsUTF8;
const PyModule_Create2 = traits.externs.PyModule_Create2;
const PyModule_GetDict = cpython_module.PyModule_GetDict;

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

var builtin_modules: std.ArrayList(BuiltinModule) = .{};
var builtin_modules_initialized = false;

/// Static module registry entry for compile-time linked C extensions
const StaticModuleEntry = struct {
    name: []const u8,
    init_fn: *const fn () callconv(.c) ?*cpython.PyObject,
};

/// Static module registry - populated at compile time with linked C extensions
/// Currently empty - modules can be added here when statically linking C extensions
const static_module_registry: []const StaticModuleEntry = &[_]StaticModuleEntry{};

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

    // In Zig 0.15, ArrayList is unmanaged - already initialized with .{}
    builtin_modules_initialized = true;
}

/// ============================================================================
/// IMPORT FUNCTIONS
/// ============================================================================
/// Import module by name (simple version)
///
/// CPython: PyObject* PyImport_ImportModule(const char *name)
pub export fn PyImport_ImportModule(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
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
        for (builtin_modules.items) |builtin_mod| {
            if (std.mem.eql(u8, builtin_mod.name, name_str)) {
                const module = builtin_mod.init_func();
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
    if (loadExtensionModule(name_str)) |module| {
        return module;
    }

    // If direct loading failed and name contains ".", try hierarchical import
    // e.g., "numpy.testing" -> import "numpy", then get "testing" attribute
    if (std.mem.indexOfScalar(u8, name_str, '.')) |dot_idx| {
        return importHierarchical(name_str, dot_idx);
    }

    return null;
}

/// Import a hierarchical module like "numpy.testing" by:
/// 1. Importing the root module ("numpy")
/// 2. For proxy modules: create a new proxy for the full submodule path
/// 3. For native modules: traverse using attribute access
fn importHierarchical(full_name: []const u8, first_dot: usize) ?*cpython.PyObject {
    // Get root module name (e.g., "numpy" from "numpy.testing")
    const root_name = full_name[0..first_dot];

    // Create null-terminated root name for recursive import
    var root_buf: [256:0]u8 = undefined;
    if (root_name.len >= root_buf.len) return null;
    @memcpy(root_buf[0..root_name.len], root_name);
    root_buf[root_name.len] = 0;

    // Import root module (recursive call handles caching)
    const root_module = PyImport_ImportModule(@ptrCast(&root_buf)) orelse return null;

    // If root is a proxy module, create a new proxy for the full submodule path
    // This handles pure Python submodules of C extensions (like numpy.testing)
    if (isProxyModule(root_module)) {
        // Verify the full submodule can be imported via subprocess
        var check_buf: [512]u8 = undefined;
        const check_code = std.fmt.bufPrint(&check_buf, "import {s}", .{full_name}) catch return null;

        const check_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "python3", "-c", check_code },
        }) catch return null;
        defer allocator.free(check_result.stdout);
        defer allocator.free(check_result.stderr);

        // Check if import succeeded
        switch (check_result.term) {
            .Exited => |code| if (code != 0) return null,
            else => return null,
        }

        // Create a proxy module for the full submodule path
        const submodule = createProxyModule(full_name) orelse return null;

        // Cache in sys.modules
        if (module_dict) |mod_dict| {
            var name_buf: [512:0]u8 = undefined;
            if (full_name.len < name_buf.len) {
                @memcpy(name_buf[0..full_name.len], full_name);
                name_buf[full_name.len] = 0;
                _ = PyDict_SetItemString(mod_dict, @ptrCast(&name_buf), submodule);
            }
        }

        return submodule;
    }

    // For non-proxy modules, traverse using attribute access
    var current_module = root_module;
    var remaining = full_name[first_dot + 1 ..];

    while (remaining.len > 0) {
        // Find next dot or end of string
        const next_dot = std.mem.indexOfScalar(u8, remaining, '.') orelse remaining.len;
        const part = remaining[0..next_dot];

        // Create null-terminated part name
        var part_buf: [256:0]u8 = undefined;
        if (part.len >= part_buf.len) {
            Py_DECREF(current_module);
            return null;
        }
        @memcpy(part_buf[0..part.len], part);
        part_buf[part.len] = 0;

        // Get submodule as attribute of current module
        const submodule = traits.externs.PyObject_GetAttrString(current_module, @ptrCast(&part_buf)) orelse {
            Py_DECREF(current_module);
            return null;
        };

        // Release previous module (unless it's the root which we still need cached)
        if (current_module != root_module) {
            Py_DECREF(current_module);
        }
        current_module = submodule;

        // Move to next part
        if (next_dot < remaining.len) {
            remaining = remaining[next_dot + 1 ..];
        } else {
            break;
        }
    }

    // Cache the final module in sys.modules
    if (module_dict) |mod_dict| {
        var name_buf: [512:0]u8 = undefined;
        if (full_name.len < name_buf.len) {
            @memcpy(name_buf[0..full_name.len], full_name);
            name_buf[full_name.len] = 0;
            _ = PyDict_SetItemString(mod_dict, @ptrCast(&name_buf), current_module);
        }
    }

    return current_module;
}

/// Import module without blocking (same as regular import for now)
///
/// CPython: PyObject* PyImport_ImportModuleNoBlock(const char *name)
pub export fn PyImport_ImportModuleNoBlock(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    return PyImport_ImportModule(name);
}

/// Import module with level (for relative imports)
///
/// CPython: PyObject* PyImport_ImportModuleLevel(const char *name, PyObject *globals,
///                                                PyObject *locals, PyObject *fromlist, int level)
pub export fn PyImport_ImportModuleLevel(
    name: [*:0]const u8,
    globals: ?*cpython.PyObject,
    locals: ?*cpython.PyObject,
    fromlist: ?*cpython.PyObject,
    level: c_int,
) callconv(.c) ?*cpython.PyObject {
    _ = locals;

    const name_str = std.mem.span(name);

    // level > 0 means relative import
    if (level > 0) {
        // Get package name from __name__ in globals
        if (globals) |g| {
            const pydict = @import("../objects/dictobject.zig");
            if (pydict.PyDict_GetItemString(g, "__package__")) |pkg_obj| {
                // Get package name as string
                if (PyUnicode_AsUTF8(pkg_obj)) |pkg_name| {
                    const pkg_str = std.mem.span(pkg_name);

                    // For level > 1, go up (level-1) package levels
                    var parent_pkg: []const u8 = pkg_str;
                    var lvl = level - 1;
                    while (lvl > 0) : (lvl -= 1) {
                        // Find last dot
                        if (std.mem.lastIndexOfScalar(u8, parent_pkg, '.')) |dot| {
                            parent_pkg = parent_pkg[0..dot];
                        } else {
                            // Can't go up further
                            break;
                        }
                    }

                    // Construct absolute module name
                    if (name_str.len > 0) {
                        // e.g., from . import foo -> parent_pkg.foo
                        var buf: [512]u8 = undefined;
                        const full_name = std.fmt.bufPrintZ(&buf, "{s}.{s}", .{ parent_pkg, name_str }) catch return null;
                        return PyImport_ImportModule(full_name.ptr);
                    } else {
                        // e.g., from . import -> import parent_pkg
                        var buf: [512]u8 = undefined;
                        const full_name = std.fmt.bufPrintZ(&buf, "{s}", .{parent_pkg}) catch return null;
                        return PyImport_ImportModule(full_name.ptr);
                    }
                }
            }
        }
    }

    // Absolute import
    const module = PyImport_ImportModule(name) orelse return null;

    // If fromlist is provided, ensure those attributes are accessible
    // This triggers proper __init__.py loading for namespace packages
    if (fromlist) |fl| {
        const pylist = @import("../objects/listobject.zig");

        const len = pylist.PyList_Size(fl);
        var i: isize = 0;
        while (i < len) : (i += 1) {
            const item = pylist.PyList_GetItem(fl, i) orelse continue;
            const item_str = PyUnicode_AsUTF8(item) orelse continue;

            // Check if attribute exists on the module
            if (traits.externs.PyObject_GetAttrString(module, item_str) == null) {
                // Attribute not found - try to import as submodule: module.attr
                // This handles cases like "from numpy.testing import assert_"
                // where assert_ is in a submodule that needs to be imported first
                var buf: [512]u8 = undefined;
                const submod_name = std.fmt.bufPrintZ(&buf, "{s}.{s}", .{
                    name_str,
                    std.mem.span(item_str),
                }) catch continue;
                _ = PyImport_ImportModule(submod_name.ptr);
                // Ignore result - the submodule import populates the namespace
            }
        }
    }

    return module;
}

/// Import using __import__ protocol
///
/// CPython: PyObject* PyImport_Import(PyObject *name)
pub export fn PyImport_Import(name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const name_str = PyUnicode_AsUTF8(name);
    if (name_str == null) return null;

    return PyImport_ImportModule(name_str.?);
}

/// Reload module
///
/// CPython: PyObject* PyImport_ReloadModule(PyObject *module)
/// In metal0's AOT compilation model, modules are compiled to native code,
/// so "reloading" has limited meaning. We clear and reinitialize the module dict.
pub export fn PyImport_ReloadModule(module: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Get module name
    const mod_obj: *cpython_module.PyModuleObject = @ptrCast(@alignCast(module));

    // Get module name from __name__ in dict
    var mod_name: ?[*:0]const u8 = null;
    if (mod_obj.md_dict) |dict| {
        const name_obj = PyDict_GetItemString(dict, "__name__");
        if (name_obj) |name| {
            mod_name = PyUnicode_AsUTF8(name);
        }
    }

    // If module has __spec__.loader.exec_module, call it
    // For AOT compiled modules, this is a no-op since code is static

    // Clear the module dict (except for essential keys)
    if (mod_obj.md_dict) |dict| {
        // Preserve __name__, __doc__, __package__, __loader__, __spec__
        const dict_obj: *@import("../objects/dictobject.zig").PyDictObject = @ptrCast(@alignCast(dict));

        // For now, just clear non-essential entries
        // A full implementation would iterate and selectively keep entries
        _ = dict_obj;
    }

    // Re-execute module init if it has one
    if (mod_obj.md_def) |def| {
        if (def.m_base.m_init) |init_fn| {
            // Call the module init function
            const result = init_fn();
            if (result == null) {
                // Init failed - module is in undefined state
                return null;
            }
            // Init returned a module - use its dict
            if (result != module) {
                const new_mod: *cpython_module.PyModuleObject = @ptrCast(@alignCast(result.?));
                if (new_mod.md_dict) |new_dict| {
                    // Copy entries to original module dict
                    if (mod_obj.md_dict) |old_dict| {
                        _ = @import("../objects/dictobject.zig").PyDict_Update(old_dict, new_dict);
                    }
                }
                // Don't need the new module
                Py_DECREF(result.?);
            }
        }
    }

    // Return the reloaded module
    Py_INCREF(module);
    return module;
}

/// Add module to sys.modules
///
/// CPython: PyObject* PyImport_AddModule(const char *name)
pub export fn PyImport_AddModule(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    initModuleSystem();

    // Check if module already exists
    if (module_dict) |mod_dict| {
        const existing = PyDict_GetItemString(mod_dict, name);
        if (existing) |module| {
            Py_INCREF(module);
            return module;
        }
    }

    // Allocate PyModuleDef on heap to avoid use-after-free
    // PyModule_Create2 stores a pointer to this, so it must outlive the module
    const module_def = allocator.create(cpython.PyModuleDef) catch return null;
    module_def.* = .{
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

    const module = PyModule_Create2(module_def, 0);
    if (module) |m| {
        // Add to sys.modules
        if (module_dict) |mod_dict| {
            _ = PyDict_SetItemString(mod_dict, name, m);
        }
        return m;
    }

    allocator.destroy(module_def);
    return null;
}

/// Add module object to sys.modules
///
/// CPython: PyObject* PyImport_AddModuleObject(PyObject *name)
pub export fn PyImport_AddModuleObject(name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const name_str = PyUnicode_AsUTF8(name);
    if (name_str == null) return null;

    return PyImport_AddModule(name_str.?);
}

/// Execute code as module
///
/// CPython: PyObject* PyImport_ExecCodeModule(const char *name, PyObject *co)
pub export fn PyImport_ExecCodeModule(name: [*:0]const u8, co: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return PyImport_ExecCodeModuleWithPathnames(name, co, null, null);
}

/// Execute code as module with pathname
///
/// CPython: PyObject* PyImport_ExecCodeModuleEx(const char *name, PyObject *co, const char *pathname)
pub export fn PyImport_ExecCodeModuleEx(name: [*:0]const u8, co: *cpython.PyObject, pathname: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    return PyImport_ExecCodeModuleWithPathnames(name, co, pathname, null);
}

/// Execute code as module with pathnames
///
/// CPython: PyObject* PyImport_ExecCodeModuleWithPathnames(const char *name, PyObject *co,
///                                                          const char *pathname, const char *cpathname)
pub export fn PyImport_ExecCodeModuleWithPathnames(
    name: [*:0]const u8,
    co: *cpython.PyObject,
    pathname: ?[*:0]const u8,
    cpathname: ?[*:0]const u8,
) callconv(.c) ?*cpython.PyObject {
    _ = cpathname;

    const pydict = @import("../objects/dictobject.zig");
    const pyunicode = @import("unicodeobject.zig");

    // Get or create module
    const module = PyImport_AddModule(name) orelse return null;

    // Get module's __dict__
    const mod_dict = PyModule_GetDict(module) orelse return null;

    // Set __file__ if pathname provided
    if (pathname) |path| {
        const path_obj = pyunicode.PyUnicode_FromString(path) orelse return null;
        _ = pydict.PyDict_SetItemString(mod_dict, "__file__", path_obj);
    }

    // Set __name__
    const name_obj = pyunicode.PyUnicode_FromString(name) orelse return null;
    _ = pydict.PyDict_SetItemString(mod_dict, "__name__", name_obj);

    // Set __loader__ to None (basic stub)
    const none = @import("../objects/noneobject.zig").Py_None();
    _ = pydict.PyDict_SetItemString(mod_dict, "__loader__", none);

    // Execute code object in module's namespace
    // The code object should populate the module dict with functions/classes
    const eval = @import("ceval.zig");
    const result = eval.PyEval_EvalCode(co, mod_dict, mod_dict);

    if (result == null) {
        // Execution failed - module is in inconsistent state
        // Return module anyway (CPython behavior)
    } else {
        Py_DECREF(result.?);
    }

    Py_INCREF(module);
    return module;
}

/// Get sys.modules dict
///
/// CPython: PyObject* PyImport_GetModuleDict(void)
pub export fn PyImport_GetModuleDict() callconv(.c) ?*cpython.PyObject {
    initModuleSystem();
    return module_dict;
}

/// Get module from sys.modules
///
/// CPython: PyObject* PyImport_GetModule(PyObject *name)
pub export fn PyImport_GetModule(name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
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
pub export fn PyImport_AppendInittab(
    name: [*:0]const u8,
    initfunc: *const fn () callconv(.c) ?*cpython.PyObject,
) callconv(.c) c_int {
    initBuiltinModules();

    const name_copy = allocator.dupeZ(u8, std.mem.span(name)) catch return -1;

    builtin_modules.append(allocator, .{
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
    name: ?[*:0]const u8,
    initfunc: ?*const fn () callconv(.c) ?*cpython.PyObject,
};

/// Extend inittab with table of entries
///
/// CPython: int PyImport_ExtendInittab(struct _inittab *newtab)
pub export fn PyImport_ExtendInittab(newtab: [*]PyImport_Inittab) callconv(.c) c_int {
    initBuiltinModules();

    var i: usize = 0;
    while (newtab[i].name != null and newtab[i].initfunc != null) : (i += 1) {
        const result = PyImport_AppendInittab(newtab[i].name.?, newtab[i].initfunc.?);
        if (result != 0) return result;
    }

    return 0;
}

/// ============================================================================
/// EXTENSION MODULE LOADING
/// ============================================================================
/// Cached search paths from environment discovery
var cached_search_paths: std.ArrayList([]const u8) = .{};
var search_paths_initialized: bool = false;

/// Get search paths dynamically from environment
fn getSearchPaths() []const []const u8 {
    if (search_paths_initialized) {
        return cached_search_paths.items;
    }

    search_paths_initialized = true;

    // Always include current directory
    cached_search_paths.append(allocator, "./") catch {};

    // 1. Check PYTHONPATH environment variable
    // Note: std.posix.getenv unavailable on Windows (uses WTF-16)
    if (if (comptime builtin.os.tag == .windows) @as(?[]const u8, null) else std.posix.getenv("PYTHONPATH")) |pythonpath| {
        var it = std.mem.splitScalar(u8, pythonpath, ':');
        while (it.next()) |path| {
            if (path.len > 0) {
                const p = allocator.dupeZ(u8, path) catch continue;
                cached_search_paths.append(allocator, p) catch {};
            }
        }
    }

    // 2. Try to discover Python installation paths dynamically
    // Check for common Python versions
    const python_versions = [_][]const u8{ "3.13", "3.12", "3.11", "3.10" };

    // Get HOME directory
    // Note: std.posix.getenv unavailable on Windows (uses WTF-16)
    const home = if (comptime builtin.os.tag == .windows) "C:\\Users\\Public" else (std.posix.getenv("HOME") orelse "/root");

    // mise/asdf python paths
    for (python_versions) |ver| {
        var buf: [512]u8 = undefined;
        // mise path pattern with "latest" symlink
        const mise_path_latest = std.fmt.bufPrint(&buf, "{s}/.local/share/mise/installs/python/latest/lib/python{s}/site-packages/", .{ home, ver }) catch continue;
        if (directoryExists(mise_path_latest)) {
            cached_search_paths.append(allocator, allocator.dupe(u8, mise_path_latest) catch continue) catch {};
        }
        // mise path with specific version (e.g., 3.12.10)
        const minor_versions = [_][]const u8{ ".0", ".1", ".2", ".3", ".4", ".5", ".6", ".7", ".8", ".9", ".10", ".11", ".12" };
        for (minor_versions) |minor| {
            var buf2: [512]u8 = undefined;
            const mise_path = std.fmt.bufPrint(&buf2, "{s}/.local/share/mise/installs/python/{s}{s}/lib/python{s}/site-packages/", .{ home, ver, minor, ver }) catch continue;
            if (directoryExists(mise_path)) {
                cached_search_paths.append(allocator, allocator.dupe(u8, mise_path) catch continue) catch {};
            }
        }
    }

    // pyenv paths
    for (python_versions) |ver| {
        var buf: [512]u8 = undefined;
        const pyenv_path = std.fmt.bufPrint(&buf, "{s}/.pyenv/versions/{s}.*/lib/python{s}/site-packages/", .{ home, ver, ver }) catch continue;
        if (directoryExists(pyenv_path)) {
            cached_search_paths.append(allocator, allocator.dupe(u8, pyenv_path) catch continue) catch {};
        }
    }

    // Homebrew paths (macOS)
    if (comptime builtin.os.tag == .macos) {
        for (python_versions) |ver| {
            var buf: [256]u8 = undefined;
            const brew_path = std.fmt.bufPrint(&buf, "/opt/homebrew/lib/python{s}/site-packages/", .{ver}) catch continue;
            if (directoryExists(brew_path)) {
                cached_search_paths.append(allocator, allocator.dupe(u8, brew_path) catch continue) catch {};
            }
        }
    }

    // System paths (Linux)
    if (comptime builtin.os.tag == .linux) {
        for (python_versions) |ver| {
            var buf: [256]u8 = undefined;
            // Standard system path
            const sys_path = std.fmt.bufPrint(&buf, "/usr/lib/python{s}/site-packages/", .{ver}) catch continue;
            if (directoryExists(sys_path)) {
                cached_search_paths.append(allocator, allocator.dupe(u8, sys_path) catch continue) catch {};
            }
            // dist-packages (Debian/Ubuntu)
            const dist_path = std.fmt.bufPrint(&buf, "/usr/lib/python{s}/dist-packages/", .{ver}) catch continue;
            if (directoryExists(dist_path)) {
                cached_search_paths.append(allocator, allocator.dupe(u8, dist_path) catch continue) catch {};
            }
        }
    }

    // Virtual environment paths
    // Note: std.posix.getenv unavailable on Windows (uses WTF-16)
    if (if (comptime builtin.os.tag == .windows) @as(?[]const u8, null) else std.posix.getenv("VIRTUAL_ENV")) |venv| {
        for (python_versions) |ver| {
            var buf: [512]u8 = undefined;
            const venv_path = std.fmt.bufPrint(&buf, "{s}/lib/python{s}/site-packages/", .{ venv, ver }) catch continue;
            if (directoryExists(venv_path)) {
                cached_search_paths.append(allocator, allocator.dupe(u8, venv_path) catch continue) catch {};
            }
        }
    }

    // Check for .venv in current directory
    for (python_versions) |ver| {
        var buf: [256]u8 = undefined;
        const local_venv = std.fmt.bufPrint(&buf, ".venv/lib/python{s}/site-packages/", .{ver}) catch continue;
        if (directoryExists(local_venv)) {
            cached_search_paths.append(allocator, allocator.dupe(u8, local_venv) catch continue) catch {};
        }
    }

    return cached_search_paths.items;
}

/// Check if a directory exists
fn directoryExists(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

/// Load C extension module from .so/.dylib/.dll file
/// Generic implementation - discovers package structure automatically
fn loadExtensionModule(name: []const u8) ?*cpython.PyObject {
    const search_paths = getSearchPaths();

    // Split name into package parts (e.g., "numpy.core" -> ["numpy", "core"])
    var parts: std.ArrayList([]const u8) = .{};
    defer parts.deinit(allocator);

    var it = std.mem.splitScalar(u8, name, '.');
    while (it.next()) |part| {
        parts.append(allocator, part) catch continue;
    }

    if (parts.items.len == 0) return null;

    const top_level = parts.items[0];

    // For each search path, try to find the extension
    for (search_paths) |base_path| {
        // Try different strategies for finding the extension module:

        // Strategy 1: Direct extension file (e.g., _json.so for "_json")
        if (tryLoadExtension(base_path, name)) |module| {
            return module;
        }

        // Strategy 2: Package with __init__ extension (e.g., numpy/__init__.so)
        if (tryLoadPackageInit(base_path, top_level)) |module| {
            return module;
        }

        // Strategy 3: Package core extension discovery
        // For packages like numpy, pandas - find their main C extension
        if (discoverPackageCoreExtension(base_path, top_level)) |module| {
            return module;
        }

        // Strategy 4: Submodule extension (e.g., numpy/core/_multiarray.so)
        if (parts.items.len > 1) {
            if (tryLoadSubmoduleExtension(base_path, parts.items)) |module| {
                return module;
            }
        }
    }

    // Strategy 5: Use subprocess Python for top-level packages only (numpy, pandas, etc.)
    // These require Python's full import machinery and have symbol conflicts with our stubs
    // For submodules like "numpy.testing", we don't try subprocess here - let the caller
    // use hierarchical import (import root, then get attribute)
    if (parts.items.len == 1) {
        if (importViaSubprocess(top_level)) |module| {
            return module;
        }
    }

    return null;
}

/// Try loading __init__ extension for a package
fn tryLoadPackageInit(base_path: []const u8, package_name: []const u8) ?*cpython.PyObject {
    var path_buf: [1024]u8 = undefined;

    for (getPlatformExtensions()) |ext| {
        const path = std.fmt.bufPrintZ(&path_buf, "{s}{s}/__init__{s}", .{ base_path, package_name, ext }) catch continue;
        if (loadSharedLibraryWithName(path, package_name)) |module| {
            return module;
        }
    }

    return null;
}

/// Discover and load core extension for a package (generic, not hardcoded)
fn discoverPackageCoreExtension(base_path: []const u8, package_name: []const u8) ?*cpython.PyObject {
    var pkg_path_buf: [512]u8 = undefined;
    const pkg_path = std.fmt.bufPrint(&pkg_path_buf, "{s}{s}/", .{ base_path, package_name }) catch return null;

    // Check if package directory exists
    var dir = std.fs.cwd().openDir(pkg_path, .{ .iterate = true }) catch return null;
    defer dir.close();

    // Search for C extension modules in common locations
    const core_subdirs = [_][]const u8{
        "_core/", // numpy 2.0+
        "core/", // numpy 1.x, pandas
        "_libs/", // pandas
        "_internal/", // sklearn
        "", // top-level extensions
    };

    for (core_subdirs) |subdir| {
        var subdir_path_buf: [1024]u8 = undefined;
        const subdir_path = std.fmt.bufPrint(&subdir_path_buf, "{s}{s}", .{ pkg_path, subdir }) catch continue;

        // Try to find any .so/.dylib file in this subdirectory
        var sub_dir = std.fs.cwd().openDir(subdir_path, .{ .iterate = true }) catch continue;
        defer sub_dir.close();

        var iter = sub_dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .file) continue;

            const entry_name = entry.name;

            // Check if it's a shared library
            for (getPlatformExtensions()) |ext| {
                if (std.mem.endsWith(u8, entry_name, ext)) {
                    // Extract module name from filename
                    const mod_name = getModuleNameFromFile(entry_name) orelse continue;

                    var full_path_buf: [1024]u8 = undefined;
                    const full_path = std.fmt.bufPrintZ(&full_path_buf, "{s}{s}", .{ subdir_path, entry_name }) catch continue;

                    if (loadSharedLibraryWithName(full_path, mod_name)) |module| {
                        return module;
                    }
                }
            }
        }
    }

    return null;
}

/// Extract module name from .so filename (e.g., "_multiarray_umath.cpython-312-darwin.so" -> "_multiarray_umath")
fn getModuleNameFromFile(filename: []const u8) ?[]const u8 {
    // Find first '.' - module name is before it
    for (filename, 0..) |c, i| {
        if (c == '.') {
            if (i > 0) {
                return filename[0..i];
            }
            return null;
        }
    }
    return null;
}

/// Try loading submodule extension
fn tryLoadSubmoduleExtension(base_path: []const u8, parts: []const []const u8) ?*cpython.PyObject {
    var path_buf: [1024]u8 = undefined;
    var pos: usize = 0;

    // Build path from parts
    for (base_path) |c| {
        if (pos >= path_buf.len - 1) return null;
        path_buf[pos] = c;
        pos += 1;
    }

    for (parts) |part| {
        for (part) |c| {
            if (pos >= path_buf.len - 1) return null;
            path_buf[pos] = c;
            pos += 1;
        }
        if (pos >= path_buf.len - 1) return null;
        path_buf[pos] = '/';
        pos += 1;
    }

    // Remove trailing slash
    if (pos > 0) pos -= 1;

    const last_part = parts[parts.len - 1];

    for (getPlatformExtensions()) |ext| {
        var full_buf: [1024]u8 = undefined;
        @memcpy(full_buf[0..pos], path_buf[0..pos]);
        const remaining = std.fmt.bufPrintZ(full_buf[pos..], "{s}", .{ext}) catch continue;
        // Calculate total length including extension
        const total_len = pos + remaining.len;

        const path_z: [:0]const u8 = full_buf[0..total_len :0];
        if (loadSharedLibraryWithName(path_z, last_part)) |module| {
            return module;
        }
    }

    return null;
}

// ============================================================================
// DYNAMIC MODULE LOADING (dlopen)
// ============================================================================
// C extension modules are loaded dynamically at runtime using dlopen.
// This works for ANY Python extension library (numpy, pandas, scipy, etc.)
// without requiring hardcoded support for each.

/// PyInit function type for C extension modules
pub const PyInitFn = *const fn () callconv(.c) ?*cpython.PyObject;

/// Cache of loaded dynamic libraries to avoid reloading
var loaded_libs: std.StringHashMap(std.DynLib) = undefined;
var loaded_libs_initialized = false;

fn initLoadedLibs() void {
    if (loaded_libs_initialized) return;
    loaded_libs = std.StringHashMap(std.DynLib).init(allocator);
    loaded_libs_initialized = true;
}

/// Get site-packages paths by querying Python's sys.path
/// This is the proper way - ask Python itself where its packages are
fn getSitePackagesPaths(alloc: std.mem.Allocator) ![][]const u8 {
    // Run: python3 -c "import sys; print('\\n'.join(sys.path))"
    const result = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &[_][]const u8{
            "python3",
            "-c",
            "import sys; print('\\n'.join(p for p in sys.path if p))",
        },
    });
    defer alloc.free(result.stdout);
    defer alloc.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) return error.PythonNotFound,
        else => return error.PythonNotFound,
    }

    // Parse the output - each line is a path
    var paths: std.ArrayList([]const u8) = .{};
    var iter = std.mem.splitScalar(u8, result.stdout, '\n');
    while (iter.next()) |line| {
        if (line.len > 0) {
            try paths.append(alloc, try alloc.dupe(u8, line));
        }
    }

    return paths.toOwnedSlice(alloc);
}

/// Try loading extension from package path
fn tryLoadPackageExtension(base_path: []const u8, subpath: []const u8, init_name: []const u8) ?*cpython.PyObject {
    var path_buf: [1024]u8 = undefined;

    for (getPlatformExtensions()) |ext| {
        const path = std.fmt.bufPrintZ(&path_buf, "{s}{s}{s}", .{ base_path, subpath, ext }) catch continue;
        if (loadSharedLibraryWithName(path, init_name)) |module| {
            return module;
        }
    }

    return null;
}

/// Try loading extension from specific path
fn tryLoadExtension(base_path: []const u8, name: []const u8) ?*cpython.PyObject {
    var path_buf: [1024]u8 = undefined;

    // Convert module name dots to slashes for submodules
    var name_path: [256]u8 = undefined;
    var name_idx: usize = 0;
    for (name) |c| {
        if (c == '.') {
            name_path[name_idx] = '/';
        } else {
            name_path[name_idx] = c;
        }
        name_idx += 1;
        if (name_idx >= name_path.len - 1) break;
    }

    // Get base name (after last slash/dot)
    var base_name = name;
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
        base_name = name[dot + 1 ..];
    }

    for (getPlatformExtensions()) |ext| {
        const path = std.fmt.bufPrintZ(&path_buf, "{s}{s}{s}", .{ base_path, name_path[0..name_idx], ext }) catch continue;
        if (loadSharedLibraryWithName(path, base_name)) |module| {
            return module;
        }
    }

    return null;
}

/// Load a statically linked C extension module by name
fn loadStaticModule(name: []const u8) ?*cpython.PyObject {
    // Search the static registry
    for (static_module_registry) |entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            const module = entry.init_fn() orelse return null;

            // Add to sys.modules
            initModuleSystem();
            if (module_dict) |mod_dict| {
                const name_z = allocator.dupeZ(u8, name) catch return module;
                defer allocator.free(name_z);
                _ = PyDict_SetItemString(mod_dict, name_z, module);
            }

            return module;
        }
    }

    // Handle submodules (e.g., "numpy.linalg" -> try "numpy" first)
    if (std.mem.indexOf(u8, name, ".")) |dot_idx| {
        const parent_name = name[0..dot_idx];
        for (static_module_registry) |entry| {
            if (std.mem.eql(u8, entry.name, parent_name)) {
                const parent_module = entry.init_fn() orelse return null;
                const submodule_name = name[dot_idx + 1 ..];
                const submodule_name_z = allocator.dupeZ(u8, submodule_name) catch return null;
                defer allocator.free(submodule_name_z);
                return traits.externs.PyObject_GetAttrString(parent_module, submodule_name_z);
            }
        }
    }

    return null;
}

/// Load module from shared library using dlopen
fn loadSharedLibraryWithName(path: [:0]const u8, init_name: []const u8) ?*cpython.PyObject {
    initLoadedLibs();

    // Check cache first
    const cached_key = allocator.dupe(u8, path) catch return loadStaticModule(init_name);
    defer allocator.free(cached_key);

    if (loaded_libs.get(cached_key)) |_| {
        // Already loaded - check sys.modules
        if (module_dict) |mod_dict| {
            const init_z = allocator.dupeZ(u8, init_name) catch return null;
            defer allocator.free(init_z);
            if (PyDict_GetItemString(mod_dict, init_z)) |existing| {
                Py_INCREF(existing);
                return existing;
            }
        }
    }

    // Open the shared library using dlopen
    var lib = std.DynLib.open(path) catch {
        // If dlopen fails, fall back to static module lookup
        return loadStaticModule(init_name);
    };

    // Build the PyInit_<modname> symbol name
    var init_fn_name_buf: [256]u8 = undefined;
    const init_fn_name = std.fmt.bufPrintZ(&init_fn_name_buf, "PyInit_{s}", .{init_name}) catch return null;

    // Look up the PyInit function
    const init_fn_ptr = lib.lookup(*const fn () callconv(.c) ?*cpython.PyObject, init_fn_name) orelse {
        // Symbol not found - library might be a dependency, not a Python module
        lib.close();
        return loadStaticModule(init_name);
    };

    // Call the init function
    const module = init_fn_ptr() orelse {
        lib.close();
        return null;
    };

    // Cache the library handle (keep it open so symbols remain valid)
    const key_copy = allocator.dupe(u8, path) catch {
        return module;
    };
    loaded_libs.put(key_copy, lib) catch {
        allocator.free(key_copy);
        // Still return module even if caching fails
    };

    // Add module to sys.modules
    initModuleSystem();
    if (module_dict) |mod_dict| {
        const init_z = allocator.dupeZ(u8, init_name) catch return module;
        defer allocator.free(init_z);
        _ = PyDict_SetItemString(mod_dict, init_z, module);
    }

    return module;
}

// ============================================================================
// LIBPYTHON FALLBACK
// ============================================================================

/// Global state for libpython loading
var libpython_handle: ?std.DynLib = null;
var libpython_initialized: bool = false;

/// Function pointers from libpython
var Py_Initialize_fn: ?*const fn () callconv(.c) void = null;
var PyImport_ImportModule_fn: ?*const fn ([*:0]const u8) callconv(.c) ?*cpython.PyObject = null;
var Py_IsInitialized_fn: ?*const fn () callconv(.c) c_int = null;

/// Find and load libpython.dylib/.so
fn loadLibPython() bool {
    if (libpython_initialized) {
        return libpython_handle != null;
    }
    libpython_initialized = true;

    // Python versions to try
    const python_versions = [_][]const u8{ "3.13", "3.12", "3.11", "3.10" };

    // Get HOME directory
    const home = if (comptime builtin.os.tag == .windows) "C:\\Users\\Public" else (std.posix.getenv("HOME") orelse "/root");

    // Try common libpython locations
    var path_buf: [512]u8 = undefined;

    // mise/asdf paths
    const minor_versions = [_][]const u8{ ".0", ".1", ".2", ".3", ".4", ".5", ".6", ".7", ".8", ".9", ".10", ".11", ".12" };
    for (python_versions) |ver| {
        for (minor_versions) |minor| {
            const lib_path = std.fmt.bufPrintZ(&path_buf, "{s}/.local/share/mise/installs/python/{s}{s}/lib/libpython{s}.dylib", .{ home, ver, minor, ver }) catch continue;
            if (std.DynLib.open(lib_path)) |lib| {
                libpython_handle = lib;
                return initLibPythonFunctions();
            } else |_| {}
        }
    }

    // Homebrew paths (macOS)
    if (comptime builtin.os.tag == .macos) {
        for (python_versions) |ver| {
            const brew_path = std.fmt.bufPrintZ(&path_buf, "/opt/homebrew/Cellar/python@{s}/*/Frameworks/Python.framework/Versions/{s}/lib/libpython{s}.dylib", .{ ver, ver, ver }) catch continue;
            if (std.DynLib.open(brew_path)) |lib| {
                libpython_handle = lib;
                return initLibPythonFunctions();
            } else |_| {}
        }
    }

    // System paths (Linux)
    if (comptime builtin.os.tag == .linux) {
        for (python_versions) |ver| {
            const sys_path = std.fmt.bufPrintZ(&path_buf, "/usr/lib/x86_64-linux-gnu/libpython{s}.so.1", .{ver}) catch continue;
            if (std.DynLib.open(sys_path)) |lib| {
                libpython_handle = lib;
                return initLibPythonFunctions();
            } else |_| {}

            const sys_path2 = std.fmt.bufPrintZ(&path_buf, "/usr/lib/libpython{s}.so.1", .{ver}) catch continue;
            if (std.DynLib.open(sys_path2)) |lib| {
                libpython_handle = lib;
                return initLibPythonFunctions();
            } else |_| {}
        }
    }

    return false;
}

/// Stored Python home path (needs to persist for lifetime of Python)
var python_home_buf: [512:0]u8 = undefined;
var python_home_set: bool = false;

/// Initialize function pointers from libpython
fn initLibPythonFunctions() bool {
    var lib = libpython_handle orelse return false;

    Py_Initialize_fn = lib.lookup(*const fn () callconv(.c) void, "Py_Initialize");
    Py_IsInitialized_fn = lib.lookup(*const fn () callconv(.c) c_int, "Py_IsInitialized");
    PyImport_ImportModule_fn = lib.lookup(*const fn ([*:0]const u8) callconv(.c) ?*cpython.PyObject, "PyImport_ImportModule");

    if (Py_Initialize_fn == null or PyImport_ImportModule_fn == null) {
        return false;
    }

    // Set PYTHONHOME environment variable before initializing
    if (!python_home_set) {
        // Find the Python prefix from the library path
        const home = if (comptime builtin.os.tag == .windows) "C:\\Users\\Public" else (std.posix.getenv("HOME") orelse "/root");
        const python_versions = [_][]const u8{ "3.13", "3.12", "3.11", "3.10" };
        const minor_versions = [_][]const u8{ ".0", ".1", ".2", ".3", ".4", ".5", ".6", ".7", ".8", ".9", ".10", ".11", ".12" };

        for (python_versions) |ver| {
            for (minor_versions) |minor| {
                const prefix_len = std.fmt.bufPrint(&python_home_buf, "{s}/.local/share/mise/installs/python/{s}{s}", .{ home, ver, minor }) catch continue;

                // Check if this is the right prefix by looking for lib/python3.x
                var check_buf: [600]u8 = undefined;
                const check_path = std.fmt.bufPrint(&check_buf, "{s}/lib/python{s}", .{ prefix_len, ver }) catch continue;
                if (std.fs.cwd().access(check_path, .{})) |_| {
                    // Set PYTHONHOME using C library setenv
                    python_home_buf[prefix_len.len] = 0;
                    const setenv_fn = @extern(*const fn ([*:0]const u8, [*:0]const u8, c_int) callconv(.c) c_int, .{ .name = "setenv" });
                    _ = setenv_fn("PYTHONHOME", &python_home_buf, 1);
                    python_home_set = true;
                    break;
                } else |_| {}
            }
            if (python_home_set) break;
        }
    }

    // Initialize Python if not already done
    if (Py_IsInitialized_fn) |is_init| {
        if (is_init() == 0) {
            Py_Initialize_fn.?();
        }
    } else {
        Py_Initialize_fn.?();
    }

    return true;
}

/// Import a module using a subprocess Python call
/// This avoids symbol conflicts by running Python in a separate process.
/// We create a wrapper module object that delegates attribute access to subprocess.
fn importViaSubprocess(name: []const u8) ?*cpython.PyObject {
    // First verify the module can be imported by Python
    var check_buf: [256]u8 = undefined;
    const check_code = std.fmt.bufPrint(&check_buf, "import {s}", .{name}) catch return null;

    const check_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "python3", "-c", check_code },
    }) catch return null;
    defer allocator.free(check_result.stdout);
    defer allocator.free(check_result.stderr);

    // Check if import succeeded
    switch (check_result.term) {
        .Exited => |code| if (code != 0) return null,
        else => return null,
    }

    // Create a proxy module object that will delegate to subprocess
    const module = createProxyModule(name) orelse return null;

    // Add to sys.modules
    initModuleSystem();
    if (module_dict) |mod_dict| {
        const name_z = allocator.dupeZ(u8, name) catch return module;
        defer allocator.free(name_z);
        _ = PyDict_SetItemString(mod_dict, name_z, module);
    }

    return module;
}

/// Create a proxy module for subprocess-based imports
fn createProxyModule(name: []const u8) ?*cpython.PyObject {
    const name_z = allocator.dupeZ(u8, name) catch return null;

    // Allocate PyModuleDef on heap to avoid use-after-free
    // PyModule_Create2 stores a pointer to this, so it must outlive the module
    const module_def = allocator.create(cpython.PyModuleDef) catch return null;
    module_def.* = .{
        .m_base = undefined,
        .m_name = name_z,
        .m_doc = null,
        .m_size = -1,
        .m_methods = null,
        .m_slots = null,
        .m_traverse = null,
        .m_clear = null,
        .m_free = null,
    };

    const module = PyModule_Create2(module_def, 0) orelse {
        allocator.destroy(module_def);
        return null;
    };

    // Store the module name in the dict for later retrieval
    const mod_obj: *cpython_module.PyModuleObject = @ptrCast(@alignCast(module));
    if (mod_obj.md_dict) |dict| {
        const proxy_name = @import("unicodeobject.zig").PyUnicode_FromString("__subprocess_proxy__") orelse return module;
        const name_obj = @import("unicodeobject.zig").PyUnicode_FromString(name_z) orelse return module;
        _ = PyDict_SetItemString(dict, "__subprocess_proxy__", proxy_name);
        _ = PyDict_SetItemString(dict, "__proxy_module_name__", name_obj);
    }

    return module;
}

/// Get an attribute from a subprocess-based proxy module
/// This is called by c_interop.getAttr when it detects a proxy module
pub fn getProxyAttr(module: *cpython.PyObject, attr_name: [*:0]const u8) ?*cpython.PyObject {
    // First verify this is actually a module object
    if (cpython_module.PyModule_Check(module) == 0) {
        return null; // Not a module, can't get proxy attributes
    }

    const mod_obj: *cpython_module.PyModuleObject = @ptrCast(@alignCast(module));
    const dict = mod_obj.md_dict orelse return null;

    // Check if this is a proxy module
    const proxy_marker = PyDict_GetItemString(dict, "__subprocess_proxy__");
    if (proxy_marker == null) return null;

    // Get the module name
    const name_obj = PyDict_GetItemString(dict, "__proxy_module_name__") orelse return null;
    const name_str = PyUnicode_AsUTF8(name_obj) orelse return null;
    const module_name = std.mem.span(name_str);

    // Run subprocess to get the attribute
    const attr_str = std.mem.span(attr_name);
    return getAttrViaSubprocess(module_name, attr_str);
}

/// Get an attribute value via subprocess
/// Uses getattr() first, then falls back to importlib.import_module() for internal submodules
/// like numpy._core._multiarray_tests that require direct import rather than attribute access
fn getAttrViaSubprocess(module_name: []const u8, attr_name: []const u8) ?*cpython.PyObject {
    var code_buf: [768]u8 = undefined;
    const py_code = std.fmt.bufPrint(&code_buf,
        \\import {s}
        \\import importlib
        \\val = getattr({s}, '{s}', None)
        \\if val is None:
        \\    try:
        \\        val = importlib.import_module('{s}.{s}')
        \\    except ImportError:
        \\        pass
        \\print(repr(val))
    , .{ module_name, module_name, attr_name, module_name, attr_name }) catch return null;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "python3", "-c", py_code },
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |exit_code| if (exit_code != 0) return null,
        else => return null,
    }

    // Parse the output and create appropriate PyObject
    const output = std.mem.trimRight(u8, result.stdout, "\n\r");
    if (output.len == 0) return null;

    return parseSubprocessOutput(output);
}

/// Check if a proxy module has an attribute via subprocess
/// Returns true if the attribute exists, false otherwise
pub fn hasattrProxy(module: *cpython.PyObject, attr_name: [*:0]const u8) bool {
    const mod_obj: *cpython_module.PyModuleObject = @ptrCast(@alignCast(module));
    const dict = mod_obj.md_dict orelse return false;

    // Check if this is a proxy module
    const proxy_marker = PyDict_GetItemString(dict, "__subprocess_proxy__");
    if (proxy_marker == null) return false;

    // Get the module name
    const name_obj = PyDict_GetItemString(dict, "__proxy_module_name__") orelse return false;
    const name_str = PyUnicode_AsUTF8(name_obj) orelse return false;
    const module_name = std.mem.span(name_str);

    // Run subprocess to check hasattr
    const attr_str = std.mem.span(attr_name);
    return hasattrViaSubprocess(module_name, attr_str);
}

/// Check if a module has an attribute via subprocess
pub fn hasattrViaSubprocess(module_name: []const u8, attr_name: []const u8) bool {
    var code_buf: [512]u8 = undefined;
    const py_code = std.fmt.bufPrint(&code_buf,
        \\import {s}
        \\print(hasattr({s}, '{s}'))
    , .{ module_name, module_name, attr_name }) catch return false;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "python3", "-c", py_code },
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |exit_code| if (exit_code != 0) return false,
        else => return false,
    }

    const output = std.mem.trimRight(u8, result.stdout, "\n\r");
    return std.mem.eql(u8, output, "True");
}

/// Decode Python escape sequences in a string
/// Handles: \n, \r, \t, \\, \', \"
fn decodePythonEscapes(alloc: std.mem.Allocator, input: []const u8) ?[]u8 {
    var result = alloc.alloc(u8, input.len) catch return null;
    var out_pos: usize = 0;
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        if (input[i] == '\\' and i + 1 < input.len) {
            const decoded: u8 = switch (input[i + 1]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                '\'' => '\'',
                '"' => '"',
                else => {
                    // Unknown escape - keep both characters
                    result[out_pos] = input[i];
                    out_pos += 1;
                    continue;
                },
            };
            result[out_pos] = decoded;
            out_pos += 1;
            i += 1; // Skip the escape character
        } else {
            result[out_pos] = input[i];
            out_pos += 1;
        }
    }
    return result[0..out_pos];
}

/// Parse subprocess output and create a PyObject
pub fn parseSubprocessOutput(output: []const u8) ?*cpython.PyObject {
    // Module: <module 'xxx' from '...'>
    // When we get a module attribute, create a proxy module for it
    if (std.mem.startsWith(u8, output, "<module '")) {
        // Extract module name from <module 'xxx' from '...'>
        const name_start = "<module '".len;
        if (std.mem.indexOfScalarPos(u8, output, name_start, '\'')) |name_end| {
            const module_name = output[name_start..name_end];
            return createProxyModule(module_name);
        }
    }

    // String: starts and ends with ' or "
    if ((output.len >= 2 and output[0] == '\'' and output[output.len - 1] == '\'') or
        (output.len >= 2 and output[0] == '"' and output[output.len - 1] == '"'))
    {
        const str_content = output[1 .. output.len - 1];
        // Decode Python escape sequences before creating the string
        const decoded = decodePythonEscapes(allocator, str_content) orelse return null;
        defer allocator.free(decoded);
        const str_z = allocator.dupeZ(u8, decoded) catch return null;
        return @import("unicodeobject.zig").PyUnicode_FromString(str_z);
    }

    // Integer
    if (std.fmt.parseInt(i64, output, 10)) |int_val| {
        return @import("../objects/longobject.zig").PyLong_FromLongLong(int_val);
    } else |_| {}

    // Float
    if (std.fmt.parseFloat(f64, output)) |float_val| {
        return @import("../objects/floatobject.zig").PyFloat_FromDouble(float_val);
    } else |_| {}

    // None
    if (std.mem.eql(u8, output, "None")) {
        return @import("../objects/noneobject.zig").Py_None();
    }

    // True/False
    if (std.mem.eql(u8, output, "True")) {
        return @import("../objects/boolobject.zig").Py_True();
    }
    if (std.mem.eql(u8, output, "False")) {
        return @import("../objects/boolobject.zig").Py_False();
    }

    // Default: return as string
    const str_z = allocator.dupeZ(u8, output) catch return null;
    return @import("unicodeobject.zig").PyUnicode_FromString(str_z);
}

/// Check if a module is a subprocess proxy
/// Returns false for non-module objects (safe to call on any PyObject)
pub fn isProxyModule(obj: *cpython.PyObject) bool {
    // SAFETY: Must check if it's actually a module before casting
    if (cpython_module.PyModule_Check(obj) == 0) {
        return false;
    }
    const mod_obj: *cpython_module.PyModuleObject = @ptrCast(@alignCast(obj));
    const dict = mod_obj.md_dict orelse return false;
    return PyDict_GetItemString(dict, "__subprocess_proxy__") != null;
}

/// Check if a PyObject is a subprocess proxy representation (non-callable string)
/// This detects objects that were created from subprocess output like "<function ...>"
/// These cannot be called directly and need special handling
pub fn isSubprocessProxy(obj: *cpython.PyObject) bool {
    // Use the correct unicode module that handles CPython's internal layout
    const pyunicode = @import("../objects/unicodeobject.zig");
    if (!pyunicode.isUnicode(obj)) {
        return false; // Not a string, so not a proxy representation
    }

    // Get the string value using the correct function that handles CPython layout
    const str_ptr = pyunicode.asUTF8(obj) orelse return false;
    const str = std.mem.span(str_ptr);

    // Check if it looks like a Python repr (starts with '<' and ends with '>')
    // This catches: <function ...>, <class ...>, <method ...>, <builtin_function_or_method ...>
    if (str.len >= 2 and str[0] == '<' and str[str.len - 1] == '>') {
        return true;
    }

    return false;
}

/// Get platform-specific extension suffixes (kept for compatibility)
fn getPlatformExtensions() []const []const u8 {
    return comptime if (builtin.os.tag == .macos)
        &[_][]const u8{ ".cpython-313-darwin.so", ".cpython-312-darwin.so", ".cpython-311-darwin.so", ".so", ".dylib" }
    else if (builtin.os.tag == .windows)
        &[_][]const u8{".pyd"}
    else
        &[_][]const u8{ ".cpython-313-x86_64-linux-gnu.so", ".cpython-312-x86_64-linux-gnu.so", ".cpython-311-x86_64-linux-gnu.so", ".so" };
}

// ============================================================================
// TESTS
// ============================================================================

test "module registry initialization" {
    initModuleSystem();
    try std.testing.expect(registry_initialized);
    try std.testing.expect(module_dict != null);
}

test "builtin module registration" {
    initBuiltinModules();
    try std.testing.expect(builtin_modules_initialized);
}
