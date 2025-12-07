/// optimizer_analysis - Optimizer Analysis
/// Mirrors cpython/Python/optimizer_analysis.c
///
/// Provides analysis routines for the bytecode optimizer including
/// type inference, escape analysis, and data flow analysis.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Type Inference
// ============================================================================

/// Type lattice for abstract interpretation
pub const TypeLattice = enum(u8) {
    /// Unknown type (bottom)
    bottom,
    /// No possible value (top/unreachable)
    top,
    /// None singleton
    none_type,
    /// Boolean
    bool_type,
    /// Small integer
    small_int,
    /// Large integer (arbitrary precision)
    big_int,
    /// Float
    float_type,
    /// Complex number
    complex_type,
    /// String
    str_type,
    /// Bytes
    bytes_type,
    /// List
    list_type,
    /// Tuple
    tuple_type,
    /// Dict
    dict_type,
    /// Set
    set_type,
    /// Frozenset
    frozenset_type,
    /// Function
    function_type,
    /// Method
    method_type,
    /// Module
    module_type,
    /// Class/type
    type_type,
    /// Object (any object)
    object_type,

    /// Join two types in the lattice
    pub fn join(self: TypeLattice, other: TypeLattice) TypeLattice {
        if (self == .bottom) return other;
        if (other == .bottom) return self;
        if (self == other) return self;
        if (self == .top or other == .top) return .top;

        // Numeric types join to object
        if (isNumeric(self) and isNumeric(other)) return .object_type;

        // Sequence types join to object
        if (isSequence(self) and isSequence(other)) return .object_type;

        return .object_type;
    }

    /// Meet two types in the lattice
    pub fn meet(self: TypeLattice, other: TypeLattice) TypeLattice {
        if (self == .top) return other;
        if (other == .top) return self;
        if (self == other) return self;
        return .bottom;
    }

    /// Check if type is numeric
    pub fn isNumeric(t: TypeLattice) bool {
        return t == .small_int or t == .big_int or t == .float_type or t == .complex_type;
    }

    /// Check if type is sequence
    pub fn isSequence(t: TypeLattice) bool {
        return t == .str_type or t == .bytes_type or t == .list_type or t == .tuple_type;
    }

    /// Check if type is container
    pub fn isContainer(t: TypeLattice) bool {
        return isSequence(t) or t == .dict_type or t == .set_type or t == .frozenset_type;
    }
};

/// Type state for a stack slot
pub const TypeState = struct {
    /// Primary type
    type_lattice: TypeLattice = .bottom,
    /// Confidence (0.0 - 1.0)
    confidence: f32 = 0.0,
    /// Known constant value (if any)
    const_value: ?ConstValue = null,
    /// Version (for SSA)
    version: u32 = 0,

    /// Create unknown type state
    pub fn unknown() TypeState {
        return .{ .type_lattice = .bottom };
    }

    /// Create type state from lattice type
    pub fn fromType(t: TypeLattice) TypeState {
        return .{ .type_lattice = t, .confidence = 1.0 };
    }

    /// Join with another state
    pub fn join(self: TypeState, other: TypeState) TypeState {
        return TypeState{
            .type_lattice = self.type_lattice.join(other.type_lattice),
            .confidence = @min(self.confidence, other.confidence),
            .const_value = if (self.const_value != null and other.const_value != null and
                self.const_value.?.eql(other.const_value.?))
                self.const_value
            else
                null,
            .version = @max(self.version, other.version) + 1,
        };
    }
};

/// Constant value for constant propagation
pub const ConstValue = union(enum) {
    none: void,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    str_val: []const u8,

    pub fn eql(self: ConstValue, other: ConstValue) bool {
        return switch (self) {
            .none => other == .none,
            .bool_val => |b| other == .bool_val and other.bool_val == b,
            .int_val => |i| other == .int_val and other.int_val == i,
            .float_val => |f| other == .float_val and other.float_val == f,
            .str_val => |s| other == .str_val and std.mem.eql(u8, other.str_val, s),
        };
    }
};

// ============================================================================
// Data Flow Analysis
// ============================================================================

/// Abstract value for data flow
pub const AbstractValue = struct {
    /// Type information
    type_state: TypeState,
    /// Definition site (instruction index)
    def_site: u32,
    /// Uses of this value
    uses: std.ArrayList(u32),

    /// Create new abstract value
    pub fn init(allocator: Allocator, def_site: u32) AbstractValue {
        return AbstractValue{
            .type_state = TypeState.unknown(),
            .def_site = def_site,
            .uses = std.ArrayList(u32).init(allocator),
        };
    }

    /// Free resources
    pub fn deinit(self: *AbstractValue) void {
        self.uses.deinit();
    }

    /// Add use
    pub fn addUse(self: *AbstractValue, use_site: u32) !void {
        try self.uses.append(use_site);
    }
};

/// Data flow analysis state
pub const DataFlowState = struct {
    const Self = @This();

    /// Values at each stack slot
    stack: std.ArrayList(TypeState),
    /// Values at each local variable
    locals: std.ArrayList(TypeState),
    /// Values at each free variable
    freevars: std.ArrayList(TypeState),
    /// Memory allocator
    allocator: Allocator,

    /// Create new state
    pub fn init(allocator: Allocator, num_locals: usize, num_freevars: usize) !Self {
        var locals = std.ArrayList(TypeState).init(allocator);
        var freevars = std.ArrayList(TypeState).init(allocator);

        try locals.resize(num_locals);
        for (locals.items) |*s| s.* = TypeState.unknown();

        try freevars.resize(num_freevars);
        for (freevars.items) |*s| s.* = TypeState.unknown();

        return Self{
            .stack = std.ArrayList(TypeState).init(allocator),
            .locals = locals,
            .freevars = freevars,
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.stack.deinit();
        self.locals.deinit();
        self.freevars.deinit();
    }

    /// Push type to stack
    pub fn push(self: *Self, state: TypeState) !void {
        try self.stack.append(state);
    }

    /// Pop type from stack
    pub fn pop(self: *Self) ?TypeState {
        return self.stack.popOrNull();
    }

    /// Peek at top of stack
    pub fn peek(self: *const Self) ?TypeState {
        if (self.stack.items.len == 0) return null;
        return self.stack.items[self.stack.items.len - 1];
    }

    /// Get local type
    pub fn getLocal(self: *const Self, idx: usize) ?TypeState {
        if (idx >= self.locals.items.len) return null;
        return self.locals.items[idx];
    }

    /// Set local type
    pub fn setLocal(self: *Self, idx: usize, state: TypeState) !void {
        if (idx >= self.locals.items.len) {
            try self.locals.resize(idx + 1);
        }
        self.locals.items[idx] = state;
    }

    /// Join with another state
    pub fn join(self: *Self, other: *const Self) void {
        // Join stacks
        const min_len = @min(self.stack.items.len, other.stack.items.len);
        for (0..min_len) |i| {
            self.stack.items[i] = self.stack.items[i].join(other.stack.items[i]);
        }

        // Join locals
        for (0..@min(self.locals.items.len, other.locals.items.len)) |i| {
            self.locals.items[i] = self.locals.items[i].join(other.locals.items[i]);
        }
    }

    /// Clone state
    pub fn clone(self: *const Self) !Self {
        var new_state = Self{
            .stack = try self.stack.clone(),
            .locals = try self.locals.clone(),
            .freevars = try self.freevars.clone(),
            .allocator = self.allocator,
        };
        return new_state;
    }
};

// ============================================================================
// Escape Analysis
// ============================================================================

/// Escape state for an object
pub const EscapeState = enum(u8) {
    /// Object does not escape
    no_escape,
    /// Object escapes to caller via argument
    arg_escape,
    /// Object escapes to caller via return
    return_escape,
    /// Object escapes globally
    global_escape,
};

/// Escape analysis result
pub const EscapeInfo = struct {
    /// Object ID
    object_id: u32,
    /// Escape state
    state: EscapeState,
    /// Allocation site
    alloc_site: u32,
    /// Is object scalar replaceable
    scalar_replaceable: bool,

    /// Can object be stack allocated
    pub fn canStackAllocate(self: *const EscapeInfo) bool {
        return self.state == .no_escape or self.state == .arg_escape;
    }
};

/// Escape analyzer
pub const EscapeAnalyzer = struct {
    const Self = @This();

    allocator: Allocator,
    escape_info: std.AutoHashMap(u32, EscapeInfo),
    next_object_id: u32 = 0,

    /// Create new analyzer
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .escape_info = std.AutoHashMap(u32, EscapeInfo).init(allocator),
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.escape_info.deinit();
    }

    /// Track new allocation
    pub fn trackAllocation(self: *Self, alloc_site: u32) !u32 {
        const id = self.next_object_id;
        self.next_object_id += 1;

        try self.escape_info.put(id, .{
            .object_id = id,
            .state = .no_escape,
            .alloc_site = alloc_site,
            .scalar_replaceable = true,
        });

        return id;
    }

    /// Mark object as escaping
    pub fn markEscape(self: *Self, object_id: u32, state: EscapeState) void {
        if (self.escape_info.getPtr(object_id)) |info| {
            // Escalate escape state
            if (@intFromEnum(state) > @intFromEnum(info.state)) {
                info.state = state;
            }
            if (state == .global_escape) {
                info.scalar_replaceable = false;
            }
        }
    }

    /// Get escape info for object
    pub fn getInfo(self: *const Self, object_id: u32) ?EscapeInfo {
        return self.escape_info.get(object_id);
    }
};

// ============================================================================
// Range Analysis
// ============================================================================

/// Integer range
pub const IntRange = struct {
    min: i64,
    max: i64,
    is_constant: bool = false,

    /// Create unknown range
    pub fn unknown() IntRange {
        return .{ .min = std.math.minInt(i64), .max = std.math.maxInt(i64) };
    }

    /// Create constant range
    pub fn constant(value: i64) IntRange {
        return .{ .min = value, .max = value, .is_constant = true };
    }

    /// Create bounded range
    pub fn bounded(min: i64, max: i64) IntRange {
        return .{ .min = min, .max = max, .is_constant = min == max };
    }

    /// Join two ranges
    pub fn join(self: IntRange, other: IntRange) IntRange {
        return .{
            .min = @min(self.min, other.min),
            .max = @max(self.max, other.max),
            .is_constant = false,
        };
    }

    /// Intersect two ranges
    pub fn intersect(self: IntRange, other: IntRange) ?IntRange {
        const new_min = @max(self.min, other.min);
        const new_max = @min(self.max, other.max);
        if (new_min > new_max) return null;
        return .{
            .min = new_min,
            .max = new_max,
            .is_constant = new_min == new_max,
        };
    }

    /// Check if can overflow on addition
    pub fn canOverflowAdd(self: IntRange, other: IntRange) bool {
        // Check for positive overflow
        if (self.max > 0 and other.max > std.math.maxInt(i64) - self.max) return true;
        // Check for negative overflow
        if (self.min < 0 and other.min < std.math.minInt(i64) - self.min) return true;
        return false;
    }

    /// Add two ranges
    pub fn add(self: IntRange, other: IntRange) IntRange {
        return .{
            .min = self.min +| other.min,
            .max = self.max +| other.max,
            .is_constant = self.is_constant and other.is_constant,
        };
    }

    /// Multiply two ranges
    pub fn mul(self: IntRange, other: IntRange) IntRange {
        const products = [_]i64{
            self.min *| other.min,
            self.min *| other.max,
            self.max *| other.min,
            self.max *| other.max,
        };
        var min = products[0];
        var max = products[0];
        for (products[1..]) |p| {
            min = @min(min, p);
            max = @max(max, p);
        }
        return .{
            .min = min,
            .max = max,
            .is_constant = self.is_constant and other.is_constant,
        };
    }
};

// ============================================================================
// Analysis Driver
// ============================================================================

/// Analysis context
pub const AnalysisContext = struct {
    const Self = @This();

    allocator: Allocator,
    dataflow: DataFlowState,
    escape: EscapeAnalyzer,
    warnings: std.ArrayList(AnalysisWarning),

    /// Create new context
    pub fn init(allocator: Allocator, num_locals: usize) !Self {
        return Self{
            .allocator = allocator,
            .dataflow = try DataFlowState.init(allocator, num_locals, 0),
            .escape = EscapeAnalyzer.init(allocator),
            .warnings = std.ArrayList(AnalysisWarning).init(allocator),
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.dataflow.deinit();
        self.escape.deinit();
        self.warnings.deinit();
    }

    /// Add warning
    pub fn warn(self: *Self, kind: WarningKind, location: u32, message: []const u8) !void {
        try self.warnings.append(.{
            .kind = kind,
            .location = location,
            .message = message,
        });
    }
};

/// Analysis warning
pub const AnalysisWarning = struct {
    kind: WarningKind,
    location: u32,
    message: []const u8,
};

/// Warning types
pub const WarningKind = enum {
    type_mismatch,
    possible_null,
    dead_code,
    unused_variable,
    possible_overflow,
    escape_detected,
};

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the optimizer analysis module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "type lattice join" {
    try std.testing.expectEqual(TypeLattice.small_int, TypeLattice.bottom.join(.small_int));
    try std.testing.expectEqual(TypeLattice.float_type, TypeLattice.float_type.join(.float_type));
    try std.testing.expectEqual(TypeLattice.object_type, TypeLattice.small_int.join(.float_type));
}

test "type state join" {
    const s1 = TypeState.fromType(.small_int);
    const s2 = TypeState.fromType(.small_int);
    const s3 = TypeState.fromType(.float_type);

    const joined_same = s1.join(s2);
    try std.testing.expectEqual(TypeLattice.small_int, joined_same.type_lattice);

    const joined_diff = s1.join(s3);
    try std.testing.expectEqual(TypeLattice.object_type, joined_diff.type_lattice);
}

test "dataflow state" {
    const allocator = std.testing.allocator;

    var state = try DataFlowState.init(allocator, 3, 0);
    defer state.deinit();

    try state.push(TypeState.fromType(.small_int));
    try state.push(TypeState.fromType(.float_type));

    try std.testing.expectEqual(@as(usize, 2), state.stack.items.len);
    try std.testing.expectEqual(TypeLattice.float_type, state.peek().?.type_lattice);

    _ = state.pop();
    try std.testing.expectEqual(TypeLattice.small_int, state.peek().?.type_lattice);
}

test "int range arithmetic" {
    const r1 = IntRange.bounded(0, 10);
    const r2 = IntRange.bounded(5, 15);

    const joined = r1.join(r2);
    try std.testing.expectEqual(@as(i64, 0), joined.min);
    try std.testing.expectEqual(@as(i64, 15), joined.max);

    const intersected = r1.intersect(r2);
    try std.testing.expect(intersected != null);
    try std.testing.expectEqual(@as(i64, 5), intersected.?.min);
    try std.testing.expectEqual(@as(i64, 10), intersected.?.max);
}

test "escape analysis" {
    const allocator = std.testing.allocator;

    var analyzer = EscapeAnalyzer.init(allocator);
    defer analyzer.deinit();

    const obj_id = try analyzer.trackAllocation(0);
    try std.testing.expectEqual(EscapeState.no_escape, analyzer.getInfo(obj_id).?.state);

    analyzer.markEscape(obj_id, .arg_escape);
    try std.testing.expectEqual(EscapeState.arg_escape, analyzer.getInfo(obj_id).?.state);
    try std.testing.expect(analyzer.getInfo(obj_id).?.canStackAllocate());

    analyzer.markEscape(obj_id, .global_escape);
    try std.testing.expectEqual(EscapeState.global_escape, analyzer.getInfo(obj_id).?.state);
    try std.testing.expect(!analyzer.getInfo(obj_id).?.canStackAllocate());
}
