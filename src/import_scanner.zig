/// Scan Python file for all imports and recursively collect dependencies
const std = @import("std");
const ast = @import("ast");
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const import_resolver = @import("import_resolver.zig");
const hashmap_helper = @import("hashmap_helper");

pub const ModuleInfo = struct {
    path: []const u8, // Full path to .py file
    imports: [][]const u8, // List of imported modules
    compiled_path: ?[]const u8, // Path to compiled .so

    pub fn deinit(self: *ModuleInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        for (self.imports) |imp| {
            allocator.free(imp);
        }
        allocator.free(self.imports);
        if (self.compiled_path) |cp| {
            allocator.free(cp);
        }
    }
};

/// Comptime constants for file patterns (zero memory cost at runtime)
const PYTHON_EXT = ".py";
const PYTHON_EXT_LEN = PYTHON_EXT.len;
const INIT_FILE = "__init__.py";
const PYCACHE_DIR = "__pycache__";

/// Comptime file extension checking (zero runtime cost)
fn isPythonFile(comptime path: []const u8) bool {
    comptime {
        return std.mem.endsWith(u8, path, PYTHON_EXT);
    }
}

/// Runtime file extension checking for dynamic paths
/// Optimized: checks length first (comptime constant)
fn isPythonFileRuntime(path: []const u8) bool {
    if (path.len < PYTHON_EXT_LEN) return false;
    return std.mem.endsWith(u8, path, PYTHON_EXT);
}

/// Comptime check if path is __pycache__ directory
fn isPycacheDir(path: []const u8) bool {
    return std.mem.indexOf(u8, path, PYCACHE_DIR) != null;
}

pub const ImportGraph = struct {
    modules: hashmap_helper.StringHashMap(ModuleInfo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ImportGraph {
        return .{
            .modules = hashmap_helper.StringHashMap(ModuleInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImportGraph) void {
        var iter = self.modules.iterator();
        while (iter.next()) |entry| {
            var info = entry.value_ptr.*;
            info.deinit(self.allocator);
        }
        self.modules.deinit();
    }

    /// Recursively scan file and all its imports
    pub fn scanRecursive(
        self: *ImportGraph,
        file_path: []const u8,
        visited: *hashmap_helper.StringHashMap(void),
    ) !void {
        // Skip non-.py files - optimized with comptime length check
        if (!isPythonFileRuntime(file_path)) return;

        // Skip __pycache__ directories (compiled bytecode)
        if (isPycacheDir(file_path)) return;

        // Check if already scanned
        if (visited.contains(file_path)) return;
        try visited.put(file_path, {});

        // Read file
        const source = try std.fs.cwd().readFileAlloc(self.allocator, file_path, 100_000_000);
        defer self.allocator.free(source);

        // Parse to find imports
        const imports = try extractImports(self.allocator, source);
        errdefer {
            for (imports) |imp| self.allocator.free(imp);
            self.allocator.free(imports);
        }

        // Store module info
        const path_copy = try self.allocator.dupe(u8, file_path);
        errdefer self.allocator.free(path_copy);

        try self.modules.put(path_copy, .{
            .path = path_copy,
            .imports = imports,
            .compiled_path = null,
        });

        // Recursively scan imports
        const dir = std.fs.path.dirname(file_path);
        for (imports) |import_name| {
            // Handle relative imports (starting with .)
            if (import_name.len > 0 and import_name[0] == '.') {
                if (dir) |source_dir| {
                    // Resolve relative import
                    const resolved = try resolveRelativeImport(import_name, source_dir, self.allocator);
                    if (resolved) |path| {
                        // Check if already visited (using resolved path)
                        if (visited.contains(path)) {
                            self.allocator.free(path);
                            continue;
                        }
                        // Check if file exists
                        std.fs.cwd().access(path, .{}) catch {
                            std.debug.print("  Skipped import (not found): {s} -> {s}\n", .{ import_name, path });
                            self.allocator.free(path);
                            continue;
                        };
                        std.debug.print("  Found import: {s} -> {s}\n", .{ import_name, path });
                        // Add to visited before recursing
                        const resolved_copy = try self.allocator.dupe(u8, path);
                        try visited.put(resolved_copy, {});
                        self.allocator.free(path);
                        try self.scanRecursive(resolved_copy, visited);
                    } else {
                        std.debug.print("  Skipped import (relative, no dir): {s}\n", .{import_name});
                    }
                }
                continue;
            }

            // Non-relative imports
            if (try import_resolver.resolveImportSource(import_name, dir, self.allocator)) |resolved| {
                std.debug.print("  Found import: {s} -> {s}\n", .{ import_name, resolved });
                defer self.allocator.free(resolved);
                try self.scanRecursive(resolved, visited);
            } else {
                std.debug.print("  Skipped import (external): {s}\n", .{import_name});
            }
        }
    }
};

/// Resolve relative import to file path
/// .app -> dir/app.py or dir/app/__init__.py
/// ..utils -> parent_dir/utils.py or parent_dir/utils/__init__.py
fn resolveRelativeImport(import_name: []const u8, source_dir: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    // Count leading dots
    var dots: usize = 0;
    while (dots < import_name.len and import_name[dots] == '.') : (dots += 1) {}

    // Get module name after dots
    const module_part = import_name[dots..];

    // Navigate up directories based on dot count
    // . = current dir, .. = parent, ... = grandparent
    var base_dir: []const u8 = source_dir;
    var levels = dots;
    while (levels > 1) : (levels -= 1) {
        if (std.fs.path.dirname(base_dir)) |parent| {
            base_dir = parent;
        } else {
            return null; // Can't go up further
        }
    }

    // Build path
    if (module_part.len == 0) {
        // from . import X - just the current package
        return null;
    }

    // Try as module file first: base_dir/module.py
    const module_path = try std.fmt.allocPrint(allocator, "{s}/{s}.py", .{ base_dir, module_part });
    std.fs.cwd().access(module_path, .{}) catch {
        allocator.free(module_path);
        // Try as package: base_dir/module/__init__.py
        const pkg_path = try std.fmt.allocPrint(allocator, "{s}/{s}/__init__.py", .{ base_dir, module_part });
        std.fs.cwd().access(pkg_path, .{}) catch {
            allocator.free(pkg_path);
            return null;
        };
        return pkg_path;
    };
    return module_path;
}

/// Extract import statements from Python source
fn extractImports(allocator: std.mem.Allocator, source: []const u8) ![][]const u8 {
    var imports = std.ArrayList([]const u8){};
    errdefer {
        for (imports.items) |imp| allocator.free(imp);
        imports.deinit(allocator);
    }

    // Tokenize
    var lex = lexer.Lexer.init(allocator, source) catch {
        // If lexer init fails, return empty list
        return imports.toOwnedSlice(allocator);
    };
    defer lex.deinit();

    const tokens = lex.tokenize() catch {
        // If tokenization fails, return empty list
        return imports.toOwnedSlice(allocator);
    };
    defer lexer.freeTokens(allocator, tokens);

    // Parse to AST
    var p = parser.Parser.init(allocator, tokens);
    const tree = p.parse() catch {
        // If parsing fails, return empty list
        return imports.toOwnedSlice(allocator);
    };
    defer tree.deinit(allocator);

    // Find all import nodes
    switch (tree) {
        .module => |mod| {
            for (mod.body) |stmt| {
                switch (stmt) {
                    .import_stmt => |imp| {
                        const module_copy = try allocator.dupe(u8, imp.module);
                        try imports.append(allocator, module_copy);
                    },
                    .import_from => |imp| {
                        // For relative imports, we'll resolve them later with source_dir context
                        // For now, store them as-is - the scanner will resolve them
                        const module_copy = try allocator.dupe(u8, imp.module);
                        try imports.append(allocator, module_copy);
                    },
                    else => {},
                }
            }
        },
        else => {},
    }

    return imports.toOwnedSlice(allocator);
}
