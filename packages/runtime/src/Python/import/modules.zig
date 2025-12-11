/// import modules - Module dictionary (sys.modules) management
const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const hashmap_helper = @import("utils.hashmap_helper");
const state = @import("state.zig");
const types = @import("types.zig");

/// Import error types
pub const ImportError = error{
    NotInitialized,
    ModuleNotFound,
    ImportFailed,
    OutOfMemory,
};

/// Initialize sys.modules
pub fn initModules() !void {
    var st = &(state.import_state orelse return error.NotInitialized);
    st.modules = hashmap_helper.StringHashMap(?*anyopaque).init(allocator_helper.fast_allocator);
}

/// Get sys.modules dictionary
pub fn getModuleDict() ?*hashmap_helper.StringHashMap(?*anyopaque) {
    var st = &(state.import_state orelse return null);
    return &st.modules;
}

/// Get a module from sys.modules
pub fn getModule(name: []const u8) ??*anyopaque {
    const st = state.import_state orelse return null;
    return st.modules.get(name) orelse null;
}

/// Set a module in sys.modules
pub fn setModule(name: []const u8, module: ?*anyopaque) !void {
    var st = &(state.import_state orelse return error.NotInitialized);
    try st.modules.put(name, module);
}

/// Remove a module from sys.modules
pub fn removeModule(name: []const u8) void {
    var st = &(state.import_state orelse return);
    _ = st.modules.remove(name);
}

/// Clear all modules from sys.modules
pub fn clearModules() void {
    var st = &(state.import_state orelse return);
    st.modules.clearRetainingCapacity();
}

/// Find built-in module by name
pub fn findBuiltin(name: []const u8) ?*const types.InittabEntry {
    const st = state.import_state orelse return null;
    for (st.inittab) |*entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            return entry;
        }
    }
    return null;
}

/// Find frozen module by name
pub fn findFrozen(name: []const u8) ?*const types.FrozenModule {
    const st = state.import_state orelse return null;
    for (st.frozen_modules) |*entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            return entry;
        }
    }
    return null;
}

/// Check if a module is built-in
pub fn isBuiltin(name: []const u8) bool {
    return findBuiltin(name) != null;
}

/// Check if a module is frozen
pub fn isFrozen(name: []const u8) bool {
    return findFrozen(name) != null;
}
