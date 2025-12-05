/// CLI entry point - Re-exports from submodules
pub const cli = @import("main/cli.zig");
pub const compile = @import("main/compile.zig");
pub const cache = @import("main/compile/cache.zig");
pub const utils = @import("main/utils.zig");

// Re-export main() for binary entry point
pub const main = cli.main;

// Re-export CompileOptions struct
pub const CompileOptions = struct {
    input_file: []const u8,
    output_file: ?[]const u8 = null,
    mode: []const u8, // "run" or "build"
    binary: bool = false, // --binary flag
    force: bool = false, // --force/-f flag
    emit_bytecode: bool = false, // --emit-bytecode flag (for runtime eval subprocess)
    wasm: bool = false, // --wasm/-w flag for WebAssembly output (legacy, use target instead)
    emit_zig_only: bool = false, // --emit-zig flag - generate .zig file only, no compilation
    debug: bool = false, // --debug/-g flag - emit debug info (.metal0.dbg)
    target: Target = .native, // --target flag for cross-compilation
    pgo_generate: bool = false, // --pgo-generate flag - generate PGO instrumented binary
    pgo_use: ?[]const u8 = null, // --pgo-use=<profile> flag - use PGO profile data

    pub const Target = enum {
        native, // Default: compile for current platform
        wasm_browser, // WebAssembly for browser: -Oz, strip, no debug, smallest size
        wasm_edge, // WebAssembly for edge (WasmEdge/Cloudflare): -O3, fast startup
        linux_x64,
        linux_arm64,
        macos_x64,
        macos_arm64,
        windows_x64,

        /// Get Zig target triple for cross-compilation
        pub fn toZigTarget(self: Target) ?[]const u8 {
            return switch (self) {
                .native => null, // Use host
                .wasm_browser, .wasm_edge => "wasm32-freestanding",
                .linux_x64 => "x86_64-linux",
                .linux_arm64 => "aarch64-linux",
                .macos_x64 => "x86_64-macos",
                .macos_arm64 => "aarch64-macos",
                .windows_x64 => "x86_64-windows",
            };
        }

        /// Get optimization flags
        pub fn optimizeMode(self: Target) []const u8 {
            return switch (self) {
                .wasm_browser => "-Oz", // Smallest size for browser downloads
                .wasm_edge => "-O3", // Fastest for edge compute
                else => "-O3", // Fast by default
            };
        }
    };
};

// Re-export commonly used functions
pub const compileFile = compile.compileFile;
pub const compilePythonSource = compile.compilePythonSource;
pub const compileNotebook = compile.compileNotebook;
pub const compileModule = compile.compileModule;

pub const buildDirectory = utils.buildDirectory;
pub const getArch = utils.getArch;
pub const detectImports = utils.detectImports;
pub const runSharedLib = utils.runSharedLib;
pub const printUsage = utils.printUsage;

pub const computeHash = cache.computeHash;
pub const getCachePath = cache.getCachePath;
pub const shouldRecompile = cache.shouldRecompile;
pub const updateCache = cache.updateCache;
