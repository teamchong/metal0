//! isLocalModule - Check if a module is a local .py file vs stdlib
//! USE: When deciding how to handle an import statement
//! CALL: module_traits.isLocalModule(module_name, source_dir)
//! RETURNS: true if local .py file exists, false if stdlib or not found

const std = @import("std");

/// Known stdlib module names that should NOT be treated as local
const StdlibModules = std.StaticStringMap(void).initComptime(.{
    // Core modules
    .{ "sys", {} },
    .{ "os", {} },
    .{ "io", {} },
    .{ "re", {} },
    .{ "json", {} },
    .{ "math", {} },
    .{ "time", {} },
    .{ "datetime", {} },
    .{ "random", {} },
    .{ "collections", {} },
    .{ "itertools", {} },
    .{ "functools", {} },
    .{ "operator", {} },
    .{ "typing", {} },
    .{ "types", {} },
    .{ "abc", {} },
    .{ "copy", {} },
    .{ "pickle", {} },
    .{ "hashlib", {} },
    .{ "base64", {} },
    .{ "struct", {} },
    .{ "string", {} },
    .{ "textwrap", {} },
    .{ "unittest", {} },
    .{ "logging", {} },
    .{ "warnings", {} },
    .{ "traceback", {} },
    .{ "inspect", {} },
    .{ "dis", {} },
    .{ "ast", {} },
    .{ "builtins", {} },
    .{ "contextlib", {} },
    .{ "dataclasses", {} },
    .{ "enum", {} },
    .{ "pathlib", {} },
    .{ "shutil", {} },
    .{ "tempfile", {} },
    .{ "glob", {} },
    .{ "fnmatch", {} },
    .{ "stat", {} },
    .{ "fileinput", {} },
    .{ "csv", {} },
    .{ "configparser", {} },
    .{ "argparse", {} },
    .{ "getopt", {} },
    .{ "socket", {} },
    .{ "ssl", {} },
    .{ "select", {} },
    .{ "threading", {} },
    .{ "multiprocessing", {} },
    .{ "subprocess", {} },
    .{ "queue", {} },
    .{ "asyncio", {} },
    .{ "concurrent", {} },
    .{ "ctypes", {} },
    .{ "sqlite3", {} },
    .{ "decimal", {} },
    .{ "fractions", {} },
    .{ "statistics", {} },
    .{ "cmath", {} },
    .{ "numbers", {} },
    .{ "bisect", {} },
    .{ "heapq", {} },
    .{ "array", {} },
    .{ "weakref", {} },
    .{ "gc", {} },
    .{ "platform", {} },
    .{ "locale", {} },
    .{ "gettext", {} },
    .{ "codecs", {} },
    .{ "unicodedata", {} },
    .{ "html", {} },
    .{ "xml", {} },
    .{ "urllib", {} },
    .{ "http", {} },
    .{ "email", {} },
    .{ "mimetypes", {} },
    .{ "zipfile", {} },
    .{ "tarfile", {} },
    .{ "gzip", {} },
    .{ "bz2", {} },
    .{ "lzma", {} },
    .{ "zlib", {} },
    // Test modules
    .{ "test", {} },
    .{ "support", {} },
});

/// Check if module is a local .py file (not stdlib)
pub fn isLocalModule(module_name: []const u8, source_dir: ?[]const u8) bool {
    // First check if it's a known stdlib module
    if (StdlibModules.has(module_name)) {
        return false;
    }

    // Check for submodules of stdlib (e.g., os.path, collections.abc)
    if (std.mem.indexOf(u8, module_name, ".")) |_| {
        const root = std.mem.sliceTo(module_name, '.');
        if (StdlibModules.has(root)) {
            return false;
        }
    }

    // If we have a source directory, check if local file exists
    if (source_dir) |dir| {
        // Check for module_name.py
        var path_buf: [1024]u8 = undefined;
        const py_path = std.fmt.bufPrint(&path_buf, "{s}/{s}.py", .{ dir, module_name }) catch return false;

        // Check if file exists
        if (std.fs.cwd().access(py_path, .{})) |_| {
            return true;
        } else |_| {
            // Also check for package (module_name/__init__.py)
            const pkg_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/__init__.py", .{ dir, module_name }) catch return false;
            if (std.fs.cwd().access(pkg_path, .{})) |_| {
                return true;
            } else |_| {
                return false;
            }
        }
    }

    // No source dir - assume not local if not obviously a test module
    // Local modules typically have lowercase names and don't start with _
    return !std.mem.startsWith(u8, module_name, "_") and
        module_name.len > 0 and
        std.ascii.isLower(module_name[0]) and
        !StdlibModules.has(module_name);
}

/// Check if a path looks like a local module path
pub fn isLocalPath(path: []const u8) bool {
    // Local paths are relative (don't start with / or contain site-packages)
    return !std.mem.startsWith(u8, path, "/") and
        std.mem.indexOf(u8, path, "site-packages") == null and
        std.mem.indexOf(u8, path, "Lib/") == null;
}
