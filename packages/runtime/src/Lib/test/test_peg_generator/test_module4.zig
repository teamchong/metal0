//! test.test_peg_generator.test_actions - Semantic actions tests
//!
//! This module tests semantic actions in PEG parsers, including action binding,
//! execution contexts, and value transformation during parsing.

const std = @import("std");

/// Represents a value that can be produced by semantic actions
pub const ActionValue = union(enum) {
    integer: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
    list: []const ActionValue,
    object: std.StringHashMap(ActionValue),
    null_value: void,

    pub fn asInt(self: ActionValue) ?i64 {
        return if (self == .integer) self.integer else null;
    }

    pub fn asFloat(self: ActionValue) ?f64 {
        return if (self == .float) self.float else null;
    }

    pub fn asString(self: ActionValue) ?[]const u8 {
        return if (self == .string) self.string else null;
    }

    pub fn asBool(self: ActionValue) ?bool {
        return if (self == .boolean) self.boolean else null;
    }

    pub fn isNull(self: ActionValue) bool {
        return self == .null_value;
    }

    pub fn eql(self: ActionValue, other: ActionValue) bool {
        if (@intFromEnum(self) != @intFromEnum(other)) return false;
        return switch (self) {
            .integer => |v| v == other.integer,
            .float => |v| v == other.float,
            .string => |v| std.mem.eql(u8, v, other.string),
            .boolean => |v| v == other.boolean,
            .null_value => true,
            else => false,
        };
    }
};

/// Context for semantic action execution
pub const ActionContext = struct {
    values: std.ArrayList(ActionValue),
    names: std.StringHashMap(ActionValue),
    parent: ?*ActionContext,
    allocator: std.mem.Allocator,
    position: usize,
    line: usize,
    column: usize,

    pub fn init(allocator: std.mem.Allocator) ActionContext {
        return .{
            .values = std.ArrayList(ActionValue).init(allocator),
            .names = std.StringHashMap(ActionValue).init(allocator),
            .parent = null,
            .allocator = allocator,
            .position = 0,
            .line = 1,
            .column = 1,
        };
    }

    pub fn deinit(self: *ActionContext) void {
        self.values.deinit();
        self.names.deinit();
    }

    pub fn push(self: *ActionContext, value: ActionValue) !void {
        try self.values.append(value);
    }

    pub fn pop(self: *ActionContext) ?ActionValue {
        return self.values.popOrNull();
    }

    pub fn peek(self: ActionContext) ?ActionValue {
        if (self.values.items.len == 0) return null;
        return self.values.items[self.values.items.len - 1];
    }

    pub fn get(self: ActionContext, index: usize) ?ActionValue {
        if (index >= self.values.items.len) return null;
        return self.values.items[index];
    }

    pub fn setNamed(self: *ActionContext, name: []const u8, value: ActionValue) !void {
        try self.names.put(name, value);
    }

    pub fn getNamed(self: ActionContext, name: []const u8) ?ActionValue {
        if (self.names.get(name)) |v| return v;
        if (self.parent) |p| return p.getNamed(name);
        return null;
    }

    pub fn createChild(self: *ActionContext) ActionContext {
        var child = ActionContext.init(self.allocator);
        child.parent = self;
        child.position = self.position;
        child.line = self.line;
        child.column = self.column;
        return child;
    }

    pub fn clear(self: *ActionContext) void {
        self.values.clearRetainingCapacity();
    }

    pub fn count(self: ActionContext) usize {
        return self.values.items.len;
    }
};

/// Represents a semantic action that transforms parsed values
pub const SemanticAction = struct {
    name: []const u8,
    handler: *const fn (*ActionContext) anyerror!ActionValue,
    arity: usize,
    description: []const u8,

    pub fn execute(self: SemanticAction, ctx: *ActionContext) !ActionValue {
        if (ctx.count() < self.arity) {
            return error.InsufficientArguments;
        }
        return try self.handler(ctx);
    }
};

/// Registry for semantic actions
pub const ActionRegistry = struct {
    actions: std.StringHashMap(SemanticAction),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ActionRegistry {
        return .{
            .actions = std.StringHashMap(SemanticAction).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ActionRegistry) void {
        self.actions.deinit();
    }

    pub fn register(self: *ActionRegistry, action: SemanticAction) !void {
        try self.actions.put(action.name, action);
    }

    pub fn get(self: ActionRegistry, name: []const u8) ?SemanticAction {
        return self.actions.get(name);
    }

    pub fn execute(self: ActionRegistry, name: []const u8, ctx: *ActionContext) !ActionValue {
        const action = self.get(name) orelse return error.ActionNotFound;
        return try action.execute(ctx);
    }

    pub fn count(self: ActionRegistry) usize {
        return self.actions.count();
    }
};

/// Built-in action: add two numbers
fn actionAdd(ctx: *ActionContext) !ActionValue {
    const b = ctx.pop() orelse return error.StackUnderflow;
    const a = ctx.pop() orelse return error.StackUnderflow;

    if (a.asInt()) |ai| {
        if (b.asInt()) |bi| {
            return .{ .integer = ai + bi };
        }
    }
    if (a.asFloat()) |af| {
        if (b.asFloat()) |bf| {
            return .{ .float = af + bf };
        }
    }
    return error.TypeMismatch;
}

/// Built-in action: subtract two numbers
fn actionSub(ctx: *ActionContext) !ActionValue {
    const b = ctx.pop() orelse return error.StackUnderflow;
    const a = ctx.pop() orelse return error.StackUnderflow;

    if (a.asInt()) |ai| {
        if (b.asInt()) |bi| {
            return .{ .integer = ai - bi };
        }
    }
    return error.TypeMismatch;
}

/// Built-in action: multiply two numbers
fn actionMul(ctx: *ActionContext) !ActionValue {
    const b = ctx.pop() orelse return error.StackUnderflow;
    const a = ctx.pop() orelse return error.StackUnderflow;

    if (a.asInt()) |ai| {
        if (b.asInt()) |bi| {
            return .{ .integer = ai * bi };
        }
    }
    return error.TypeMismatch;
}

/// Built-in action: negate a number
fn actionNeg(ctx: *ActionContext) !ActionValue {
    const a = ctx.pop() orelse return error.StackUnderflow;

    if (a.asInt()) |ai| {
        return .{ .integer = -ai };
    }
    if (a.asFloat()) |af| {
        return .{ .float = -af };
    }
    return error.TypeMismatch;
}

/// Built-in action: concatenate strings
fn actionConcat(ctx: *ActionContext) !ActionValue {
    const b = ctx.pop() orelse return error.StackUnderflow;
    const a = ctx.pop() orelse return error.StackUnderflow;

    if (a.asString()) |as| {
        if (b.asString()) |bs| {
            const result = try ctx.allocator.alloc(u8, as.len + bs.len);
            @memcpy(result[0..as.len], as);
            @memcpy(result[as.len..], bs);
            return .{ .string = result };
        }
    }
    return error.TypeMismatch;
}

/// Built-in action: create a list from stack values
fn actionMakeList(ctx: *ActionContext) !ActionValue {
    const items = try ctx.allocator.alloc(ActionValue, ctx.count());
    for (ctx.values.items, 0..) |item, i| {
        items[i] = item;
    }
    ctx.clear();
    return .{ .list = items };
}

/// Built-in action: identity (return top of stack)
fn actionIdentity(ctx: *ActionContext) !ActionValue {
    return ctx.pop() orelse return error.StackUnderflow;
}

/// Built-in action: discard top of stack
fn actionDiscard(ctx: *ActionContext) !ActionValue {
    _ = ctx.pop();
    return .{ .null_value = {} };
}

/// Built-in action: duplicate top of stack
fn actionDup(ctx: *ActionContext) !ActionValue {
    const top = ctx.peek() orelse return error.StackUnderflow;
    try ctx.push(top);
    return top;
}

/// Built-in action: swap top two values
fn actionSwap(ctx: *ActionContext) !ActionValue {
    const b = ctx.pop() orelse return error.StackUnderflow;
    const a = ctx.pop() orelse return error.StackUnderflow;
    try ctx.push(b);
    try ctx.push(a);
    return a;
}

/// Creates a registry with standard built-in actions
pub fn createStandardRegistry(allocator: std.mem.Allocator) !ActionRegistry {
    var registry = ActionRegistry.init(allocator);

    try registry.register(.{ .name = "add", .handler = actionAdd, .arity = 2, .description = "Add two numbers" });
    try registry.register(.{ .name = "sub", .handler = actionSub, .arity = 2, .description = "Subtract two numbers" });
    try registry.register(.{ .name = "mul", .handler = actionMul, .arity = 2, .description = "Multiply two numbers" });
    try registry.register(.{ .name = "neg", .handler = actionNeg, .arity = 1, .description = "Negate a number" });
    try registry.register(.{ .name = "concat", .handler = actionConcat, .arity = 2, .description = "Concatenate strings" });
    try registry.register(.{ .name = "list", .handler = actionMakeList, .arity = 0, .description = "Create list from stack" });
    try registry.register(.{ .name = "id", .handler = actionIdentity, .arity = 1, .description = "Return top value" });
    try registry.register(.{ .name = "discard", .handler = actionDiscard, .arity = 1, .description = "Discard top value" });
    try registry.register(.{ .name = "dup", .handler = actionDup, .arity = 1, .description = "Duplicate top value" });
    try registry.register(.{ .name = "swap", .handler = actionSwap, .arity = 2, .description = "Swap top two values" });

    return registry;
}

// Tests
test "action_value_types" {
    const int_val = ActionValue{ .integer = 42 };
    try std.testing.expectEqual(@as(i64, 42), int_val.asInt().?);
    try std.testing.expect(int_val.asFloat() == null);

    const float_val = ActionValue{ .float = 3.14 };
    try std.testing.expect(float_val.asFloat().? == 3.14);
    try std.testing.expect(float_val.asInt() == null);

    const str_val = ActionValue{ .string = "hello" };
    try std.testing.expectEqualStrings("hello", str_val.asString().?);

    const bool_val = ActionValue{ .boolean = true };
    try std.testing.expect(bool_val.asBool().?);

    const null_val = ActionValue{ .null_value = {} };
    try std.testing.expect(null_val.isNull());
}

test "action_value_equality" {
    const a = ActionValue{ .integer = 10 };
    const b = ActionValue{ .integer = 10 };
    const c = ActionValue{ .integer = 20 };

    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));

    const s1 = ActionValue{ .string = "test" };
    const s2 = ActionValue{ .string = "test" };
    try std.testing.expect(s1.eql(s2));
}

test "action_context_push_pop" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{ .integer = 1 });
    try ctx.push(.{ .integer = 2 });
    try ctx.push(.{ .integer = 3 });

    try std.testing.expectEqual(@as(usize, 3), ctx.count());

    const top = ctx.pop().?;
    try std.testing.expectEqual(@as(i64, 3), top.asInt().?);

    try std.testing.expectEqual(@as(usize, 2), ctx.count());
}

test "action_context_peek" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try std.testing.expect(ctx.peek() == null);

    try ctx.push(.{ .string = "value" });
    const peeked = ctx.peek().?;
    try std.testing.expectEqualStrings("value", peeked.asString().?);
    try std.testing.expectEqual(@as(usize, 1), ctx.count()); // peek doesn't remove
}

test "action_context_named_values" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.setNamed("x", .{ .integer = 100 });
    try ctx.setNamed("y", .{ .float = 2.5 });

    const x = ctx.getNamed("x").?;
    try std.testing.expectEqual(@as(i64, 100), x.asInt().?);

    const y = ctx.getNamed("y").?;
    try std.testing.expect(y.asFloat().? == 2.5);

    try std.testing.expect(ctx.getNamed("z") == null);
}

test "action_context_child_scope" {
    var parent = ActionContext.init(std.testing.allocator);
    defer parent.deinit();

    try parent.setNamed("shared", .{ .integer = 42 });

    var child = parent.createChild();
    defer child.deinit();

    // Child can see parent's named values
    const shared = child.getNamed("shared").?;
    try std.testing.expectEqual(@as(i64, 42), shared.asInt().?);

    // Child's own values don't affect parent
    try child.setNamed("local", .{ .boolean = true });
    try std.testing.expect(parent.getNamed("local") == null);
}

test "action_context_clear" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{ .integer = 1 });
    try ctx.push(.{ .integer = 2 });
    try std.testing.expectEqual(@as(usize, 2), ctx.count());

    ctx.clear();
    try std.testing.expectEqual(@as(usize, 0), ctx.count());
}

test "action_registry_register_and_get" {
    var registry = ActionRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(.{
        .name = "test",
        .handler = actionIdentity,
        .arity = 1,
        .description = "Test action",
    });

    try std.testing.expectEqual(@as(usize, 1), registry.count());

    const action = registry.get("test").?;
    try std.testing.expectEqualStrings("test", action.name);
    try std.testing.expectEqual(@as(usize, 1), action.arity);
}

test "action_add" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{ .integer = 10 });
    try ctx.push(.{ .integer = 20 });

    const result = try actionAdd(&ctx);
    try std.testing.expectEqual(@as(i64, 30), result.asInt().?);
}

test "action_sub" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{ .integer = 50 });
    try ctx.push(.{ .integer = 20 });

    const result = try actionSub(&ctx);
    try std.testing.expectEqual(@as(i64, 30), result.asInt().?);
}

test "action_mul" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{ .integer = 6 });
    try ctx.push(.{ .integer = 7 });

    const result = try actionMul(&ctx);
    try std.testing.expectEqual(@as(i64, 42), result.asInt().?);
}

test "action_neg" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{ .integer = 42 });

    const result = try actionNeg(&ctx);
    try std.testing.expectEqual(@as(i64, -42), result.asInt().?);
}

test "action_dup" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{ .integer = 5 });
    _ = try actionDup(&ctx);

    try std.testing.expectEqual(@as(usize, 2), ctx.count());
    try std.testing.expectEqual(@as(i64, 5), ctx.pop().?.asInt().?);
    try std.testing.expectEqual(@as(i64, 5), ctx.pop().?.asInt().?);
}

test "action_swap" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{ .integer = 1 });
    try ctx.push(.{ .integer = 2 });
    _ = try actionSwap(&ctx);

    try std.testing.expectEqual(@as(i64, 1), ctx.pop().?.asInt().?);
    try std.testing.expectEqual(@as(i64, 2), ctx.pop().?.asInt().?);
}

test "action_make_list" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{ .integer = 1 });
    try ctx.push(.{ .integer = 2 });
    try ctx.push(.{ .integer = 3 });

    const result = try actionMakeList(&ctx);
    const list = result.list;

    try std.testing.expectEqual(@as(usize, 3), list.len);
    try std.testing.expectEqual(@as(i64, 1), list[0].asInt().?);
    try std.testing.expectEqual(@as(i64, 2), list[1].asInt().?);
    try std.testing.expectEqual(@as(i64, 3), list[2].asInt().?);
}

test "standard_registry" {
    var registry = try createStandardRegistry(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expect(registry.get("add") != null);
    try std.testing.expect(registry.get("sub") != null);
    try std.testing.expect(registry.get("mul") != null);
    try std.testing.expect(registry.get("neg") != null);
    try std.testing.expect(registry.get("concat") != null);
    try std.testing.expect(registry.get("list") != null);
}

test "registry_execute" {
    var registry = try createStandardRegistry(std.testing.allocator);
    defer registry.deinit();

    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{ .integer = 15 });
    try ctx.push(.{ .integer = 27 });

    const result = try registry.execute("add", &ctx);
    try std.testing.expectEqual(@as(i64, 42), result.asInt().?);
}

test "action_insufficient_arguments" {
    var ctx = ActionContext.init(std.testing.allocator);
    defer ctx.deinit();

    try ctx.push(.{ .integer = 5 });
    // Only one value, but add needs two

    const action = SemanticAction{
        .name = "add",
        .handler = actionAdd,
        .arity = 2,
        .description = "Add two numbers",
    };

    try std.testing.expectError(error.InsufficientArguments, action.execute(&ctx));
}
