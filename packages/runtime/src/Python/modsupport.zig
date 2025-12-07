/// modsupport - Module Support Functions
/// Mirrors cpython/Python/modsupport.c
///
/// This module provides functions for building Python objects from C values
/// (Py_BuildValue) and for module initialization helpers (PyModule_Add*).

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

/// Built value types
pub const BuiltValue = union(enum) {
    none: void,
    bool_true: void,
    bool_false: void,
    int: i64,
    uint: u64,
    float: f64,
    string: []const u8,
    bytes: []const u8,
    unicode: []const u8,
    object: *anyopaque,
    tuple: []BuiltValue,
    list: []BuiltValue,
    dict: []KeyValue,

    pub const KeyValue = struct {
        key: BuiltValue,
        value: BuiltValue,
    };
};

/// Format characters for Py_BuildValue
pub const FormatChar = enum(u8) {
    // None
    None = 'N',

    // Boolean
    bool_p = 'p',

    // Integer types
    byte = 'b',
    Byte = 'B',
    short = 'h',
    ushort = 'H',
    int = 'i',
    uint = 'I',
    long = 'l',
    ulong = 'k',
    longlong = 'L',
    ulonglong = 'K',
    ssize = 'n',

    // Float types
    float = 'f',
    double = 'd',
    complex = 'D',

    // Character types
    char = 'c',
    unicode_char = 'C',

    // String types
    string = 's',
    string_or_none = 'z',
    string_bytes = 'y',
    unicode = 'u',
    unicode_obj = 'U',
    bytes_obj = 'S',
    bytearray = 'Y',

    // Object
    object = 'O',

    // Container start/end
    tuple_start = '(',
    tuple_end = ')',
    list_start = '[',
    list_end = ']',
    dict_start = '{',
    dict_end = '}',

    _,
};

/// Error type for value building
pub const BuildError = error{
    InvalidFormat,
    NullObject,
    OutOfMemory,
    TypeError,
};

/// Value builder state
pub const ValueBuilder = struct {
    format: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,
    values: std.ArrayList(BuiltValue),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, format: []const u8) Self {
        return .{
            .format = format,
            .pos = 0,
            .allocator = allocator,
            .values = std.ArrayList(BuiltValue).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.values.deinit();
    }

    fn peek(self: *const Self) ?u8 {
        if (self.pos < self.format.len) {
            return self.format[self.pos];
        }
        return null;
    }

    fn advance(self: *Self) void {
        if (self.pos < self.format.len) {
            self.pos += 1;
        }
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.format.len) {
            const c = self.format[self.pos];
            if (c != ' ' and c != '\t' and c != ',' and c != ':') break;
            self.pos += 1;
        }
    }

    /// Count items until endchar
    fn countFormat(self: *Self, endchar: u8) BuildError!usize {
        var count: usize = 0;
        var level: usize = 0;
        const start = self.pos;

        while (self.pos < self.format.len) {
            const c = self.format[self.pos];

            if (level == 0 and c == endchar) {
                self.pos = start;
                return count;
            }

            switch (c) {
                '(', '[', '{' => {
                    if (level == 0) count += 1;
                    level += 1;
                },
                ')', ']', '}' => {
                    if (level == 0) {
                        self.pos = start;
                        return BuildError.InvalidFormat;
                    }
                    level -= 1;
                },
                '#', '&', ',', ':', ' ', '\t' => {},
                else => {
                    if (level == 0) count += 1;
                },
            }
            self.pos += 1;
        }

        self.pos = start;
        return BuildError.InvalidFormat;
    }

    /// Build a single value from format and arguments
    pub fn buildOne(self: *Self, args: *ArgIterator) BuildError!?BuiltValue {
        self.skipWhitespace();
        const c = self.peek() orelse return null;

        switch (c) {
            ')', ']', '}' => return null,
            '(' => return self.buildTuple(args),
            '[' => return self.buildList(args),
            '{' => return self.buildDict(args),
            else => {
                self.advance();
                return self.buildSimple(c, args);
            },
        }
    }

    fn buildSimple(self: *Self, c: u8, args: *ArgIterator) BuildError!BuiltValue {
        _ = self;
        return switch (c) {
            'N' => BuiltValue{ .none = {} },
            'p' => {
                const val = args.nextInt() orelse return BuildError.InvalidFormat;
                return if (val != 0) BuiltValue{ .bool_true = {} } else BuiltValue{ .bool_false = {} };
            },
            'b', 'B', 'h', 'H', 'i', 'I', 'n' => {
                const val = args.nextInt() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .int = val };
            },
            'l', 'L' => {
                const val = args.nextLong() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .int = val };
            },
            'k', 'K' => {
                const val = args.nextULong() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .uint = val };
            },
            'f', 'd' => {
                const val = args.nextDouble() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .float = val };
            },
            'c', 'C' => {
                const val = args.nextInt() orelse return BuildError.InvalidFormat;
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(@intCast(val), &buf) catch return BuildError.InvalidFormat;
                return BuiltValue{ .string = buf[0..len] };
            },
            's', 'z' => {
                const str = args.nextString() orelse {
                    if (c == 'z') return BuiltValue{ .none = {} };
                    return BuildError.InvalidFormat;
                };
                return BuiltValue{ .string = str };
            },
            'y' => {
                const str = args.nextString() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .bytes = str };
            },
            'u', 'U' => {
                const str = args.nextString() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .unicode = str };
            },
            'S' => {
                const str = args.nextString() orelse return BuildError.InvalidFormat;
                return BuiltValue{ .bytes = str };
            },
            'O' => {
                const obj = args.nextObject() orelse return BuildError.NullObject;
                return BuiltValue{ .object = obj };
            },
            else => BuildError.InvalidFormat,
        };
    }

    fn buildTuple(self: *Self, args: *ArgIterator) BuildError!BuiltValue {
        self.advance(); // skip '('
        const count = try self.countFormat(')');

        var items = std.ArrayList(BuiltValue).init(self.allocator);
        errdefer items.deinit();

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const value = try self.buildOne(args) orelse break;
            items.append(value) catch return BuildError.OutOfMemory;
        }

        self.skipWhitespace();
        if (self.peek() == ')') self.advance();

        return BuiltValue{ .tuple = items.toOwnedSlice() catch return BuildError.OutOfMemory };
    }

    fn buildList(self: *Self, args: *ArgIterator) BuildError!BuiltValue {
        self.advance(); // skip '['
        const count = try self.countFormat(']');

        var items = std.ArrayList(BuiltValue).init(self.allocator);
        errdefer items.deinit();

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const value = try self.buildOne(args) orelse break;
            items.append(value) catch return BuildError.OutOfMemory;
        }

        self.skipWhitespace();
        if (self.peek() == ']') self.advance();

        return BuiltValue{ .list = items.toOwnedSlice() catch return BuildError.OutOfMemory };
    }

    fn buildDict(self: *Self, args: *ArgIterator) BuildError!BuiltValue {
        self.advance(); // skip '{'
        const count = try self.countFormat('}');

        if (count % 2 != 0) {
            return BuildError.InvalidFormat;
        }

        var items = std.ArrayList(BuiltValue.KeyValue).init(self.allocator);
        errdefer items.deinit();

        var i: usize = 0;
        while (i < count) : (i += 2) {
            const key = try self.buildOne(args) orelse break;
            const value = try self.buildOne(args) orelse return BuildError.InvalidFormat;
            items.append(.{ .key = key, .value = value }) catch return BuildError.OutOfMemory;
        }

        self.skipWhitespace();
        if (self.peek() == '}') self.advance();

        return BuiltValue{ .dict = items.toOwnedSlice() catch return BuildError.OutOfMemory };
    }

    /// Build all values from format
    pub fn buildAll(self: *Self, args: *ArgIterator) BuildError![]BuiltValue {
        while (try self.buildOne(args)) |value| {
            self.values.append(value) catch return BuildError.OutOfMemory;
        }
        return self.values.toOwnedSlice() catch return BuildError.OutOfMemory;
    }
};

/// Iterator over variadic arguments (stub - would use actual va_list in C)
pub const ArgIterator = struct {
    int_args: []const i64,
    long_args: []const i64,
    ulong_args: []const u64,
    double_args: []const f64,
    string_args: []const []const u8,
    object_args: []const *anyopaque,
    int_pos: usize = 0,
    long_pos: usize = 0,
    ulong_pos: usize = 0,
    double_pos: usize = 0,
    string_pos: usize = 0,
    object_pos: usize = 0,

    const Self = @This();

    pub fn initEmpty() Self {
        return .{
            .int_args = &.{},
            .long_args = &.{},
            .ulong_args = &.{},
            .double_args = &.{},
            .string_args = &.{},
            .object_args = &.{},
        };
    }

    pub fn nextInt(self: *Self) ?i64 {
        if (self.int_pos < self.int_args.len) {
            const val = self.int_args[self.int_pos];
            self.int_pos += 1;
            return val;
        }
        return null;
    }

    pub fn nextLong(self: *Self) ?i64 {
        if (self.long_pos < self.long_args.len) {
            const val = self.long_args[self.long_pos];
            self.long_pos += 1;
            return val;
        }
        return null;
    }

    pub fn nextULong(self: *Self) ?u64 {
        if (self.ulong_pos < self.ulong_args.len) {
            const val = self.ulong_args[self.ulong_pos];
            self.ulong_pos += 1;
            return val;
        }
        return null;
    }

    pub fn nextDouble(self: *Self) ?f64 {
        if (self.double_pos < self.double_args.len) {
            const val = self.double_args[self.double_pos];
            self.double_pos += 1;
            return val;
        }
        return null;
    }

    pub fn nextString(self: *Self) ?[]const u8 {
        if (self.string_pos < self.string_args.len) {
            const val = self.string_args[self.string_pos];
            self.string_pos += 1;
            return val;
        }
        return null;
    }

    pub fn nextObject(self: *Self) ?*anyopaque {
        if (self.object_pos < self.object_args.len) {
            const val = self.object_args[self.object_pos];
            self.object_pos += 1;
            return val;
        }
        return null;
    }
};

/// Module definition for extension modules
pub const ModuleDef = struct {
    name: []const u8,
    doc: ?[]const u8,
    size: isize, // -1 for single-phase init
    methods: ?[]const MethodDef,
    slots: ?[]const ModuleSlot,
    traverse: ?*const fn (*anyopaque, *anyopaque) callconv(.C) c_int,
    clear: ?*const fn (*anyopaque) callconv(.C) c_int,
    free: ?*const fn (*anyopaque) callconv(.C) void,
};

/// Method definition
pub const MethodDef = struct {
    name: []const u8,
    func: *const anyopaque,
    flags: MethodFlags,
    doc: ?[]const u8,

    pub const MethodFlags = packed struct {
        varargs: bool = false,
        keywords: bool = false,
        noargs: bool = false,
        o: bool = false, // single object argument
        class: bool = false,
        static: bool = false,
        coexist: bool = false,
        fastcall: bool = false,
        _padding: u8 = 0,
    };

    pub const METH_VARARGS: u16 = 0x0001;
    pub const METH_KEYWORDS: u16 = 0x0002;
    pub const METH_NOARGS: u16 = 0x0004;
    pub const METH_O: u16 = 0x0008;
    pub const METH_CLASS: u16 = 0x0010;
    pub const METH_STATIC: u16 = 0x0020;
    pub const METH_COEXIST: u16 = 0x0040;
    pub const METH_FASTCALL: u16 = 0x0080;
};

/// Module slot for multi-phase initialization
pub const ModuleSlot = struct {
    slot: SlotId,
    value: *anyopaque,

    pub const SlotId = enum(c_int) {
        Py_mod_create = 1,
        Py_mod_exec = 2,
        Py_mod_multiple_interpreters = 3,
        Py_mod_gil = 4,
    };
};

/// Module state for extension modules
pub const ModuleState = struct {
    module: ?*anyopaque,
    dict: ?*anyopaque,
    name: []const u8,
    doc: ?[]const u8,
    def: ?*const ModuleDef,
    state: ?*anyopaque,
    weaklist: ?*anyopaque,
    index: isize,
};

/// Add an object to a module's dict
pub fn moduleAddObject(
    module: *anyopaque,
    name: []const u8,
    value: *anyopaque,
) !void {
    _ = module;
    _ = name;
    _ = value;
    // Would call PyModule_AddObjectRef
}

/// Add an object ref to a module (increments refcount)
pub fn moduleAddObjectRef(
    module: *anyopaque,
    name: []const u8,
    value: *anyopaque,
) !void {
    _ = module;
    _ = name;
    _ = value;
    // Would call PyModule_AddObjectRef and incref
}

/// Add an integer constant to a module
pub fn moduleAddIntConstant(
    module: *anyopaque,
    name: []const u8,
    value: i64,
) !void {
    _ = module;
    _ = name;
    _ = value;
    // Would create PyLong and add to module
}

/// Add a string constant to a module
pub fn moduleAddStringConstant(
    module: *anyopaque,
    name: []const u8,
    value: []const u8,
) !void {
    _ = module;
    _ = name;
    _ = value;
    // Would create PyUnicode and add to module
}

/// Add a type to a module
pub fn moduleAddType(
    module: *anyopaque,
    type_obj: *anyopaque,
) !void {
    _ = module;
    _ = type_obj;
    // Would call PyType_Ready and add to module
}

/// Create a new module from definition
pub fn moduleCreate(def: *const ModuleDef) !*anyopaque {
    _ = def;
    // Would allocate and initialize module object
    return error.NotImplemented;
}

/// Multi-phase module initialization
pub fn moduleExecDef(module: *anyopaque, def: *const ModuleDef) !void {
    _ = module;
    _ = def;
    // Would execute module slots
}

/// Get module state
pub fn moduleGetState(module: *anyopaque) ?*anyopaque {
    _ = module;
    return null;
}

/// Get module definition
pub fn moduleGetDef(module: *anyopaque) ?*const ModuleDef {
    _ = module;
    return null;
}

/// Get module dict
pub fn moduleGetDict(module: *anyopaque) ?*anyopaque {
    _ = module;
    return null;
}

/// Get module name
pub fn moduleGetName(module: *anyopaque) ?[]const u8 {
    _ = module;
    return null;
}

/// Convert optional to ssize_t
pub fn convertOptionalToSsizeT(obj: ?*anyopaque) ?isize {
    if (obj == null) return null;
    // Would check if None and convert
    return 0;
}

/// Convert optional to non-negative ssize_t
pub fn convertOptionalToNonNegativeSsizeT(obj: ?*anyopaque) !?isize {
    const value = convertOptionalToSsizeT(obj) orelse return null;
    if (value < 0) {
        return error.ValueError;
    }
    return value;
}

/// GIL state for module operations
pub const GILState = enum {
    locked,
    unlocked,
};

/// Ensure GIL is held for module operations
pub fn ensureGIL() GILState {
    return .locked;
}

/// Release GIL
pub fn releaseGIL(state: GILState) void {
    _ = state;
}

/// Module initialization guard
pub const InitGuard = struct {
    initialized: bool = false,
    module: ?*anyopaque = null,

    pub fn acquire(self: *InitGuard) bool {
        if (self.initialized) return false;
        self.initialized = true;
        return true;
    }

    pub fn release(self: *InitGuard) void {
        self.initialized = false;
        self.module = null;
    }
};

/// Extension module registry
pub const ModuleRegistry = struct {
    modules: hashmap_helper.StringHashMap(*anyopaque),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .modules = hashmap_helper.StringHashMap(*anyopaque).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.modules.deinit();
    }

    pub fn register(self: *Self, name: []const u8, module: *anyopaque) !void {
        try self.modules.put(name, module);
    }

    pub fn lookup(self: *Self, name: []const u8) ?*anyopaque {
        return self.modules.get(name);
    }

    pub fn unregister(self: *Self, name: []const u8) void {
        _ = self.modules.remove(name);
    }
};

// Thread-local module registry
threadlocal var module_registry: ?ModuleRegistry = null;

pub fn getModuleRegistry(allocator: std.mem.Allocator) *ModuleRegistry {
    if (module_registry == null) {
        module_registry = ModuleRegistry.init(allocator);
    }
    return &module_registry.?;
}

/// Initialize module support
pub fn init() void {
    // Initialize any global state
}

/// Finalize module support
pub fn fini() void {
    if (module_registry) |*reg| {
        reg.deinit();
        module_registry = null;
    }
}

// Tests
test "value builder simple" {
    const allocator = std.testing.allocator;
    var builder = ValueBuilder.init(allocator, "i");
    defer builder.deinit();

    var args = ArgIterator{
        .int_args = &[_]i64{42},
        .long_args = &.{},
        .ulong_args = &.{},
        .double_args = &.{},
        .string_args = &.{},
        .object_args = &.{},
    };

    const value = try builder.buildOne(&args);
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(i64, 42), value.?.int);
}

test "value builder tuple" {
    const allocator = std.testing.allocator;
    var builder = ValueBuilder.init(allocator, "(ii)");
    defer builder.deinit();

    var args = ArgIterator{
        .int_args = &[_]i64{ 1, 2 },
        .long_args = &.{},
        .ulong_args = &.{},
        .double_args = &.{},
        .string_args = &.{},
        .object_args = &.{},
    };

    const value = try builder.buildOne(&args);
    try std.testing.expect(value != null);
    const tuple = value.?.tuple;
    defer allocator.free(tuple);
    try std.testing.expectEqual(@as(usize, 2), tuple.len);
}

test "method flags" {
    const flags = MethodDef.MethodFlags{
        .varargs = true,
        .keywords = true,
    };
    try std.testing.expect(flags.varargs);
    try std.testing.expect(flags.keywords);
    try std.testing.expect(!flags.noargs);
}

test "module registry" {
    const allocator = std.testing.allocator;
    var registry = ModuleRegistry.init(allocator);
    defer registry.deinit();

    var dummy: u8 = 0;
    try registry.register("test_module", &dummy);

    const found = registry.lookup("test_module");
    try std.testing.expect(found != null);

    const not_found = registry.lookup("nonexistent");
    try std.testing.expect(not_found == null);
}
