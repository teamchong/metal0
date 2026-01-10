//! test.test_tools.test_build - Build scripts testing
//! Tests for Python's build system tools including configure, make,
//! and cross-compilation support.

const std = @import("std");

/// Build configuration options
pub const BuildConfig = struct {
    prefix: []const u8 = "/usr/local",
    exec_prefix: ?[]const u8 = null,
    build_type: BuildType = .release,
    enable_shared: bool = false,
    enable_static: bool = true,
    enable_optimizations: bool = true,
    enable_lto: bool = false,
    with_pydebug: bool = false,
    with_trace_refs: bool = false,
    with_assertions: bool = false,
    cross_compiling: bool = false,
    host: ?[]const u8 = null,
    build: ?[]const u8 = null,
    target: ?[]const u8 = null,

    pub const BuildType = enum {
        debug,
        release,
        release_with_debug,
        profile,
    };

    pub fn isDebug(self: BuildConfig) bool {
        return self.build_type == .debug or self.with_pydebug;
    }

    pub fn getOptimizationLevel(self: BuildConfig) u8 {
        return switch (self.build_type) {
            .debug => 0,
            .release => 3,
            .release_with_debug => 2,
            .profile => 2,
        };
    }

    pub fn getCFlags(self: BuildConfig, allocator: std.mem.Allocator) ![]u8 {
        var flags = std.ArrayList(u8).init(allocator);
        errdefer flags.deinit();

        if (self.isDebug()) {
            try flags.appendSlice("-g ");
        }

        var buf: [8]u8 = undefined;
        const opt_str = std.fmt.bufPrint(&buf, "-O{d} ", .{self.getOptimizationLevel()}) catch "-O2 ";
        try flags.appendSlice(opt_str);

        if (self.with_assertions) {
            try flags.appendSlice("-UNDEBUG ");
        } else {
            try flags.appendSlice("-DNDEBUG ");
        }

        if (self.enable_lto) {
            try flags.appendSlice("-flto ");
        }

        return flags.toOwnedSlice();
    }
};

/// Compiler detection and configuration
pub const Compiler = struct {
    name: CompilerType,
    version: Version,
    path: []const u8,
    supports_c11: bool = true,
    supports_c99: bool = true,

    pub const CompilerType = enum {
        gcc,
        clang,
        msvc,
        icc,
        unknown,
    };

    pub const Version = struct {
        major: u16,
        minor: u16,
        patch: u16 = 0,

        pub fn format(self: Version, allocator: std.mem.Allocator) ![]u8 {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}.{d}.{d}", .{
                self.major,
                self.minor,
                self.patch,
            }) catch "0.0.0";
            return allocator.dupe(u8, str);
        }

        pub fn atLeast(self: Version, major: u16, minor: u16) bool {
            if (self.major > major) return true;
            if (self.major == major and self.minor >= minor) return true;
            return false;
        }
    };

    pub fn supportsFlag(self: Compiler, flag: []const u8) bool {
        // Simulate flag checking
        if (std.mem.eql(u8, flag, "-flto")) {
            return self.version.atLeast(4, 5);
        }
        if (std.mem.eql(u8, flag, "-fstack-protector-strong")) {
            return self.name == .gcc and self.version.atLeast(4, 9);
        }
        return true;
    }

    pub fn isGccCompatible(self: Compiler) bool {
        return self.name == .gcc or self.name == .clang;
    }
};

/// Module configuration for extension modules
pub const ModuleConfig = struct {
    name: []const u8,
    sources: []const []const u8,
    include_dirs: []const []const u8 = &.{},
    library_dirs: []const []const u8 = &.{},
    libraries: []const []const u8 = &.{},
    extra_compile_args: []const []const u8 = &.{},
    extra_link_args: []const []const u8 = &.{},
    define_macros: []const Macro = &.{},
    undef_macros: []const []const u8 = &.{},
    depends: []const []const u8 = &.{},
    language: Language = .c,
    optional: bool = false,

    pub const Macro = struct {
        name: []const u8,
        value: ?[]const u8 = null,
    };

    pub const Language = enum {
        c,
        cpp,
    };

    pub fn sourceCount(self: ModuleConfig) usize {
        return self.sources.len;
    }

    pub fn hasLibrary(self: ModuleConfig, lib: []const u8) bool {
        for (self.libraries) |l| {
            if (std.mem.eql(u8, l, lib)) return true;
        }
        return false;
    }
};

/// Configure script generator
pub const ConfigureGenerator = struct {
    allocator: std.mem.Allocator,
    checks: std.ArrayList(Check),
    results: std.StringHashMap(CheckResult),

    pub const Check = struct {
        name: []const u8,
        kind: Kind,
        description: ?[]const u8 = null,

        pub const Kind = enum {
            header,
            function,
            type,
            struct_member,
            library,
            compiler_flag,
            program,
            sizeof,
        };
    };

    pub const CheckResult = struct {
        passed: bool,
        value: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator) ConfigureGenerator {
        return .{
            .allocator = allocator,
            .checks = std.ArrayList(Check).init(allocator),
            .results = std.StringHashMap(CheckResult).init(allocator),
        };
    }

    pub fn deinit(self: *ConfigureGenerator) void {
        self.checks.deinit();
        self.results.deinit();
    }

    pub fn addCheck(self: *ConfigureGenerator, check: Check) !void {
        try self.checks.append(check);
    }

    pub fn setResult(self: *ConfigureGenerator, name: []const u8, result: CheckResult) !void {
        try self.results.put(name, result);
    }

    pub fn hasHeader(self: ConfigureGenerator, header: []const u8) bool {
        if (self.results.get(header)) |result| {
            return result.passed;
        }
        return false;
    }

    pub fn hasFunction(self: ConfigureGenerator, func: []const u8) bool {
        if (self.results.get(func)) |result| {
            return result.passed;
        }
        return false;
    }

    pub fn getValue(self: ConfigureGenerator, name: []const u8) ?[]const u8 {
        if (self.results.get(name)) |result| {
            return result.value;
        }
        return null;
    }
};

/// Makefile generator
pub const MakefileGenerator = struct {
    allocator: std.mem.Allocator,
    variables: std.StringHashMap([]const u8),
    targets: std.ArrayList(Target),
    default_target: ?[]const u8 = null,

    pub const Target = struct {
        name: []const u8,
        dependencies: []const []const u8 = &.{},
        commands: []const []const u8 = &.{},
        phony: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) MakefileGenerator {
        return .{
            .allocator = allocator,
            .variables = std.StringHashMap([]const u8).init(allocator),
            .targets = std.ArrayList(Target).init(allocator),
        };
    }

    pub fn deinit(self: *MakefileGenerator) void {
        self.variables.deinit();
        self.targets.deinit();
    }

    pub fn setVariable(self: *MakefileGenerator, name: []const u8, value: []const u8) !void {
        try self.variables.put(name, value);
    }

    pub fn addTarget(self: *MakefileGenerator, target: Target) !void {
        try self.targets.append(target);
        if (self.default_target == null) {
            self.default_target = target.name;
        }
    }

    pub fn generate(self: MakefileGenerator, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        // Variables
        var var_iter = self.variables.iterator();
        while (var_iter.next()) |entry| {
            try result.appendSlice(entry.key_ptr.*);
            try result.appendSlice(" = ");
            try result.appendSlice(entry.value_ptr.*);
            try result.append('\n');
        }
        try result.append('\n');

        // Phony targets
        try result.appendSlice(".PHONY:");
        for (self.targets.items) |target| {
            if (target.phony) {
                try result.append(' ');
                try result.appendSlice(target.name);
            }
        }
        try result.appendSlice("\n\n");

        // Targets
        for (self.targets.items) |target| {
            try result.appendSlice(target.name);
            try result.append(':');
            for (target.dependencies) |dep| {
                try result.append(' ');
                try result.appendSlice(dep);
            }
            try result.append('\n');
            for (target.commands) |cmd| {
                try result.append('\t');
                try result.appendSlice(cmd);
                try result.append('\n');
            }
            try result.append('\n');
        }

        return result.toOwnedSlice();
    }
};

/// Cross-compilation configuration
pub const CrossCompileConfig = struct {
    host_triple: []const u8,
    target_triple: []const u8,
    sysroot: ?[]const u8 = null,
    toolchain_prefix: ?[]const u8 = null,
    cc: ?[]const u8 = null,
    cxx: ?[]const u8 = null,
    ar: ?[]const u8 = null,
    ranlib: ?[]const u8 = null,
    pkg_config: ?[]const u8 = null,

    pub fn getCC(self: CrossCompileConfig) []const u8 {
        if (self.cc) |cc| return cc;
        if (self.toolchain_prefix) |prefix| {
            // Would need allocation in real implementation
            _ = prefix;
            return "gcc";
        }
        return "gcc";
    }

    pub fn isCrossCompiling(self: CrossCompileConfig) bool {
        return !std.mem.eql(u8, self.host_triple, self.target_triple);
    }

    pub fn getTargetArch(self: CrossCompileConfig) ?[]const u8 {
        if (std.mem.indexOf(u8, self.target_triple, "-")) |idx| {
            return self.target_triple[0..idx];
        }
        return null;
    }

    pub fn getTargetOS(self: CrossCompileConfig) ?[]const u8 {
        var parts = std.mem.split(u8, self.target_triple, "-");
        _ = parts.next(); // arch
        _ = parts.next(); // vendor
        return parts.next(); // os
    }
};

/// Build dependency tracker
pub const DependencyTracker = struct {
    allocator: std.mem.Allocator,
    dependencies: std.StringHashMap(std.ArrayList([]const u8)),
    timestamps: std.StringHashMap(i64),

    pub fn init(allocator: std.mem.Allocator) DependencyTracker {
        return .{
            .allocator = allocator,
            .dependencies = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .timestamps = std.StringHashMap(i64).init(allocator),
        };
    }

    pub fn deinit(self: *DependencyTracker) void {
        var iter = self.dependencies.valueIterator();
        while (iter.next()) |list| {
            list.deinit();
        }
        self.dependencies.deinit();
        self.timestamps.deinit();
    }

    pub fn addDependency(self: *DependencyTracker, target: []const u8, dep: []const u8) !void {
        const result = try self.dependencies.getOrPut(target);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }
        try result.value_ptr.append(dep);
    }

    pub fn setTimestamp(self: *DependencyTracker, file: []const u8, timestamp: i64) !void {
        try self.timestamps.put(file, timestamp);
    }

    pub fn needsRebuild(self: DependencyTracker, target: []const u8) bool {
        const target_time = self.timestamps.get(target) orelse return true;
        const deps = self.dependencies.get(target) orelse return false;

        for (deps.items) |dep| {
            const dep_time = self.timestamps.get(dep) orelse return true;
            if (dep_time > target_time) return true;
        }
        return false;
    }

    pub fn getDependencies(self: DependencyTracker, target: []const u8) ?[]const []const u8 {
        if (self.dependencies.get(target)) |list| {
            return list.items;
        }
        return null;
    }
};

/// Package builder for creating distribution packages
pub const PackageBuilder = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    version: []const u8,
    files: std.ArrayList(FileEntry),
    metadata: Metadata,

    pub const FileEntry = struct {
        source: []const u8,
        destination: []const u8,
        mode: u32 = 0o644,
        is_executable: bool = false,
    };

    pub const Metadata = struct {
        author: ?[]const u8 = null,
        author_email: ?[]const u8 = null,
        description: ?[]const u8 = null,
        url: ?[]const u8 = null,
        license: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8) PackageBuilder {
        return .{
            .allocator = allocator,
            .name = name,
            .version = version,
            .files = std.ArrayList(FileEntry).init(allocator),
            .metadata = .{},
        };
    }

    pub fn deinit(self: *PackageBuilder) void {
        self.files.deinit();
    }

    pub fn addFile(self: *PackageBuilder, entry: FileEntry) !void {
        try self.files.append(entry);
    }

    pub fn fileCount(self: PackageBuilder) usize {
        return self.files.items.len;
    }

    pub fn setMetadata(self: *PackageBuilder, metadata: Metadata) void {
        self.metadata = metadata;
    }
};

// Tests
test "build_config_basic" {
    const config = BuildConfig{
        .prefix = "/opt/python",
        .build_type = .release,
        .enable_lto = true,
    };

    try std.testing.expect(!config.isDebug());
    try std.testing.expectEqual(@as(u8, 3), config.getOptimizationLevel());
}

test "build_config_debug" {
    const config = BuildConfig{
        .build_type = .debug,
        .with_pydebug = true,
        .with_assertions = true,
    };

    try std.testing.expect(config.isDebug());
    try std.testing.expectEqual(@as(u8, 0), config.getOptimizationLevel());
}

test "build_config_cflags" {
    const config = BuildConfig{
        .build_type = .release,
        .enable_lto = true,
    };

    const flags = try config.getCFlags(std.testing.allocator);
    defer std.testing.allocator.free(flags);

    try std.testing.expect(std.mem.indexOf(u8, flags, "-O3") != null);
    try std.testing.expect(std.mem.indexOf(u8, flags, "-flto") != null);
}

test "compiler_version" {
    const version = Compiler.Version{ .major = 11, .minor = 2, .patch = 0 };
    try std.testing.expect(version.atLeast(11, 0));
    try std.testing.expect(version.atLeast(11, 2));
    try std.testing.expect(!version.atLeast(12, 0));
}

test "compiler_flags" {
    const compiler = Compiler{
        .name = .gcc,
        .version = .{ .major = 10, .minor = 0 },
        .path = "/usr/bin/gcc",
    };

    try std.testing.expect(compiler.supportsFlag("-flto"));
    try std.testing.expect(compiler.supportsFlag("-fstack-protector-strong"));
    try std.testing.expect(compiler.isGccCompatible());
}

test "module_config" {
    const config = ModuleConfig{
        .name = "mymodule",
        .sources = &[_][]const u8{ "module.c", "helper.c" },
        .libraries = &[_][]const u8{ "z", "ssl" },
    };

    try std.testing.expectEqual(@as(usize, 2), config.sourceCount());
    try std.testing.expect(config.hasLibrary("z"));
    try std.testing.expect(!config.hasLibrary("crypto"));
}

test "configure_generator" {
    var gen = ConfigureGenerator.init(std.testing.allocator);
    defer gen.deinit();

    try gen.addCheck(.{
        .name = "sys/types.h",
        .kind = .header,
    });

    try gen.setResult("sys/types.h", .{ .passed = true });
    try gen.setResult("memfd_create", .{ .passed = false });

    try std.testing.expect(gen.hasHeader("sys/types.h"));
    try std.testing.expect(!gen.hasFunction("memfd_create"));
}

test "makefile_generator" {
    var gen = MakefileGenerator.init(std.testing.allocator);
    defer gen.deinit();

    try gen.setVariable("CC", "gcc");
    try gen.setVariable("CFLAGS", "-O2 -Wall");

    try gen.addTarget(.{
        .name = "all",
        .dependencies = &[_][]const u8{"python"},
        .phony = true,
    });

    try gen.addTarget(.{
        .name = "clean",
        .commands = &[_][]const u8{ "rm -f *.o", "rm -f python" },
        .phony = true,
    });

    const makefile = try gen.generate(std.testing.allocator);
    defer std.testing.allocator.free(makefile);

    try std.testing.expect(std.mem.indexOf(u8, makefile, "CC = gcc") != null);
    try std.testing.expect(std.mem.indexOf(u8, makefile, ".PHONY:") != null);
}

test "cross_compile_config" {
    const config = CrossCompileConfig{
        .host_triple = "x86_64-linux-gnu",
        .target_triple = "aarch64-linux-gnu",
        .toolchain_prefix = "aarch64-linux-gnu-",
    };

    try std.testing.expect(config.isCrossCompiling());
    try std.testing.expectEqualStrings("aarch64", config.getTargetArch().?);
    try std.testing.expectEqualStrings("gnu", config.getTargetOS().?);
}

test "dependency_tracker" {
    var tracker = DependencyTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try tracker.addDependency("main.o", "main.c");
    try tracker.addDependency("main.o", "header.h");
    try tracker.setTimestamp("main.c", 1000);
    try tracker.setTimestamp("header.h", 2000);
    try tracker.setTimestamp("main.o", 1500);

    try std.testing.expect(tracker.needsRebuild("main.o"));

    try tracker.setTimestamp("main.o", 3000);
    try std.testing.expect(!tracker.needsRebuild("main.o"));
}

test "package_builder" {
    var builder = PackageBuilder.init(std.testing.allocator, "mypackage", "1.0.0");
    defer builder.deinit();

    try builder.addFile(.{
        .source = "src/main.py",
        .destination = "lib/python/main.py",
    });

    try builder.addFile(.{
        .source = "bin/script",
        .destination = "bin/script",
        .is_executable = true,
    });

    builder.setMetadata(.{
        .author = "Test Author",
        .license = "MIT",
    });

    try std.testing.expectEqual(@as(usize, 2), builder.fileCount());
    try std.testing.expectEqualStrings("MIT", builder.metadata.license.?);
}
