/// entry - Symbol Table Entry
/// Per-scope symbol information and child scope tracking.

const std = @import("std");
const Allocator = std.mem.Allocator;
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");

pub const BlockType = types.BlockType;
pub const ComprehensionType = types.ComprehensionType;
pub const SymbolFlags = types.SymbolFlags;
pub const Scope = types.Scope;
pub const SourceLocation = types.SourceLocation;

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
    table: ?*anyopaque = null, // SymbolTable pointer

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
        self.symbols.deinit(self.allocator);

        // Free varnames
        for (self.varnames.items) |name| {
            self.allocator.free(name);
        }
        self.varnames.deinit(self.allocator);

        // Free children (recursive)
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit(self.allocator);

        // Free directive maps
        self.global_names.deinit(self.allocator);
        self.nonlocal_names.deinit(self.allocator);

        // Free name
        self.allocator.free(self.name);
    }

    /// Add a symbol to this scope
    pub fn addSymbol(self: *Self, name: []const u8, flags: SymbolFlags, location: SourceLocation) !void {
        const result = try self.symbols.getOrPut(self.allocator, try self.allocator.dupe(u8, name));
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
        try self.varnames.append(self.allocator, try self.allocator.dupe(u8, name));
        try self.addSymbol(name, .{ .param = true }, location);
    }

    /// Add a child scope
    pub fn addChild(self: *Self, child: *SymbolTableEntry) !void {
        child.parent = self;
        child.nested = self.nested or isFunctionLike(self);
        try self.children.append(self.allocator, child);
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
                try free.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
            }
        }
        return free.toOwnedSlice(allocator);
    }

    /// Get all cell variables
    pub fn getCellVars(self: *Self, allocator: Allocator) ![][]const u8 {
        var cells = std.ArrayList([]const u8).init(allocator);
        var it = self.symbols.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.scope == .cell) {
                try cells.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
            }
        }
        return cells.toOwnedSlice(allocator);
    }

    /// Get all local variables
    pub fn getLocals(self: *Self, allocator: Allocator) ![][]const u8 {
        var locals = std.ArrayList([]const u8).init(allocator);
        var it = self.symbols.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.scope == .local) {
                try locals.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
            }
        }
        return locals.toOwnedSlice(allocator);
    }

    /// Get all global variables
    pub fn getGlobals(self: *Self, allocator: Allocator) ![][]const u8 {
        var globals = std.ArrayList([]const u8).init(allocator);
        var it = self.symbols.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.scope == .global_explicit or
                entry.value_ptr.scope == .global_implicit)
            {
                try globals.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
            }
        }
        return globals.toOwnedSlice(allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

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
