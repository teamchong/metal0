//! test.test_tools.test_freeze - Freeze tool testing
//! Tests for Python's freeze functionality which creates standalone executables
//! by bundling Python bytecode and the interpreter.

const std = @import("std");

/// Represents a frozen module entry
pub const FrozenModule = struct {
    name: []const u8,
    code: []const u8,
    size: usize,
    is_package: bool = false,
    get_code: ?*const fn () []const u8 = null,

    pub fn init(name: []const u8, code: []const u8, is_package: bool) FrozenModule {
        return .{
            .name = name,
            .code = code,
            .size = code.len,
            .is_package = is_package,
        };
    }

    pub fn getCode(self: FrozenModule) []const u8 {
        if (self.get_code) |getter| {
            return getter();
        }
        return self.code;
    }

    pub fn isBuiltin(self: FrozenModule) bool {
        return std.mem.startsWith(u8, self.name, "_") or
            std.mem.eql(u8, self.name, "builtins") or
            std.mem.eql(u8, self.name, "sys");
    }
};

/// Registry of frozen modules
pub const FrozenRegistry = struct {
    allocator: std.mem.Allocator,
    modules: std.StringHashMap(FrozenModule),
    search_order: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) FrozenRegistry {
        return .{
            .allocator = allocator,
            .modules = std.StringHashMap(FrozenModule).init(allocator),
            .search_order = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *FrozenRegistry) void {
        self.modules.deinit();
        self.search_order.deinit();
    }

    pub fn register(self: *FrozenRegistry, module: FrozenModule) !void {
        try self.modules.put(module.name, module);
        try self.search_order.append(module.name);
    }

    pub fn find(self: FrozenRegistry, name: []const u8) ?FrozenModule {
        return self.modules.get(name);
    }

    pub fn count(self: FrozenRegistry) usize {
        return self.modules.count();
    }

    pub fn contains(self: FrozenRegistry, name: []const u8) bool {
        return self.modules.contains(name);
    }

    pub fn getPackageModules(self: FrozenRegistry, package: []const u8) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        errdefer result.deinit();

        var iter = self.modules.iterator();
        while (iter.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, package) and
                entry.key_ptr.*.len > package.len and
                entry.key_ptr.*[package.len] == '.')
            {
                try result.append(entry.key_ptr.*);
            }
        }

        return result.toOwnedSlice();
    }
};

/// Module finder for frozen modules (PEP 302 compatible)
pub const FrozenImporter = struct {
    registry: *FrozenRegistry,

    pub fn init(registry: *FrozenRegistry) FrozenImporter {
        return .{ .registry = registry };
    }

    pub fn findModule(self: FrozenImporter, fullname: []const u8, path: ?[]const u8) ?FrozenModule {
        _ = path;
        return self.registry.find(fullname);
    }

    pub fn loadModule(self: FrozenImporter, fullname: []const u8) !LoadedModule {
        const frozen = self.registry.find(fullname) orelse return error.ModuleNotFound;
        return LoadedModule{
            .name = fullname,
            .code = frozen.getCode(),
            .is_package = frozen.is_package,
            .filename = if (frozen.is_package) "<frozen package>" else "<frozen>",
        };
    }

    pub const LoadedModule = struct {
        name: []const u8,
        code: []const u8,
        is_package: bool,
        filename: []const u8,
    };
};

/// Bytecode marshaling utilities
pub const Marshal = struct {
    pub const TYPE_CODE: u8 = 'c';
    pub const TYPE_STRING: u8 = 's';
    pub const TYPE_TUPLE: u8 = '(';
    pub const TYPE_LIST: u8 = '[';
    pub const TYPE_DICT: u8 = '{';
    pub const TYPE_NONE: u8 = 'N';
    pub const TYPE_INT: u8 = 'i';
    pub const TYPE_FLOAT: u8 = 'f';
    pub const TYPE_LONG: u8 = 'l';
    pub const TYPE_TRUE: u8 = 'T';
    pub const TYPE_FALSE: u8 = 'F';

    pub const FLAG_REF: u8 = 0x80;

    pub fn readLong(data: []const u8) !struct { value: i32, consumed: usize } {
        if (data.len < 4) return error.UnexpectedEof;
        const value = std.mem.readInt(i32, data[0..4], .little);
        return .{ .value = value, .consumed = 4 };
    }

    pub fn writeLong(value: i32) [4]u8 {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(i32, &buf, value, .little);
        return buf;
    }

    pub fn readString(data: []const u8) !struct { value: []const u8, consumed: usize } {
        const len_result = try readLong(data);
        const len: usize = @intCast(len_result.value);
        if (data.len < len_result.consumed + len) return error.UnexpectedEof;
        return .{
            .value = data[len_result.consumed .. len_result.consumed + len],
            .consumed = len_result.consumed + len,
        };
    }

    pub fn getType(type_byte: u8) u8 {
        return type_byte & ~FLAG_REF;
    }

    pub fn hasRef(type_byte: u8) bool {
        return (type_byte & FLAG_REF) != 0;
    }
};

/// Python bytecode magic number handling
pub const PyMagic = struct {
    pub const MAGIC_3_11: u32 = 0x0A0D_0D0A; // Python 3.11
    pub const MAGIC_3_10: u32 = 0x0A0D_0D0A; // Python 3.10
    pub const MAGIC_3_9: u32 = 0x0A0D_0D0A; // Python 3.9

    magic: u32,
    bit_field: u32,
    timestamp: u32,
    source_size: u32,

    pub fn parse(data: []const u8) !PyMagic {
        if (data.len < 16) return error.InvalidHeader;
        return .{
            .magic = std.mem.readInt(u32, data[0..4], .little),
            .bit_field = std.mem.readInt(u32, data[4..8], .little),
            .timestamp = std.mem.readInt(u32, data[8..12], .little),
            .source_size = std.mem.readInt(u32, data[12..16], .little),
        };
    }

    pub fn isValid(self: PyMagic) bool {
        return (self.magic & 0xFFFF) == 0x0D0A;
    }

    pub fn majorVersion(self: PyMagic) u8 {
        return @intCast((self.magic >> 16) / 100);
    }

    pub fn minorVersion(self: PyMagic) u8 {
        return @intCast((self.magic >> 16) % 100);
    }
};

/// Freeze configuration options
pub const FreezeConfig = struct {
    output_path: []const u8 = "frozen_modules.h",
    variable_name: []const u8 = "PyImport_FrozenModules",
    include_stdlib: bool = true,
    compress: bool = false,
    optimize_level: u8 = 0,
    exclude_patterns: []const []const u8 = &.{},
    include_patterns: []const []const u8 = &.{},

    pub fn shouldInclude(self: FreezeConfig, name: []const u8) bool {
        // Check exclusions first
        for (self.exclude_patterns) |pattern| {
            if (matchPattern(name, pattern)) {
                return false;
            }
        }

        // If include patterns specified, must match one
        if (self.include_patterns.len > 0) {
            for (self.include_patterns) |pattern| {
                if (matchPattern(name, pattern)) {
                    return true;
                }
            }
            return false;
        }

        return true;
    }

    fn matchPattern(name: []const u8, pattern: []const u8) bool {
        if (std.mem.indexOf(u8, pattern, "*")) |star_idx| {
            const prefix = pattern[0..star_idx];
            const suffix = pattern[star_idx + 1 ..];
            return std.mem.startsWith(u8, name, prefix) and
                std.mem.endsWith(u8, name, suffix);
        }
        return std.mem.eql(u8, name, pattern);
    }
};

/// Code object structure (simplified)
pub const CodeObject = struct {
    argcount: u32,
    posonlyargcount: u32,
    kwonlyargcount: u32,
    nlocals: u32,
    stacksize: u32,
    flags: u32,
    code: []const u8,
    consts: []const Const,
    names: []const []const u8,
    varnames: []const []const u8,
    filename: []const u8,
    name: []const u8,
    firstlineno: u32,
    linetable: []const u8,

    pub const Const = union(enum) {
        none,
        true_val,
        false_val,
        int: i64,
        float: f64,
        string: []const u8,
        bytes: []const u8,
        tuple: []const Const,
        code: *const CodeObject,
    };

    pub const Flags = struct {
        pub const OPTIMIZED: u32 = 0x0001;
        pub const NEWLOCALS: u32 = 0x0002;
        pub const VARARGS: u32 = 0x0004;
        pub const VARKEYWORDS: u32 = 0x0008;
        pub const NESTED: u32 = 0x0010;
        pub const GENERATOR: u32 = 0x0020;
        pub const NOFREE: u32 = 0x0040;
        pub const COROUTINE: u32 = 0x0080;
        pub const ITERABLE_COROUTINE: u32 = 0x0100;
        pub const ASYNC_GENERATOR: u32 = 0x0200;
    };

    pub fn isGenerator(self: CodeObject) bool {
        return (self.flags & Flags.GENERATOR) != 0;
    }

    pub fn isCoroutine(self: CodeObject) bool {
        return (self.flags & Flags.COROUTINE) != 0;
    }

    pub fn hasVarargs(self: CodeObject) bool {
        return (self.flags & Flags.VARARGS) != 0;
    }

    pub fn hasVarkeywords(self: CodeObject) bool {
        return (self.flags & Flags.VARKEYWORDS) != 0;
    }
};

/// Freeze analysis - analyzes dependencies
pub const DependencyAnalyzer = struct {
    allocator: std.mem.Allocator,
    dependencies: std.StringHashMap(std.StringHashMap(void)),
    visited: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) DependencyAnalyzer {
        return .{
            .allocator = allocator,
            .dependencies = std.StringHashMap(std.StringHashMap(void)).init(allocator),
            .visited = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *DependencyAnalyzer) void {
        var iter = self.dependencies.valueIterator();
        while (iter.next()) |val| {
            var v = val;
            v.deinit();
        }
        self.dependencies.deinit();
        self.visited.deinit();
    }

    pub fn addDependency(self: *DependencyAnalyzer, module: []const u8, depends_on: []const u8) !void {
        const result = try self.dependencies.getOrPut(module);
        if (!result.found_existing) {
            result.value_ptr.* = std.StringHashMap(void).init(self.allocator);
        }
        try result.value_ptr.put(depends_on, {});
    }

    pub fn getDependencies(self: DependencyAnalyzer, module: []const u8) ?[]const []const u8 {
        if (self.dependencies.get(module)) |deps| {
            var result = std.ArrayList([]const u8).init(self.allocator);
            var iter = deps.keyIterator();
            while (iter.next()) |key| {
                result.append(key.*) catch return null;
            }
            return result.toOwnedSlice() catch null;
        }
        return null;
    }

    pub fn hasCycle(self: *DependencyAnalyzer, module: []const u8) bool {
        return self.detectCycle(module, std.StringHashMap(void).init(self.allocator));
    }

    fn detectCycle(self: *DependencyAnalyzer, module: []const u8, path: std.StringHashMap(void)) bool {
        var current_path = path;
        if (current_path.contains(module)) {
            return true;
        }
        current_path.put(module, {}) catch return false;

        if (self.dependencies.get(module)) |deps| {
            var iter = deps.keyIterator();
            while (iter.next()) |dep| {
                if (self.detectCycle(dep.*, current_path)) {
                    return true;
                }
            }
        }

        _ = current_path.remove(module);
        return false;
    }
};

/// Output generator for frozen modules
pub const FreezeOutput = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) FreezeOutput {
        return .{
            .allocator = allocator,
            .output = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *FreezeOutput) void {
        self.output.deinit();
    }

    pub fn generateHeader(self: *FreezeOutput, modules: []const FrozenModule) ![]u8 {
        try self.output.appendSlice("/* Auto-generated frozen modules */\n\n");
        try self.output.appendSlice("#include \"Python.h\"\n\n");

        // Generate extern declarations
        for (modules) |module| {
            try self.output.appendSlice("extern unsigned char _Py_M__");
            try self.output.appendSlice(sanitizeName(module.name));
            try self.output.appendSlice("[];\n");
        }

        try self.output.appendSlice("\nstatic struct _frozen _PyImport_FrozenModules[] = {\n");

        for (modules) |module| {
            try self.output.appendSlice("    {\"");
            try self.output.appendSlice(module.name);
            try self.output.appendSlice("\", _Py_M__");
            try self.output.appendSlice(sanitizeName(module.name));
            try self.output.appendSlice(", ");

            var buf: [16]u8 = undefined;
            const size_str = std.fmt.bufPrint(&buf, "{d}", .{module.size}) catch "0";
            if (module.is_package) {
                try self.output.append('-');
            }
            try self.output.appendSlice(size_str);
            try self.output.appendSlice("},\n");
        }

        try self.output.appendSlice("    {0, 0, 0}\n};\n");

        return self.output.toOwnedSlice();
    }

    fn sanitizeName(name: []const u8) []const u8 {
        // In real implementation, replace dots with underscores
        return name;
    }
};

// Tests
test "frozen_module_basic" {
    const module = FrozenModule.init("test_module", "print('hello')", false);
    try std.testing.expectEqualStrings("test_module", module.name);
    try std.testing.expectEqual(@as(usize, 14), module.size);
    try std.testing.expect(!module.is_package);
}

test "frozen_module_builtin" {
    const builtin = FrozenModule.init("_collections", "", false);
    try std.testing.expect(builtin.isBuiltin());

    const user = FrozenModule.init("mymodule", "", false);
    try std.testing.expect(!user.isBuiltin());
}

test "frozen_registry" {
    var registry = FrozenRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(FrozenModule.init("os", "os_code", false));
    try registry.register(FrozenModule.init("os.path", "path_code", false));
    try registry.register(FrozenModule.init("sys", "sys_code", false));

    try std.testing.expect(registry.contains("os"));
    try std.testing.expect(registry.contains("sys"));
    try std.testing.expectEqual(@as(usize, 3), registry.count());

    const pkg_modules = try registry.getPackageModules("os");
    defer std.testing.allocator.free(pkg_modules);
    try std.testing.expectEqual(@as(usize, 1), pkg_modules.len);
}

test "frozen_importer" {
    var registry = FrozenRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(FrozenModule.init("json", "json_code", true));

    var importer = FrozenImporter.init(&registry);
    const module = try importer.loadModule("json");

    try std.testing.expectEqualStrings("json", module.name);
    try std.testing.expect(module.is_package);
}

test "marshal_long" {
    const written = Marshal.writeLong(12345);
    const read = try Marshal.readLong(&written);
    try std.testing.expectEqual(@as(i32, 12345), read.value);
    try std.testing.expectEqual(@as(usize, 4), read.consumed);
}

test "marshal_string" {
    var buf: [16]u8 = undefined;
    const len_bytes = Marshal.writeLong(5);
    @memcpy(buf[0..4], &len_bytes);
    @memcpy(buf[4..9], "hello");

    const result = try Marshal.readString(&buf);
    try std.testing.expectEqualStrings("hello", result.value);
    try std.testing.expectEqual(@as(usize, 9), result.consumed);
}

test "marshal_types" {
    try std.testing.expectEqual(@as(u8, 'c'), Marshal.getType('c'));
    try std.testing.expectEqual(@as(u8, 's'), Marshal.getType('s' | Marshal.FLAG_REF));
    try std.testing.expect(!Marshal.hasRef('N'));
    try std.testing.expect(Marshal.hasRef('N' | Marshal.FLAG_REF));
}

test "pymagic_parse" {
    var header: [16]u8 = undefined;
    std.mem.writeInt(u32, header[0..4], 0x0A0D_0D0A, .little);
    std.mem.writeInt(u32, header[4..8], 0, .little);
    std.mem.writeInt(u32, header[8..12], 1234567890, .little);
    std.mem.writeInt(u32, header[12..16], 1024, .little);

    const magic = try PyMagic.parse(&header);
    try std.testing.expect(magic.isValid());
}

test "freeze_config" {
    const config = FreezeConfig{
        .exclude_patterns = &[_][]const u8{"test_*"},
        .include_patterns = &[_][]const u8{},
    };

    try std.testing.expect(config.shouldInclude("json"));
    try std.testing.expect(!config.shouldInclude("test_json"));
}

test "code_object_flags" {
    const code = CodeObject{
        .argcount = 0,
        .posonlyargcount = 0,
        .kwonlyargcount = 0,
        .nlocals = 0,
        .stacksize = 1,
        .flags = CodeObject.Flags.GENERATOR | CodeObject.Flags.VARARGS,
        .code = "",
        .consts = &.{},
        .names = &.{},
        .varnames = &.{},
        .filename = "test.py",
        .name = "test",
        .firstlineno = 1,
        .linetable = "",
    };

    try std.testing.expect(code.isGenerator());
    try std.testing.expect(!code.isCoroutine());
    try std.testing.expect(code.hasVarargs());
}

test "dependency_analyzer" {
    var analyzer = DependencyAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();

    try analyzer.addDependency("json", "codecs");
    try analyzer.addDependency("json", "re");
    try analyzer.addDependency("re", "sre_parse");

    const deps = analyzer.getDependencies("json");
    try std.testing.expect(deps != null);
    defer std.testing.allocator.free(deps.?);
    try std.testing.expectEqual(@as(usize, 2), deps.?.len);
}

test "freeze_output" {
    var output = FreezeOutput.init(std.testing.allocator);
    defer output.deinit();

    const modules = [_]FrozenModule{
        FrozenModule.init("sys", "sys_code", false),
        FrozenModule.init("os", "os_code", true),
    };

    const header = try output.generateHeader(&modules);
    defer std.testing.allocator.free(header);

    try std.testing.expect(std.mem.indexOf(u8, header, "_PyImport_FrozenModules") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "\"sys\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "\"os\"") != null);
}
