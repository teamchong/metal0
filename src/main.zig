/// CLI entry point - Re-exports from submodules
pub const cli = @import("main/cli.zig");
pub const compile = @import("main/compile.zig");
pub const cache = @import("main/cache.zig");
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
