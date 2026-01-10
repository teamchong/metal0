//! test.test_tools.test_wasm - WebAssembly tools testing
//! Tests for Python's WebAssembly/Emscripten build tools and
//! browser integration utilities.

const std = @import("std");

/// WebAssembly module representation
pub const WasmModule = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    imports: std.ArrayList(Import),
    exports: std.ArrayList(Export),
    functions: std.ArrayList(Function),
    memories: std.ArrayList(Memory),
    tables: std.ArrayList(Table),
    globals: std.ArrayList(Global),

    pub const Import = struct {
        module: []const u8,
        name: []const u8,
        kind: ImportKind,

        pub const ImportKind = enum {
            function,
            table,
            memory,
            global,
        };
    };

    pub const Export = struct {
        name: []const u8,
        kind: ExportKind,
        index: u32,

        pub const ExportKind = enum {
            function,
            table,
            memory,
            global,
        };
    };

    pub const Function = struct {
        name: ?[]const u8,
        params: []const ValueType,
        results: []const ValueType,
        locals: []const ValueType = &.{},
        is_imported: bool = false,
    };

    pub const Memory = struct {
        min_pages: u32,
        max_pages: ?u32 = null,
        is_shared: bool = false,
    };

    pub const Table = struct {
        element_type: ElementType,
        min: u32,
        max: ?u32 = null,

        pub const ElementType = enum {
            funcref,
            externref,
        };
    };

    pub const Global = struct {
        value_type: ValueType,
        mutable: bool,
        init_value: ?i64 = null,
    };

    pub const ValueType = enum {
        i32,
        i64,
        f32,
        f64,
        v128,
        funcref,
        externref,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8) WasmModule {
        return .{
            .allocator = allocator,
            .name = name,
            .imports = std.ArrayList(Import).init(allocator),
            .exports = std.ArrayList(Export).init(allocator),
            .functions = std.ArrayList(Function).init(allocator),
            .memories = std.ArrayList(Memory).init(allocator),
            .tables = std.ArrayList(Table).init(allocator),
            .globals = std.ArrayList(Global).init(allocator),
        };
    }

    pub fn deinit(self: *WasmModule) void {
        self.imports.deinit();
        self.exports.deinit();
        self.functions.deinit();
        self.memories.deinit();
        self.tables.deinit();
        self.globals.deinit();
    }

    pub fn addImport(self: *WasmModule, import: Import) !void {
        try self.imports.append(import);
    }

    pub fn addExport(self: *WasmModule, export: Export) !void {
        try self.exports.append(export);
    }

    pub fn addFunction(self: *WasmModule, func: Function) !void {
        try self.functions.append(func);
    }

    pub fn getExport(self: WasmModule, name: []const u8) ?Export {
        for (self.exports.items) |exp| {
            if (std.mem.eql(u8, exp.name, name)) return exp;
        }
        return null;
    }

    pub fn hasExport(self: WasmModule, name: []const u8) bool {
        return self.getExport(name) != null;
    }

    pub fn importCount(self: WasmModule) usize {
        return self.imports.items.len;
    }

    pub fn exportCount(self: WasmModule) usize {
        return self.exports.items.len;
    }
};

/// Emscripten configuration
pub const EmscriptenConfig = struct {
    allocator: std.mem.Allocator,
    optimization_level: u8 = 2,
    debug_level: u8 = 0,
    memory_size: usize = 16 * 1024 * 1024, // 16MB
    stack_size: usize = 64 * 1024, // 64KB
    allow_memory_growth: bool = true,
    modularize: bool = true,
    export_name: []const u8 = "Module",
    exported_functions: std.ArrayList([]const u8),
    exported_runtime_methods: std.ArrayList([]const u8),
    pre_js: ?[]const u8 = null,
    post_js: ?[]const u8 = null,
    shell_file: ?[]const u8 = null,
    use_pthreads: bool = false,
    environment: Environment = .web,

    pub const Environment = enum {
        web,
        node,
        worker,
        shell,
    };

    pub fn init(allocator: std.mem.Allocator) EmscriptenConfig {
        return .{
            .allocator = allocator,
            .exported_functions = std.ArrayList([]const u8).init(allocator),
            .exported_runtime_methods = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *EmscriptenConfig) void {
        self.exported_functions.deinit();
        self.exported_runtime_methods.deinit();
    }

    pub fn addExportedFunction(self: *EmscriptenConfig, func: []const u8) !void {
        try self.exported_functions.append(func);
    }

    pub fn addExportedRuntimeMethod(self: *EmscriptenConfig, method: []const u8) !void {
        try self.exported_runtime_methods.append(method);
    }

    pub fn getFlags(self: EmscriptenConfig, allocator: std.mem.Allocator) ![]u8 {
        var flags = std.ArrayList(u8).init(allocator);
        errdefer flags.deinit();

        var buf: [32]u8 = undefined;

        // Optimization
        const opt_str = std.fmt.bufPrint(&buf, "-O{d} ", .{self.optimization_level}) catch "-O2 ";
        try flags.appendSlice(opt_str);

        // Debug
        if (self.debug_level > 0) {
            const dbg_str = std.fmt.bufPrint(&buf, "-g{d} ", .{self.debug_level}) catch "-g ";
            try flags.appendSlice(dbg_str);
        }

        // Memory
        const mem_str = std.fmt.bufPrint(&buf, "-sINITIAL_MEMORY={d} ", .{self.memory_size}) catch "";
        try flags.appendSlice(mem_str);

        if (self.allow_memory_growth) {
            try flags.appendSlice("-sALLOW_MEMORY_GROWTH=1 ");
        }

        if (self.modularize) {
            try flags.appendSlice("-sMODULARIZE=1 ");
        }

        if (self.use_pthreads) {
            try flags.appendSlice("-pthread ");
        }

        return flags.toOwnedSlice();
    }

    pub fn getEnvironmentFlag(self: EmscriptenConfig) []const u8 {
        return switch (self.environment) {
            .web => "-sENVIRONMENT=web",
            .node => "-sENVIRONMENT=node",
            .worker => "-sENVIRONMENT=worker",
            .shell => "-sENVIRONMENT=shell",
        };
    }
};

/// WASI configuration
pub const WASIConfig = struct {
    allocator: std.mem.Allocator,
    preopened_dirs: std.ArrayList(PreopenedDir),
    env_vars: std.StringHashMap([]const u8),
    args: std.ArrayList([]const u8),

    pub const PreopenedDir = struct {
        host_path: []const u8,
        guest_path: []const u8,
        readonly: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) WASIConfig {
        return .{
            .allocator = allocator,
            .preopened_dirs = std.ArrayList(PreopenedDir).init(allocator),
            .env_vars = std.StringHashMap([]const u8).init(allocator),
            .args = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *WASIConfig) void {
        self.preopened_dirs.deinit();
        self.env_vars.deinit();
        self.args.deinit();
    }

    pub fn addPreopenedDir(self: *WASIConfig, dir: PreopenedDir) !void {
        try self.preopened_dirs.append(dir);
    }

    pub fn setEnv(self: *WASIConfig, key: []const u8, value: []const u8) !void {
        try self.env_vars.put(key, value);
    }

    pub fn addArg(self: *WASIConfig, arg: []const u8) !void {
        try self.args.append(arg);
    }
};

/// JavaScript bridge for Python-WASM integration
pub const JSBridge = struct {
    allocator: std.mem.Allocator,
    bindings: std.StringHashMap(Binding),
    callbacks: std.ArrayList(Callback),

    pub const Binding = struct {
        name: []const u8,
        js_code: []const u8,
        param_types: []const ParamType,
        return_type: ?ParamType = null,

        pub const ParamType = enum {
            number,
            string,
            boolean,
            object,
            array,
            function,
            undefined_type,
            null_type,
        };
    };

    pub const Callback = struct {
        name: []const u8,
        signature: []const u8,
        handler: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator) JSBridge {
        return .{
            .allocator = allocator,
            .bindings = std.StringHashMap(Binding).init(allocator),
            .callbacks = std.ArrayList(Callback).init(allocator),
        };
    }

    pub fn deinit(self: *JSBridge) void {
        self.bindings.deinit();
        self.callbacks.deinit();
    }

    pub fn addBinding(self: *JSBridge, binding: Binding) !void {
        try self.bindings.put(binding.name, binding);
    }

    pub fn addCallback(self: *JSBridge, callback: Callback) !void {
        try self.callbacks.append(callback);
    }

    pub fn getBinding(self: JSBridge, name: []const u8) ?Binding {
        return self.bindings.get(name);
    }

    pub fn hasBinding(self: JSBridge, name: []const u8) bool {
        return self.bindings.contains(name);
    }

    pub fn bindingCount(self: JSBridge) usize {
        return self.bindings.count();
    }
};

/// Browser runtime environment
pub const BrowserRuntime = struct {
    allocator: std.mem.Allocator,
    supported_features: std.StringHashMap(bool),
    required_features: std.ArrayList([]const u8),

    pub const Feature = struct {
        pub const WASM_BASIC: []const u8 = "wasm";
        pub const WASM_THREADS: []const u8 = "wasm-threads";
        pub const WASM_SIMD: []const u8 = "wasm-simd";
        pub const WASM_EXCEPTIONS: []const u8 = "wasm-exceptions";
        pub const WASM_BULK_MEMORY: []const u8 = "wasm-bulk-memory";
        pub const SHARED_ARRAY_BUFFER: []const u8 = "shared-array-buffer";
        pub const BIGINT: []const u8 = "bigint";
    };

    pub fn init(allocator: std.mem.Allocator) BrowserRuntime {
        var self = BrowserRuntime{
            .allocator = allocator,
            .supported_features = std.StringHashMap(bool).init(allocator),
            .required_features = std.ArrayList([]const u8).init(allocator),
        };
        self.initDefaultFeatures() catch {};
        return self;
    }

    fn initDefaultFeatures(self: *BrowserRuntime) !void {
        try self.supported_features.put(Feature.WASM_BASIC, true);
        try self.supported_features.put(Feature.BIGINT, true);
    }

    pub fn deinit(self: *BrowserRuntime) void {
        self.supported_features.deinit();
        self.required_features.deinit();
    }

    pub fn setFeature(self: *BrowserRuntime, feature: []const u8, supported: bool) !void {
        try self.supported_features.put(feature, supported);
    }

    pub fn requireFeature(self: *BrowserRuntime, feature: []const u8) !void {
        try self.required_features.append(feature);
    }

    pub fn isFeatureSupported(self: BrowserRuntime, feature: []const u8) bool {
        return self.supported_features.get(feature) orelse false;
    }

    pub fn checkRequirements(self: BrowserRuntime) bool {
        for (self.required_features.items) |feature| {
            if (!self.isFeatureSupported(feature)) {
                return false;
            }
        }
        return true;
    }
};

/// WebAssembly binary builder
pub const WasmBuilder = struct {
    allocator: std.mem.Allocator,
    sections: std.ArrayList(Section),
    output: std.ArrayList(u8),

    pub const Section = struct {
        id: SectionId,
        data: []const u8,

        pub const SectionId = enum(u8) {
            custom = 0,
            type_section = 1,
            import = 2,
            function = 3,
            table = 4,
            memory = 5,
            global = 6,
            export = 7,
            start = 8,
            element = 9,
            code = 10,
            data = 11,
            data_count = 12,
        };
    };

    pub const MAGIC: [4]u8 = .{ 0x00, 0x61, 0x73, 0x6D }; // \0asm
    pub const VERSION: [4]u8 = .{ 0x01, 0x00, 0x00, 0x00 }; // version 1

    pub fn init(allocator: std.mem.Allocator) WasmBuilder {
        return .{
            .allocator = allocator,
            .sections = std.ArrayList(Section).init(allocator),
            .output = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *WasmBuilder) void {
        self.sections.deinit();
        self.output.deinit();
    }

    pub fn addSection(self: *WasmBuilder, section: Section) !void {
        try self.sections.append(section);
    }

    pub fn build(self: *WasmBuilder) ![]u8 {
        // Write magic and version
        try self.output.appendSlice(&MAGIC);
        try self.output.appendSlice(&VERSION);

        // Write sections
        for (self.sections.items) |section| {
            try self.output.append(@intFromEnum(section.id));
            // Write section size (simplified)
            try self.writeLEB128(@as(u32, @intCast(section.data.len)));
            try self.output.appendSlice(section.data);
        }

        return self.output.toOwnedSlice();
    }

    fn writeLEB128(self: *WasmBuilder, value: u32) !void {
        var v = value;
        while (true) {
            var byte: u8 = @intCast(v & 0x7F);
            v >>= 7;
            if (v != 0) {
                byte |= 0x80;
            }
            try self.output.append(byte);
            if (v == 0) break;
        }
    }

    pub fn getOutput(self: WasmBuilder) []const u8 {
        return self.output.items;
    }
};

/// Python/WASM integration testing
pub const WasmPythonTest = struct {
    allocator: std.mem.Allocator,
    test_cases: std.ArrayList(TestCase),
    results: std.ArrayList(TestResult),

    pub const TestCase = struct {
        name: []const u8,
        python_code: []const u8,
        expected_output: ?[]const u8 = null,
        expected_error: ?[]const u8 = null,
        timeout_ms: u32 = 30000,
    };

    pub const TestResult = struct {
        name: []const u8,
        passed: bool,
        output: ?[]const u8 = null,
        error_message: ?[]const u8 = null,
        duration_ms: u64,
    };

    pub fn init(allocator: std.mem.Allocator) WasmPythonTest {
        return .{
            .allocator = allocator,
            .test_cases = std.ArrayList(TestCase).init(allocator),
            .results = std.ArrayList(TestResult).init(allocator),
        };
    }

    pub fn deinit(self: *WasmPythonTest) void {
        self.test_cases.deinit();
        self.results.deinit();
    }

    pub fn addTest(self: *WasmPythonTest, test_case: TestCase) !void {
        try self.test_cases.append(test_case);
    }

    pub fn addResult(self: *WasmPythonTest, result: TestResult) !void {
        try self.results.append(result);
    }

    pub fn passedCount(self: WasmPythonTest) usize {
        var count: usize = 0;
        for (self.results.items) |result| {
            if (result.passed) count += 1;
        }
        return count;
    }

    pub fn failedCount(self: WasmPythonTest) usize {
        return self.results.items.len - self.passedCount();
    }

    pub fn allPassed(self: WasmPythonTest) bool {
        return self.failedCount() == 0 and self.results.items.len > 0;
    }
};

// Tests
test "wasm_module_basic" {
    var module = WasmModule.init(std.testing.allocator, "test_module");
    defer module.deinit();

    try module.addImport(.{
        .module = "env",
        .name = "memory",
        .kind = .memory,
    });

    try module.addExport(.{
        .name = "main",
        .kind = .function,
        .index = 0,
    });

    try std.testing.expectEqual(@as(usize, 1), module.importCount());
    try std.testing.expectEqual(@as(usize, 1), module.exportCount());
    try std.testing.expect(module.hasExport("main"));
}

test "wasm_module_functions" {
    var module = WasmModule.init(std.testing.allocator, "test");
    defer module.deinit();

    try module.addFunction(.{
        .name = "add",
        .params = &[_]WasmModule.ValueType{ .i32, .i32 },
        .results = &[_]WasmModule.ValueType{.i32},
    });

    try std.testing.expectEqual(@as(usize, 1), module.functions.items.len);
}

test "emscripten_config" {
    var config = EmscriptenConfig.init(std.testing.allocator);
    defer config.deinit();

    config.optimization_level = 3;
    config.memory_size = 32 * 1024 * 1024;
    config.allow_memory_growth = true;

    try config.addExportedFunction("_main");
    try config.addExportedFunction("_PyRun_SimpleString");

    const flags = try config.getFlags(std.testing.allocator);
    defer std.testing.allocator.free(flags);

    try std.testing.expect(std.mem.indexOf(u8, flags, "-O3") != null);
    try std.testing.expect(std.mem.indexOf(u8, flags, "ALLOW_MEMORY_GROWTH") != null);
}

test "emscripten_environment" {
    const config = EmscriptenConfig.init(std.testing.allocator);

    try std.testing.expectEqualStrings("-sENVIRONMENT=web", config.getEnvironmentFlag());
}

test "wasi_config" {
    var config = WASIConfig.init(std.testing.allocator);
    defer config.deinit();

    try config.addPreopenedDir(.{
        .host_path = "/tmp",
        .guest_path = "/tmp",
    });

    try config.setEnv("PYTHONPATH", "/lib/python");
    try config.addArg("--version");

    try std.testing.expectEqual(@as(usize, 1), config.preopened_dirs.items.len);
    try std.testing.expectEqual(@as(usize, 1), config.args.items.len);
}

test "js_bridge" {
    var bridge = JSBridge.init(std.testing.allocator);
    defer bridge.deinit();

    try bridge.addBinding(.{
        .name = "console_log",
        .js_code = "console.log",
        .param_types = &[_]JSBridge.Binding.ParamType{.string},
    });

    try bridge.addCallback(.{
        .name = "onReady",
        .signature = "() => void",
    });

    try std.testing.expect(bridge.hasBinding("console_log"));
    try std.testing.expectEqual(@as(usize, 1), bridge.bindingCount());
}

test "browser_runtime" {
    var runtime = BrowserRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    try std.testing.expect(runtime.isFeatureSupported(BrowserRuntime.Feature.WASM_BASIC));

    try runtime.requireFeature(BrowserRuntime.Feature.WASM_BASIC);
    try runtime.requireFeature(BrowserRuntime.Feature.BIGINT);

    try std.testing.expect(runtime.checkRequirements());

    try runtime.requireFeature(BrowserRuntime.Feature.WASM_THREADS);
    try std.testing.expect(!runtime.checkRequirements());
}

test "wasm_builder" {
    var builder = WasmBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addSection(.{
        .id = .type_section,
        .data = &[_]u8{ 0x01, 0x60, 0x00, 0x00 },
    });

    const output = try builder.build();
    defer std.testing.allocator.free(output);

    // Check magic number
    try std.testing.expectEqual(@as(u8, 0x00), output[0]);
    try std.testing.expectEqual(@as(u8, 0x61), output[1]);
    try std.testing.expectEqual(@as(u8, 0x73), output[2]);
    try std.testing.expectEqual(@as(u8, 0x6D), output[3]);
}

test "wasm_python_test" {
    var tester = WasmPythonTest.init(std.testing.allocator);
    defer tester.deinit();

    try tester.addTest(.{
        .name = "test_print",
        .python_code = "print('Hello, WASM!')",
        .expected_output = "Hello, WASM!\n",
    });

    try tester.addResult(.{
        .name = "test_print",
        .passed = true,
        .duration_ms = 100,
    });

    try tester.addResult(.{
        .name = "test_fail",
        .passed = false,
        .error_message = "Assertion failed",
        .duration_ms = 50,
    });

    try std.testing.expectEqual(@as(usize, 1), tester.passedCount());
    try std.testing.expectEqual(@as(usize, 1), tester.failedCount());
    try std.testing.expect(!tester.allPassed());
}
