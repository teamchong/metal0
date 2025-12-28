/// PyType_* Functions
/// Type object manipulation and creation.

const std = @import("std");
const cpython = @import("../include/object.zig");
const pyunicode = @import("../objects/unicodeobject.zig");
const type_ = @import("../include/typeslots.zig");

pub export fn PyType_ClearCache() callconv(.c) c_uint {
    return 0;
}

pub export fn PyType_Freeze(tp: *cpython.PyTypeObject) callconv(.c) c_int {
    _ = tp;
    return 0;
}

pub export fn PyType_FromMetaclass(metaclass: ?*cpython.PyTypeObject, module: ?*cpython.PyObject, spec: *cpython.PyType_Spec, bases: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = metaclass;
    _ = module;
    _ = bases;
    return type_.PyType_FromSpec(spec);
}

pub export fn PyType_FromModuleAndSpec(module: *cpython.PyObject, spec: *cpython.PyType_Spec, bases: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = module;
    _ = bases;
    return type_.PyType_FromSpec(spec);
}

pub export fn PyType_FromSpec(spec: *cpython.PyType_Spec) callconv(.c) ?*cpython.PyObject {
    return type_.PyType_FromSpec(spec);
}

pub export fn PyType_FromSpecWithBases(spec: *cpython.PyType_Spec, bases: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = bases;
    return type_.PyType_FromSpec(spec);
}

pub export fn PyType_GetBaseByToken(tp: *cpython.PyTypeObject, token: ?*anyopaque, result: *?*cpython.PyTypeObject) callconv(.c) c_int {
    _ = token;
    result.* = tp.tp_base;
    return if (result.* != null) 1 else 0;
}

pub export fn PyType_GetFullyQualifiedName(tp: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    return pyunicode.PyUnicode_FromString(tp.tp_name orelse "unknown");
}

pub export fn PyType_GetModuleByDef(tp: *cpython.PyTypeObject, def: *cpython.PyModuleDef) callconv(.c) ?*cpython.PyObject {
    _ = tp;
    _ = def;
    return null;
}

pub export fn PyType_GetModuleByToken(tp: *cpython.PyTypeObject, token: ?*anyopaque) callconv(.c) ?*cpython.PyObject {
    _ = tp;
    _ = token;
    return null;
}

pub export fn PyType_GetModuleName(tp: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    _ = tp;
    return pyunicode.PyUnicode_FromString("builtins");
}

pub export fn PyType_GetTypeDataSize(tp: *cpython.PyTypeObject) callconv(.c) isize {
    _ = tp;
    return 0;
}
