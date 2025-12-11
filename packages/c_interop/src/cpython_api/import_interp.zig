/// PyImport_* and PyInterpreterState_* Functions
/// Import system and interpreter state management.

const std = @import("std");
const cpython = @import("../include/object.zig");
const pydict = @import("../objects/dictobject.zig");
const pyunicode = @import("../objects/unicodeobject.zig");
const traits = @import("../objects/typetraits.zig");

// --- PyImport_* Functions ---

export fn PyImport_AddModuleRef(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const import_mod = @import("../include/import.zig");
    const module = import_mod.PyImport_ImportModule(name);
    if (module) |m| {
        traits.incref(m);
    }
    return module;
}

export fn PyImport_ExecCodeModuleObject(name: *cpython.PyObject, co: *cpython.PyObject, pathname: *cpython.PyObject, cpathname: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = cpathname;
    const import_mod = @import("../include/import.zig");
    const module_mod = @import("../include/moduleobject.zig");

    const name_str = pyunicode.PyUnicode_AsUTF8(name) orelse return null;
    const module = import_mod.PyImport_AddModule(name_str) orelse return null;

    _ = module_mod.PyModule_AddObject(module, "__file__", pathname);
    traits.incref(pathname);

    const dict = module_mod.PyModule_GetDict(module);
    if (dict) |d| {
        const eval_mod = @import("../include/ceval.zig");
        _ = eval_mod.PyEval_EvalCode(co, d, d);
    }

    return module;
}

export fn PyImport_ExecCodeModuleWithPathnames(name: [*:0]const u8, co: *cpython.PyObject, pathname: [*:0]const u8, cpathname: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = cpathname;
    const name_obj = pyunicode.PyUnicode_FromString(name) orelse return null;
    const path_obj = pyunicode.PyUnicode_FromString(pathname) orelse return null;
    return PyImport_ExecCodeModuleObject(name_obj, co, path_obj, null);
}

export fn PyImport_GetImporter(path: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const result = pydict.PyDict_New() orelse return null;
    _ = pydict.PyDict_SetItemString(result, "path", path);
    return result;
}

export fn PyImport_GetMagicNumber() callconv(.c) c_long {
    return 3495; // Python 3.12 magic number
}

export fn PyImport_GetMagicTag() callconv(.c) [*:0]const u8 {
    return "cpython-312";
}

export fn PyImport_ImportFrozenModule(name: [*:0]const u8) callconv(.c) c_int {
    _ = name;
    return 0;
}

export fn PyImport_ImportFrozenModuleObject(name: *cpython.PyObject) callconv(.c) c_int {
    _ = name;
    return 0;
}

export fn PyImport_ImportModuleLevelObject(name: *cpython.PyObject, globals: ?*cpython.PyObject, locals: ?*cpython.PyObject, fromlist: ?*cpython.PyObject, level: c_int) callconv(.c) ?*cpython.PyObject {
    _ = globals;
    _ = locals;
    _ = fromlist;
    _ = level;
    if (pyunicode.PyUnicode_AsUTF8(name)) |cname| {
        const import_mod = @import("../include/import.zig");
        return import_mod.PyImport_ImportModule(cname);
    }
    return null;
}

// --- PyInterpreterState_* Functions ---

export fn PyInterpreterState_Clear(interp: ?*anyopaque) callconv(.c) void {
    _ = interp;
}

export fn PyInterpreterState_Delete(interp: ?*anyopaque) callconv(.c) void {
    _ = interp;
}

export fn PyInterpreterState_GetDict(interp: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    _ = interp;
    return pydict.PyDict_New();
}

export fn PyInterpreterState_GetID(interp: ?*anyopaque) callconv(.c) i64 {
    _ = interp;
    return 0;
}

export fn PyInterpreterState_New() callconv(.c) ?*anyopaque {
    return @ptrFromInt(1); // Dummy interpreter state
}
