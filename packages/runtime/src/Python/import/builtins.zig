/// import builtins - Built-in module table and initializers
const types = @import("types.zig");
const InittabEntry = types.InittabEntry;
const FrozenModule = types.FrozenModule;

/// Table of built-in modules (compile-time known)
pub const builtin_modules = [_]InittabEntry{
    .{ .name = "builtins", .init = initBuiltins },
    .{ .name = "sys", .init = initSys },
    .{ .name = "_io", .init = initIO },
    .{ .name = "_warnings", .init = initWarnings },
    .{ .name = "_thread", .init = initThread },
    .{ .name = "_weakref", .init = initWeakref },
    .{ .name = "_abc", .init = initAbc },
    .{ .name = "_collections", .init = initCollections },
    .{ .name = "_functools", .init = initFunctools },
    .{ .name = "_operator", .init = initOperator },
    .{ .name = "_string", .init = initString },
    .{ .name = "_stat", .init = initStat },
    .{ .name = "atexit", .init = initAtexit },
    .{ .name = "errno", .init = initErrno },
    .{ .name = "faulthandler", .init = initFaulthandler },
    .{ .name = "gc", .init = initGc },
    .{ .name = "itertools", .init = initItertools },
    .{ .name = "marshal", .init = initMarshal },
    .{ .name = "posix", .init = initPosix },
    .{ .name = "pwd", .init = initPwd },
    .{ .name = "time", .init = initTime },
    .{ .name = "zipimport", .init = initZipimport },
};

/// Empty frozen modules table
pub const frozen_modules = [_]FrozenModule{};

// Built-in module initializers (stubs)
fn initBuiltins() ?*anyopaque { return null; }
fn initSys() ?*anyopaque { return null; }
fn initIO() ?*anyopaque { return null; }
fn initWarnings() ?*anyopaque { return null; }
fn initThread() ?*anyopaque { return null; }
fn initWeakref() ?*anyopaque { return null; }
fn initAbc() ?*anyopaque { return null; }
fn initCollections() ?*anyopaque { return null; }
fn initFunctools() ?*anyopaque { return null; }
fn initOperator() ?*anyopaque { return null; }
fn initString() ?*anyopaque { return null; }
fn initStat() ?*anyopaque { return null; }
fn initAtexit() ?*anyopaque { return null; }
fn initErrno() ?*anyopaque { return null; }
fn initFaulthandler() ?*anyopaque { return null; }
fn initGc() ?*anyopaque { return null; }
fn initItertools() ?*anyopaque { return null; }
fn initMarshal() ?*anyopaque { return null; }
fn initPosix() ?*anyopaque { return null; }
fn initPwd() ?*anyopaque { return null; }
fn initTime() ?*anyopaque { return null; }
fn initZipimport() ?*anyopaque { return null; }
