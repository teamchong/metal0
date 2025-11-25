/// Symbol table and method lookup system for native code generation
/// Provides scope-aware symbol resolution and class method lookup with inheritance support
const std = @import("std");
const ast = @import("../../ast.zig");
const NativeType = @import("../../analysis/native_types.zig").NativeType;
const hashmap_helper = @import("../../utils/hashmap_helper.zig");

const FnvSymbolMap = hashmap_helper.StringHashMap(SymbolInfo);
const FnvClassDefMap = hashmap_helper.StringHashMap(ast.Node.ClassDef);
const FnvStringMap = hashmap_helper.StringHashMap([]const u8);

/// Symbol information
pub const SymbolInfo = struct {
    name: []const u8,
    symbol_type: NativeType,
    scope_level: usize, // 0 = global, 1+ = nested
    is_mutable: bool,
    is_parameter: bool,
    is_closure_var: bool,
};

/// Symbol table with scope support
pub const SymbolTable = struct {
    allocator: std.mem.Allocator,

    // Stack of scopes: scopes[0] = global, scopes[n] = current
    scopes: std.ArrayList(FnvSymbolMap),

    pub fn init(allocator: std.mem.Allocator) SymbolTable {
        var scopes = std.ArrayList(FnvSymbolMap){};

        // Initialize with global scope
        const global = FnvSymbolMap.init(allocator);
        scopes.append(allocator, global) catch unreachable;

        return SymbolTable{
            .allocator = allocator,
            .scopes = scopes,
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        var i: usize = 0;
        while (i < self.scopes.items.len) : (i += 1) {
            self.scopes.items[i].deinit();
        }
        self.scopes.deinit(self.allocator);
    }

    /// Push a new scope
    pub fn pushScope(self: *SymbolTable) !void {
        const scope = FnvSymbolMap.init(self.allocator);
        try self.scopes.append(self.allocator, scope);
    }

    /// Pop current scope
    pub fn popScope(self: *SymbolTable) void {
        if (self.scopes.items.len > 1) {
            self.scopes.items[self.scopes.items.len - 1].deinit();
            _ = self.scopes.pop();
        }
    }

    /// Declare a symbol in current scope
    pub fn declare(
        self: *SymbolTable,
        name: []const u8,
        symbol_type: NativeType,
        is_mutable: bool,
    ) !void {
        const current_scope_level = self.scopes.items.len - 1;
        const info = SymbolInfo{
            .name = name,
            .symbol_type = symbol_type,
            .scope_level = current_scope_level,
            .is_mutable = is_mutable,
            .is_parameter = false,
            .is_closure_var = false,
        };

        try self.scopes.items[current_scope_level].put(name, info);
    }

    /// Look up symbol in all scopes (inner to outer)
    pub fn lookup(self: *SymbolTable, name: []const u8) ?SymbolInfo {
        // Search from innermost to outermost scope
        var i: usize = self.scopes.items.len;
        while (i > 0) {
            i -= 1;
            if (self.scopes.items[i].get(name)) |info| {
                return info;
            }
        }
        return null;
    }

    /// Check if symbol is declared in current scope (not parent scopes)
    pub fn isDeclaredInCurrentScope(self: *SymbolTable, name: []const u8) bool {
        const current = self.scopes.items[self.scopes.items.len - 1];
        return current.contains(name);
    }

    /// Get symbol's type
    pub fn getType(self: *SymbolTable, name: []const u8) ?NativeType {
        if (self.lookup(name)) |info| {
            return info.symbol_type;
        }
        return null;
    }

    /// Check if symbol is mutable
    pub fn isMutable(self: *SymbolTable, name: []const u8) bool {
        if (self.lookup(name)) |info| {
            return info.is_mutable;
        }
        return false;
    }

    /// Get current scope level (0 = global)
    pub fn currentScopeLevel(self: *SymbolTable) usize {
        return self.scopes.items.len - 1;
    }
};

/// Method signature information
pub const MethodInfo = struct {
    name: []const u8,
    class_name: []const u8,
    params: []ast.Arg,
    return_type: ?NativeType,
    is_static: bool,
};

/// Class registry with method lookup
pub const ClassRegistry = struct {
    allocator: std.mem.Allocator,

    // Maps class name → ClassDef
    classes: FnvClassDefMap,

    // Maps class name → parent class name (for inheritance)
    inheritance: FnvStringMap,

    pub fn init(allocator: std.mem.Allocator) ClassRegistry {
        return ClassRegistry{
            .allocator = allocator,
            .classes = FnvClassDefMap.init(allocator),
            .inheritance = FnvStringMap.init(allocator),
        };
    }

    pub fn deinit(self: *ClassRegistry) void {
        self.classes.deinit();
        self.inheritance.deinit();
    }

    /// Register a class
    pub fn registerClass(
        self: *ClassRegistry,
        class_name: []const u8,
        class_def: ast.Node.ClassDef,
    ) !void {
        try self.classes.put(class_name, class_def);

        // Register inheritance if base classes exist
        if (class_def.bases.len > 0) {
            const parent = class_def.bases[0];
            try self.inheritance.put(class_name, parent);
        }
    }

    /// Find method in class (searches inheritance chain)
    pub fn findMethod(
        self: *ClassRegistry,
        class_name: []const u8,
        method_name: []const u8,
    ) ?MethodInfo {
        var current_class = class_name;

        // Search up inheritance chain
        while (true) {
            // Look in current class
            if (self.classes.get(current_class)) |class_def| {
                for (class_def.body) |stmt| {
                    if (stmt == .function_def) {
                        const func = stmt.function_def;
                        if (std.mem.eql(u8, func.name, method_name)) {
                            return MethodInfo{
                                .name = func.name,
                                .class_name = current_class,
                                .params = func.args,
                                .return_type = null, // TODO: infer from body
                                .is_static = false,
                            };
                        }
                    }
                }
            }

            // Move to parent class
            if (self.inheritance.get(current_class)) |parent| {
                current_class = parent;
            } else {
                break; // No parent, method not found
            }
        }

        return null;
    }

    /// Check if class has method
    pub fn hasMethod(
        self: *ClassRegistry,
        class_name: []const u8,
        method_name: []const u8,
    ) bool {
        return self.findMethod(class_name, method_name) != null;
    }

    /// Get all methods in class (including inherited)
    pub fn getMethods(
        self: *ClassRegistry,
        class_name: []const u8,
        allocator: std.mem.Allocator,
    ) ![]MethodInfo {
        var methods = std.ArrayList(MethodInfo){};

        var current_class = class_name;
        while (true) {
            if (self.classes.get(current_class)) |class_def| {
                for (class_def.body) |stmt| {
                    if (stmt == .function_def) {
                        const func = stmt.function_def;
                        const info = MethodInfo{
                            .name = func.name,
                            .class_name = current_class,
                            .params = func.args,
                            .return_type = null,
                            .is_static = false,
                        };
                        try methods.append(allocator, info);
                    }
                }
            }

            if (self.inheritance.get(current_class)) |parent| {
                current_class = parent;
            } else {
                break;
            }
        }

        return methods.toOwnedSlice(allocator);
    }

    /// Get a class definition by name
    pub fn getClass(self: *ClassRegistry, class_name: []const u8) ?ast.Node.ClassDef {
        return self.classes.get(class_name);
    }

    /// Get iterator over all registered classes
    pub fn iterator(self: *ClassRegistry) FnvClassDefMap.Iterator {
        return self.classes.iterator();
    }
};
