/// Import handling and module compilation
const std = @import("std");
const ast = @import("ast");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const statements = @import("../statements.zig");
const import_resolver = @import("../../../import_resolver.zig");
const fnv_hash = @import("fnv_hash");

const hashmap_helper = @import("hashmap_helper");
const FnvVoidMap = hashmap_helper.StringHashMap(void);

/// Infer return type from type string
fn inferReturnTypeFromString(
    type_name: []const u8,
) @import("../../../analysis/native_types.zig").NativeType {
    if (std.mem.eql(u8, type_name, "int")) return .int;
    if (std.mem.eql(u8, type_name, "float")) return .float;
    if (std.mem.eql(u8, type_name, "str")) return .{ .string = .runtime };
    if (std.mem.eql(u8, type_name, "bool")) return .bool;

    return .int;
}

/// Compile a Python module as an inlined Zig struct
/// Returns Zig code as a string (caller must free)
/// parent_module_prefix: For submodules, the full parent path (e.g. "testpkg.submod")
pub fn compileModuleAsStruct(
    module_name: []const u8,
    source_file_dir: ?[]const u8,
    allocator: std.mem.Allocator,
    main_type_inferrer: ?*@import("../../../analysis/native_types.zig").TypeInferrer,
) anyerror![]const u8 {
    return compileModuleAsStructWithPrefix(module_name, null, source_file_dir, allocator, main_type_inferrer);
}

fn compileModuleAsStructWithPrefix(
    module_name: []const u8,
    parent_prefix: ?[]const u8,
    source_file_dir: ?[]const u8,
    allocator: std.mem.Allocator,
    main_type_inferrer: ?*@import("../../../analysis/native_types.zig").TypeInferrer,
) anyerror![]const u8 {
    // Use arena for intermediate allocations
    // Base allocator used for: return value and qualified_names in type_inferrer
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    // Use import resolver to find the module (prefers compiled .so)
    const resolved_path = try import_resolver.resolveImport(module_name, source_file_dir, aa) orelse {
        std.debug.print("Error: Cannot find module '{s}'\n", .{module_name});
        std.debug.print("Searched in: ", .{});
        if (source_file_dir) |dir| {
            std.debug.print("{s}/, ", .{dir});
        }
        std.debug.print("./, examples/, build/\n", .{});
        return error.ModuleNotFound;
    };

    // If it's a compiled .so module, still need to register types from source
    // Try to find the .py source file alongside the .so
    var py_path_to_use: []const u8 = resolved_path;
    if (std.mem.endsWith(u8, resolved_path, ".so")) {
        // Try to find the .py source for type registration (skip .so files)
        const py_source = try import_resolver.resolveImportSource(module_name, source_file_dir, aa);
        if (py_source) |src| {
            py_path_to_use = src;
        } else {
            // No .py source found - return the import statement and skip type registration
            return try std.fmt.allocPrint(allocator, "const {s} = @import(\"./{s}.zig\");\n", .{ module_name, module_name });
        }
    }

    const py_path = py_path_to_use;

    // Analyze if this is a package with submodules
    const pkg_info = try import_resolver.analyzePackage(py_path, aa);

    // Read source (handle both relative and absolute paths)
    const source = blk: {
        // Try as absolute path first
        if (std.fs.path.isAbsolute(py_path)) {
            const file = std.fs.openFileAbsolute(py_path, .{}) catch |err| {
                std.debug.print("Error: Cannot read file '{s}': {}\n", .{ py_path, err });
                return error.ModuleNotFound;
            };
            defer file.close();
            break :blk try file.readToEndAlloc(aa, 10 * 1024 * 1024);
        } else {
            // Relative path
            break :blk try std.fs.cwd().readFileAlloc(aa, py_path, 10 * 1024 * 1024);
        }
    };

    // Lex, parse, analyze
    const lexer_mod = @import("../../../lexer.zig");
    const parser_mod = @import("../../../parser.zig");
    const semantic_types_mod = @import("../../../analysis/types.zig");
    const lifetime_analysis_mod = @import("../../../analysis/lifetime.zig");
    const native_types_mod = @import("../../../analysis/native_types.zig");

    var lex = try lexer_mod.Lexer.init(aa, source);
    const tokens = try lex.tokenize();

    var p = parser_mod.Parser.init(aa, tokens);
    defer p.deinit();
    const tree = try p.parse();

    if (tree != .module) return error.InvalidAST;

    var semantic_info = semantic_types_mod.SemanticInfo.init(aa);
    _ = try lifetime_analysis_mod.analyzeLifetimes(&semantic_info, tree, 1);

    var type_inferrer = try native_types_mod.TypeInferrer.init(aa);
    try type_inferrer.analyze(tree.module);

    // Use full codegen to generate proper module code
    var codegen = try NativeCodegen.init(aa, &type_inferrer, &semantic_info);

    // Set mode to module so functions are wrapped in pub struct
    codegen.mode = .module;
    codegen.module_name = module_name;

    // Register function return types in main type inferrer
    if (main_type_inferrer) |type_inf| {
        for (tree.module.body) |stmt| {
            if (stmt == .function_def) {
                const func = stmt.function_def;
                // Infer return type from function
                const return_type = if (func.return_type) |ret_type_name|
                    inferReturnTypeFromString(ret_type_name)
                else
                    native_types_mod.NativeType.int;

                // Format: "module.function" or "parent.module.function" -> return type
                const qualified_name = if (parent_prefix) |prefix|
                    try std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{ prefix, module_name, func.name })
                else
                    try std.fmt.allocPrint(allocator, "{s}.{s}", .{ module_name, func.name });

                try type_inf.func_return_types.put(qualified_name, return_type);
                // Note: qualified_name is kept allocated for the lifetime of the map
            }
        }
    }

    // Use full code generation for the module
    const module_code = try codegen.generate(tree.module);
    defer aa.free(module_code);

    // Extract just the module struct (remove leading imports)
    const module_body = blk: {
        // Find "pub const module_name = struct {"
        if (std.mem.indexOf(u8, module_code, "pub const ")) |start| {
            break :blk module_code[start..];
        }
        break :blk module_code;
    };

    // Compile submodules if this is a package
    var submodule_code = std.ArrayList(u8){};

    if (pkg_info.is_package and pkg_info.submodules.len > 0) {
        for (pkg_info.submodules) |submod_name| {
            // Build path to submodule
            const submod_path = try std.fmt.allocPrint(aa, "{s}/{s}.py", .{ pkg_info.package_dir, submod_name });

            // Check if submodule exists (handle absolute paths)
            const exists = if (std.fs.path.isAbsolute(submod_path))
                std.fs.accessAbsolute(submod_path, .{})
            else
                std.fs.cwd().access(submod_path, .{});
            exists catch continue;

            // Compile submodule (recursively, in case it's also a package)
            // Build full qualified prefix for submodule
            const submod_prefix = if (parent_prefix) |prefix|
                try std.fmt.allocPrint(aa, "{s}.{s}", .{ prefix, module_name })
            else
                try aa.dupe(u8, module_name);

            const submod_struct = compileModuleAsStructWithPrefix(submod_name, submod_prefix, pkg_info.package_dir, allocator, // Recursive call uses base allocator for return value
                main_type_inferrer) catch |err| {
                std.debug.print("Warning: Could not compile submodule {s}.{s}: {}\n", .{ module_name, submod_name, err });
                continue;
            };
            defer allocator.free(submod_struct); // Free recursive call's return value

            // Extract just the struct body (remove outer const declaration)
            const struct_body = blk: {
                // Find "const submod_name = struct {"
                const struct_start = std.mem.indexOf(u8, submod_struct, "struct {") orelse break :blk submod_struct;
                const body_start = struct_start + "struct {".len;

                // Find closing "};"
                var brace_count: i32 = 1;
                var i = body_start;
                while (i < submod_struct.len and brace_count > 0) : (i += 1) {
                    if (submod_struct[i] == '{') brace_count += 1;
                    if (submod_struct[i] == '}') brace_count -= 1;
                }

                if (brace_count == 0 and i > body_start) {
                    break :blk submod_struct[body_start .. i - 1]; // Exclude closing brace
                }
                break :blk submod_struct;
            };

            // Add as nested struct
            try submodule_code.writer(aa).print("    pub const {s} = struct {{\n" ++
                "{s}" ++
                "    }};\n\n", .{ submod_name, struct_body });
        }
    }

    // Add submodules if needed (use base allocator for return value)
    if (submodule_code.items.len > 0) {
        // Need to inject submodules into the struct
        // Find the closing brace of the struct
        if (std.mem.lastIndexOf(u8, module_body, "};")) |close_idx| {
            var struct_code = std.ArrayList(u8){};
            errdefer struct_code.deinit(allocator);

            try struct_code.writer(allocator).print("// Inlined module: {s}\n" ++
                "{s}" ++ // Everything up to closing brace
                "{s}" ++ // Submodules
                "}};\n", // Closing brace
                .{ module_name, module_body[0..close_idx], submodule_code.items });

            return try struct_code.toOwnedSlice(allocator);
        }
    }

    // No submodules or couldn't find closing brace - return as is
    var struct_code = std.ArrayList(u8){};
    errdefer struct_code.deinit(allocator);

    try struct_code.writer(allocator).print("// Inlined module: {s}\n{s}", .{ module_name, module_body });

    return try struct_code.toOwnedSlice(allocator);
}

/// Scan AST for import statements and collect module names with registry lookup
/// Returns list of modules that need to be compiled from Python source
pub fn collectImports(
    self: *NativeCodegen,
    module: ast.Node.Module,
    source_file_dir: ?[]const u8,
) !std.ArrayList([]const u8) {
    var imports = std.ArrayList([]const u8){};

    // Collect unique Python module names from import statements
    var module_names = FnvVoidMap.init(self.allocator);
    defer module_names.deinit();

    // Clear previous from-imports
    self.from_imports.clearRetainingCapacity();

    for (module.body) |stmt| {
        // Handle both "import X" and "from X import Y"
        switch (stmt) {
            .import_stmt => |imp| {
                const module_name = imp.module;
                try module_names.put(module_name, {});
                // Also add root module for dotted imports (e.g., "test.support" -> "test")
                if (std.mem.indexOfScalar(u8, module_name, '.')) |dot_idx| {
                    try module_names.put(module_name[0..dot_idx], {});
                }
            },
            .import_from => |imp| {
                const module_name = imp.module;
                try module_names.put(module_name, {});
                // Also add root module for dotted imports (e.g., "test.support" -> "test")
                if (std.mem.indexOfScalar(u8, module_name, '.')) |dot_idx| {
                    try module_names.put(module_name[0..dot_idx], {});
                }

                // Store from-import info for symbol re-export generation
                try self.from_imports.append(self.allocator, core.FromImportInfo{
                    .module = module_name,
                    .names = imp.names,
                    .asnames = imp.asnames,
                });
            },
            else => {},
        }
    }

    // Process each module using registry
    for (module_names.keys()) |python_module| {
        // Handle relative imports (starting with .)
        // Convert .app to full path like flask/app when inside flask/__init__.py
        if (python_module.len > 0 and python_module[0] == '.') {
            // Relative import - resolve relative to source directory
            if (source_file_dir) |dir| {
                // Count leading dots
                var dots: usize = 0;
                while (dots < python_module.len and python_module[dots] == '.') : (dots += 1) {}

                // Get module name after dots
                const module_part = python_module[dots..];

                // For single dot, use current package directory
                // For double dot, go up one level, etc.
                var parent_dir = dir;
                var levels = dots;
                while (levels > 1) : (levels -= 1) {
                    if (std.fs.path.dirname(parent_dir)) |p| {
                        parent_dir = p;
                    }
                }

                // Build resolved path
                if (module_part.len > 0) {
                    // .app -> dir/app.py
                    const resolved_path = std.fmt.allocPrint(self.allocator, "{s}/{s}.py", .{ parent_dir, module_part }) catch continue;
                    defer self.allocator.free(resolved_path);

                    // Check if file exists
                    std.fs.cwd().access(resolved_path, .{}) catch {
                        // Try as package: dir/app/__init__.py
                        const pkg_path = std.fmt.allocPrint(self.allocator, "{s}/{s}/__init__.py", .{ parent_dir, module_part }) catch continue;
                        defer self.allocator.free(pkg_path);
                        std.fs.cwd().access(pkg_path, .{}) catch {
                            // Not found - skip
                            continue;
                        };
                    };

                    // Add the relative module for compilation
                    try imports.append(self.allocator, python_module);
                    continue;
                }
            }
            // Can't resolve relative import - skip
            continue;
        }
        if (self.import_registry.lookup(python_module)) |info| {
            switch (info.strategy) {
                .zig_runtime => {
                    // Include modules with Zig implementations
                    try imports.append(self.allocator, python_module);

                    // Add C library to linking list if specified (e.g. gzip needs zlib)
                    if (info.c_library) |lib_name| {
                        try self.c_libraries.append(self.allocator, lib_name);
                        std.debug.print("[C Extension] Detected {s} → link {s}\n", .{ python_module, lib_name });
                    }
                },
                .c_library => {
                    // Include C library modules
                    try imports.append(self.allocator, python_module);

                    // Add C library to linking list
                    if (info.c_library) |lib_name| {
                        try self.c_libraries.append(self.allocator, lib_name);
                        std.debug.print("[C Extension] Detected {s} → link {s}\n", .{ python_module, lib_name });
                    }
                },
                .compile_python => {
                    // Include for compilation (will be handled in generate())
                    try imports.append(self.allocator, python_module);
                },
                .unsupported => {
                    std.debug.print("Error: Dynamic imports not supported in AOT compilation\n", .{});
                    std.debug.print("  --> import {s}\n", .{python_module});
                    std.debug.print("   |\n", .{});
                    std.debug.print("   = metal0 resolves all imports at compile time\n", .{});
                    std.debug.print("   = Dynamic runtime module loading not supported\n", .{});
                    if (std.mem.eql(u8, python_module, "importlib")) {
                        std.debug.print("   = Suggestion: Use static imports (import json) instead of importlib.import_module('json')\n", .{});
                    }
                    return error.UnsupportedModule;
                },
            }
        } else {
            // Module not in registry - first check if it's a builtin module we don't support
            // These are stdlib modules with unsupported syntax (subprocess, tempfile, os, etc.)
            if (import_resolver.isBuiltinModule(python_module)) {
                // Built-in module without Zig runtime support - skip it
                try self.markSkippedModule(python_module);
                continue;
            }

            // Check if it's a local .py file
            const is_local = try import_resolver.isLocalModule(
                python_module,
                source_file_dir,
                self.allocator,
            );

            if (is_local) {
                // Local user module - add to imports list for compilation
                try imports.append(self.allocator, python_module);
            } else {
                // Check if module was already compiled by import_scanner (e.g., stdlib modules)
                const compiled_path = try std.fmt.allocPrint(self.allocator, ".build/{s}.zig", .{python_module});
                defer self.allocator.free(compiled_path);
                const already_compiled = std.fs.cwd().access(compiled_path, .{}) != error.FileNotFound;

                if (already_compiled) {
                    // Module was compiled by import_scanner - add to imports
                    try imports.append(self.allocator, python_module);
                } else {
                    // Check if it's a C extension installed in site-packages
                    const is_c_ext = import_resolver.isCExtension(python_module, self.allocator);
                    if (is_c_ext) {
                        std.debug.print("[C Extension] Detected {s} in site-packages (no mapping yet)\n", .{python_module});
                    } else {
                        // External package not in registry - skip with warning
                        std.debug.print("Warning: External module '{s}' not found, skipping import\n", .{python_module});
                        // Track this module as skipped so we can skip code that references it
                        try self.markSkippedModule(python_module);
                    }
                }
            }
        }
    }

    return imports;
}
