/// AST Bridge - Convert AST expressions to ZigValues with type confidence
///
/// This is the key integration point for structured codegen.
/// Converts Python AST expressions to ZigValues, enabling:
/// - Type-safe operations (compile-time checks on value compatibility)
/// - Automatic PyValue wrapping for uncertain types (Two-Flow TypeSystem)
/// - Unified comparison dispatch through builder APIs
///
/// All expression types are converted to ZigValue with confidence tracking.
/// The builder can then emit appropriate code based on confidence levels.
///
const std = @import("std");
const ast = @import("analysis.ast");
const ZigValue = @import("zig_value.zig").ZigValue;
const TypeConfidence = @import("zig_value.zig").TypeConfidence;
const TypeHint = @import("zig_value.zig").TypeHint;
const CompOp = @import("zig_value.zig").CompOp;
const BinOp = @import("zig_value.zig").BinOp;

/// AST to ZigValue bridge
/// Maintains reference to codegen state for type inference and variable tracking
pub const AstBridge = struct {
    allocator: std.mem.Allocator,

    /// Arena allocator for string allocations (freed all at once)
    arena: std.mem.Allocator,

    /// Callback to get inferred type for a variable name
    /// Returns null if type is unknown
    get_var_type: ?*const fn (name: []const u8) ?TypeHint,

    /// Callback to check if a variable is a PyValue type
    is_pyvalue_var: ?*const fn (name: []const u8) bool,

    /// Callback to apply variable renames (comprehension, params, etc.)
    apply_rename: ?*const fn (name: []const u8) []const u8,

    /// Callback to emit expression to buffer and return raw string
    /// Used for complex expressions not yet migrated
    emit_expr: ?*const fn (node: ast.Node) ?[]const u8,

    /// Initialize bridge with allocator only (for simple cases)
    pub fn init(allocator: std.mem.Allocator, arena: std.mem.Allocator) AstBridge {
        return .{
            .allocator = allocator,
            .arena = arena,
            .get_var_type = null,
            .is_pyvalue_var = null,
            .apply_rename = null,
            .emit_expr = null,
        };
    }

    // ============================================
    // Main Conversion Entry Point
    // ============================================

    /// Convert any AST expression node to a ZigValue with type confidence
    ///
    /// Returns:
    /// - .certain_* variants for known types (literals, annotated variables)
    /// - .uncertain_pyvalue for unknown types (user functions, subscripts)
    /// - .raw_expr for complex expressions that need to be emitted as-is
    pub fn exprToValue(self: *AstBridge, node: ast.Node) !ZigValue {
        return switch (node) {
            // Literals - always certain
            .constant => |c| self.constantToValue(c),

            // Names - check confidence from type inferrer
            .name => |n| self.nameToValue(n),

            // Binary operations - defer to builder
            .binop => |b| self.binOpToValue(b),

            // Unary operations
            .unaryop => |u| self.unaryOpToValue(u),

            // Comparisons
            .compare => |c| try self.compareToValue(c),

            // Boolean operations (and/or)
            .boolop => |b| try self.boolOpToValue(b),

            // Function/method calls
            .call => |c| try self.callToValue(c),

            // Attribute access (obj.field)
            .attribute => |a| try self.attributeToValue(a),

            // Subscript access (obj[idx])
            .subscript => |s| try self.subscriptToValue(s),

            // Container literals
            .list => |l| try self.listToValue(l),
            .tuple => |t| try self.tupleToValue(t),
            .dict => |d| try self.dictToValue(d),
            .set => |s| try self.setToValue(s),

            // Comprehensions
            .listcomp => try self.comprehensionToValue(node),
            .dictcomp => try self.comprehensionToValue(node),
            .genexp => try self.comprehensionToValue(node),

            // Conditional expression (ternary)
            .if_expr => |i| try self.ifExprToValue(i),

            // Lambda
            .lambda => try self.lambdaToValue(node),

            // F-strings
            .fstring => try self.fstringToValue(node),

            // Star expressions
            .starred => |s| try self.starredToValue(s),

            // Walrus operator
            .named_expr => |n| try self.namedExprToValue(n),

            // Slice range
            .slice_expr => |s| try self.sliceExprToValue(s),

            // Await expression
            .await_expr => |a| try self.awaitExprToValue(a),

            // Ellipsis literal
            .ellipsis_literal => ZigValue.raw("runtime.Ellipsis"),

            // Statements and other nodes - not expressions
            else => self.fallbackToRaw(node),
        };
    }

    // ============================================
    // Literal Converters
    // ============================================

    fn constantToValue(self: *AstBridge, c: ast.Node.Constant) ZigValue {
        _ = self;
        return switch (c.value) {
            .int => |i| ZigValue.int(i),
            .float => |f| ZigValue.float(f),
            .string => |s| ZigValue.string(s),
            .bool => |b| ZigValue.boolean(b),
            .none => ZigValue.null_(),
            .bytes => |s| ZigValue.string(s),
            // BigInt and complex need special handling
            .bigint, .complex => ZigValue.pyvalue(.unknown),
        };
    }

    // ============================================
    // Name/Variable Converters
    // ============================================

    fn nameToValue(self: *AstBridge, n: ast.Node.Name) ZigValue {
        const orig_name = n.id;

        // Check for Python singletons first
        if (std.mem.eql(u8, orig_name, "True")) {
            return ZigValue.boolean(true);
        }
        if (std.mem.eql(u8, orig_name, "False")) {
            return ZigValue.boolean(false);
        }
        if (std.mem.eql(u8, orig_name, "None")) {
            return ZigValue.null_();
        }

        // Apply variable rename if callback provided
        const name = if (self.apply_rename) |f| f(orig_name) else orig_name;

        // Check if it's a PyValue variable
        if (self.is_pyvalue_var) |f| {
            if (f(name)) {
                return ZigValue.raw(name);
            }
        }

        // Check type from inferrer
        if (self.get_var_type) |f| {
            if (f(name)) |hint| {
                // Map hint to ZigValue type
                return switch (hint) {
                    .int_like => ZigValue.fromName(name),
                    .float_like => ZigValue.fromName(name),
                    .str_like => ZigValue.fromName(name),
                    .bool_like => ZigValue.fromName(name),
                    .none_like => ZigValue.fromName(name),
                    .list_like, .dict_like, .class_instance, .callable, .unknown => ZigValue.raw(name),
                };
            }
        }

        // Default: named binding (assume certain)
        return ZigValue.fromName(name);
    }

    // ============================================
    // Operation Converters
    // ============================================

    fn binOpToValue(self: *AstBridge, b: ast.Node.BinOp) ZigValue {
        _ = self;
        _ = b;
        // Binary operations: for now return uncertain
        // The builder will handle the actual emission
        return ZigValue.pyvalue(.unknown);
    }

    fn unaryOpToValue(self: *AstBridge, u: ast.Node.UnaryOp) ZigValue {
        _ = self;
        _ = u;
        // Unary operations: return uncertain
        return ZigValue.pyvalue(.unknown);
    }

    fn compareToValue(self: *AstBridge, c: ast.Node.Compare) !ZigValue {
        _ = self;
        _ = c;
        // Comparisons always return bool, but marked uncertain since
        // the comparison itself may need runtime dispatch
        return ZigValue.pyvalue(.bool_like);
    }

    fn boolOpToValue(self: *AstBridge, b: ast.Node.BoolOp) !ZigValue {
        _ = self;
        _ = b;
        // Boolean operations return bool
        return ZigValue.pyvalue(.bool_like);
    }

    // ============================================
    // Call/Access Converters
    // ============================================

    fn callToValue(self: *AstBridge, c: ast.Node.Call) !ZigValue {
        _ = self;
        // Check for known builtins with certain return types
        if (c.func.* == .name) {
            const func_name = c.func.name.id;
            // len() returns int
            if (std.mem.eql(u8, func_name, "len")) {
                return ZigValue.pyvalue(.int_like);
            }
            // bool() returns bool
            if (std.mem.eql(u8, func_name, "bool")) {
                return ZigValue.pyvalue(.bool_like);
            }
            // int() returns int
            if (std.mem.eql(u8, func_name, "int")) {
                return ZigValue.pyvalue(.int_like);
            }
            // float() returns float
            if (std.mem.eql(u8, func_name, "float")) {
                return ZigValue.pyvalue(.float_like);
            }
            // str() returns str
            if (std.mem.eql(u8, func_name, "str")) {
                return ZigValue.pyvalue(.str_like);
            }
        }
        // Default: unknown return type
        return ZigValue.pyvalue(.unknown);
    }

    fn attributeToValue(self: *AstBridge, a: ast.Node.Attribute) !ZigValue {
        _ = self;
        _ = a;
        // Attribute access: uncertain unless we have type info
        return ZigValue.pyvalue(.unknown);
    }

    fn subscriptToValue(self: *AstBridge, s: ast.Node.Subscript) !ZigValue {
        _ = self;
        _ = s;
        // Subscript access: always uncertain (could be any type)
        return ZigValue.pyvalue(.unknown);
    }

    // ============================================
    // Container Converters
    // ============================================

    fn listToValue(self: *AstBridge, l: ast.Node.List) !ZigValue {
        _ = self;
        _ = l;
        // List literal: uncertain (mixed types possible)
        return ZigValue.pyvalue(.list_like);
    }

    fn tupleToValue(self: *AstBridge, t: ast.Node.Tuple) !ZigValue {
        _ = self;
        _ = t;
        // Tuple literal: uncertain
        return ZigValue.pyvalue(.unknown);
    }

    fn dictToValue(self: *AstBridge, d: ast.Node.Dict) !ZigValue {
        _ = self;
        _ = d;
        // Dict literal: uncertain
        return ZigValue.pyvalue(.dict_like);
    }

    fn setToValue(self: *AstBridge, s: ast.Node.Set) !ZigValue {
        _ = self;
        _ = s;
        // Set literal: uncertain
        return ZigValue.pyvalue(.unknown);
    }

    fn comprehensionToValue(self: *AstBridge, node: ast.Node) !ZigValue {
        _ = self;
        _ = node;
        // Comprehensions: uncertain
        return ZigValue.pyvalue(.list_like);
    }

    // ============================================
    // Expression Converters
    // ============================================

    fn ifExprToValue(self: *AstBridge, i: ast.Node.IfExpr) !ZigValue {
        _ = self;
        _ = i;
        // Ternary: uncertain (depends on branches)
        return ZigValue.pyvalue(.unknown);
    }

    fn lambdaToValue(self: *AstBridge, node: ast.Node) !ZigValue {
        _ = self;
        _ = node;
        // Lambda: callable
        return ZigValue.pyvalue(.callable);
    }

    fn fstringToValue(self: *AstBridge, node: ast.Node) !ZigValue {
        _ = self;
        _ = node;
        // F-string: returns string
        return ZigValue.pyvalue(.str_like);
    }

    fn starredToValue(self: *AstBridge, s: ast.Node.Starred) !ZigValue {
        // Starred expression: get value and mark uncertain
        _ = s;
        _ = self;
        return ZigValue.pyvalue(.unknown);
    }

    fn namedExprToValue(self: *AstBridge, n: ast.Node.NamedExpr) !ZigValue {
        // Walrus operator: return the value's type
        return self.exprToValue(n.value.*);
    }

    fn sliceExprToValue(self: *AstBridge, s: ast.Node.SliceRange) !ZigValue {
        _ = self;
        _ = s;
        // Slice range: uncertain
        return ZigValue.pyvalue(.unknown);
    }

    fn awaitExprToValue(self: *AstBridge, a: ast.Node.AwaitExpr) !ZigValue {
        _ = self;
        _ = a;
        // Await: uncertain (async result)
        return ZigValue.pyvalue(.unknown);
    }

    // ============================================
    // Fallback
    // ============================================

    fn fallbackToRaw(self: *AstBridge, node: ast.Node) ZigValue {
        // For nodes not yet handled: use emit callback if available
        if (self.emit_expr) |f| {
            if (f(node)) |raw| {
                return ZigValue.raw(raw);
            }
        }
        // Otherwise return uncertain
        return ZigValue.pyvalue(.unknown);
    }

    // ============================================
    // Utility Functions
    // ============================================

    /// Convert Python comparison operator to CompOp
    pub fn cmpOpToCompOp(op: ast.CmpOp) CompOp {
        return switch (op) {
            .Eq => .eq,
            .NotEq => .ne,
            .Lt => .lt,
            .LtE => .le,
            .Gt => .gt,
            .GtE => .ge,
            .In => .in_,
            .NotIn => .not_in,
            .Is => .is,
            .IsNot => .is_not,
        };
    }

    /// Convert Python binary operator to BinOp
    pub fn operatorToBinOp(op: ast.Operator) BinOp {
        return switch (op) {
            .Add => .add,
            .Sub => .sub,
            .Mult => .mul,
            .Div => .div,
            .FloorDiv => .floor_div,
            .Mod => .mod,
            .Pow => .pow,
            .BitAnd => .bit_and,
            .BitOr => .bit_or,
            .BitXor => .bit_xor,
            .LShift => .lshift,
            .RShift => .rshift,
            .MatMult => .mul, // Matrix multiplication maps to mul for now
        };
    }
};

// ============================================
// Tests
// ============================================

test "AstBridge.constantToValue" {
    var bridge = AstBridge.init(std.testing.allocator, std.testing.allocator);

    // Integer constant
    const int_const = ast.Node.Constant{ .value = .{ .int = 42 } };
    const int_val = bridge.constantToValue(int_const);
    try std.testing.expect(int_val == .certain_int);
    try std.testing.expectEqual(@as(i64, 42), int_val.certain_int);

    // Float constant
    const float_const = ast.Node.Constant{ .value = .{ .float = 3.14 } };
    const float_val = bridge.constantToValue(float_const);
    try std.testing.expect(float_val == .certain_float);

    // String constant
    const str_const = ast.Node.Constant{ .value = .{ .string = "hello" } };
    const str_val = bridge.constantToValue(str_const);
    try std.testing.expect(str_val == .certain_str);

    // Bool constant
    const bool_const = ast.Node.Constant{ .value = .{ .bool = true } };
    const bool_val = bridge.constantToValue(bool_const);
    try std.testing.expect(bool_val == .certain_bool);

    // None constant
    const none_const = ast.Node.Constant{ .value = .none };
    const none_val = bridge.constantToValue(none_const);
    try std.testing.expect(none_val == .certain_null);
}

test "AstBridge.nameToValue singletons" {
    var bridge = AstBridge.init(std.testing.allocator, std.testing.allocator);

    // True
    const true_name = ast.Node.Name{ .id = "True", .ctx = .load };
    const true_val = bridge.nameToValue(true_name);
    try std.testing.expect(true_val == .certain_bool);
    try std.testing.expect(true_val.certain_bool);

    // False
    const false_name = ast.Node.Name{ .id = "False", .ctx = .load };
    const false_val = bridge.nameToValue(false_name);
    try std.testing.expect(false_val == .certain_bool);
    try std.testing.expect(!false_val.certain_bool);

    // None
    const none_name = ast.Node.Name{ .id = "None", .ctx = .load };
    const none_val = bridge.nameToValue(none_name);
    try std.testing.expect(none_val == .certain_null);
}

test "AstBridge.cmpOpToCompOp" {
    try std.testing.expectEqual(CompOp.eq, AstBridge.cmpOpToCompOp(.Eq));
    try std.testing.expectEqual(CompOp.ne, AstBridge.cmpOpToCompOp(.NotEq));
    try std.testing.expectEqual(CompOp.lt, AstBridge.cmpOpToCompOp(.Lt));
    try std.testing.expectEqual(CompOp.le, AstBridge.cmpOpToCompOp(.LtE));
    try std.testing.expectEqual(CompOp.gt, AstBridge.cmpOpToCompOp(.Gt));
    try std.testing.expectEqual(CompOp.ge, AstBridge.cmpOpToCompOp(.GtE));
    try std.testing.expectEqual(CompOp.in_, AstBridge.cmpOpToCompOp(.In));
    try std.testing.expectEqual(CompOp.not_in, AstBridge.cmpOpToCompOp(.NotIn));
    try std.testing.expectEqual(CompOp.is, AstBridge.cmpOpToCompOp(.Is));
    try std.testing.expectEqual(CompOp.is_not, AstBridge.cmpOpToCompOp(.IsNot));
}

test "AstBridge.operatorToBinOp" {
    try std.testing.expectEqual(BinOp.add, AstBridge.operatorToBinOp(.Add));
    try std.testing.expectEqual(BinOp.sub, AstBridge.operatorToBinOp(.Sub));
    try std.testing.expectEqual(BinOp.mul, AstBridge.operatorToBinOp(.Mult));
    try std.testing.expectEqual(BinOp.div, AstBridge.operatorToBinOp(.Div));
    try std.testing.expectEqual(BinOp.floor_div, AstBridge.operatorToBinOp(.FloorDiv));
    try std.testing.expectEqual(BinOp.mod, AstBridge.operatorToBinOp(.Mod));
    try std.testing.expectEqual(BinOp.pow, AstBridge.operatorToBinOp(.Pow));
}
