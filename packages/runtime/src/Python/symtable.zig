/// symtable - Symbol Table Analysis
/// Mirrors cpython/Python/symtable.c
///
/// This module provides symbol table functionality for Python compilation:
/// - Name binding analysis (local, global, free, cell)
/// - Scope resolution
/// - Nested scope tracking
/// - Comprehension handling
/// - Class/function distinction

const std = @import("std");
const Allocator = std.mem.Allocator;
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Block Types
// ============================================================================

/// Type of code block
pub const BlockType = enum {
    function, // Function definition
    class, // Class definition
    module, // Module-level code
    annotation, // Annotation block (PEP 649)
    type_alias, // Type alias (PEP 695)
    type_parameters, // Generic type parameters
    type_variable, // TypeVar/TypeVarTuple/ParamSpec
};

/// Comprehension type
pub const ComprehensionType = enum(u8) {
    none = 0,
    list = 1,
    dict = 2,
    set = 3,
    generator = 4,
};

// ============================================================================
// Symbol Flags (DEF_* constants)
// ============================================================================

/// Symbol definition flags
pub const SymbolFlags = packed struct(u32) {
    global: bool = false, // global statement
    local: bool = false, // assignment in code block
    param: bool = false, // formal parameter
    nonlocal: bool = false, // nonlocal statement
    used: bool = false, // name is used
    free_class: bool = false, // free variable from class method
    imported: bool = false, // assignment via import
    annotated: bool = false, // annotated name
    comp_iter: bool = false, // comprehension iteration variable
    type_param: bool = false, // type parameter
    comp_cell: bool = false, // cell in inlined comprehension
    _padding: u21 = 0,

    pub const BOUND_MASK = SymbolFlags{
        .local = true,
        .param = true,
        .imported = true,
    };

    pub fn isBound(self: SymbolFlags) bool {
        return self.local or self.param or self.imported;
    }

    pub fn merge(self: SymbolFlags, other: SymbolFlags) SymbolFlags {
        return @bitCast(@as(u32, @bitCast(self)) | @as(u32, @bitCast(other)));
    }
};

/// Variable scope
pub const Scope = enum(u8) {
    unknown = 0,
    local = 1,
    global_explicit = 2,
    global_implicit = 3,
    free = 4,
    cell = 5,
};

// ============================================================================
// Source Location
// ============================================================================

/// Source location information
pub const SourceLocation = struct {
    lineno: i32 = -1,
    end_lineno: i32 = -1,
    col_offset: i32 = -1,
    end_col_offset: i32 = -1,

    pub const NO_LOCATION = SourceLocation{};
    pub const NEXT_LOCATION = SourceLocation{
        .lineno = -2,
        .end_lineno = -2,
        .col_offset = -2,
        .end_col_offset = -2,
    };

    pub fn isValid(self: SourceLocation) bool {
        return self.lineno >= 0;
    }
};

// ============================================================================
// Future Features
// ============================================================================

/// __future__ flags
pub const FutureFeatures = struct {
    features: u32 = 0,
    location: SourceLocation = SourceLocation.NO_LOCATION,

    // Feature flag constants
    pub const ANNOTATIONS = 1 << 0; // from __future__ import annotations
    pub const BARRY_AS_BDFL = 1 << 1; // Easter egg

    pub fn hasAnnotations(self: FutureFeatures) bool {
        return (self.features & ANNOTATIONS) != 0;
    }
};

// ============================================================================
// Symbol Table Entry
// ============================================================================

/// Symbol table entry for a single scope
pub const SymbolTableEntry = struct {
    allocator: Allocator,

    // Identity
    id: usize, // Unique ID for this entry
    name: []const u8, // Name of this scope

    // Symbol information
    symbols: hashmap_helper.StringHashMap(SymbolInfo), // Name -> flags + scope
    varnames: std.ArrayList([]const u8), // Parameter names (ordered)
    children: std.ArrayList(*SymbolTableEntry), // Nested scopes

    // Directives
    global_names: hashmap_helper.StringHashMap(SourceLocation), // global statements
    nonlocal_names: hashmap_helper.StringHashMap(SourceLocation), // nonlocal statements

    // Block info
    block_type: BlockType,
    location: SourceLocation,

    // Flags
    nested: bool = false,
    generator: bool = false,
    coroutine: bool = false,
    annotations_used: bool = false,
    comprehension: ComprehensionType = .none,
    varargs: bool = false,
    varkeywords: bool = false,
    returns_value: bool = false,
    needs_class_closure: bool = false,
    needs_classdict: bool = false,
    comp_inlined: bool = false,
    comp_iter_target: bool = false,
    can_see_class_scope: bool = false,
    has_docstring: bool = false,
    is_method: bool = false,
    has_conditional_annotations: bool = false,
    in_conditional_block: bool = false,
    in_unevaluated_annotation: bool = false,

    // Links
    parent: ?*SymbolTableEntry = null,
    annotation_block: ?*SymbolTableEntry = null,
    table: ?*SymbolTable = null,

    const Self = @This();

    /// Symbol information stored per name
    pub const SymbolInfo = struct {
        flags: SymbolFlags = .{},
        scope: Scope = .unknown,
        def_location: SourceLocation = SourceLocation.NO_LOCATION,
        use_location: SourceLocation = SourceLocation.NO_LOCATION,
    };

    pub fn init(allocator: Allocator, name: []const u8, block_type: BlockType, id: usize) !*Self {
        const entry = try allocator.create(Self);
        entry.* = .{
            .allocator = allocator,
            .id = id,
            .name = try allocator.dupe(u8, name),
            .symbols = hashmap_helper.StringHashMap(SymbolInfo).init(allocator),
            .varnames = std.ArrayList([]const u8).init(allocator),
            .children = std.ArrayList(*SymbolTableEntry).init(allocator),
            .global_names = hashmap_helper.StringHashMap(SourceLocation).init(allocator),
            .nonlocal_names = hashmap_helper.StringHashMap(SourceLocation).init(allocator),
            .block_type = block_type,
            .location = SourceLocation.NO_LOCATION,
        };
        return entry;
    }

    pub fn deinit(self: *Self) void {
        // Free symbol keys
        var it = self.symbols.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.symbols.deinit();

        // Free varnames
        for (self.varnames.items) |name| {
            self.allocator.free(name);
        }
        self.varnames.deinit();

        // Free children (recursive)
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();

        // Free directive maps
        self.global_names.deinit();
        self.nonlocal_names.deinit();

        // Free name
        self.allocator.free(self.name);
    }

    /// Add a symbol to this scope
    pub fn addSymbol(self: *Self, name: []const u8, flags: SymbolFlags, location: SourceLocation) !void {
        const result = try self.symbols.getOrPut(try self.allocator.dupe(u8, name));
        if (result.found_existing) {
            result.value_ptr.flags = result.value_ptr.flags.merge(flags);
            // Update use location if this is a use
            if (flags.used) {
                if (!result.value_ptr.use_location.isValid()) {
                    result.value_ptr.use_location = location;
                }
            }
        } else {
            result.value_ptr.* = .{
                .flags = flags,
                .def_location = if (flags.isBound()) location else SourceLocation.NO_LOCATION,
                .use_location = if (flags.used) location else SourceLocation.NO_LOCATION,
            };
        }
    }

    /// Get symbol info
    pub fn getSymbol(self: *Self, name: []const u8) ?SymbolInfo {
        return self.symbols.get(name);
    }

    /// Check if name is defined in this scope
    pub fn isDefined(self: *Self, name: []const u8) bool {
        if (self.symbols.get(name)) |info| {
            return info.flags.isBound();
        }
        return false;
    }

    /// Add a parameter
    pub fn addParameter(self: *Self, name: []const u8, location: SourceLocation) !void {
        try self.varnames.append(try self.allocator.dupe(u8, name));
        try self.addSymbol(name, .{ .param = true }, location);
    }

    /// Add a child scope
    pub fn addChild(self: *Self, child: *SymbolTableEntry) !void {
        child.parent = self;
        child.nested = self.nested or isFunctionLike(self);
        try self.children.append(child);
    }

    /// Check if this is a function-like scope
    pub fn isFunctionLike(self: *const Self) bool {
        return switch (self.block_type) {
            .function, .type_alias, .type_parameters, .type_variable => true,
            .class, .module, .annotation => false,
        };
    }

    /// Get all free variables
    pub fn getFreeVars(self: *Self, allocator: Allocator) ![][]const u8 {
        var free = std.ArrayList([]const u8).init(allocator);
        var it = self.symbols.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.scope == .free) {
                try free.append(try allocator.dupe(u8, entry.key_ptr.*));
            }
        }
        return free.toOwnedSlice();
    }

    /// Get all cell variables
    pub fn getCellVars(self: *Self, allocator: Allocator) ![][]const u8 {
        var cells = std.ArrayList([]const u8).init(allocator);
        var it = self.symbols.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.scope == .cell) {
                try cells.append(try allocator.dupe(u8, entry.key_ptr.*));
            }
        }
        return cells.toOwnedSlice();
    }

    /// Get all local variables
    pub fn getLocals(self: *Self, allocator: Allocator) ![][]const u8 {
        var locals = std.ArrayList([]const u8).init(allocator);
        var it = self.symbols.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.scope == .local) {
                try locals.append(try allocator.dupe(u8, entry.key_ptr.*));
            }
        }
        return locals.toOwnedSlice();
    }

    /// Get all global variables
    pub fn getGlobals(self: *Self, allocator: Allocator) ![][]const u8 {
        var globals = std.ArrayList([]const u8).init(allocator);
        var it = self.symbols.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.scope == .global_explicit or
                entry.value_ptr.scope == .global_implicit)
            {
                try globals.append(try allocator.dupe(u8, entry.key_ptr.*));
            }
        }
        return globals.toOwnedSlice();
    }
};

// ============================================================================
// Symbol Table
// ============================================================================

/// Complete symbol table for a module
pub const SymbolTable = struct {
    allocator: Allocator,

    // File info
    filename: []const u8,

    // Entries
    top: ?*SymbolTableEntry = null, // Module-level entry
    current: ?*SymbolTableEntry = null, // Currently active entry
    entries: std.AutoHashMap(usize, *SymbolTableEntry), // All entries by ID

    // State
    stack: std.ArrayList(*SymbolTableEntry), // Scope stack
    next_id: usize = 0,

    // Settings
    future: FutureFeatures = .{},
    private: ?[]const u8 = null, // Current class name for mangling

    const Self = @This();

    pub fn init(allocator: Allocator, filename: []const u8) !*Self {
        const table = try allocator.create(Self);
        table.* = .{
            .allocator = allocator,
            .filename = try allocator.dupe(u8, filename),
            .entries = std.AutoHashMap(usize, *SymbolTableEntry).init(allocator),
            .stack = std.ArrayList(*SymbolTableEntry).init(allocator),
        };
        return table;
    }

    pub fn deinit(self: *Self) void {
        // Free all entries
        for (self.entries.values()) |entry_ptr| {
            entry_ptr.deinit();
            self.allocator.destroy(entry_ptr);
        }
        self.entries.deinit();

        self.stack.deinit();
        self.allocator.free(self.filename);
        if (self.private) |p| self.allocator.free(p);
        self.allocator.destroy(self);
    }

    /// Enter a new scope
    pub fn enterBlock(
        self: *Self,
        name: []const u8,
        block_type: BlockType,
        location: SourceLocation,
    ) !*SymbolTableEntry {
        const id = self.next_id;
        self.next_id += 1;

        const entry = try SymbolTableEntry.init(self.allocator, name, block_type, id);
        entry.location = location;
        entry.table = self;

        try self.entries.put(id, entry);

        // Add as child of current scope
        if (self.current) |cur| {
            try cur.addChild(entry);
        }

        // Set as top if module
        if (block_type == .module) {
            self.top = entry;
        }

        // Push onto stack
        try self.stack.append(entry);
        self.current = entry;

        return entry;
    }

    /// Exit current scope
    pub fn exitBlock(self: *Self) void {
        if (self.stack.items.len > 0) {
            _ = self.stack.pop();
            self.current = if (self.stack.items.len > 0)
                self.stack.items[self.stack.items.len - 1]
            else
                null;
        }
    }

    /// Lookup entry by ID
    pub fn lookup(self: *Self, id: usize) ?*SymbolTableEntry {
        return self.entries.get(id);
    }

    /// Add a name to current scope
    pub fn addName(self: *Self, name: []const u8, flags: SymbolFlags, location: SourceLocation) !void {
        if (self.current) |cur| {
            try cur.addSymbol(name, flags, location);
        }
    }

    /// Analyze and resolve all scopes
    pub fn analyze(self: *Self) !void {
        if (self.top) |top| {
            try self.analyzeBlock(top, null);
        }
    }

    fn analyzeBlock(self: *Self, entry: *SymbolTableEntry, parent_free: ?*hashmap_helper.StringHashMap(void)) !void {
        // Collect free variables from this scope
        var local_free = hashmap_helper.StringHashMap(void).init(self.allocator);
        defer local_free.deinit();

        // First pass: determine initial scopes
        var it = entry.symbols.iterator();
        while (it.next()) |sym_entry| {
            const name = sym_entry.key_ptr.*;
            const info = sym_entry.value_ptr;

            // Global takes precedence
            if (info.flags.global) {
                info.scope = .global_explicit;
                continue;
            }

            // Nonlocal
            if (info.flags.nonlocal) {
                info.scope = .free;
                try local_free.put(name, {});
                continue;
            }

            // Bound locally
            if (info.flags.isBound()) {
                info.scope = .local;
                continue;
            }

            // Will be resolved later
            info.scope = .unknown;
        }

        // Analyze children first
        for (entry.children.items) |child| {
            try self.analyzeBlock(child, &local_free);
        }

        // Second pass: resolve unknowns and determine cells
        it = entry.symbols.iterator();
        while (it.next()) |sym_entry| {
            const name = sym_entry.key_ptr.*;
            const info = sym_entry.value_ptr;

            if (info.scope == .unknown) {
                // Check if it's free from child
                if (local_free.contains(name)) {
                    info.scope = .cell;
                } else if (parent_free != null and self.lookupInParent(entry, name)) {
                    // It's free in this scope too
                    info.scope = .free;
                    try parent_free.?.put(name, {});
                } else {
                    // Implicit global
                    info.scope = .global_implicit;
                }
            } else if (info.scope == .local and local_free.contains(name)) {
                // Local is also needed by child - make it a cell
                info.scope = .cell;
            }
        }
    }

    fn lookupInParent(self: *Self, entry: *SymbolTableEntry, name: []const u8) bool {
        _ = self;
        var parent = entry.parent;
        while (parent) |p| {
            if (p.symbols.get(name)) |info| {
                if (info.flags.isBound() or info.scope == .cell or info.scope == .free) {
                    return true;
                }
            }
            parent = p.parent;
        }
        return false;
    }

    /// Set the current class name for name mangling
    pub fn setPrivate(self: *Self, class_name: ?[]const u8) !void {
        if (self.private) |p| {
            self.allocator.free(p);
            self.private = null;
        }
        if (class_name) |cn| {
            self.private = try self.allocator.dupe(u8, cn);
        }
    }

    /// Mangle a private name
    pub fn mangleName(self: *Self, name: []const u8) ![]const u8 {
        if (self.private) |class_name| {
            if (name.len >= 2 and std.mem.startsWith(u8, name, "__") and
                !std.mem.endsWith(u8, name, "__"))
            {
                // Strip leading underscores from class name
                var stripped = class_name;
                while (stripped.len > 0 and stripped[0] == '_') {
                    stripped = stripped[1..];
                }
                if (stripped.len > 0) {
                    return std.fmt.allocPrint(self.allocator, "_{s}{s}", .{ class_name, name });
                }
            }
        }
        return self.allocator.dupe(u8, name);
    }
};

// ============================================================================
// Error Messages (matching CPython)
// ============================================================================

pub const ErrorMessages = struct {
    pub const GLOBAL_PARAM = "name '{s}' is parameter and global";
    pub const NONLOCAL_PARAM = "name '{s}' is parameter and nonlocal";
    pub const GLOBAL_AFTER_ASSIGN = "name '{s}' is assigned to before global declaration";
    pub const NONLOCAL_AFTER_ASSIGN = "name '{s}' is assigned to before nonlocal declaration";
    pub const GLOBAL_AFTER_USE = "name '{s}' is used prior to global declaration";
    pub const NONLOCAL_AFTER_USE = "name '{s}' is used prior to nonlocal declaration";
    pub const GLOBAL_ANNOT = "annotated name '{s}' can't be global";
    pub const NONLOCAL_ANNOT = "annotated name '{s}' can't be nonlocal";
    pub const IMPORT_STAR_WARNING = "import * only allowed at module level";
    pub const DUPLICATE_PARAMETER = "duplicate argument '{s}' in function definition";
    pub const ASYNC_WITH_OUTSIDE_ASYNC = "'async with' outside async function";
    pub const ASYNC_FOR_OUTSIDE_ASYNC = "'async for' outside async function";
};

// ============================================================================
// Symbol Table Builder
// ============================================================================

/// Builder for constructing symbol tables from AST
pub const SymbolTableBuilder = struct {
    allocator: Allocator,
    table: *SymbolTable,
    errors: std.ArrayList(Error),

    pub const Error = struct {
        message: []const u8,
        location: SourceLocation,
    };

    const Self = @This();

    pub fn init(allocator: Allocator, filename: []const u8) !Self {
        return .{
            .allocator = allocator,
            .table = try SymbolTable.init(allocator, filename),
            .errors = std.ArrayList(Error).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit();
    }

    /// Add an error
    pub fn addError(self: *Self, comptime fmt: []const u8, args: anytype, location: SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.errors.append(.{
            .message = message,
            .location = location,
        });
    }

    /// Check for errors
    pub fn hasErrors(self: *Self) bool {
        return self.errors.items.len > 0;
    }

    /// Enter module scope
    pub fn enterModule(self: *Self) !*SymbolTableEntry {
        return self.table.enterBlock("<module>", .module, SourceLocation.NO_LOCATION);
    }

    /// Enter function scope
    pub fn enterFunction(self: *Self, name: []const u8, location: SourceLocation) !*SymbolTableEntry {
        return self.table.enterBlock(name, .function, location);
    }

    /// Enter class scope
    pub fn enterClass(self: *Self, name: []const u8, location: SourceLocation) !*SymbolTableEntry {
        try self.table.setPrivate(name);
        return self.table.enterBlock(name, .class, location);
    }

    /// Exit current scope
    pub fn exitBlock(self: *Self) void {
        if (self.table.current) |cur| {
            if (cur.block_type == .class) {
                self.table.setPrivate(null) catch {};
            }
        }
        self.table.exitBlock();
    }

    /// Add a name binding
    pub fn addDef(self: *Self, name: []const u8, flags: SymbolFlags, location: SourceLocation) !void {
        const entry = self.table.current orelse return;

        // Check for conflicts
        if (entry.symbols.get(name)) |existing| {
            // Check global/param conflict
            if (flags.global and existing.flags.param) {
                try self.addError(ErrorMessages.GLOBAL_PARAM, .{name}, location);
                return;
            }

            // Check nonlocal/param conflict
            if (flags.nonlocal and existing.flags.param) {
                try self.addError(ErrorMessages.NONLOCAL_PARAM, .{name}, location);
                return;
            }

            // Check global after assignment
            if (flags.global and existing.flags.local) {
                try self.addError(ErrorMessages.GLOBAL_AFTER_ASSIGN, .{name}, location);
                return;
            }

            // Check nonlocal after assignment
            if (flags.nonlocal and existing.flags.local) {
                try self.addError(ErrorMessages.NONLOCAL_AFTER_ASSIGN, .{name}, location);
                return;
            }
        }

        try self.table.addName(name, flags, location);
    }

    /// Record a name use
    pub fn addUse(self: *Self, name: []const u8, location: SourceLocation) !void {
        try self.table.addName(name, .{ .used = true }, location);
    }

    /// Add a parameter
    pub fn addParameter(self: *Self, name: []const u8, location: SourceLocation) !void {
        const entry = self.table.current orelse return;

        // Check for duplicate parameter
        for (entry.varnames.items) |existing| {
            if (std.mem.eql(u8, existing, name)) {
                try self.addError(ErrorMessages.DUPLICATE_PARAMETER, .{name}, location);
                return;
            }
        }

        try entry.addParameter(name, location);
    }

    /// Mark current function as generator
    pub fn setGenerator(self: *Self) void {
        if (self.table.current) |entry| {
            entry.generator = true;
        }
    }

    /// Mark current function as coroutine
    pub fn setCoroutine(self: *Self) void {
        if (self.table.current) |entry| {
            entry.coroutine = true;
        }
    }

    /// Finalize and return the symbol table
    pub fn build(self: *Self) !*SymbolTable {
        try self.table.analyze();
        return self.table;
    }
};

// ============================================================================
// Initialization
// ============================================================================

/// Initialize symtable module
pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "symbol flags" {
    var flags = SymbolFlags{};
    flags.local = true;
    try std.testing.expect(flags.isBound());

    var flags2 = SymbolFlags{ .param = true };
    const merged = flags.merge(flags2);
    try std.testing.expect(merged.local);
    try std.testing.expect(merged.param);
}

test "symbol table entry" {
    const allocator = std.testing.allocator;

    const entry = try SymbolTableEntry.init(allocator, "test_func", .function, 0);
    defer {
        entry.deinit();
        allocator.destroy(entry);
    }

    try entry.addSymbol("x", .{ .local = true }, SourceLocation.NO_LOCATION);
    try entry.addSymbol("y", .{ .param = true }, SourceLocation.NO_LOCATION);

    try std.testing.expect(entry.isDefined("x"));
    try std.testing.expect(entry.isDefined("y"));
    try std.testing.expect(!entry.isDefined("z"));
}

test "symbol table scopes" {
    const allocator = std.testing.allocator;

    const table = try SymbolTable.init(allocator, "test.py");
    defer table.deinit();

    // Enter module
    _ = try table.enterBlock("<module>", .module, SourceLocation.NO_LOCATION);

    // Add some module-level names
    try table.addName("global_var", .{ .local = true }, SourceLocation.NO_LOCATION);

    // Enter function
    const func_entry = try table.enterBlock("my_func", .function, SourceLocation.NO_LOCATION);

    // Add function parameters and locals
    try func_entry.addParameter("arg", SourceLocation.NO_LOCATION);
    try table.addName("local_var", .{ .local = true }, SourceLocation.NO_LOCATION);

    // Exit function
    table.exitBlock();

    try std.testing.expect(table.current != null);
    try std.testing.expect(table.top != null);
}

test "name mangling" {
    const allocator = std.testing.allocator;

    const table = try SymbolTable.init(allocator, "test.py");
    defer table.deinit();

    try table.setPrivate("MyClass");

    // Should mangle
    const mangled = try table.mangleName("__private");
    defer allocator.free(mangled);
    try std.testing.expectEqualStrings("_MyClass__private", mangled);

    // Should not mangle (dunder)
    const not_mangled = try table.mangleName("__init__");
    defer allocator.free(not_mangled);
    try std.testing.expectEqualStrings("__init__", not_mangled);

    // Should not mangle (no leading __)
    const public = try table.mangleName("public");
    defer allocator.free(public);
    try std.testing.expectEqualStrings("public", public);
}

test "builder basic" {
    const allocator = std.testing.allocator;

    var builder = try SymbolTableBuilder.init(allocator, "test.py");
    defer builder.deinit();

    _ = try builder.enterModule();

    // Add a function
    _ = try builder.enterFunction("foo", .{ .lineno = 1, .col_offset = 0, .end_lineno = 5, .end_col_offset = 0 });
    try builder.addParameter("x", .{ .lineno = 1, .col_offset = 8 });
    try builder.addDef("y", .{ .local = true }, .{ .lineno = 2 });
    builder.exitBlock();

    const table = try builder.build();
    defer table.deinit();

    try std.testing.expect(!builder.hasErrors());
    try std.testing.expect(table.top != null);
}
