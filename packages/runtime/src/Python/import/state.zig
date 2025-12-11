/// import state - Import system state management
const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const builtins = @import("builtins.zig");

const InittabEntry = types.InittabEntry;
const FrozenModule = types.FrozenModule;

/// Module cache entry
pub const ModuleCacheEntry = struct {
    name: []const u8,
    module: ?*anyopaque,
    def: ?*const types.ModuleDef,
};

/// Global import state
pub const ImportState = struct {
    modules: hashmap_helper.StringHashMap(?*anyopaque),
    modules_by_index: std.ArrayList(?*anyopaque),
    last_module_index: i64,
    inittab: []const InittabEntry,
    frozen_modules: []const FrozenModule,
    import_mutex: std.Thread.Mutex,
    import_lock_count: u32,
    import_lock_thread: u64,
    pkgcontext: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .modules = hashmap_helper.StringHashMap(?*anyopaque).init(allocator),
            .modules_by_index = std.ArrayList(?*anyopaque).init(allocator),
            .last_module_index = 0,
            .inittab = &builtins.builtin_modules,
            .frozen_modules = &builtins.frozen_modules,
            .import_mutex = .{},
            .import_lock_count = 0,
            .import_lock_thread = 0,
            .pkgcontext = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.modules.deinit();
        self.modules_by_index.deinit();
    }
};

/// Global import state
pub var import_state: ?ImportState = null;

/// Initialize the import system
pub fn init() void {
    if (import_state != null) {
        return;
    }
    import_state = ImportState.init(allocator_helper.fast_allocator);
}

/// Finalize the import system
pub fn fini() void {
    if (import_state) |*state| {
        state.deinit();
        import_state = null;
    }
}

/// Initialize module lookup tables
pub fn initModuleTables() void {
    // Pre-populate with built-in module names
}
