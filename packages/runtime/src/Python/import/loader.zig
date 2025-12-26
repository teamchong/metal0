/// import loader - Module loading and creation
const std = @import("std");
const types = @import("types.zig");
const state = @import("state.zig");
const modules = @import("modules.zig");

const ModuleDef = types.ModuleDef;
const FrozenModule = types.FrozenModule;
const ImportError = modules.ImportError;

/// Simple module object representation for AOT-compiled code
pub const ModuleObject = struct {
    name: []const u8,
    dict: ?*anyopaque = null,
    doc: ?[]const u8 = null,
    initialized: bool = false,

    pub fn init(mod_name: []const u8) ModuleObject {
        return .{
            .name = mod_name,
            .initialized = true,
        };
    }
};

/// Storage for created module objects
var module_objects: [256]?ModuleObject = [_]?ModuleObject{null} ** 256;
var module_object_count: usize = 0;

/// Import a module by name
pub fn importModule(name: []const u8) ImportError!?*anyopaque {
    if (modules.getModule(name)) |cached| {
        return cached;
    }

    if (modules.findBuiltin(name)) |entry| {
        const module = entry.init();
        if (module != null) {
            try modules.setModule(name, module);
        }
        return module;
    }

    if (modules.findFrozen(name)) |frozen| {
        const module = try loadFrozenModule(name, frozen);
        if (module != null) {
            try modules.setModule(name, module);
        }
        return module;
    }

    return error.ModuleNotFound;
}

/// Import a module with given globals/locals
pub fn importModuleEx(
    name: []const u8,
    globals: ?*anyopaque,
    locals: ?*anyopaque,
    fromlist: ?[]const []const u8,
) ImportError!?*anyopaque {
    _ = globals;
    _ = locals;
    _ = fromlist;
    return importModule(name);
}

/// Import a submodule with level
pub fn importModuleLevel(
    name: []const u8,
    globals: ?*anyopaque,
    locals: ?*anyopaque,
    fromlist: ?[]const []const u8,
    level: i32,
) ImportError!?*anyopaque {
    if (level == 0) {
        return importModuleEx(name, globals, locals, fromlist);
    }

    const st = state.import_state orelse return error.ModuleNotFound;
    const package_name = st.pkgcontext orelse return error.ModuleNotFound;

    var resolved_package = package_name;
    var dots_to_consume: usize = @intCast(level - 1);
    while (dots_to_consume > 0) : (dots_to_consume -= 1) {
        if (std.mem.lastIndexOf(u8, resolved_package, ".")) |dot_pos| {
            resolved_package = resolved_package[0..dot_pos];
        } else {
            return error.ModuleNotFound;
        }
    }

    const full_name = if (name.len > 0)
        blk: {
            var buf: [512]u8 = undefined;
            const len = std.fmt.bufPrint(&buf, "{s}.{s}", .{ resolved_package, name }) catch
                return error.ModuleNotFound;
            break :blk len;
        }
    else
        resolved_package;

    // For relative imports, we resolve the name and use importModule directly
    // globals/locals/fromlist are already handled in the absolute import case (level == 0)
    return importModule(full_name);
}

/// Load a frozen module
pub fn loadFrozenModule(name: []const u8, frozen: *const FrozenModule) ImportError!?*anyopaque {
    _ = name;
    _ = frozen;
    return null;
}

/// Add a new module to sys.modules
pub fn addModule(name: []const u8) !?*anyopaque {
    if (modules.getModule(name)) |existing| {
        return existing;
    }

    if (module_object_count < module_objects.len) {
        module_objects[module_object_count] = ModuleObject.init(name);
        const module_ptr: *anyopaque = @ptrCast(&module_objects[module_object_count].?);
        module_object_count += 1;

        try modules.setModule(name, module_ptr);
        return module_ptr;
    }

    return null;
}

/// Reload a module (no-op in AOT)
pub fn reloadModule(module: ?*anyopaque) ImportError!?*anyopaque {
    if (module == null) {
        return error.ImportFailed;
    }
    return module;
}

/// Get next module index
pub fn getNextModuleIndex() i64 {
    var st = &(state.import_state orelse return -1);
    st.last_module_index += 1;
    return st.last_module_index;
}

/// Get module by index
pub fn getModuleByIndex(index: i64) ??*anyopaque {
    const st = state.import_state orelse return null;
    if (index < 0 or index >= @as(i64, @intCast(st.modules_by_index.items.len))) {
        return null;
    }
    return st.modules_by_index.items[@intCast(index)];
}

/// Set module by index
pub fn setModuleByIndex(index: i64, module: ?*anyopaque) !void {
    var st = &(state.import_state orelse return error.NotInitialized);

    while (st.modules_by_index.items.len <= @as(usize, @intCast(index))) {
        try st.modules_by_index.append(null);
    }

    st.modules_by_index.items[@intCast(index)] = module;
}

/// Create a module from definition
pub fn moduleCreate(def: *const ModuleDef) ?*anyopaque {
    return moduleCreate2(def, 0);
}

/// Create a module from definition with version
pub fn moduleCreate2(def: *const ModuleDef, module_api_version: i32) ?*anyopaque {
    _ = module_api_version;
    const index = getNextModuleIndex();
    var mutable_def = @constCast(def);
    mutable_def.base.m_index = index;
    return @ptrCast(@constCast(def));
}

/// Initialize module definition
pub fn moduleDefInit(def: *ModuleDef) *ModuleDef {
    if (def.base.m_index == 0) {
        def.base.m_index = getNextModuleIndex();
    }
    return def;
}

/// Filetab entry for dynamic loading
pub const FileTab = struct {
    suffix: []const u8,
    file_type: FileType,

    pub const FileType = enum {
        source,
        bytecode,
        extension,
        resource,
    };
};

/// Supported file extensions for modules
pub const import_filetab = [_]FileTab{
    .{ .suffix = ".zig", .file_type = .source },
    .{ .suffix = ".pyc", .file_type = .bytecode },
    .{ .suffix = ".pyo", .file_type = .bytecode },
    .{ .suffix = ".so", .file_type = .extension },
    .{ .suffix = ".dylib", .file_type = .extension },
    .{ .suffix = ".dll", .file_type = .extension },
};
