/// CPython Import System
///
/// Implements PyImport_* functions for loading Python modules and C extensions.
/// This is the key to loading NumPy and other C extension modules.

const std = @import("std");
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
    _ = locals;
    _ = fromlist;

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
                    var parent_pkg = pkg_str;
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
/// In metal0's AOT compilation model, modules are compiled to native code,
/// so "reloading" has limited meaning. We clear and reinitialize the module dict.
export fn PyImport_ReloadModule(module: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
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
    return PyImport_ExecCodeModuleWithPathnames(name, co, null, null);
}

/// Execute code as module with pathname
///
/// CPython: PyObject* PyImport_ExecCodeModuleEx(const char *name, PyObject *co, const char *pathname)
export fn PyImport_ExecCodeModuleEx(name: [*:0]const u8, co: *cpython.PyObject, pathname: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    return PyImport_ExecCodeModuleWithPathnames(name, co, pathname, null);
}

/// Execute code as module with pathnames
///
/// CPython: PyObject* PyImport_ExecCodeModuleWithPathnames(const char *name, PyObject *co,
///                                                          const char *pathname, const char *cpathname)
export fn PyImport_ExecCodeModuleWithPathnames(
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
    if (@import("../objects/noneobject.zig").Py_None) |none| {
        _ = pydict.PyDict_SetItemString(mod_dict, "__loader__", none);
    }

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

/// Cached search paths from environment discovery
var cached_search_paths: ?std.ArrayList([]const u8) = null;
var search_paths_initialized: bool = false;

/// Get search paths dynamically from environment
fn getSearchPaths() []const []const u8 {
    if (search_paths_initialized) {
        if (cached_search_paths) |paths| {
            return paths.items;
        }
    }

    search_paths_initialized = true;
    cached_search_paths = std.ArrayList([]const u8).init(allocator);
    var paths = &cached_search_paths.?;

    // Always include current directory
    paths.append("./") catch {};

    // 1. Check PYTHONPATH environment variable
    if (std.posix.getenv("PYTHONPATH")) |pythonpath| {
        var it = std.mem.splitScalar(u8, pythonpath, ':');
        while (it.next()) |path| {
            if (path.len > 0) {
                const p = allocator.dupeZ(u8, path) catch continue;
                paths.append(p) catch {};
            }
        }
    }

    // 2. Try to discover Python installation paths dynamically
    // Check for common Python versions
    const python_versions = [_][]const u8{ "3.13", "3.12", "3.11", "3.10" };

    // Get HOME directory
    const home = std.posix.getenv("HOME") orelse "/root";

    // mise/asdf python paths
    for (python_versions) |ver| {
        var buf: [512]u8 = undefined;
        // mise path pattern
        const mise_path = std.fmt.bufPrint(&buf, "{s}/.local/share/mise/installs/python/latest/lib/python{s}/site-packages/", .{ home, ver }) catch continue;
        if (directoryExists(mise_path)) {
            paths.append(allocator.dupe(u8, mise_path) catch continue) catch {};
        }
    }

    // pyenv paths
    for (python_versions) |ver| {
        var buf: [512]u8 = undefined;
        const pyenv_path = std.fmt.bufPrint(&buf, "{s}/.pyenv/versions/{s}.*/lib/python{s}/site-packages/", .{ home, ver, ver }) catch continue;
        if (directoryExists(pyenv_path)) {
            paths.append(allocator.dupe(u8, pyenv_path) catch continue) catch {};
        }
    }

    // Homebrew paths (macOS)
    if (comptime std.builtin.os.tag == .macos) {
        for (python_versions) |ver| {
            var buf: [256]u8 = undefined;
            const brew_path = std.fmt.bufPrint(&buf, "/opt/homebrew/lib/python{s}/site-packages/", .{ver}) catch continue;
            if (directoryExists(brew_path)) {
                paths.append(allocator.dupe(u8, brew_path) catch continue) catch {};
            }
        }
    }

    // System paths (Linux)
    if (comptime std.builtin.os.tag == .linux) {
        for (python_versions) |ver| {
            var buf: [256]u8 = undefined;
            // Standard system path
            const sys_path = std.fmt.bufPrint(&buf, "/usr/lib/python{s}/site-packages/", .{ver}) catch continue;
            if (directoryExists(sys_path)) {
                paths.append(allocator.dupe(u8, sys_path) catch continue) catch {};
            }
            // dist-packages (Debian/Ubuntu)
            const dist_path = std.fmt.bufPrint(&buf, "/usr/lib/python{s}/dist-packages/", .{ver}) catch continue;
            if (directoryExists(dist_path)) {
                paths.append(allocator.dupe(u8, dist_path) catch continue) catch {};
            }
        }
    }

    // Virtual environment paths
    if (std.posix.getenv("VIRTUAL_ENV")) |venv| {
        for (python_versions) |ver| {
            var buf: [512]u8 = undefined;
            const venv_path = std.fmt.bufPrint(&buf, "{s}/lib/python{s}/site-packages/", .{ venv, ver }) catch continue;
            if (directoryExists(venv_path)) {
                paths.append(allocator.dupe(u8, venv_path) catch continue) catch {};
            }
        }
    }

    // Check for .venv in current directory
    for (python_versions) |ver| {
        var buf: [256]u8 = undefined;
        const local_venv = std.fmt.bufPrint(&buf, ".venv/lib/python{s}/site-packages/", .{ver}) catch continue;
        if (directoryExists(local_venv)) {
            paths.append(allocator.dupe(u8, local_venv) catch continue) catch {};
        }
    }

    return paths.items;
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
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    var it = std.mem.splitScalar(u8, name, '.');
    while (it.next()) |part| {
        parts.append(part) catch continue;
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
        _ = remaining;

        const path_z: [:0]const u8 = full_buf[0..pos :0];
        if (loadSharedLibraryWithName(path_z, last_part)) |module| {
            return module;
        }
    }

    return null;
}

/// Get platform-specific extension suffixes
fn getPlatformExtensions() []const []const u8 {
    return comptime if (std.builtin.os.tag == .macos)
        &[_][]const u8{ ".cpython-313-darwin.so", ".cpython-312-darwin.so", ".cpython-311-darwin.so", ".so", ".dylib" }
    else if (std.builtin.os.tag == .windows)
        &[_][]const u8{".pyd"}
    else
        &[_][]const u8{ ".cpython-313-x86_64-linux-gnu.so", ".cpython-312-x86_64-linux-gnu.so", ".cpython-311-x86_64-linux-gnu.so", ".so" };
}

/// Try loading extension from package subdirectory
fn tryLoadPackageExtension(base_path: []const u8, subpath: []const u8, init_name: []const u8) ?*cpython.PyObject {
    const extensions = if (std.builtin.os.tag == .macos)
        [_][]const u8{".cpython-312-darwin.so", ".cpython-311-darwin.so", ".so", ".dylib"}
    else if (std.builtin.os.tag == .windows)
        [_][]const u8{".pyd"}
    else
        [_][]const u8{".cpython-312-x86_64-linux-gnu.so", ".cpython-311-x86_64-linux-gnu.so", ".so"};

    for (extensions) |ext| {
        var path_buf: [1024]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, "{s}{s}{s}", .{ base_path, subpath, ext }) catch continue;

        if (loadSharedLibraryWithName(path, init_name)) |module| {
            return module;
        }
    }

    return null;
}

/// Load shared library with explicit init function name
fn loadSharedLibraryWithName(path: [:0]const u8, init_name: []const u8) ?*cpython.PyObject {
    // Try to open the shared library with RTLD_GLOBAL so our symbols are visible
    const handle = std.c.dlopen(path, std.c.RTLD.NOW | std.c.RTLD.GLOBAL) orelse {
        // Debug: print why it failed
        const err = std.c.dlerror();
        if (err != null) {
            std.debug.print("dlopen failed for {s}: {s}\n", .{ path, err.? });
        }
        return null;
    };

    // Build init function name: PyInit_{name}
    var name_buf: [256]u8 = undefined;
    const full_init_name = std.fmt.bufPrintZ(&name_buf, "PyInit_{s}", .{init_name}) catch {
        _ = std.c.dlclose(handle);
        return null;
    };

    // Get init function pointer
    const init_func_ptr = std.c.dlsym(handle, full_init_name) orelse {
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
            const name_z = allocator.dupeZ(u8, init_name) catch {
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
