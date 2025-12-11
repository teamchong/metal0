/// PyObject_*, PyOS_*, PyIter_*, PyList_*, PyLong_*, PyMapping_*, PyMember_*, PyModule_*, PySequence_*, PySys_* Functions
/// Object manipulation, OS utilities, and various Python API functions.

const std = @import("std");
const cpython = @import("../include/object.zig");
const pylong = @import("../objects/longobject.zig");
const pydict = @import("../objects/dictobject.zig");
const pylist = @import("../objects/listobject.zig");
const pyunicode = @import("../objects/unicodeobject.zig");
const pyiter = @import("../objects/iterobject.zig");
const pymethod = @import("../objects/methodobject.zig");
const exceptions = @import("../objects/exceptions.zig");
const traits = @import("../objects/typetraits.zig");
const misc = @import("../include/pymisc.zig");

// --- PyIter_* ---

export fn PyIter_NextItem(iter: *cpython.PyObject, item: *?*cpython.PyObject) callconv(.c) c_int {
    const result = pyiter.PyIter_Next(iter);
    item.* = result;
    return if (result != null) 1 else 0;
}

// --- PyList_* ---

export fn PyList_GetItemRef(list: *cpython.PyObject, index: isize) callconv(.c) ?*cpython.PyObject {
    const item = pylist.PyList_GetItem(list, index);
    if (item) |i| {
        traits.incref(i);
    }
    return item;
}

// --- PyLong_* New Functions ---

export fn PyLong_AsInt(obj: *cpython.PyObject) callconv(.c) c_int {
    return @intCast(pylong.PyLong_AsLong(obj));
}

export fn PyLong_AsNativeBytes(obj: *cpython.PyObject, buffer: [*]u8, n_bytes: isize, flags: c_int) callconv(.c) isize {
    _ = flags;
    const val = pylong.PyLong_AsLong(obj);
    const bytes: [8]u8 = @bitCast(val);
    const copy_len: usize = @min(@as(usize, @intCast(n_bytes)), 8);
    @memcpy(buffer[0..copy_len], bytes[0..copy_len]);
    return @intCast(copy_len);
}

export fn PyLong_FromNativeBytes(buffer: [*]const u8, n_bytes: usize, flags: c_int) callconv(.c) ?*cpython.PyObject {
    _ = flags;
    if (n_bytes >= 8) {
        const val: i64 = @bitCast(buffer[0..8].*);
        return pylong.PyLong_FromLongLong(val);
    }
    return pylong.PyLong_FromLong(0);
}

export fn PyLong_FromUnsignedNativeBytes(buffer: [*]const u8, n_bytes: usize, flags: c_int) callconv(.c) ?*cpython.PyObject {
    _ = flags;
    if (n_bytes >= 8) {
        const val: u64 = @bitCast(buffer[0..8].*);
        return pylong.PyLong_FromUnsignedLongLong(val);
    }
    return pylong.PyLong_FromUnsignedLong(0);
}

export fn PyLong_GetInfo() callconv(.c) ?*cpython.PyObject {
    return pydict.PyDict_New();
}

// --- PyMapping_* New Functions ---

export fn PyMapping_GetOptionalItem(obj: *cpython.PyObject, key: *cpython.PyObject, result: *?*cpython.PyObject) callconv(.c) c_int {
    const tp = cpython.Py_TYPE(obj);
    if (tp.tp_as_mapping) |m| {
        if (m.mp_subscript) |subscript| {
            const item = subscript(obj, key);
            if (item) |i| {
                result.* = i;
                return 1;
            }
        }
    }
    result.* = null;
    return 0;
}

export fn PyMapping_GetOptionalItemString(obj: *cpython.PyObject, key: [*:0]const u8, result: *?*cpython.PyObject) callconv(.c) c_int {
    const mapping = @import("../include/mapping.zig");
    const item = mapping.PyMapping_GetItemString(obj, key);
    result.* = item;
    return if (item != null) 1 else 0;
}

export fn PyMapping_HasKeyStringWithError(obj: *cpython.PyObject, key: [*:0]const u8) callconv(.c) c_int {
    const mapping = @import("../include/mapping.zig");
    return mapping.PyMapping_HasKeyString(obj, key);
}

export fn PyMapping_HasKeyWithError(obj: *cpython.PyObject, key: *cpython.PyObject) callconv(.c) c_int {
    const mapping = @import("../include/mapping.zig");
    return mapping.PyMapping_HasKey(obj, key);
}

// --- PyMember_* ---

export fn PyMember_GetOne(obj: [*]const u8, member: *const cpython.PyMemberDef) callconv(.c) ?*cpython.PyObject {
    const offset: usize = @intCast(member.offset);
    const ptr = obj + offset;
    return switch (member.@"type") {
        0 => pylong.PyLong_FromLong(@as(*const c_int, @ptrCast(@alignCast(ptr))).*), // T_INT
        1 => pylong.PyLong_FromLong(@as(*const c_short, @ptrCast(@alignCast(ptr))).*), // T_SHORT
        2 => pylong.PyLong_FromLong(@as(*const c_long, @ptrCast(@alignCast(ptr))).*), // T_LONG
        else => null,
    };
}

export fn PyMember_SetOne(obj: [*]u8, member: *const cpython.PyMemberDef, value: *cpython.PyObject) callconv(.c) c_int {
    const offset: usize = @intCast(member.offset);
    const ptr = obj + offset;
    const val = pylong.PyLong_AsLong(value);
    switch (member.@"type") {
        0 => @as(*c_int, @ptrCast(@alignCast(ptr))).* = @intCast(val), // T_INT
        1 => @as(*c_short, @ptrCast(@alignCast(ptr))).* = @intCast(val), // T_SHORT
        2 => @as(*c_long, @ptrCast(@alignCast(ptr))).* = val, // T_LONG
        else => return -1,
    }
    return 0;
}

// --- PyModule_* New Functions ---

export fn PyModule_Add(module: *cpython.PyObject, name: [*:0]const u8, value: *cpython.PyObject) callconv(.c) c_int {
    const module_mod = @import("../include/moduleobject.zig");
    return module_mod.PyModule_AddObject(module, name, value);
}

export fn PyModule_AddFunctions(module: *cpython.PyObject, methods: [*]const cpython.PyMethodDef) callconv(.c) c_int {
    const module_mod = @import("../include/moduleobject.zig");
    var i: usize = 0;
    while (methods[i].ml_name != null) : (i += 1) {
        const method = &methods[i];
        const func = pymethod.PyCFunction_NewEx(method, null, module) orelse return -1;
        if (module_mod.PyModule_AddObject(module, method.ml_name.?, func) < 0) {
            return -1;
        }
    }
    return 0;
}

export fn PyModule_Exec(module: *cpython.PyObject, def: *cpython.PyModuleDef) callconv(.c) c_int {
    return PyModule_ExecDef(module, def);
}

export fn PyModule_ExecDef(module: *cpython.PyObject, def: *cpython.PyModuleDef) callconv(.c) c_int {
    const module_mod = @import("../include/moduleobject.zig");

    if (def.m_methods) |methods| {
        if (PyModule_AddFunctions(module, methods) < 0) {
            return -1;
        }
    }

    if (def.m_slots) |slots| {
        var i: usize = 0;
        while (slots[i].slot != 0) : (i += 1) {
            const slot = &slots[i];
            switch (slot.slot) {
                1 => { // Py_mod_exec
                    if (slot.value) |exec_fn| {
                        const func: *const fn (*cpython.PyObject) callconv(.c) c_int = @ptrCast(exec_fn);
                        if (func(module) < 0) {
                            return -1;
                        }
                    }
                },
                2 => {}, // Py_mod_create
                3 => {}, // Py_mod_multiple_interpreters
                4 => {}, // Py_mod_gil
                else => {},
            }
        }
    }

    if (def.m_name) |name| {
        const name_obj = pyunicode.PyUnicode_FromString(name) orelse return -1;
        _ = module_mod.PyModule_AddObject(module, "__name__", name_obj);
    }

    if (def.m_doc) |doc| {
        const doc_obj = pyunicode.PyUnicode_FromString(doc) orelse return -1;
        _ = module_mod.PyModule_AddObject(module, "__doc__", doc_obj);
    }

    return 0;
}

export fn PyModule_FromSlotsAndSpec(def: *cpython.PyModuleDef, spec: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = spec;
    const module_mod = @import("../include/moduleobject.zig");
    const module = module_mod.PyModule_Create2(def, 1013) orelse return null;
    if (PyModule_ExecDef(module, def) < 0) {
        traits.decref(module);
        return null;
    }
    return module;
}

export fn PyModule_GetFilenameObject(module: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = module;
    return pyunicode.PyUnicode_FromString("<unknown>");
}

export fn PyModule_GetNameObject(module: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const module_mod = @import("../include/moduleobject.zig");
    const name = module_mod.PyModule_GetName(module);
    if (name) |n| {
        return pyunicode.PyUnicode_FromString(n);
    }
    return null;
}

export fn PyModule_GetStateSize(module: *cpython.PyObject) callconv(.c) isize {
    _ = module;
    return 0;
}

export fn PyModule_GetToken(module: *cpython.PyObject) callconv(.c) ?*anyopaque {
    _ = module;
    return null;
}

// --- PyObject_* New Functions ---

export fn PyObject_CallFunctionObjArgs(callable: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const call = @import("../include/call.zig");
    return call.PyObject_CallNoArgs(callable);
}

export fn PyObject_CallMethodObjArgs(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const call = @import("../include/call.zig");
    return call.PyObject_CallMethodNoArgs(obj, name);
}

export fn PyObject_DelAttr(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) c_int {
    return misc.PyObject_SetAttr(obj, name, null);
}

export fn PyObject_DelItemString(obj: *cpython.PyObject, key: [*:0]const u8) callconv(.c) c_int {
    const mapping = @import("../include/mapping.zig");
    return mapping.PyMapping_DelItemString(obj, key);
}

export fn PyObject_GC_IsFinalized(obj: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    return 0;
}

export fn PyObject_GC_NewVar(tp: *cpython.PyTypeObject, nitems: isize) callconv(.c) ?*cpython.PyVarObject {
    const size = tp.tp_basicsize + tp.tp_itemsize * @as(isize, @intCast(if (nitems > 0) nitems else 0));
    const mem = std.heap.c_allocator.alloc(u8, @intCast(size)) catch return null;
    const obj: *cpython.PyVarObject = @ptrCast(@alignCast(mem.ptr));
    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = tp;
    obj.ob_size = nitems;
    return obj;
}

export fn PyObject_GC_Resize(obj: *cpython.PyVarObject, nitems: isize) callconv(.c) ?*cpython.PyVarObject {
    obj.ob_size = nitems;
    return obj;
}

export fn PyObject_GetOptionalAttr(obj: *cpython.PyObject, name: *cpython.PyObject, result: *?*cpython.PyObject) callconv(.c) c_int {
    result.* = misc.PyObject_GetAttr(obj, name);
    return if (result.* != null) 1 else 0;
}

export fn PyObject_GetOptionalAttrString(obj: *cpython.PyObject, name: [*:0]const u8, result: *?*cpython.PyObject) callconv(.c) c_int {
    result.* = misc.PyObject_GetAttrString(obj, name);
    return if (result.* != null) 1 else 0;
}

export fn PyObject_GetTypeData(obj: *cpython.PyObject, cls: *cpython.PyTypeObject) callconv(.c) ?*anyopaque {
    _ = cls;
    const base: [*]u8 = @ptrCast(obj);
    const tp = cpython.Py_TYPE(obj);
    return @ptrCast(base + @as(usize, @intCast(tp.tp_basicsize)));
}

export fn PyObject_HasAttrStringWithError(obj: *cpython.PyObject, name: [*:0]const u8) callconv(.c) c_int {
    return if (misc.PyObject_GetAttrString(obj, name) != null) 1 else 0;
}

export fn PyObject_HasAttrWithError(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) c_int {
    return if (misc.PyObject_GetAttr(obj, name) != null) 1 else 0;
}

export fn PyObject_HashNotImplemented(obj: *cpython.PyObject) callconv(.c) isize {
    _ = obj;
    exceptions.PyErr_SetString(&exceptions.PyExc_TypeError, "unhashable type");
    return -1;
}

// --- PyOS_* Functions ---

export fn PyOS_CheckStack() callconv(.c) c_int {
    return 0;
}

export fn PyOS_getsig(sig: c_int) callconv(.c) ?*const fn (c_int) callconv(.c) void {
    _ = sig;
    return null;
}

export fn PyOS_mystricmp(s1: [*:0]const u8, s2: [*:0]const u8) callconv(.c) c_int {
    var i: usize = 0;
    while (s1[i] != 0 and s2[i] != 0) : (i += 1) {
        const c1 = std.ascii.toLower(s1[i]);
        const c2 = std.ascii.toLower(s2[i]);
        if (c1 != c2) return @as(c_int, c1) - @as(c_int, c2);
    }
    return @as(c_int, s1[i]) - @as(c_int, s2[i]);
}

export fn PyOS_mystrnicmp(s1: [*:0]const u8, s2: [*:0]const u8, n: isize) callconv(.c) c_int {
    var i: usize = 0;
    const max: usize = @intCast(n);
    while (i < max and s1[i] != 0 and s2[i] != 0) : (i += 1) {
        const c1 = std.ascii.toLower(s1[i]);
        const c2 = std.ascii.toLower(s2[i]);
        if (c1 != c2) return @as(c_int, c1) - @as(c_int, c2);
    }
    if (i >= max) return 0;
    return @as(c_int, s1[i]) - @as(c_int, s2[i]);
}

export fn PyOS_setsig(sig: c_int, handler: ?*const fn (c_int) callconv(.c) void) callconv(.c) ?*const fn (c_int) callconv(.c) void {
    _ = sig;
    _ = handler;
    return null;
}

// --- PySequence_* ---

export fn PySequence_In(seq: *cpython.PyObject, obj: *cpython.PyObject) callconv(.c) c_int {
    const sequence = @import("../include/sequence.zig");
    return sequence.PySequence_Contains(seq, obj);
}

// --- PySys_* Functions ---

export fn PySys_Audit(event: [*:0]const u8, argFormat: [*:0]const u8) callconv(.c) c_int {
    _ = event;
    _ = argFormat;
    return 0;
}

export fn PySys_AuditTuple(event: [*:0]const u8, args: *cpython.PyObject) callconv(.c) c_int {
    _ = event;
    _ = args;
    return 0;
}

export fn PySys_GetAttr(name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = name;
    return null;
}

export fn PySys_GetAttrString(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = name;
    return null;
}

export fn PySys_GetOptionalAttr(name: *cpython.PyObject, result: *?*cpython.PyObject) callconv(.c) c_int {
    result.* = PySys_GetAttr(name);
    return if (result.* != null) 1 else 0;
}

export fn PySys_GetOptionalAttrString(name: [*:0]const u8, result: *?*cpython.PyObject) callconv(.c) c_int {
    result.* = PySys_GetAttrString(name);
    return if (result.* != null) 1 else 0;
}

export fn PySys_GetXOptions() callconv(.c) ?*cpython.PyObject {
    return pydict.PyDict_New();
}
