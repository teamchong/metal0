/// ast_preprocess - AST Pre-processing
/// Mirrors cpython/Python/ast_preprocess.c
///
/// Pre-processes the AST before compilation, handling:
/// - Constant folding
/// - Control flow in finally warnings (PEP 765)
/// - Docstring extraction
/// - Optimization passes

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Control Flow Context (PEP 765)
// ============================================================================

/// Context for tracking control flow in finally blocks
pub const ControlFlowContext = struct {
    /// In a finally block
    in_finally: bool = false,
    /// In a function definition
    in_funcdef: bool = false,
    /// In a loop
    in_loop: bool = false,
};

/// Stack of control flow contexts
pub const ContextStack = struct {
    const Self = @This();

    contexts: std.ArrayList(ControlFlowContext),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .contexts = std.ArrayList(ControlFlowContext).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.contexts.deinit();
    }

    pub fn push(self: *Self, ctx: ControlFlowContext) !void {
        try self.contexts.append(ctx);
    }

    pub fn pop(self: *Self) void {
        if (self.contexts.items.len > 0) {
            _ = self.contexts.pop();
        }
    }

    pub fn top(self: *const Self) ?ControlFlowContext {
        if (self.contexts.items.len == 0) return null;
        return self.contexts.items[self.contexts.items.len - 1];
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.contexts.items.len == 0;
    }
};

// ============================================================================
// AST Preprocess State
// ============================================================================

/// AST preprocessing state
pub const PreprocessState = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// Source filename
    filename: []const u8,
    /// Module name
    module_name: ?[]const u8 = null,
    /// Optimization level (0-2)
    optimize: u8 = 0,
    /// Future features flags
    ff_features: u32 = 0,
    /// Syntax check only mode
    syntax_check_only: bool = false,
    /// Enable warnings
    enable_warnings: bool = true,
    /// Control flow context stack
    cf_context: ContextStack,
    /// Collected warnings
    warnings: std.ArrayList(Warning),
    /// Collected errors
    errors: std.ArrayList(PreprocessError),

    pub fn init(allocator: Allocator, filename: []const u8) Self {
        return Self{
            .allocator = allocator,
            .filename = filename,
            .cf_context = ContextStack.init(allocator),
            .warnings = std.ArrayList(Warning).init(allocator),
            .errors = std.ArrayList(PreprocessError).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.cf_context.deinit();
        self.warnings.deinit();
        self.errors.deinit();
    }

    /// Enter finally block
    pub fn enterFinally(self: *Self) !void {
        try self.cf_context.push(.{
            .in_finally = true,
            .in_funcdef = false,
            .in_loop = false,
        });
    }

    /// Exit finally block
    pub fn exitFinally(self: *Self) void {
        self.cf_context.pop();
    }

    /// Enter function body
    pub fn enterFuncBody(self: *Self) !void {
        try self.cf_context.push(.{
            .in_finally = false,
            .in_funcdef = true,
            .in_loop = false,
        });
    }

    /// Exit function body
    pub fn exitFuncBody(self: *Self) void {
        self.cf_context.pop();
    }

    /// Enter loop body
    pub fn enterLoopBody(self: *Self) !void {
        try self.cf_context.push(.{
            .in_finally = false,
            .in_funcdef = false,
            .in_loop = true,
        });
    }

    /// Exit loop body
    pub fn exitLoopBody(self: *Self) void {
        self.cf_context.pop();
    }

    /// Check before return statement
    pub fn beforeReturn(self: *Self, lineno: u32, col_offset: u32) !void {
        if (!self.enable_warnings or self.cf_context.isEmpty()) return;
        if (self.cf_context.top()) |ctx| {
            if (ctx.in_finally and !ctx.in_funcdef) {
                try self.addWarning(.return_in_finally, lineno, col_offset);
            }
        }
    }

    /// Check before break/continue
    pub fn beforeLoopExit(self: *Self, keyword: []const u8, lineno: u32, col_offset: u32) !void {
        if (!self.enable_warnings or self.cf_context.isEmpty()) return;
        if (self.cf_context.top()) |ctx| {
            if (ctx.in_finally and !ctx.in_loop) {
                const kind: WarningKind = if (std.mem.eql(u8, keyword, "break"))
                    .break_in_finally
                else
                    .continue_in_finally;
                try self.addWarning(kind, lineno, col_offset);
            }
        }
    }

    /// Add warning
    fn addWarning(self: *Self, kind: WarningKind, lineno: u32, col_offset: u32) !void {
        try self.warnings.append(.{
            .kind = kind,
            .lineno = lineno,
            .col_offset = col_offset,
            .filename = self.filename,
        });
    }

    /// Add error
    pub fn addError(self: *Self, kind: ErrorKind, message: []const u8, lineno: u32, col_offset: u32) !void {
        try self.errors.append(.{
            .kind = kind,
            .message = message,
            .lineno = lineno,
            .col_offset = col_offset,
            .filename = self.filename,
        });
    }

    /// Check if errors occurred
    pub fn hasErrors(self: *const Self) bool {
        return self.errors.items.len > 0;
    }

    /// Get warning count
    pub fn warningCount(self: *const Self) usize {
        return self.warnings.items.len;
    }
};

// ============================================================================
// Warnings and Errors
// ============================================================================

/// Warning kinds
pub const WarningKind = enum {
    return_in_finally,
    break_in_finally,
    continue_in_finally,
    deprecated_syntax,
    other,
};

/// Warning message
pub const Warning = struct {
    kind: WarningKind,
    lineno: u32,
    col_offset: u32,
    filename: []const u8,

    pub fn getMessage(self: *const Warning) []const u8 {
        return switch (self.kind) {
            .return_in_finally => "'return' in a 'finally' block",
            .break_in_finally => "'break' in a 'finally' block",
            .continue_in_finally => "'continue' in a 'finally' block",
            .deprecated_syntax => "deprecated syntax",
            .other => "warning",
        };
    }
};

/// Error kinds
pub const ErrorKind = enum {
    syntax_error,
    indentation_error,
    tab_error,
    invalid_escape,
    optimization_failed,
};

/// Preprocessing error
pub const PreprocessError = struct {
    kind: ErrorKind,
    message: []const u8,
    lineno: u32,
    col_offset: u32,
    filename: []const u8,
};

// ============================================================================
// Constant Folding
// ============================================================================

/// Constant value for folding
pub const ConstValue = union(enum) {
    none: void,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    str_val: []const u8,
    bytes_val: []const u8,

    /// Check if value is truthy
    pub fn isTruthy(self: ConstValue) bool {
        return switch (self) {
            .none => false,
            .bool_val => |v| v,
            .int_val => |v| v != 0,
            .float_val => |v| v != 0.0,
            .str_val => |v| v.len > 0,
            .bytes_val => |v| v.len > 0,
        };
    }
};

/// Binary operation for constant folding
pub const BinOp = enum {
    add,
    sub,
    mult,
    div,
    floor_div,
    mod,
    pow,
    lshift,
    rshift,
    bit_or,
    bit_xor,
    bit_and,
};

/// Fold binary operation on constants
pub fn foldBinaryOp(op: BinOp, left: ConstValue, right: ConstValue) ?ConstValue {
    // Both must be numeric
    const left_int = switch (left) {
        .int_val => |v| v,
        else => return null,
    };
    const right_int = switch (right) {
        .int_val => |v| v,
        else => return null,
    };

    return switch (op) {
        .add => .{ .int_val = left_int +| right_int },
        .sub => .{ .int_val = left_int -| right_int },
        .mult => .{ .int_val = left_int *| right_int },
        .floor_div => blk: {
            if (right_int == 0) break :blk null;
            break :blk .{ .int_val = @divFloor(left_int, right_int) };
        },
        .mod => blk: {
            if (right_int == 0) break :blk null;
            break :blk .{ .int_val = @mod(left_int, right_int) };
        },
        .lshift => blk: {
            if (right_int < 0 or right_int > 63) break :blk null;
            break :blk .{ .int_val = left_int << @intCast(right_int) };
        },
        .rshift => blk: {
            if (right_int < 0 or right_int > 63) break :blk null;
            break :blk .{ .int_val = left_int >> @intCast(right_int) };
        },
        .bit_or => .{ .int_val = left_int | right_int },
        .bit_xor => .{ .int_val = left_int ^ right_int },
        .bit_and => .{ .int_val = left_int & right_int },
        else => null,
    };
}

/// Unary operation for constant folding
pub const UnaryOp = enum {
    invert,
    not_op,
    uadd,
    usub,
};

/// Fold unary operation on constant
pub fn foldUnaryOp(op: UnaryOp, operand: ConstValue) ?ConstValue {
    return switch (op) {
        .not_op => .{ .bool_val = !operand.isTruthy() },
        .invert => switch (operand) {
            .int_val => |v| .{ .int_val = ~v },
            else => null,
        },
        .uadd => switch (operand) {
            .int_val => operand,
            .float_val => operand,
            else => null,
        },
        .usub => switch (operand) {
            .int_val => |v| .{ .int_val = -v },
            .float_val => |v| .{ .float_val = -v },
            else => null,
        },
    };
}

// ============================================================================
// Docstring Extraction
// ============================================================================

/// Extract docstring from statement list
pub fn extractDocstring(stmts: []const Statement) ?[]const u8 {
    if (stmts.len == 0) return null;

    // First statement must be an expression statement with a string literal
    const first = stmts[0];
    if (first.kind != .expr) return null;

    if (first.expr_value) |expr| {
        if (expr.kind == .constant) {
            if (expr.const_value) |cv| {
                switch (cv) {
                    .str_val => |s| return s,
                    else => return null,
                }
            }
        }
    }
    return null;
}

/// Statement placeholder (minimal for docstring extraction)
pub const Statement = struct {
    kind: StmtKind,
    expr_value: ?*const Expression = null,
};

pub const StmtKind = enum {
    expr,
    assign,
    other,
};

pub const Expression = struct {
    kind: ExprKind,
    const_value: ?ConstValue = null,
};

pub const ExprKind = enum {
    constant,
    name,
    call,
    other,
};

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the ast_preprocess module
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

test "context stack operations" {
    const allocator = std.testing.allocator;

    var stack = ContextStack.init(allocator);
    defer stack.deinit();

    try std.testing.expect(stack.isEmpty());
    try std.testing.expect(stack.top() == null);

    try stack.push(.{ .in_finally = true, .in_funcdef = false, .in_loop = false });
    try std.testing.expect(!stack.isEmpty());
    try std.testing.expect(stack.top().?.in_finally);

    stack.pop();
    try std.testing.expect(stack.isEmpty());
}

test "preprocess state control flow" {
    const allocator = std.testing.allocator;

    var state = PreprocessState.init(allocator, "test.py");
    defer state.deinit();

    try state.enterFinally();
    try state.beforeReturn(10, 0);
    try std.testing.expectEqual(@as(usize, 1), state.warningCount());

    state.exitFinally();
}

test "constant folding - binary ops" {
    const left = ConstValue{ .int_val = 10 };
    const right = ConstValue{ .int_val = 5 };

    const add_result = foldBinaryOp(.add, left, right);
    try std.testing.expect(add_result != null);
    try std.testing.expectEqual(@as(i64, 15), add_result.?.int_val);

    const sub_result = foldBinaryOp(.sub, left, right);
    try std.testing.expect(sub_result != null);
    try std.testing.expectEqual(@as(i64, 5), sub_result.?.int_val);

    const mult_result = foldBinaryOp(.mult, left, right);
    try std.testing.expect(mult_result != null);
    try std.testing.expectEqual(@as(i64, 50), mult_result.?.int_val);
}

test "constant folding - unary ops" {
    const int_val = ConstValue{ .int_val = 5 };
    const bool_val = ConstValue{ .bool_val = true };

    const neg_result = foldUnaryOp(.usub, int_val);
    try std.testing.expect(neg_result != null);
    try std.testing.expectEqual(@as(i64, -5), neg_result.?.int_val);

    const not_result = foldUnaryOp(.not_op, bool_val);
    try std.testing.expect(not_result != null);
    try std.testing.expect(!not_result.?.bool_val);
}

test "constant truthiness" {
    const none_val = ConstValue{ .none = {} };
    const true_val = ConstValue{ .bool_val = true };
    const zero_val = ConstValue{ .int_val = 0 };
    const one_val = ConstValue{ .int_val = 1 };
    const empty_str = ConstValue{ .str_val = "" };
    const non_empty = ConstValue{ .str_val = "hello" };

    try std.testing.expect(!none_val.isTruthy());
    try std.testing.expect(true_val.isTruthy());
    try std.testing.expect(!zero_val.isTruthy());
    try std.testing.expect(one_val.isTruthy());
    try std.testing.expect(!empty_str.isTruthy());
    try std.testing.expect(non_empty.isTruthy());
}

test "division by zero" {
    const left = ConstValue{ .int_val = 10 };
    const right = ConstValue{ .int_val = 0 };

    const result = foldBinaryOp(.floor_div, left, right);
    try std.testing.expect(result == null);

    const mod_result = foldBinaryOp(.mod, left, right);
    try std.testing.expect(mod_result == null);
}
