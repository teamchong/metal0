/// Unified Comparison Dispatcher
///
/// Single entry point for all comparison operations.
/// Routes to runtime functions based on type patterns.
///
/// | Type Pattern | Eq/NotEq | Ordering | In/NotIn | Is/IsNot |
/// |--------------|----------|----------|----------|----------|
/// | primitives | native == | native < | N/A | native == |
/// | strings | std.mem.eql | std.mem.order | indexOf | ptr compare |
/// | containers | pyAnyEql | pyValueLt | pyContains | ptr compare |
/// | class inst | __eq__/pyAnyEql | __lt__/pyValueLt | __contains__ | ptr compare |
/// | unknown | pyAnyEql | pyValueLt | pyContains | @TypeOf check |
///
/// Usage: Replace 16+ specialized branches in genCompare with single dispatcher call
///
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const shared = @import("../../shared_maps.zig");
const CompOpStrings = shared.CompOpStrings;

/// CompareOp alias for clarity
pub const CompareOp = ast.CompareOp;

/// Classification of operand types for dispatch
const TypeClass = enum {
    primitive, // int, float, bool
    string, // string, bytes
    container, // list, dict, set, tuple
    class_instance, // user-defined class
    none, // None type
    unknown, // unknown, pyvalue, or needs runtime dispatch
};

/// Classify a NativeType for comparison dispatch
fn classifyType(t: NativeType) TypeClass {
    if (type_traits.isNone(t)) return .none;
    if (type_traits.isUnknown(t) or t == .pyvalue) return .unknown;
    if (type_traits.isClassInstance(t)) return .class_instance;
    if (string_traits.isStringLike(t)) return .string;
    if (container_traits.isContainer(t) or container_traits.isTuple(t)) return .container;
    // Complex numbers are NOT primitive - they need .eql() comparison, not native ==
    // Use std.meta.activeTag for 0.15 compatibility
    if (std.meta.activeTag(t) == .complex or std.meta.activeTag(t) == .pow_result) return .unknown;
    if (type_traits.isNumeric(t) or type_traits.isBoolean(t)) return .primitive;
    return .unknown;
}

// ============================================================================
// MAIN DISPATCHER
// ============================================================================

/// Unified comparison emission - single entry point for all comparison types
/// This replaces 16+ specialized branches in the original genCompare
pub fn emitComparison(
    self: *NativeCodegen,
    left: ast.Node,
    left_type: NativeType,
    op: CompareOp,
    right: ast.Node,
    right_type: NativeType,
) CodegenError!void {
    const left_class = classifyType(left_type);
    const right_class = classifyType(right_type);

    // Route based on operator category
    switch (op) {
        .Eq, .NotEq => try emitEqualityComparison(self, left, left_type, left_class, op, right, right_type, right_class),
        .Lt, .LtEq, .Gt, .GtEq => try emitOrderingComparison(self, left, left_type, left_class, op, right, right_type, right_class),
        .In, .NotIn => try emitContainmentCheck(self, left, left_type, left_class, op, right, right_type, right_class),
        .Is, .IsNot => try emitIdentityComparison(self, left, left_type, left_class, op, right, right_type, right_class),
    }
}

// ============================================================================
// EQUALITY COMPARISONS (==, !=)
// ============================================================================

fn emitEqualityComparison(
    self: *NativeCodegen,
    left: ast.Node,
    left_type: NativeType,
    left_class: TypeClass,
    op: CompareOp,
    right: ast.Node,
    right_type: NativeType,
    right_class: TypeClass,
) CodegenError!void {
    const is_neq = (op == .NotEq);

    // Both primitives: native comparison
    if (left_class == .primitive and right_class == .primitive) {
        try emitNativeComparison(self, left, left_type, op, right, right_type);
        return;
    }

    // Both strings: std.mem.eql
    if (left_class == .string and right_class == .string) {
        if (is_neq) try self.emit("!");
        try self.emit("std.mem.eql(u8, ");
        try genExpr(self, left);
        try self.emit(", ");
        try genExpr(self, right);
        try self.emit(")");
        return;
    }

    // None comparison: check for optional params
    if (left_class == .none or right_class == .none) {
        try emitNoneComparison(self, left, left_type, left_class, op, right, right_type, right_class);
        return;
    }

    // Class instance with known dunder method
    if (left_class == .class_instance) {
        if (try emitClassDunderCall(self, left, left_type, op, right)) return;
        // Fall through to pyAnyEql if no dunder
    }
    if (right_class == .class_instance and left_class != .class_instance) {
        if (try emitClassDunderCall(self, right, right_type, reverseOp(op), left)) return;
    }

    // Default: use runtime.pyAnyEql for Python semantics
    if (is_neq) try self.emit("!");
    try self.emit("runtime.pyAnyEql(");
    try genExpr(self, left);
    try self.emit(", ");
    try genExpr(self, right);
    try self.emit(")");
}

// ============================================================================
// ORDERING COMPARISONS (<, <=, >, >=)
// ============================================================================

fn emitOrderingComparison(
    self: *NativeCodegen,
    left: ast.Node,
    left_type: NativeType,
    left_class: TypeClass,
    op: CompareOp,
    right: ast.Node,
    right_type: NativeType,
    right_class: TypeClass,
) CodegenError!void {
    // Both primitives: native comparison with type coercion
    if (left_class == .primitive and right_class == .primitive) {
        try emitNativeComparison(self, left, left_type, op, right, right_type);
        return;
    }

    // Both strings: lexicographic ordering
    if (left_class == .string and right_class == .string) {
        try emitStringOrdering(self, left, op, right);
        return;
    }

    // Class instance with ordering dunder
    if (left_class == .class_instance) {
        if (try emitClassDunderCall(self, left, left_type, op, right)) return;
    }
    if (right_class == .class_instance and left_class != .class_instance) {
        if (try emitClassDunderCall(self, right, right_type, reverseOp(op), left)) return;
    }

    // Default: use runtime.pyValueLt/Le/Gt/Ge via PyValue conversion
    try emitPyValueOrdering(self, left, op, right);
}

// ============================================================================
// CONTAINMENT CHECKS (in, not in)
// ============================================================================

fn emitContainmentCheck(
    self: *NativeCodegen,
    left: ast.Node,
    left_type: NativeType,
    left_class: TypeClass,
    op: CompareOp,
    right: ast.Node,
    right_type: NativeType,
    right_class: TypeClass,
) CodegenError!void {
    const is_not_in = (op == .NotIn);
    _ = left_type;
    _ = left_class;

    // String substring check
    if (right_class == .string) {
        if (is_not_in) try self.emit("(");
        try self.emit("std.mem.indexOf(u8, ");
        try genExpr(self, right); // haystack
        try self.emit(", ");
        try genExpr(self, left); // needle
        if (is_not_in) {
            try self.emit(") == null)");
        } else {
            try self.emit(") != null");
        }
        return;
    }

    // Dict key containment - use runtime.container_dispatch.dictContains for type safety
    // This handles type mismatches (like int key on StringHashMap) by returning false
    if (container_traits.isDict(right_type)) {
        if (is_not_in) try self.emit("!");
        try self.emit("runtime.container_dispatch.dictContains(@TypeOf(");
        try genExpr(self, right);
        try self.emit("), @TypeOf(");
        try genExpr(self, left);
        try self.emit("), ");
        try genExpr(self, right);
        try self.emit(", ");
        try genExpr(self, left);
        try self.emit(")");
        return;
    }

    // Class instance with __contains__
    if (right_class == .class_instance) {
        if (is_not_in) try self.emit("!");
        try self.emit("(try ");
        try genExpr(self, right);
        try self.emit(".__contains__(__global_allocator, ");
        try genExpr(self, left);
        try self.emit("))");
        return;
    }

    // Default: use runtime.pyContains for lists/tuples/sets
    // Need to infer element type and handle list literals properly
    const right_is_list_literal = right == .list;

    if (right_is_list_literal) {
        // For list literals, use inline for loop to avoid slice coercion issues
        // Check: for (array) |item| if (item == value) ...
        if (is_not_in) try self.emit("!");
        try self.emit("(inline_blk: { for (");
        try genExpr(self, right);
        try self.emit(") |__item| { if (runtime.pyAnyEql(__item, ");
        try genExpr(self, left);
        try self.emit(")) break :inline_blk true; } break :inline_blk false; })");
    } else if (container_traits.isList(right_type)) {
        // ArrayList type: use .items to get slice
        const elem_type = right_type.list.*.toSimpleZigType();
        if (is_not_in) try self.emit("!");
        try self.emitFmt("runtime.pyContains({s}, ", .{elem_type});
        try genExpr(self, right);
        try self.emit(".items, ");
        try genExpr(self, left);
        try self.emit(")");
    } else {
        // Other containers: use container_dispatch
        if (is_not_in) try self.emit("!");
        try self.emit("runtime.container_dispatch.contains(@TypeOf(");
        try genExpr(self, right);
        try self.emit("), ");
        try genExpr(self, right);
        try self.emit(", ");
        try genExpr(self, left);
        try self.emit(")");
    }
}

// ============================================================================
// IDENTITY COMPARISONS (is, is not)
// ============================================================================

fn emitIdentityComparison(
    self: *NativeCodegen,
    left: ast.Node,
    left_type: NativeType,
    left_class: TypeClass,
    op: CompareOp,
    right: ast.Node,
    right_type: NativeType,
    right_class: TypeClass,
) CodegenError!void {
    const is_is = (op == .Is);
    // These types are only used for class instance checks (handled by left_class/right_class)
    _ = left_type;
    _ = right_type;

    // None identity check
    if (left_class == .none or right_class == .none) {
        // For anytype/optional params, use comptime type check
        const check_side = if (left_class == .none) right else left;
        try self.emit("(@TypeOf(");
        try genExpr(self, check_side);
        if (is_is) {
            try self.emit(") == @TypeOf(null))");
        } else {
            try self.emit(") != @TypeOf(null))");
        }
        return;
    }

    // Literal containers: always distinct identity
    const left_is_literal = left == .list or left == .dict or left == .set;
    const right_is_literal = right == .list or right == .dict or right == .set;
    if (left_is_literal and right_is_literal) {
        try self.emit(if (is_is) "false" else "true");
        return;
    }

    // Primitives: identity == equality
    if (left_class == .primitive and right_class == .primitive) {
        try genExpr(self, left);
        try self.emit(if (is_is) " == " else " != ");
        try genExpr(self, right);
        return;
    }

    // Default: compare addresses using runtime.pyIdentical
    if (!is_is) try self.emit("!");
    try self.emit("runtime.pyIdentical(");
    try genExpr(self, left);
    try self.emit(", ");
    try genExpr(self, right);
    try self.emit(")");
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Emit native comparison for primitives with proper type coercion
fn emitNativeComparison(
    self: *NativeCodegen,
    left: ast.Node,
    left_type: NativeType,
    op: CompareOp,
    right: ast.Node,
    right_type: NativeType,
) CodegenError!void {
    const left_is_usize = (left_type == .usize);
    const right_is_usize = (right_type == .usize);
    const left_is_int = type_traits.isIntegral(left_type);
    const right_is_int = type_traits.isIntegral(right_type);
    const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

    // Cast left operand if needed
    if (left_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
    }
    try genExpr(self, left);
    if (left_is_usize and needs_cast) {
        try self.emit("))");
    }

    try self.emit(CompOpStrings.get(@tagName(op)) orelse " == ");

    // Cast right operand if needed
    if (right_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
    }
    try genExpr(self, right);
    if (right_is_usize and needs_cast) {
        try self.emit("))");
    }
}

/// Emit None comparison handling optional parameters
fn emitNoneComparison(
    self: *NativeCodegen,
    left: ast.Node,
    left_type: NativeType,
    left_class: TypeClass,
    op: CompareOp,
    right: ast.Node,
    right_type: NativeType,
    right_class: TypeClass,
) CodegenError!void {
    const is_eq = (op == .Eq);

    // Check for optional parameter (tracked in none_default_params)
    const check_var = if (left_class == .none) right else left;
    const is_optional_param = blk: {
        if (check_var != .name) break :blk false;
        const var_name = check_var.name.id;
        if (self.none_default_params.contains(var_name)) break :blk true;
        if (self.anytype_params.contains(var_name)) break :blk true;
        if (self.var_renames.get(var_name) != null) break :blk true;
        break :blk false;
    };

    if (is_optional_param) {
        // Use comptime type check for anytype params
        try self.emit("(@TypeOf(");
        try genExpr(self, check_var);
        if (is_eq) {
            try self.emit(") == @TypeOf(null))");
        } else {
            try self.emit(") != @TypeOf(null))");
        }
    } else if (type_traits.isOptional(if (left_class == .none) right_type else left_type)) {
        // Known optional type: direct null comparison
        try genExpr(self, check_var);
        try self.emit(if (is_eq) " == null" else " != null");
    } else {
        // Different types: compile-time known result
        if (left_class != right_class) {
            try self.emit(if (is_eq) "false" else "true");
        } else {
            // Both None
            try self.emit(if (is_eq) "true" else "false");
        }
    }
}

/// Emit class dunder method call if available
/// Returns true if call was emitted, false to fall through to default
fn emitClassDunderCall(
    self: *NativeCodegen,
    class_operand: ast.Node,
    class_type: NativeType,
    op: CompareOp,
    other_operand: ast.Node,
) CodegenError!bool {
    if (class_type != .class_instance) return false;

    const class_name = class_type.class_instance;
    const class_info = self.type_inferrer.class_fields.get(class_name) orelse return false;

    const method_name = switch (op) {
        .Eq => "__eq__",
        .NotEq => "__ne__",
        .Lt => "__lt__",
        .LtEq => "__le__",
        .Gt => "__gt__",
        .GtEq => "__ge__",
        else => return false,
    };

    if (!class_info.methods.contains(method_name)) {
        // Try fallback for NotEq -> !__eq__
        if (op == .NotEq and class_info.methods.contains("__eq__")) {
            try self.emit("!");
            try genExpr(self, class_operand);
            try self.emit(".__eq__(");
            try genExpr(self, other_operand);
            try self.emit(")");
            return true;
        }
        return false;
    }

    // Emit method call
    if (op == .Lt or op == .LtEq or op == .Gt or op == .GtEq) {
        // Ordering methods return PyValue, need toBool
        try self.emit("runtime.toBool(");
    }
    try genExpr(self, class_operand);
    try self.emitFmt(".{s}(", .{method_name});
    try genExpr(self, other_operand);
    try self.emit(")");
    if (op == .Lt or op == .LtEq or op == .Gt or op == .GtEq) {
        try self.emit(")");
    }
    return true;
}

/// Emit string ordering comparison using std.mem.order
fn emitStringOrdering(
    self: *NativeCodegen,
    left: ast.Node,
    op: CompareOp,
    right: ast.Node,
) CodegenError!void {
    try self.emit("(std.mem.order(u8, ");
    try genExpr(self, left);
    try self.emit(", ");
    try genExpr(self, right);
    try self.emit(") == ");
    switch (op) {
        .Lt => try self.emit(".lt"),
        .LtEq => try self.emit(".lt or std.mem.order(u8, "),
        .Gt => try self.emit(".gt"),
        .GtEq => try self.emit(".gt or std.mem.order(u8, "),
        else => try self.emit(".eq"),
    }
    // Handle <= and >= which need extra check
    if (op == .LtEq or op == .GtEq) {
        try genExpr(self, left);
        try self.emit(", ");
        try genExpr(self, right);
        try self.emit(") == .eq");
    }
    try self.emit(")");
}

/// Emit PyValue ordering comparison
fn emitPyValueOrdering(
    self: *NativeCodegen,
    left: ast.Node,
    op: CompareOp,
    right: ast.Node,
) CodegenError!void {
    const method = switch (op) {
        .Lt => "lt",
        .LtEq => "le",
        .Gt => "gt",
        .GtEq => "ge",
        else => "lt",
    };
    try self.emit("runtime.PyValue.from(");
    try genExpr(self, left);
    try self.emitFmt(").{s}(runtime.PyValue.from(", .{method});
    try genExpr(self, right);
    try self.emit("))");
}

/// Reverse comparison operator for reflected dunder calls
fn reverseOp(op: CompareOp) CompareOp {
    return switch (op) {
        .Lt => .Gt,
        .LtEq => .GtEq,
        .Gt => .Lt,
        .GtEq => .LtEq,
        else => op, // Eq, NotEq, In, NotIn, Is, IsNot are symmetric
    };
}
