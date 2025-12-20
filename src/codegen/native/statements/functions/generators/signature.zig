/// Function and method signature generation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const param_analyzer = @import("../param_analyzer.zig");
const self_analyzer = @import("../self_analyzer.zig");
const zig_keywords = @import("utils.zig_keywords");
const state_machine = @import("../../../async_state_machine.zig");
const type_traits = @import("../../../../../analysis/traits/type_traits.zig");

// NOTE: Async strategy is now determined per-function via function_traits
// Query self.shouldUseStateMachineAsync(func.name) instead of hardcoded constant
const shared = @import("../../../shared_maps.zig");
const TypeHints = shared.PyTypeToZig;

/// Check if method has @staticmethod decorator
pub fn hasStaticmethodDecorator(decorators: []const ast.Node) bool {
    for (decorators) |decorator| {
        if (decorator == .name and std.mem.eql(u8, decorator.name.id, "staticmethod")) {
            return true;
        }
    }
    return false;
}

/// Check if method has @classmethod decorator
/// Also handles @abc.abstractclassmethod and @classmethod + @abc.abstractmethod combinations
pub fn hasClassmethodDecorator(decorators: []const ast.Node) bool {
    for (decorators) |decorator| {
        // Simple @classmethod
        if (decorator == .name and std.mem.eql(u8, decorator.name.id, "classmethod")) {
            return true;
        }
        // @abc.abstractclassmethod or @abc.classmethod
        if (decorator == .attribute) {
            const attr = decorator.attribute;
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "abc")) {
                if (std.mem.eql(u8, attr.attr, "abstractclassmethod") or
                    std.mem.eql(u8, attr.attr, "classmethod"))
                {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Get type from call site argument types (for functions without annotations)
/// Returns allocated Zig type string if found, null otherwise
fn getTypeFromCallSiteOrScope(self: *NativeCodegen, func: ast.Node.FunctionDef, arg: ast.Arg, param_idx: usize) CodegenError!?[]const u8 {
    // Try function_call_args first (more accurate than default i64)
    if (self.type_inferrer.function_call_args.get(func.name)) |call_arg_types| {
        // For methods, func.args includes 'self' but call_arg_types doesn't
        // Adjust the index: if first arg is 'self', offset by 1
        const is_method = func.args.len > 0 and std.mem.eql(u8, func.args[0].name, "self");
        const call_idx = if (is_method and param_idx > 0) param_idx - 1 else param_idx;

        if (call_idx < call_arg_types.len) {
            const call_type = call_arg_types[call_idx];
            const call_type_tag = @as(std.meta.Tag(@TypeOf(call_type)), call_type);
            if (call_type_tag != .unknown and call_type_tag != .int) {
                // For dict types with =None default, use anytype since different call sites
                // may pass dicts with different value types (e.g., {"x": [1]} vs {"y": [1,2,3]})
                // This is a common Python pattern for optional dict parameters
                if (call_type_tag == .dict and arg.default != null) {
                    const is_none_default = arg.default.?.* == .constant and
                        arg.default.?.constant.value == .none;
                    if (is_none_default) {
                        // Use anytype for optional dict parameters (polymorphic)
                        return null; // Will fall through to other handling
                    }
                }
                // Found non-default type from call site
                return try self.nativeTypeToZigType(call_type);
            }
        }
    }
    // Not found in call args
    return null;
}

/// Known Zig primitive types for return type validation (O(1) lookup)
const KnownZigTypes = std.StaticStringMap(void).initComptime(.{
    .{ "i64", {} }, .{ "i32", {} }, .{ "i8", {} }, .{ "u8", {} }, .{ "u16", {} },
    .{ "u32", {} }, .{ "u64", {} }, .{ "usize", {} }, .{ "isize", {} },
    .{ "bool", {} }, .{ "void", {} }, .{ "f32", {} }, .{ "f64", {} },
    .{ "[]const u8", {} }, .{ "[]u8", {} },
    .{ "*runtime.PyObject", {} }, .{ "@This()", {} }, .{ "anytype", {} },
});

/// Magic method return types - these have fixed return types in Python
/// regardless of what the method body might suggest
/// NOTE: __eq__/__ne__ return runtime.PyValue to support NotImplemented returns.
/// __lt__/__le__/__gt__/__ge__ can return any type (e.g., SymbolicBool, NotImplemented).
/// `return NotImplemented` is converted to `return runtime.PyValue{ .not_implemented = {} }`.
const MagicMethodReturnTypes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "__bool__", "runtime.PythonError!bool" }, // Must return bool or error
    .{ "__len__", "runtime.PythonError!i64" }, // Must return non-negative int or error
    .{ "__hash__", "i64" },
    .{ "__repr__", "[]const u8" },
    .{ "__str__", "[]const u8" },
    .{ "__bytes__", "[]const u8" },
    .{ "__format__", "[]const u8" },
    .{ "__int__", "runtime.PythonError!i64" }, // Can error (ValueError, OverflowError)
    .{ "__float__", "runtime.PythonError!f64" }, // Can error (ZeroDivisionError, ValueError)
    .{ "__index__", "runtime.PythonError!i64" }, // Can error
    .{ "__sizeof__", "i64" },
    .{ "__contains__", "bool" },
    .{ "__eq__", "runtime.PyValue" }, // Can return NotImplemented for rich comparison protocol
    .{ "__ne__", "runtime.PyValue" }, // Can return NotImplemented for rich comparison protocol
    .{ "__lt__", "runtime.PyValue" }, // Can return NotImplemented for rich comparison protocol
    .{ "__le__", "runtime.PyValue" }, // Can return NotImplemented for rich comparison protocol
    .{ "__gt__", "runtime.PyValue" }, // Can return NotImplemented for rich comparison protocol
    .{ "__ge__", "runtime.PyValue" }, // Can return NotImplemented for rich comparison protocol
    // __new__ should return the class instance type, but in Zig we can't determine
    // the type at compile time, especially for metaclasses. Default to i64.
    .{ "__new__", "i64" },
});

/// Check if a method has type-changing patterns that require polymorphic return type
/// Pattern: methods that return different types based on input (Rat for int/Rat, f64 for float)
fn hasPolymorphicReturnPattern(method: ast.Node.FunctionDef, anytype_params: anytype) bool {
    _ = anytype_params;
    // Look for pattern: if isnum(other): return float(self) + other <- returns f64
    // when other branches return Rat via Rat.init() or @This().init()

    var has_class_return = false;
    var has_float_return = false;

    for (method.body) |stmt| {
        if (stmt != .if_stmt) continue;
        const if_stmt = stmt.if_stmt;
        if (if_stmt.condition.* != .call) continue;
        const call = if_stmt.condition.call;
        if (call.func.* != .name) continue;
        const func_name = call.func.name.id;

        // Check for isint/isRat returning class instance
        if (std.mem.eql(u8, func_name, "isint") or std.mem.eql(u8, func_name, "isRat") or std.mem.eql(u8, func_name, "isinstance")) {
            for (if_stmt.body) |body_stmt| {
                if (body_stmt == .return_stmt) {
                    if (body_stmt.return_stmt.value) |val| {
                        // Check if returning class constructor call
                        if (val.* == .call and val.call.func.* == .name) {
                            has_class_return = true;
                        }
                    }
                }
            }
        } else if (std.mem.eql(u8, func_name, "isnum")) {
            // Check if body returns float operation
            for (if_stmt.body) |body_stmt| {
                if (body_stmt != .return_stmt) continue;
                if (body_stmt.return_stmt.value) |val| {
                    if (val.* == .binop or val.* == .call) {
                        // float(self) + other or runtime.divideFloat(...) or similar
                        has_float_return = true;
                    }
                }
            }
        }
    }

    // Polymorphic pattern: both class return AND float return paths exist
    return has_class_return and has_float_return;
}

/// Get the fixed return type for a magic method, or null if not a special method
pub fn getMagicMethodReturnType(method_name: []const u8) ?[]const u8 {
    return MagicMethodReturnTypes.get(method_name);
}

/// Convert Python type hint to Zig type
pub fn pythonTypeToZig(type_hint: ?[]const u8) []const u8 {
    if (type_hint) |hint| {
        if (TypeHints.get(hint)) |zig_type| return zig_type;
    }
    return "i64"; // Default to i64 instead of anytype (most class fields are integers)
}

/// Import NativeType for pythonTypeToNativeType
const core = @import("../../../../../analysis/native_types/core.zig");
const NativeType = core.NativeType;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}


/// Get inferred return type string from type inferrer (DRY helper)
/// Returns tuple: (type_string, needs_free)
fn getInferredReturnTypeStr(self: *NativeCodegen, func_name: []const u8) struct { str: []const u8, needs_free: bool } {
    const inferred_type = self.type_inferrer.func_return_types.get(func_name);
    if (inferred_type) |inf_type| {
        const inf_tag = @as(std.meta.Tag(NativeType), inf_type);
        if (inf_tag == .int) return .{ .str = inf_type.toSimpleZigType(), .needs_free = false };
        if (inf_tag == .unknown) return .{ .str = "i64", .needs_free = false };
        return .{ .str = self.nativeTypeToZigType(inf_type) catch "i64", .needs_free = true };
    }
    return .{ .str = "i64", .needs_free = false };
}

/// Emit inferred return type with optional error union (DRY helper)
fn emitInferredReturnType(self: *NativeCodegen, func_name: []const u8, needs_error: bool) CodegenError!void {
    const type_info = getInferredReturnTypeStr(self, func_name);
    defer if (type_info.needs_free) self.allocator.free(type_info.str);
    if (needs_error) try emitConst(self,"!");
    try emitConst(self,type_info.str);
    try emitConst(self," {\n");

    // Two-Flow: Track if this function returns PyValue (needs boxing at return statements)
    if (std.mem.eql(u8, type_info.str, "runtime.PyValue")) {
        self.current_function_returns_pyvalue = true;
    }
}

/// Check if an expression produces BigInt (for determining parameter types)
fn expressionProducesBigInt(expr: ast.Node) bool {
    switch (expr) {
        .binop => |b| {
            // Large left shift: 1 << N where N >= 63
            if (b.op == .LShift) {
                if (b.right.* == .constant and b.right.constant.value == .int) {
                    if (b.right.constant.value.int >= 63) return true;
                }
            }
            // Large power: N ** M where M >= 20
            if (b.op == .Pow) {
                if (b.right.* == .constant and b.right.constant.value == .int) {
                    if (b.right.constant.value.int >= 20) return true;
                }
            }
            // Arithmetic on BigInt also produces BigInt
            if (expressionProducesBigInt(b.left.*) or expressionProducesBigInt(b.right.*)) {
                return true;
            }
        },
        .unaryop => |u| {
            // Negation of BigInt is BigInt
            return expressionProducesBigInt(u.operand.*);
        },
        else => {},
    }
    return false;
}

/// Check if any call to a method in the class body passes BigInt to a specific parameter index
fn methodReceivesBigIntArg(class_body: []const ast.Node, method_name: []const u8, param_index: usize) bool {
    for (class_body) |stmt| {
        if (checkStmtForBigIntMethodCall(stmt, method_name, param_index)) {
            return true;
        }
    }
    return false;
}

fn checkStmtForBigIntMethodCall(stmt: ast.Node, method_name: []const u8, param_index: usize) bool {
    switch (stmt) {
        .expr_stmt => |e| return checkExprForBigIntMethodCall(e.value.*, method_name, param_index),
        .function_def => |f| {
            for (f.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
        },
        .class_def => |c| {
            for (c.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
        },
        .for_stmt => |f| {
            for (f.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
            if (f.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
                }
            }
        },
        .while_stmt => |w| {
            for (w.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
            if (w.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
                }
            }
        },
        .if_stmt => |i| {
            for (i.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
            for (i.else_body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
        },
        .try_stmt => |t| {
            for (t.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
            for (t.handlers) |handler| {
                for (handler.body) |s| {
                    if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
                }
            }
            for (t.else_body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
            for (t.finalbody) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
        },
        .with_stmt => |w| {
            for (w.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
        },
        .match_stmt => |m| {
            for (m.cases) |case| {
                for (case.body) |s| {
                    if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
                }
            }
        },
        else => {},
    }
    return false;
}

fn checkExprForBigIntMethodCall(expr: ast.Node, method_name: []const u8, param_index: usize) bool {
    switch (expr) {
        .call => |c| {
            // Check if this is a call to self.method_name
            if (c.func.* == .attribute) {
                const attr = c.func.attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    if (std.mem.eql(u8, attr.attr, method_name)) {
                        // Found call to self.method_name - check the argument at param_index
                        if (param_index < c.args.len) {
                            if (expressionProducesBigInt(c.args[param_index])) {
                                return true;
                            }
                        }
                    }
                }
            }
            // Also check arguments recursively
            for (c.args) |arg| {
                if (checkExprForBigIntMethodCall(arg, method_name, param_index)) return true;
            }
            // Check keyword arguments
            for (c.keyword_args) |kw| {
                if (checkExprForBigIntMethodCall(kw.value, method_name, param_index)) return true;
            }
        },
        .binop => |b| {
            if (checkExprForBigIntMethodCall(b.left.*, method_name, param_index)) return true;
            if (checkExprForBigIntMethodCall(b.right.*, method_name, param_index)) return true;
        },
        .unaryop => |u| {
            if (checkExprForBigIntMethodCall(u.operand.*, method_name, param_index)) return true;
        },
        .boolop => |b| {
            for (b.values) |v| {
                if (checkExprForBigIntMethodCall(v, method_name, param_index)) return true;
            }
        },
        .compare => |c| {
            if (checkExprForBigIntMethodCall(c.left.*, method_name, param_index)) return true;
            for (c.comparators) |comp| {
                if (checkExprForBigIntMethodCall(comp, method_name, param_index)) return true;
            }
        },
        .if_expr => |ie| {
            if (checkExprForBigIntMethodCall(ie.condition.*, method_name, param_index)) return true;
            if (checkExprForBigIntMethodCall(ie.body.*, method_name, param_index)) return true;
            if (checkExprForBigIntMethodCall(ie.orelse_value.*, method_name, param_index)) return true;
        },
        .subscript => |sub| {
            if (checkExprForBigIntMethodCall(sub.value.*, method_name, param_index)) return true;
            switch (sub.slice) {
                .index => |idx| if (checkExprForBigIntMethodCall(idx.*, method_name, param_index)) return true,
                .slice => |sr| {
                    if (sr.lower) |l| if (checkExprForBigIntMethodCall(l.*, method_name, param_index)) return true;
                    if (sr.upper) |u| if (checkExprForBigIntMethodCall(u.*, method_name, param_index)) return true;
                    if (sr.step) |s| if (checkExprForBigIntMethodCall(s.*, method_name, param_index)) return true;
                },
            }
        },
        .list => |lst| {
            for (lst.elts) |e| {
                if (checkExprForBigIntMethodCall(e, method_name, param_index)) return true;
            }
        },
        .tuple => |tup| {
            for (tup.elts) |e| {
                if (checkExprForBigIntMethodCall(e, method_name, param_index)) return true;
            }
        },
        .dict => |d| {
            for (d.keys) |k| {
                if (checkExprForBigIntMethodCall(k, method_name, param_index)) return true;
            }
            for (d.values) |v| {
                if (checkExprForBigIntMethodCall(v, method_name, param_index)) return true;
            }
        },
        .fstring => |fs| {
            for (fs.parts) |part| {
                switch (part) {
                    .expr => |e| if (checkExprForBigIntMethodCall(e.node.*, method_name, param_index)) return true,
                    .format_expr => |fe| if (checkExprForBigIntMethodCall(fe.expr.*, method_name, param_index)) return true,
                    .conv_expr => |ce| if (checkExprForBigIntMethodCall(ce.expr.*, method_name, param_index)) return true,
                    .literal => {},
                }
            }
        },
        .listcomp => |lc| {
            if (checkExprForBigIntMethodCall(lc.elt.*, method_name, param_index)) return true;
            for (lc.generators) |gen| {
                if (checkExprForBigIntMethodCall(gen.iter.*, method_name, param_index)) return true;
                for (gen.ifs) |cond| if (checkExprForBigIntMethodCall(cond, method_name, param_index)) return true;
            }
        },
        .dictcomp => |dc| {
            if (checkExprForBigIntMethodCall(dc.key.*, method_name, param_index)) return true;
            if (checkExprForBigIntMethodCall(dc.value.*, method_name, param_index)) return true;
            for (dc.generators) |gen| {
                if (checkExprForBigIntMethodCall(gen.iter.*, method_name, param_index)) return true;
                for (gen.ifs) |cond| if (checkExprForBigIntMethodCall(cond, method_name, param_index)) return true;
            }
        },
        .genexp => |ge| {
            if (checkExprForBigIntMethodCall(ge.elt.*, method_name, param_index)) return true;
            for (ge.generators) |gen| {
                if (checkExprForBigIntMethodCall(gen.iter.*, method_name, param_index)) return true;
                for (gen.ifs) |cond| if (checkExprForBigIntMethodCall(cond, method_name, param_index)) return true;
            }
        },
        .lambda => |lam| if (checkExprForBigIntMethodCall(lam.body.*, method_name, param_index)) return true,
        .starred => |st| if (checkExprForBigIntMethodCall(st.value.*, method_name, param_index)) return true,
        .attribute => |attr| if (checkExprForBigIntMethodCall(attr.value.*, method_name, param_index)) return true,
        else => {},
    }
    return false;
}

/// Convert Python type hint to NativeType (for type inference)
pub fn pythonTypeToNativeType(type_hint: ?[]const u8) NativeType {
    if (type_hint) |hint| {
        if (std.mem.eql(u8, hint, "int")) return .{ .int = .bounded };
        if (std.mem.eql(u8, hint, "float")) return .float;
        if (std.mem.eql(u8, hint, "bool")) return .bool;
        if (std.mem.eql(u8, hint, "str")) return .{ .string = .runtime };
    }
    return .unknown;
}

/// Check if function returns a lambda (closure)
pub fn returnsLambda(body: []ast.Node) bool {
    for (body) |stmt| {
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                if (val.* == .lambda) return true;
            }
        }
        // Check nested statements
        if (stmt == .if_stmt) {
            if (returnsLambda(stmt.if_stmt.body)) return true;
            if (returnsLambda(stmt.if_stmt.else_body)) return true;
        }
        if (stmt == .while_stmt) {
            if (returnsLambda(stmt.while_stmt.body)) return true;
            if (stmt.while_stmt.orelse_body) |orelse_body| {
                if (returnsLambda(orelse_body)) return true;
            }
        }
        if (stmt == .for_stmt) {
            if (returnsLambda(stmt.for_stmt.body)) return true;
            if (stmt.for_stmt.orelse_body) |orelse_body| {
                if (returnsLambda(orelse_body)) return true;
            }
        }
        if (stmt == .match_stmt) {
            for (stmt.match_stmt.cases) |case| {
                if (returnsLambda(case.body)) return true;
            }
        }
        if (stmt == .try_stmt) {
            if (returnsLambda(stmt.try_stmt.body)) return true;
            for (stmt.try_stmt.handlers) |handler| {
                if (returnsLambda(handler.body)) return true;
            }
            if (returnsLambda(stmt.try_stmt.else_body)) return true;
            if (returnsLambda(stmt.try_stmt.finalbody)) return true;
        }
        if (stmt == .with_stmt) {
            if (returnsLambda(stmt.with_stmt.body)) return true;
        }
    }
    return false;
}

/// Check if function returns a nested function (closure by name)
/// Returns the name of the nested function if found, null otherwise
pub fn getReturnedNestedFuncName(body: []ast.Node) ?[]const u8 {
    // First, collect all nested function names defined in this body
    var nested_funcs: [32][]const u8 = undefined;
    var nested_count: usize = 0;

    for (body) |stmt| {
        if (stmt == .function_def) {
            if (nested_count < nested_funcs.len) {
                nested_funcs[nested_count] = stmt.function_def.name;
                nested_count += 1;
            }
        }
    }

    if (nested_count == 0) return null;

    // Now check if any return statement returns one of these names
    for (body) |stmt| {
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                if (val.* == .name) {
                    for (nested_funcs[0..nested_count]) |func_name| {
                        if (std.mem.eql(u8, val.name.id, func_name)) {
                            return func_name;
                        }
                    }
                }
            }
        }
        // Check nested statements
        if (stmt == .if_stmt) {
            if (getReturnedNestedFuncName(stmt.if_stmt.body)) |name| return name;
            if (getReturnedNestedFuncName(stmt.if_stmt.else_body)) |name| return name;
        }
        if (stmt == .while_stmt) {
            if (getReturnedNestedFuncName(stmt.while_stmt.body)) |name| return name;
            if (stmt.while_stmt.orelse_body) |orelse_body| {
                if (getReturnedNestedFuncName(orelse_body)) |name| return name;
            }
        }
        if (stmt == .for_stmt) {
            if (getReturnedNestedFuncName(stmt.for_stmt.body)) |name| return name;
            if (stmt.for_stmt.orelse_body) |orelse_body| {
                if (getReturnedNestedFuncName(orelse_body)) |name| return name;
            }
        }
        if (stmt == .match_stmt) {
            for (stmt.match_stmt.cases) |case| {
                if (getReturnedNestedFuncName(case.body)) |name| return name;
            }
        }
        if (stmt == .try_stmt) {
            if (getReturnedNestedFuncName(stmt.try_stmt.body)) |name| return name;
            for (stmt.try_stmt.handlers) |handler| {
                if (getReturnedNestedFuncName(handler.body)) |name| return name;
            }
            if (getReturnedNestedFuncName(stmt.try_stmt.else_body)) |name| return name;
            if (getReturnedNestedFuncName(stmt.try_stmt.finalbody)) |name| return name;
        }
        if (stmt == .with_stmt) {
            if (getReturnedNestedFuncName(stmt.with_stmt.body)) |name| return name;
        }
    }
    return null;
}

/// Check if lambda references 'self' in its body (captures self from method scope)
pub fn lambdaCapturesSelf(lambda_body: ast.Node) bool {
    return switch (lambda_body) {
        .name => |n| std.mem.eql(u8, n.id, "self"),
        .attribute => |attr| lambdaCapturesSelf(attr.value.*),
        .binop => |b| lambdaCapturesSelf(b.left.*) or lambdaCapturesSelf(b.right.*),
        .compare => |cmp| blk: {
            if (lambdaCapturesSelf(cmp.left.*)) break :blk true;
            for (cmp.comparators) |comp| {
                if (lambdaCapturesSelf(comp)) break :blk true;
            }
            break :blk false;
        },
        .call => |c| blk: {
            if (lambdaCapturesSelf(c.func.*)) break :blk true;
            for (c.args) |arg| {
                if (lambdaCapturesSelf(arg)) break :blk true;
            }
            break :blk false;
        },
        .subscript => |sub| blk: {
            if (lambdaCapturesSelf(sub.value.*)) break :blk true;
            if (sub.slice == .index) {
                if (lambdaCapturesSelf(sub.slice.index.*)) break :blk true;
            }
            break :blk false;
        },
        .if_expr => |ie| lambdaCapturesSelf(ie.condition.*) or
            lambdaCapturesSelf(ie.body.*) or lambdaCapturesSelf(ie.orelse_value.*),
        .unaryop => |u| lambdaCapturesSelf(u.operand.*),
        else => false,
    };
}

/// Get returned lambda from method body (for closure type detection)
pub fn getReturnedLambda(body: []ast.Node) ?ast.Node.Lambda {
    for (body) |stmt| {
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                if (val.* == .lambda) return val.lambda;
            }
        }
    }
    return null;
}

/// Check if function has a return statement (recursively)
pub fn hasReturnStatement(body: []ast.Node) bool {
    for (body) |stmt| {
        if (stmt == .return_stmt) return true;
        // Check nested statements
        if (stmt == .if_stmt) {
            if (hasReturnStatement(stmt.if_stmt.body)) return true;
            if (hasReturnStatement(stmt.if_stmt.else_body)) return true;
        }
        if (stmt == .while_stmt) {
            if (hasReturnStatement(stmt.while_stmt.body)) return true;
            if (stmt.while_stmt.orelse_body) |orelse_body| {
                if (hasReturnStatement(orelse_body)) return true;
            }
        }
        if (stmt == .for_stmt) {
            if (hasReturnStatement(stmt.for_stmt.body)) return true;
            if (stmt.for_stmt.orelse_body) |orelse_body| {
                if (hasReturnStatement(orelse_body)) return true;
            }
        }
        if (stmt == .match_stmt) {
            for (stmt.match_stmt.cases) |case| {
                if (hasReturnStatement(case.body)) return true;
            }
        }
        if (stmt == .try_stmt) {
            if (hasReturnStatement(stmt.try_stmt.body)) return true;
            for (stmt.try_stmt.handlers) |handler| {
                if (hasReturnStatement(handler.body)) return true;
            }
            if (hasReturnStatement(stmt.try_stmt.else_body)) return true;
            if (hasReturnStatement(stmt.try_stmt.finalbody)) return true;
        }
        if (stmt == .with_stmt) {
            if (hasReturnStatement(stmt.with_stmt.body)) return true;
        }
    }
    return false;
}

/// Check if function body contains a return statement WITH a value (not bare `return`)
/// This is important for return type inference: functions with only bare `return` are void,
/// while functions with `return value` need a non-void return type.
pub fn hasReturnWithValue(body: []ast.Node) bool {
    for (body) |stmt| {
        if (stmt == .return_stmt) {
            // Only count returns that have a value
            if (stmt.return_stmt.value != null) return true;
        }
        // Check nested statements
        if (stmt == .if_stmt) {
            if (hasReturnWithValue(stmt.if_stmt.body)) return true;
            if (hasReturnWithValue(stmt.if_stmt.else_body)) return true;
        }
        if (stmt == .while_stmt) {
            if (hasReturnWithValue(stmt.while_stmt.body)) return true;
            if (stmt.while_stmt.orelse_body) |orelse_body| {
                if (hasReturnWithValue(orelse_body)) return true;
            }
        }
        if (stmt == .for_stmt) {
            if (hasReturnWithValue(stmt.for_stmt.body)) return true;
            if (stmt.for_stmt.orelse_body) |orelse_body| {
                if (hasReturnWithValue(orelse_body)) return true;
            }
        }
        if (stmt == .match_stmt) {
            for (stmt.match_stmt.cases) |case| {
                if (hasReturnWithValue(case.body)) return true;
            }
        }
        if (stmt == .try_stmt) {
            if (hasReturnWithValue(stmt.try_stmt.body)) return true;
            for (stmt.try_stmt.handlers) |handler| {
                if (hasReturnWithValue(handler.body)) return true;
            }
            if (hasReturnWithValue(stmt.try_stmt.else_body)) return true;
            if (hasReturnWithValue(stmt.try_stmt.finalbody)) return true;
        }
        if (stmt == .with_stmt) {
            if (hasReturnWithValue(stmt.with_stmt.body)) return true;
        }
    }
    return false;
}

/// Check if function body contains any yield statements (is a generator)
pub fn hasYieldStatement(body: []ast.Node) bool {
    for (body) |stmt| {
        if (stmt == .yield_stmt or stmt == .yield_from_stmt) return true;
        // Check nested statements
        if (stmt == .if_stmt) {
            if (hasYieldStatement(stmt.if_stmt.body)) return true;
            if (hasYieldStatement(stmt.if_stmt.else_body)) return true;
        }
        if (stmt == .while_stmt) {
            if (hasYieldStatement(stmt.while_stmt.body)) return true;
            if (stmt.while_stmt.orelse_body) |orelse_body| {
                if (hasYieldStatement(orelse_body)) return true;
            }
        }
        if (stmt == .for_stmt) {
            if (hasYieldStatement(stmt.for_stmt.body)) return true;
            if (stmt.for_stmt.orelse_body) |orelse_body| {
                if (hasYieldStatement(orelse_body)) return true;
            }
        }
        if (stmt == .try_stmt) {
            if (hasYieldStatement(stmt.try_stmt.body)) return true;
            for (stmt.try_stmt.handlers) |h| {
                if (hasYieldStatement(h.body)) return true;
            }
            if (hasYieldStatement(stmt.try_stmt.else_body)) return true;
            if (hasYieldStatement(stmt.try_stmt.finalbody)) return true;
        }
        if (stmt == .with_stmt) {
            if (hasYieldStatement(stmt.with_stmt.body)) return true;
        }
        if (stmt == .match_stmt) {
            for (stmt.match_stmt.cases) |case| {
                if (hasYieldStatement(case.body)) return true;
            }
        }
    }
    return false;
}

/// Generate function signature: fn name(params...) return_type {
pub fn genFunctionSignature(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    needs_allocator: bool,
) CodegenError!void {
    // For async functions, generate wrapper that returns a Task
    if (func.is_async) {
        try genAsyncFunctionSignature(self, func, needs_allocator);
        return;
    }

    // Check if any parameter is used in isinstance() - these need inline fn
    // so that comptime type checks can be evaluated and branches pruned
    var has_type_check_param = false;
    for (func.args) |arg| {
        if (param_analyzer.isParameterUsedInTypeCheck(func.body, arg.name)) {
            has_type_check_param = true;
            break;
        }
    }

    // Generate function signature: fn name(param: type, ...) return_type {
    // Rename "main" to "__user_main" to avoid conflict with entry point
    // Use "inline fn" if function has type-check parameters for comptime branch pruning
    // Use "export fn" for WASM browser targets (expose to JavaScript)
    if (has_type_check_param) {
        try emitConst(self,"inline fn ");
    } else if (self.target_wasm_browser and !std.mem.eql(u8, func.name, "main")) {
        // Export functions for WASM (except main which becomes _start)
        try emitConst(self,"export fn ");
    } else {
        try emitConst(self,"fn ");
    }
    if (std.mem.eql(u8, func.name, "main")) {
        try emitConst(self,"__user_main");
    } else {
        // Escape Zig reserved keywords (e.g., "test" -> @"test")
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func.name);
    }
    try emitConst(self,"(");

    // Add allocator as first parameter if needed
    var param_offset: usize = 0;
    if (needs_allocator) {
        // Check if allocator is actually used in function body
        const allocator_used = param_analyzer.isNameUsedInBody(func.body, "allocator");
        if (!allocator_used) {
            try emitConst(self,"_: std.mem.Allocator");
        } else {
            try emitConst(self,"allocator: std.mem.Allocator");
        }
        param_offset = 1;
        if (func.args.len > 0) {
            try emitConst(self,", ");
        }
    }

    // Check if this is a generator function (has yield statements) - generators
    // have their bodies transformed, so all params may appear unused in generated code
    const is_generator = hasYieldStatement(func.body);

    // Generate parameters
    for (func.args, 0..) |arg, i| {
        if (i > 0) try emitConst(self,", ");

        // Check if parameter name shadows a module-level function, variable, or imported module
        // If so, we need to rename it to avoid Zig shadowing errors
        // Also check zig_keywords.wouldShadowModule for common Python stdlib modules that
        // get aliased at module level (e.g., `const types = std;`)
        const shadows_module_level = self.module_level_funcs.contains(arg.name) or
            self.module_level_vars.contains(arg.name) or
            self.imported_modules.contains(arg.name) or
            zig_keywords.wouldShadowModule(arg.name);

        // Check if parameter shadows a local variable from an outer scope
        // e.g., for module in modules: class C: def setUpClass(module): ... - `module` shadows loop var
        // Use isDeclaredInAnyScope to check all scopes (including outer function scopes)
        const shadows_local_scope = self.isDeclaredInAnyScope(arg.name);

        // Check if parameter name shadows a sibling method or class-level attribute
        // e.g., def __release_buffer__(self, buffer): ... where 'buffer' is also a method
        // Also check class-level assignments like 'num = property(...)' which become lazy methods
        const shadows_class_member = if (self.current_class_body) |class_body| blk: {
            for (class_body) |stmt| {
                // Check methods
                if (stmt == .function_def) {
                    if (std.mem.eql(u8, stmt.function_def.name, arg.name)) {
                        break :blk true;
                    }
                }
                // Check class-level assignments (become lazy attrs or fields)
                // e.g., num = property(_get_num) or items = [lambda i=i: i for i in range(5)]
                if (stmt == .assign) {
                    for (stmt.assign.targets) |target| {
                        if (target == .name) {
                            if (std.mem.eql(u8, target.name.id, arg.name)) {
                                break :blk true;
                            }
                        }
                    }
                }
            }
            break :blk false;
        } else false;

        // Check if parameter is used in function body - prefix unused with "_"
        // Also check if parameter is captured by any nested class (used via closure)
        // Note: When parameter shadows module-level function, body uses the renamed
        // version (e.g., indices__local), so we must check for that usage too
        // For generators, always mark params as used since yield body isn't properly generated
        const is_used_directly = if (is_generator) true else param_analyzer.isNameUsedInBody(func.body, arg.name);
        const is_captured = self.isVarCapturedByAnyNestedClass(arg.name);
        const is_used = is_used_directly or is_captured or shadows_module_level or shadows_class_member or shadows_local_scope;

        // For unused parameters, use "_" (anonymous) instead of "_name" in Zig 0.15+
        // "_name" still triggers unused warnings - only "_" fully ignores
        if (!is_used) {
            try emitConst(self,"_: ");
            // Skip straight to type - no name, no suffix
        } else {
            // Check if this parameter was renamed (set up in generators.zig before signature generation)
            // This ensures signature and body use the same renamed parameter name
            if (self.var_renames.get(arg.name)) |renamed| {
                try emitConst(self,renamed);
                // NameGen renames don't include _param suffix, so add it if has default
                if (arg.default != null) {
                    try emitConst(self,"_param");
                }
            } else if (shadows_local_scope) {
                // Parameter shadows local variable from outer scope - rename to avoid Zig error
                const renamed = try std.fmt.allocPrint(self.allocator, "{s}__param", .{arg.name});
                try emitConst(self,renamed);
                try self.var_renames.put(arg.name, renamed);
            } else {
                // Use centralized parameter naming (handles keywords, shadows, and defaults in correct priority)
                // Priority: has_default → _param suffix (avoids collision, e.g., "stop" → "stop_param")
                //           shadows method → _ suffix (e.g., "stop" → "stop_")
                //           zig keyword → @"" escaping (e.g., "type" → @"type")
                const param_info = try zig_keywords.getZigParamName(self.allocator, arg.name, arg.default != null);
                try emitConst(self,param_info.name);
                // Note: No separate _param suffix needed - getZigParamName handles it
            }
            try emitConst(self,": ");
        }

        // Check if this parameter is used as a function (called or returned - decorator pattern)
        // For decorators, use anytype to accept any function type
        const is_func = param_analyzer.isParameterUsedAsFunction(func.body, arg.name);
        const is_iter = param_analyzer.isParameterUsedAsIterator(func.body, arg.name);
        const is_type_check = param_analyzer.isParameterUsedInTypeCheck(func.body, arg.name);
        const is_passed_to_callable = param_analyzer.isParameterPassedToCallableParam(func.body, arg.name, func.args);
        // Check if function has any callable parameter - if so, all other params need anytype
        // since they may be passed (directly or indirectly) to the callable
        const has_callable_param = blk: {
            for (func.args) |p| {
                if (param_analyzer.isParameterUsedAsFunction(func.body, p.name)) {
                    break :blk true;
                }
            }
            break :blk false;
        };
        if (is_func and arg.default == null) {
            try emitConst(self,"anytype"); // For decorators and higher-order functions (without defaults)
            try self.anytype_params.put(arg.name, {});
        } else if (is_iter and arg.type_annotation == null) {
            // Parameter used as iterator (for x in param:) - use anytype for slice inference
            // Note: ?anytype is not valid in Zig, so we don't add ? prefix for anytype params
            try emitConst(self,"anytype");
            try self.anytype_params.put(arg.name, {});
        } else if (is_type_check and arg.type_annotation == null) {
            // Parameter used in isinstance() type check - use anytype for runtime type checking
            // e.g., def isint(x): return isinstance(x, int)
            try emitConst(self,"anytype");
            try self.anytype_params.put(arg.name, {});
        } else if ((is_passed_to_callable or has_callable_param) and arg.type_annotation == null) {
            // Parameter passed to another param that is called as a function, OR
            // function has a callable param (may be passed indirectly)
            // e.g., def foo(fxn, arg, x): fxn(arg); y = (x,) - all non-callable need anytype
            try emitConst(self,"anytype");
            try self.anytype_params.put(arg.name, {});
        } else if (arg.type_annotation) |_| {
            // Use explicit type annotation if provided
            const zig_type = pythonTypeToZig(arg.type_annotation);
            // Make optional if has default value
            if (arg.default != null) {
                try emitConst(self,"?");
            }
            try emitConst(self,zig_type);
        } else if (arg.default) |default_expr| {
            // No annotation but has default - infer type from default value
            const default_type = self.type_inferrer.inferExpr(default_expr.*) catch .unknown;
            const default_tag = @as(std.meta.Tag(@TypeOf(default_type)), default_type);
            if (default_tag == .unknown) {
                // Two-Flow: Unknown type with default = uncertain, use PyValue fallback
                try emitConst(self,"?runtime.PyValue");
            } else if (default_tag == .none) {
                // For None defaults, use ?i64 (most common case)
                try emitConst(self,"?i64");
            } else {
                try emitConst(self,"?");
                const zig_type = try self.nativeTypeToZigType(default_type);
                defer self.allocator.free(zig_type);
                try emitConst(self,zig_type);
            }
        } else if (param_analyzer.isParameterComparedToString(func.body, arg.name)) {
            // Parameter compared to string constant - infer as string type
            // e.g., def foo(encoding): if encoding == "utf-8": ...
            if (arg.default != null) {
                try emitConst(self,"?");
            }
            try emitConst(self,"[]const u8");
            // Also register with type inferrer so comparison codegen knows to use std.mem.eql
            // Store in scoped_var_types with function name as scope key
            const scoped_key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ func.name, arg.name });
            try self.type_inferrer.scoped_var_types.put(scoped_key, .{ .string = .literal });
        } else if (try getTypeFromCallSiteOrScope(self, func, arg, i)) |zig_type| {
            defer self.allocator.free(zig_type);
            if (arg.default != null) try emitConst(self,"?");
            try emitConst(self,zig_type);
            // Also register parameter type with type inferrer for aug_assign detection
            // Without this, mutable copies would not know their type
            const native_type_core = @import("../../../../../analysis/native_types/core.zig");
            const native_type = native_type_core.zigTypeStringToNative(zig_type);
            if (native_type != .unknown) {
                const scoped_key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ func.name, arg.name });
                try self.type_inferrer.scoped_var_types.put(scoped_key, native_type);
            }
        } else if (self.getVarTypeInScope(func.name, arg.name)) |var_type| {
            // Use scoped type inference for function parameters
            // This avoids type pollution from variables with same name in other scopes
            const var_type_tag = @as(std.meta.Tag(@TypeOf(var_type)), var_type);
            if (var_type_tag != .unknown) {
                // For dict types with =None default, use anytype since different call sites
                // may pass dicts with different value types (polymorphic pattern)
                if (var_type_tag == .dict and arg.default != null) {
                    const is_none_default = arg.default.?.* == .constant and
                        arg.default.?.constant.value == .none;
                    if (is_none_default) {
                        try emitConst(self,"anytype");
                        try self.anytype_params.put(arg.name, {});
                        continue; // Skip to next parameter
                    }
                }
                const zig_type = try self.nativeTypeToZigType(var_type);
                defer self.allocator.free(zig_type);
                // Make optional if has default value
                if (arg.default != null) {
                    try emitConst(self,"?");
                }
                try emitConst(self,zig_type);
            } else if (arg.default) |default_expr| {
                // .unknown but has default value - infer from default
                const default_type = self.type_inferrer.inferExpr(default_expr.*) catch .unknown;
                const default_tag = @as(std.meta.Tag(@TypeOf(default_type)), default_type);
                if (default_tag != .unknown and default_tag != .none) {
                    try emitConst(self,"?");
                    const zig_type = try self.nativeTypeToZigType(default_type);
                    defer self.allocator.free(zig_type);
                    try emitConst(self,zig_type);
                } else {
                    // Two-Flow: Check confidence before defaulting to i64
                    // Create scoped key for parameter confidence lookup
                    const param_scoped_key = std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ func.name, arg.name }) catch null;
                    defer if (param_scoped_key) |k| self.allocator.free(k);
                    const param_confidence = if (param_scoped_key) |k|
                        self.type_inferrer.scoped_var_confidence.get(k) orelse .uncertain
                    else
                        .uncertain;
                    if (param_confidence == .uncertain) {
                        try emitConst(self,"?runtime.PyValue");
                    } else {
                        try emitConst(self,"?i64");
                    }
                }
            } else {
                // Two-Flow: .unknown means we don't know - check confidence
                const param_scoped_key = std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ func.name, arg.name }) catch null;
                defer if (param_scoped_key) |k| self.allocator.free(k);
                const param_confidence = if (param_scoped_key) |k|
                    self.type_inferrer.scoped_var_confidence.get(k) orelse .uncertain
                else
                    .uncertain;
                if (param_confidence == .uncertain) {
                    try emitConst(self,"runtime.PyValue");
                } else {
                    try emitConst(self,"i64");
                }
            }
        } else if (arg.default) |default_expr| {
            // Infer type from default value
            const default_type = self.type_inferrer.inferExpr(default_expr.*) catch .unknown;
            const default_tag = @as(std.meta.Tag(@TypeOf(default_type)), default_type);
            if (default_tag != .unknown and default_tag != .none) {
                try emitConst(self,"?");
                const zig_type = try self.nativeTypeToZigType(default_type);
                defer self.allocator.free(zig_type);
                try emitConst(self,zig_type);
            } else {
                // Two-Flow: Check confidence before defaulting to i64
                const param_scoped_key = std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ func.name, arg.name }) catch null;
                defer if (param_scoped_key) |k| self.allocator.free(k);
                const param_confidence = if (param_scoped_key) |k|
                    self.type_inferrer.scoped_var_confidence.get(k) orelse .uncertain
                else
                    .uncertain;
                if (param_confidence == .uncertain) {
                    try emitConst(self,"?runtime.PyValue");
                } else {
                    try emitConst(self,"?i64");
                }
            }
        } else {
            // No type hint, no inference, no default, no call site
            // Two-Flow: Check confidence before defaulting to i64
            const param_scoped_key = std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ func.name, arg.name }) catch null;
            defer if (param_scoped_key) |k| self.allocator.free(k);
            const param_confidence = if (param_scoped_key) |k|
                self.type_inferrer.scoped_var_confidence.get(k) orelse .uncertain
            else
                .uncertain;
            if (param_confidence == .uncertain) {
                try emitConst(self,"runtime.PyValue");
            } else {
                try emitConst(self,"i64");
            }
        }
    }

    // Add *args parameter as a slice if present
    if (func.vararg) |vararg_name| {
        if (func.args.len > 0 or needs_allocator) try emitConst(self,", ");
        // Check if vararg is used in function body - use "_:" for unused params
        const vararg_is_used = param_analyzer.isNameUsedInBody(func.body, vararg_name);
        if (!vararg_is_used) {
            try emitConst(self,"_: anytype"); // Unused vararg - use anytype for flexibility
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), vararg_name);
            try emitConst(self,": anytype"); // Use anytype for varargs to handle any slice type
        }
    }

    // Add **kwargs parameter as a HashMap if present
    if (func.kwarg) |kwarg_name| {
        if (func.args.len > 0 or func.vararg != null or needs_allocator) try emitConst(self,", ");
        // Check if kwargs is used in function body - use "_:" for unused params
        const kwarg_is_used = param_analyzer.isNameUsedInBody(func.body, kwarg_name);
        if (!kwarg_is_used) {
            try emitConst(self,"_: *runtime.PyObject"); // Unused kwarg
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), kwarg_name);
            try emitConst(self,": *runtime.PyObject"); // PyDict wrapped in PyObject
        }
    }

    try emitConst(self,") ");

    // Determine return type based on type annotation or return statements
    try genReturnType(self, func, needs_allocator);
}

/// Generate async function signature that spawns green threads
fn genAsyncFunctionSignature(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    needs_allocator: bool,
) CodegenError!void {
    _ = needs_allocator; // Async functions always need allocator

    // Use state machine approach when ANY async function has I/O (for gather compatibility)
    // State machine: single-threaded, kqueue netpoller - optimal for I/O concurrency
    // Thread pool: multi-threaded, parallel execution - optimal for CPU-bound work
    if (self.anyAsyncHasIO()) {
        return state_machine.genAsyncStateMachine(self, func);
    }

    // Fallback: thread-based approach (blocking)
    // Rename "main" to "__user_main" to avoid conflict with entry point
    const func_name = if (std.mem.eql(u8, func.name, "main")) "__user_main" else func.name;

    // For functions with parameters, generate a context struct first
    if (func.args.len > 0) {
        try emitConst(self,"const ");
        try emitConst(self,func_name);
        try emitConst(self,"_Context = struct {\n");
        for (func.args) |arg| {
            try emitConst(self,"    ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try emitConst(self,": ");
            if (arg.type_annotation) |_| {
                const zig_type = pythonTypeToZig(arg.type_annotation);
                try emitConst(self,zig_type);
            } else {
                try emitConst(self,"i64");
            }
            try emitConst(self,",\n");
        }
        try emitConst(self,"};\n\n");
    }

    // Generate wrapper function that spawns green thread
    try emitConst(self,"fn ");
    try emitConst(self,func_name);
    try emitConst(self,"_async(");

    // Generate parameters for wrapper
    for (func.args, 0..) |arg, i| {
        if (i > 0) try emitConst(self,", ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
        try emitConst(self,": ");

        if (arg.type_annotation) |_| {
            const zig_type = pythonTypeToZig(arg.type_annotation);
            try emitConst(self,zig_type);
        } else {
            try emitConst(self,"i64");
        }
    }

    try emitConst(self,") !*runtime.GreenThread {\n");

    // Use spawn0() for zero-parameter functions, spawn() for functions with parameters
    if (func.args.len == 0) {
        try emitConst(self,"    return try runtime.scheduler.?.spawn0(");
        try emitConst(self,func_name);
        try emitConst(self,"_impl);\n");
    } else {
        try emitConst(self,"    return try runtime.scheduler.?.spawn(");
        try emitConst(self,func_name);
        try emitConst(self,"_impl, .{");

        // Pass parameters as struct fields
        for (func.args, 0..) |arg, i| {
            if (i > 0) try emitConst(self,", ");
            try emitConst(self,".");
            try emitConst(self,arg.name);
            try emitConst(self," = ");
            try emitConst(self,arg.name);
        }

        try emitConst(self,"});\n");
    }

    try emitConst(self,"}\n\n");

    // Generate implementation function
    try emitConst(self,"fn ");
    try emitConst(self,func_name);
    try emitConst(self,"_impl(");

    // For functions with parameters, take pointer to context struct
    if (func.args.len > 0) {
        try emitConst(self,"ctx: *");
        try emitConst(self,func_name);
        try emitConst(self,"_Context");
    }

    try emitConst(self,") !");

    // Determine return type for implementation
    if (func.return_type) |_| {
        const zig_return_type = pythonTypeToZig(func.return_type);
        try emitConst(self,zig_return_type);
    } else if (hasReturnStatement(func.body)) {
        try emitConst(self,"i64");
    } else {
        try emitConst(self,"void");
    }

    try emitConst(self," {\n");

    // Unpack context fields into local variables
    if (func.args.len > 0) {
        for (func.args) |arg| {
            try emitConst(self,"    const ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try emitConst(self," = ctx.");
            try emitConst(self,arg.name);
            try emitConst(self,";\n");
        }
    }
}

/// Generate return type for function signature
fn genReturnType(self: *NativeCodegen, func: ast.Node.FunctionDef, needs_allocator: bool) CodegenError!void {
    // Check if function needs error union via function_traits analysis
    // This detects: raise, assert, try/except, int/float conversion, etc.
    const needs_error = needs_allocator or self.funcNeedsErrorUnion(func.name);

    // For generator functions, return []runtime.PyValue (eager evaluation)
    // Generator functions ALWAYS need error union because they allocate ArrayList
    if (self.in_generator_function) {
        try emitConst(self,"![]runtime.PyValue {\n");
        return;
    }

    if (func.return_type) |type_hint| {
        // Use explicit return type annotation if provided
        // First try simple type mapping
        const simple_zig_type = pythonTypeToZig(func.return_type);
        const is_simple_type = !std.mem.eql(u8, simple_zig_type, "i64") or
            std.mem.eql(u8, type_hint, "int");

        if (is_simple_type) {
            if (needs_error) try emitConst(self,"!");
            try emitConst(self,simple_zig_type);
            try emitConst(self," {\n");
        } else {
            // Complex type (like tuple[str, str]) - use inferred type
            try emitInferredReturnType(self, func.name, needs_error);
        }
    } else if (hasReturnStatement(func.body)) {
        // Check if this returns a parameter (decorator pattern)
        var returned_param_name: ?[]const u8 = null;
        var returned_param_has_default = false;
        for (func.body) |stmt| {
            if (stmt == .return_stmt) {
                if (stmt.return_stmt.value) |val| {
                    if (val.* == .name) {
                        // Check if returned value is a parameter that's anytype
                        for (func.args) |arg| {
                            if (std.mem.eql(u8, arg.name, val.name.id)) {
                                if (param_analyzer.isParameterUsedAsFunction(func.body, arg.name)) {
                                    returned_param_name = arg.name;
                                    returned_param_has_default = arg.default != null;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Only use @TypeOf(param) for decorator pattern IF param doesn't have defaults
        // Params with defaults use anytype/?type which breaks @TypeOf inference
        if (returned_param_name != null and !returned_param_has_default) {
            const param_name = returned_param_name.?;
            // Decorator pattern: return @TypeOf(param)
            try emitConst(self,"@TypeOf(");
            try emitConst(self,param_name);
            try emitConst(self,") {\n");
        } else if (getReturnedNestedFuncName(func.body)) |nested_func_name| {
            // Function returns a nested function (closure factory pattern)
            // The closure wrapper struct must be pre-declared at module level
            // Check if we have a pre-declared closure type for this
            const closure_type_name = self.pending_closure_types.get(nested_func_name);
            if (closure_type_name) |type_name| {
                if (needs_error) {
                    try emitConst(self,"!");
                }
                try emitConst(self,type_name);
                try emitConst(self," {\n");
            } else {
                // No pre-declared type - fallback to i64
                if (needs_error) try emitConst(self,"!");
                try emitConst(self,"i64 {\n");
            }
        } else {
            // Try to infer return type from func_return_types
            try emitInferredReturnType(self, func.name, needs_error);
        }
    } else {
        // Functions with allocator or errors but no return still need error union for void
        if (needs_error) {
            try emitConst(self,"!void {\n");
        } else {
            try emitConst(self,"void {\n");
        }
    }
}

/// Generate method signature for class methods
pub fn genMethodSignature(
    self: *NativeCodegen,
    class_name: []const u8,
    method: ast.Node.FunctionDef,
    mutates_self: bool,
    needs_allocator: bool,
) CodegenError!void {
    return genMethodSignatureWithSkip(self, class_name, method, mutates_self, needs_allocator, false, true);
}

/// Generate method signature with skip flag for skipped test methods
pub fn genMethodSignatureWithSkip(
    self: *NativeCodegen,
    class_name: []const u8,
    method: ast.Node.FunctionDef,
    mutates_self: bool,
    needs_allocator: bool,
    is_skipped: bool,
    actually_uses_allocator: bool,
) CodegenError!void {
    try emitConst(self,"\n");
    try self.emitIndent();

    // For __new__ methods, the first Python parameter is 'cls' not 'self'
    const is_new_method = std.mem.eql(u8, method.name, "__new__");

    // Check for @staticmethod and @classmethod decorators
    // Note: __init_subclass__ and __class_getitem__ are implicit classmethods in Python
    const is_staticmethod = hasStaticmethodDecorator(method.decorators);
    const is_implicit_classmethod = std.mem.eql(u8, method.name, "__init_subclass__") or
        std.mem.eql(u8, method.name, "__class_getitem__") or
        std.mem.eql(u8, method.name, "__new__");
    const is_classmethod = hasClassmethodDecorator(method.decorators) or is_implicit_classmethod;

    // Check if class has a known parent - for parameter usage detection
    const has_known_parent = self.getParentClassName(class_name) != null;

    // Generate "pub fn methodname(...)"
    // Escape method name if it's a Zig keyword (e.g., "test" -> @"test")
    try emitConst(self,"pub fn ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method.name);
    try emitConst(self,"(");

    // For @staticmethod: no self/cls parameter at all
    // For @classmethod: no self parameter (cls is skipped from Python params)
    // For regular methods: add self parameter
    var has_first_param = false;
    if (!is_staticmethod and !is_classmethod) {
        // Use *const for methods that don't mutate self (read-only methods)
        // Use __self for nested classes inside methods to avoid shadowing outer self parameter
        // NOTE: We always use "self" or "__self" (never "_") because:
        // 1. self_analyzer can't detect class attribute access (self.attr -> @This().attr)
        // 2. Instead, we emit "_ = &self;" in the body to suppress unused warnings
        // EXCEPTION: For __new__ methods, use __cls (or _) because the method body often creates
        // a local 'self' variable (self = super().__new__(cls)) which would shadow __self
        const self_param_name = if (is_new_method)
            (if (self.method_nesting_depth > 0) "__cls" else "_")
        else if (self.method_nesting_depth > 0)
            "__self"
        else
            "self";

        try self.output.writer(self.allocator).print("{s}: ", .{self_param_name});
        if (mutates_self) {
            try emitConst(self,"*@This()");
        } else {
            try emitConst(self,"*const @This()");
        }
        has_first_param = true;
    }

    // Add allocator parameter if method needs it (for error union return type)
    // Use "_" if allocator is not actually used in the body to avoid unused parameter error
    // Use __alloc for nested classes to avoid shadowing outer allocator
    // Note: Check if "allocator" name is literally used in Python source - the allocator param
    // is added by codegen, so if Python code doesn't use it, we should use "_"
    if (needs_allocator) {
        if (has_first_param) try emitConst(self,", ");
        // Check if any code in the method body actually references "allocator" by name
        // (This handles cases where Python code explicitly uses allocator, though rare)
        const allocator_literally_used = param_analyzer.isNameUsedInBody(method.body, "allocator");
        if (actually_uses_allocator and allocator_literally_used) {
            const is_nested = self.nested_class_names.contains(class_name);
            const alloc_name = if (is_nested) "__alloc" else "allocator";
            try self.output.writer(self.allocator).print("{s}: std.mem.Allocator", .{alloc_name});
        } else {
            try emitConst(self,"_: std.mem.Allocator");
        }
        has_first_param = true;
    }

    // Add other parameters (skip 'self' for regular methods, skip 'cls' for classmethod)
    // For skipped methods or unused parameters, use "_:" to suppress unused warnings
    // Get class body for BigInt call site checking
    const class_body: ?[]const ast.Node = if (self.class_registry.getClass(class_name)) |cd| cd.body else null;

    var param_index: usize = 0;
    var is_first_python_param = true;
    for (method.args) |arg| {
        // For @staticmethod: include ALL parameters (no self/cls to skip)
        // For @classmethod: skip the first parameter (cls)
        // For regular methods: skip the first parameter (self)
        if (is_first_python_param) {
            is_first_python_param = false;
            if (!is_staticmethod) {
                // Skip self/cls for regular methods and classmethods
                // NOTE: Don't increment param_index here - it's 0-based for non-self params
                continue;
            }
        }
        // NOTE: param_index is incremented at the end of the loop, not with defer,
        // so it doesn't increment when we continue (skip first param for non-static methods)

        // Add comma separator before this parameter (if not the first parameter overall)
        if (has_first_param or param_index > 0) {
            try emitConst(self,", ");
        }
        // Check if parameter is used in method body
        // For __init__ and __new__ methods, exclude parent calls (they're skipped in codegen)
        const is_init_or_new = std.mem.eql(u8, method.name, "__init__") or std.mem.eql(u8, method.name, "__new__");

        // In __new__ methods, 'cls' is never used in Zig (we don't use class references)
        // The generated code returns the value directly, not cls()
        const is_cls_in_new = is_new_method and std.mem.eql(u8, arg.name, "cls");

        // Check if this is a comparison magic method's second parameter (comparison target)
        // The second param (after self) in comparison methods is always used for comparison
        // even if analysis doesn't detect it (e.g., `return self is other` codegen incomplete)
        const is_comparison_method = std.mem.eql(u8, method.name, "__eq__") or
            std.mem.eql(u8, method.name, "__ne__") or
            std.mem.eql(u8, method.name, "__lt__") or
            std.mem.eql(u8, method.name, "__le__") or
            std.mem.eql(u8, method.name, "__gt__") or
            std.mem.eql(u8, method.name, "__ge__");
        // param_index is 0-based AFTER self, so param_index==0 is the second Python param
        const is_comparison_second_param = is_comparison_method and param_index == 0;

        // For classes without known parents, super() calls are stripped during codegen.
        // Use isNameUsedInBodyExcludingSuperCalls to avoid marking params as "used" when
        // they only appear in stripped super() calls.
        const is_param_used = if (is_cls_in_new)
            false // cls is never used in __new__ - we return value directly
        else if (is_comparison_second_param)
            true // Always consider comparison target used in comparison methods
        else if (is_init_or_new)
            param_analyzer.isNameUsedInInitBody(method.body, arg.name)
        else if (!has_known_parent)
            param_analyzer.isNameUsedInBodyExcludingSuperCalls(method.body, arg.name)
        else
            param_analyzer.isNameUsedInBody(method.body, arg.name);
        // Check if parameter name shadows a sibling method in the same class
        // This includes both explicit methods AND attributes assigned to None (which become stub methods)
        const shadows_class_method = if (self.current_class_body) |cb| blk: {
            for (cb) |stmt| {
                // Check explicit methods
                if (stmt == .function_def) {
                    if (std.mem.eql(u8, stmt.function_def.name, arg.name)) {
                        break :blk true;
                    }
                }
                // Check class attributes assigned to None - these become stub methods
                if (stmt == .assign) {
                    for (stmt.assign.targets) |target| {
                        if (target == .name and stmt.assign.value.* == .constant and
                            stmt.assign.value.constant.value == .none)
                        {
                            if (std.mem.eql(u8, target.name.id, arg.name)) {
                                break :blk true;
                            }
                        }
                    }
                }
            }
            break :blk false;
        } else false;

        // Check if parameter shadows an imported module (e.g., 'test', 'copy')
        const shadows_imported_module = self.imported_modules.contains(arg.name);

        // Check if parameter shadows a local variable from an outer scope
        // e.g., for module in modules: class C: def setUpClass(module): ... - `module` shadows loop var
        const shadows_local_scope = self.isDeclaredInAnyScope(arg.name);

        if (is_skipped or !is_param_used) {
            // Use anonymous parameter for unused
            try emitConst(self,"_: ");
        } else {
            // Add rename suffix if shadows class method, imported module, or local scope variable
            // Use deterministic naming ({name}__shadow) so signature and body can compute same name
            // This is needed because var_renames is cleared before body generation
            if (shadows_class_method or shadows_imported_module or shadows_local_scope) {
                // Use deterministic rename pattern (not name_gen which has a counter)
                const renamed = try std.fmt.allocPrint(self.allocator, "{s}__shadow", .{arg.name});
                try zig_keywords.writeParamName(self.output.writer(self.allocator), renamed);
                // NOTE: We intentionally don't add to var_renames here because it gets cleared
                // before body generation. function_gen.zig will detect the shadow and add
                // the same rename using the same deterministic pattern.
            } else {
                // Use writeParamName to handle Zig keywords AND method shadowing (e.g., "init" -> "init_arg")
                try zig_keywords.writeParamName(self.output.writer(self.allocator), arg.name);
            }
            try emitConst(self,": ");
        }
        // Use anytype for method params without type annotation to support string literals
        // This lets Zig infer the type from the call site
        // Parameters with defaults become optional (? prefix)

        // Check if any call site passes BigInt to this parameter
        const receives_bigint = if (class_body) |cb|
            methodReceivesBigIntArg(cb, method.name, param_index)
        else
            false;

        // Check if this parameter is used as a function (called directly, e.g., op(a, b))
        // For such parameters, use anytype to accept any callable type
        // This must be checked BEFORE type inference, which might return .callable → PyCallable
        const is_callable_param = param_analyzer.isParameterUsedAsFunction(method.body, arg.name);

        if (is_callable_param and arg.default == null) {
            // Parameter is called as a function - use anytype for any callable type
            try emitConst(self,"anytype");
            try self.anytype_params.put(arg.name, {});
        } else if (receives_bigint) {
            // Parameter receives BigInt at some call site - use anytype
            try emitConst(self,"anytype");
            try self.anytype_params.put(arg.name, {});
        } else if (arg.type_annotation) |_| {
            if (arg.default != null) {
                try emitConst(self,"?");
            }
            const param_type = pythonTypeToZig(arg.type_annotation);
            try emitConst(self,param_type);
        } else if (self.getVarType(arg.name)) |var_type| {
            // Check if this is a dunder arithmetic method that needs anytype for polymorphism
            // Methods like __add__, __sub__, etc. need to accept multiple types (int, Rat, float, etc.)
            // So we use anytype instead of *runtime.PyObject
            const is_dunder_arithmetic = std.mem.startsWith(u8, method.name, "__") and
                (std.mem.eql(u8, method.name, "__add__") or
                std.mem.eql(u8, method.name, "__sub__") or
                std.mem.eql(u8, method.name, "__mul__") or
                std.mem.eql(u8, method.name, "__truediv__") or
                std.mem.eql(u8, method.name, "__floordiv__") or
                std.mem.eql(u8, method.name, "__mod__") or
                std.mem.eql(u8, method.name, "__pow__") or
                std.mem.eql(u8, method.name, "__radd__") or
                std.mem.eql(u8, method.name, "__rsub__") or
                std.mem.eql(u8, method.name, "__rmul__") or
                std.mem.eql(u8, method.name, "__rtruediv__") or
                std.mem.eql(u8, method.name, "__rfloordiv__") or
                std.mem.eql(u8, method.name, "__rmod__") or
                std.mem.eql(u8, method.name, "__rpow__") or
                std.mem.eql(u8, method.name, "__eq__") or
                std.mem.eql(u8, method.name, "__ne__") or
                std.mem.eql(u8, method.name, "__lt__") or
                std.mem.eql(u8, method.name, "__le__") or
                std.mem.eql(u8, method.name, "__gt__") or
                std.mem.eql(u8, method.name, "__ge__"));

            if (is_dunder_arithmetic and std.mem.eql(u8, arg.name, "other")) {
                // Force anytype for polymorphic dunder methods
                try emitConst(self,"anytype");
                try self.anytype_params.put(arg.name, {});
                param_index += 1;
                continue;
            }

            // Try inferred type from type inferrer
            const var_type_tag = @as(std.meta.Tag(@TypeOf(var_type)), var_type);
            if (var_type_tag != .unknown) {
                // Check for class_instance type - if the class isn't in the registry,
                // it's probably a locally-defined class inside the function and we can't
                // use it as a parameter type (it would be undefined at function signature scope)
                if (type_traits.isClassInstance(var_type)) {
                    const inferred_class_name = var_type.class_instance;
                    if (!self.class_registry.classes.contains(inferred_class_name)) {
                        // Class not in registry - use anytype instead
                        try emitConst(self,"anytype");
                        try self.anytype_params.put(arg.name, {});
                    } else {
                        if (arg.default != null) {
                            try emitConst(self,"?");
                        }
                        const zig_type = try self.nativeTypeToZigType(var_type);
                        defer self.allocator.free(zig_type);
                        try emitConst(self,zig_type);
                    }
                } else {
                    // For dict types with =None default, use anytype since different call sites
                    // may pass dicts with different value types (polymorphic pattern)
                    if (var_type_tag == .dict and arg.default != null) {
                        const is_none_default = arg.default.?.* == .constant and
                            arg.default.?.constant.value == .none;
                        if (is_none_default) {
                            try emitConst(self,"anytype");
                            try self.anytype_params.put(arg.name, {});
                            param_index += 1;
                            continue; // Skip to next parameter
                        }
                    }
                    if (arg.default != null) {
                        try emitConst(self,"?");
                    }
                    const zig_type = try self.nativeTypeToZigType(var_type);
                    defer self.allocator.free(zig_type);
                    try emitConst(self,zig_type);
                }
            } else {
                // For anytype, we can't use ? prefix, so use anytype as-is
                // The caller must handle the optionality
                try emitConst(self,"anytype");
                try self.anytype_params.put(arg.name, {});
            }
        } else {
            try emitConst(self,"anytype");
            try self.anytype_params.put(arg.name, {});
        }

        // Increment param_index at end of loop (not defer) so it doesn't increment when we continue
        param_index += 1;
    }

    // Track if any parameter has been emitted (for proper comma handling)
    var any_param_emitted = has_first_param or param_index > 0;

    // Add *args parameter as a slice if present
    if (method.vararg) |vararg_name| {
        if (any_param_emitted) try emitConst(self,", ");
        any_param_emitted = true;

        // Track this method as having varargs for call site argument wrapping
        // Store param_index = number of regular params before varargs (not counting self)
        const method_key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, method.name });
        try self.vararg_methods.put(method_key, param_index);

        const is_vararg_used = param_analyzer.isNameUsedInBody(method.body, vararg_name);
        if (is_skipped or !is_vararg_used) {
            try emitConst(self,"_: []const runtime.PyValue"); // Use concrete slice type
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), vararg_name);
            try emitConst(self,": []const runtime.PyValue"); // Use concrete slice type
        }
    }

    // Add **kwargs parameter if present
    if (method.kwarg) |kwarg_name| {
        if (any_param_emitted) try emitConst(self,", ");
        const is_kwarg_used = param_analyzer.isNameUsedInBody(method.body, kwarg_name);
        if (is_skipped or !is_kwarg_used) {
            try emitConst(self,"_: anytype"); // Use anonymous for unused
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), kwarg_name);
            try emitConst(self,": anytype");
        }
    }

    try emitConst(self,") ");

    // Check for polymorphic return pattern - methods that return different types
    // based on input type (e.g., Rat.__add__ returns Rat for int/Rat, f64 for float)
    if (hasPolymorphicReturnPattern(method, self.anytype_params)) {
        // Generate comptime-computed return type based on anytype param
        // Find the anytype param name
        var anytype_param: ?[]const u8 = null;
        for (method.args) |arg| {
            if (self.anytype_params.contains(arg.name)) {
                anytype_param = arg.name;
                break;
            }
        }
        if (anytype_param) |param_name| {
            // Generate: PolymorphicReturn(@TypeOf(param))
            // Check if parameter was renamed due to shadowing (e.g., other -> other__shadow)
            // Same conditions used in parameter generation above
            const shadows_class_method = if (class_body) |cb| blk: {
                for (cb) |class_stmt| {
                    if (class_stmt == .function_def) {
                        if (std.mem.eql(u8, class_stmt.function_def.name, param_name)) {
                            break :blk true;
                        }
                    }
                }
                break :blk false;
            } else false;
            const shadows_imported_module = self.imported_modules.contains(param_name);
            const shadows_local_scope = self.isDeclaredInAnyScope(param_name);
            const param_was_renamed = shadows_class_method or shadows_imported_module or shadows_local_scope;

            try emitConst(self,"PolymorphicReturn__");
            try emitConst(self,method.name);
            try emitConst(self,"(@TypeOf(");
            if (param_was_renamed) {
                try emitConst(self,param_name);
                try emitConst(self,"__shadow");
            } else {
                try emitConst(self,param_name);
            }
            try emitConst(self,")) {\n");
            return;
        }
    }

    // Check for magic method return types FIRST
    // Some dunder methods have fixed return types that already include error union or not
    if (getMagicMethodReturnType(method.name)) |magic_return_type| {
        // Magic method return types already include error union if needed
        // e.g., "__bool__" -> "runtime.PythonError!bool", "__float__" -> "f64"
        try emitConst(self,magic_return_type);

        // Track if this method returns PyValue (for comparison magic methods)
        // But not if it returns a CONTAINER of PyValue (ArrayList, slice, etc.)
        if (std.mem.eql(u8, magic_return_type, "runtime.PyValue")) {
            self.current_function_returns_pyvalue = true;
        }
    } else if (std.mem.eql(u8, method.name, "__iter__")) {
        // Special handling for __iter__ - returns an iterator/slice
        // Check if method returns 'self' - common pattern for iterator classes
        const returns_self = blk: {
            for (method.body) |stmt| {
                if (stmt == .return_stmt) {
                    if (stmt.return_stmt.value) |val| {
                        if (val.* == .name and std.mem.eql(u8, val.name.id, "self")) {
                            break :blk true;
                        }
                    }
                }
            }
            break :blk false;
        };
        const needs_error = needs_allocator or self.funcNeedsErrorUnion(method.name);
        if (needs_error) try emitConst(self,"!");
        if (returns_self) {
            // Iterator class pattern: def __iter__(self): return self
            try emitConst(self,"*@This()");
        } else {
            // Non-self __iter__ - use PyValue for flexibility
            // This handles iter(range(...)) and other complex cases
            try emitConst(self,"runtime.PyValue");
        }
    } else if (std.mem.eql(u8, method.name, "__next__")) {
        // __next__ returns the next item or raises StopIteration
        // Use PyValue for flexibility
        const needs_error = needs_allocator or self.funcNeedsErrorUnion(method.name);
        if (needs_error) try emitConst(self,"!");
        try emitConst(self,"runtime.PyValue");
    } else if (method.return_type != null) {
        // Determine return type (add error union if allocator needed or function can error)
        // Note: funcNeedsErrorUnion uses simple name lookup, which works for most methods
        const needs_error = needs_allocator or self.funcNeedsErrorUnion(method.name);
        if (needs_error) {
            try emitConst(self,"!");
        }
        const type_hint = method.return_type.?;
        // Use explicit return type annotation if provided
        // If return type is class name, use @This() instead for self-reference
        if (std.mem.eql(u8, type_hint, class_name)) {
            try emitConst(self,"@This()");
        } else {
            const zig_return_type = pythonTypeToZig(method.return_type);
            try emitConst(self,zig_return_type);
        }
    } else if (hasReturnWithValue(method.body)) {
        // Determine if error union is needed for methods without explicit return type
        // IMPORTANT: Use hasReturnWithValue() not hasReturnStatement() because functions
        // that only have bare `return` (no value) should return void, not i64.
        // e.g., `def test_foo(self): if cond: return; ... # rest of code`
        const needs_error = needs_allocator or self.funcNeedsErrorUnion(method.name);

        // NOTE: Don't emit error union here! The nested class constructor path
        // (getReturnedNestedClassConstructor) unconditionally emits error union.
        // Emitting here would cause double error union (!!). Instead, we only emit
        // the error union in the specific paths that need it but don't already add it.

        // Check if method returns a lambda that captures self (closure)
        if (getReturnedLambda(method.body)) |lambda| {
            if (lambdaCapturesSelf(lambda.body.*)) {
                // Method returns a closure - use closure type name
                // The closure will be generated with current ID
                const id = self.name_gen.nextId();
                const closure_type = try std.fmt.allocPrint(
                    self.allocator,
                    "__m{d}_Closure",
                    .{id},
                );
                defer self.allocator.free(closure_type);
                try emitConst(self,closure_type);
                try emitConst(self," {\n");
                return;
            }
        }

        // Check if method returns 'self' or 'cls' - for nested classes this should be pointer type
        // Note: 'cls' is the first param in metaclass instance methods (like 'self' in regular classes)
        const returns_self = blk: {
            for (method.body) |stmt| {
                if (stmt == .return_stmt) {
                    if (stmt.return_stmt.value) |val| {
                        if (val.* == .name and (std.mem.eql(u8, val.name.id, "self") or
                            std.mem.eql(u8, val.name.id, "cls")))
                        {
                            break :blk true;
                        }
                    }
                }
            }
            break :blk false;
        };

        if (returns_self) {
            // For nested classes, self is a pointer, so returning self returns a pointer
            const current_class_is_nested = self.nested_class_names.contains(class_name);
            if (needs_error) try emitConst(self,"!");
            if (current_class_is_nested) {
                try emitConst(self,"*@This() {\n");
                return;
            }
            // Top-level classes return value type
            try emitConst(self,"@This() {\n");
            return;
        }

        // Check if method returns a parameter directly (for anytype params)
        var returned_param_name: ?[]const u8 = null;
        for (method.body) |stmt| {
            if (stmt == .return_stmt) {
                if (stmt.return_stmt.value) |val| {
                    if (val.* == .name) {
                        // Check if returned value is a parameter (not 'self')
                        for (method.args) |arg| {
                            // Skip self and cls - these are instance params, not general return values
                            if (!std.mem.eql(u8, arg.name, "self") and
                                !std.mem.eql(u8, arg.name, "cls") and
                                std.mem.eql(u8, arg.name, val.name.id) and
                                arg.type_annotation == null)
                            {
                                returned_param_name = arg.name;
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (returned_param_name) |param_name| {
            // Method returns an anytype param - use @TypeOf(param)
            // Use writeParamName to handle renamed params (e.g., init -> init_arg)
            if (needs_error) try emitConst(self,"!");
            try emitConst(self,"@TypeOf(");
            try zig_keywords.writeParamName(self.output.writer(self.allocator), param_name);
            try emitConst(self,")");
        } else {
            // First, check if method returns a constructor call to a nested class
            // This handles inherited methods like aug_test.__add__ returning aug_test(...)
            const returned_class = getReturnedNestedClassConstructor(method.body, self);
            if (returned_class) |rc| {
                // Class constructors can fail (allocator error), so ALWAYS add error union
                // when returning a class instance. The constructor uses try, so the
                // method must also be able to propagate errors.
                try emitConst(self,"!");
                // Nested classes are heap-allocated and return pointers
                // Check if the returned class OR the current class is nested
                const current_class_is_nested = self.nested_class_names.contains(class_name);
                const is_nested = self.nested_class_names.contains(rc) or current_class_is_nested;
                if (is_nested) {
                    try emitConst(self,"*");
                }
                // If returning same class, use @This() for self-reference
                if (std.mem.eql(u8, rc, class_name)) {
                    try emitConst(self,"@This()");
                } else {
                    // Check if the class was hoisted and renamed (e.g., name collision)
                    // hoisted_local_classes stores original_name -> actual_generated_name
                    const actual_name = self.hoisted_local_classes.get(rc) orelse self.var_renames.get(rc) orelse rc;
                    try emitConst(self,actual_name);
                }
                try emitConst(self," {\n");
                return;
            }

            // Try to get inferred return type from class_fields.methods
            const class_info = self.type_inferrer.class_fields.get(class_name);
            const inferred_type = if (class_info) |info| info.methods.get(method.name) else null;

            // Emit error union before the type
            if (needs_error) try emitConst(self,"!");

            if (inferred_type) |inf_type| {
                // Use inferred type (skip if .int or .unknown - those are defaults)
                if (inf_type != .int and inf_type != .unknown) {
                    const return_type_str = try self.nativeTypeToZigType(inf_type);
                    defer self.allocator.free(return_type_str);
                    // If return type matches class name, use @This() for self-reference
                    if (std.mem.eql(u8, return_type_str, class_name)) {
                        try emitConst(self,"@This()");
                    } else {
                        // Check if the return type is a known class or a safe Zig type
                        // Avoid using unknown names (like captured variables) as types
                        const is_known_type = KnownZigTypes.has(return_type_str) or
                            self.type_inferrer.class_fields.contains(return_type_str) or
                            self.nested_class_names.contains(return_type_str);
                        if (is_known_type) {
                            try emitConst(self,return_type_str);
                        } else {
                            // Unknown type (likely a captured variable) - use i64 as safe default
                            try emitConst(self,"i64");
                        }
                    }
                } else {
                    try emitConst(self,"i64");
                }
            } else {
                try emitConst(self,"i64");
            }
        }
    } else {
        // Methods without return statements - check if it's a generator method
        // Generator methods (with yield) ALWAYS need error union because they allocate ArrayList
        if (hasYieldStatement(method.body)) {
            try emitConst(self,"![]runtime.PyValue");
        } else {
            // Non-generator methods - check if body needs error union
            const needs_error = needs_allocator or self.funcNeedsErrorUnion(method.name);
            if (needs_error) {
                try emitConst(self,"!void");
            } else {
                try emitConst(self,"void");
            }
        }
    }

    try emitConst(self," {\n");

    // Emit self parameter suppression directly in signature generation as a safety net.
    // This ensures _ = &self; (or _ = &__self;) is always emitted for regular methods,
    // even in edge cases where the body generation might miss it (e.g., property decorators).
    // The suppression is harmless when self IS used (taking address of any variable is valid).
    if (!is_staticmethod and !is_classmethod) {
        const self_param_name: ?[]const u8 = if (std.mem.eql(u8, method.name, "__new__"))
            (if (self.method_nesting_depth > 0) "__cls" else null)
        else if (self.method_nesting_depth > 0)
            "__self"
        else
            "self";
        if (self_param_name) |spn| {
            self.indent();
            try self.emitIndent();
            try emitConst(self,"_ = &");
            try emitConst(self,spn);
            try emitConst(self,";\n");
            self.dedent();
        }
    }
}


/// Check if method returns a constructor call to a nested class
/// Returns the class name if found, null otherwise
/// Recursively searches inside if/elif/else blocks
fn getReturnedNestedClassConstructor(body: []const ast.Node, self: *NativeCodegen) ?[]const u8 {
    // First, collect all class definitions in this body (locally-defined classes)
    var local_class_names: [32][]const u8 = undefined;
    var local_class_count: usize = 0;
    collectLocalClassDefinitions(body, &local_class_names, &local_class_count);

    for (body) |stmt| {
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                if (val.* == .call) {
                    const call = val.call;
                    if (call.func.* == .name) {
                        const func_name = call.func.name.id;
                        // Check if this is a locally-defined class in this body
                        for (local_class_names[0..local_class_count]) |local_name| {
                            if (std.mem.eql(u8, func_name, local_name)) {
                                return func_name;
                            }
                        }
                        // Check if this is a nested class constructor
                        if (self.nested_class_names.contains(func_name)) {
                            return func_name;
                        }
                        // Also check if this is the current class being generated
                        if (self.current_class_name) |ccn| {
                            if (std.mem.eql(u8, func_name, ccn)) {
                                return func_name;
                            }
                        }
                        // Also check class_registry for top-level user-defined classes
                        if (self.class_registry.getClass(func_name) != null) {
                            return func_name;
                        }
                    }
                }
            }
        } else if (stmt == .if_stmt) {
            // Recursively search inside if/elif/else blocks
            if (getReturnedNestedClassConstructor(stmt.if_stmt.body, self)) |found| {
                return found;
            }
            // Search else_body (else/elif chain)
            if (getReturnedNestedClassConstructor(stmt.if_stmt.else_body, self)) |found| {
                return found;
            }
        }
    }
    return null;
}

/// Collect class definition names from a body (including nested control flow)
fn collectLocalClassDefinitions(body: []const ast.Node, names: *[32][]const u8, count: *usize) void {
    for (body) |stmt| {
        switch (stmt) {
            .class_def => |cd| {
                if (count.* < 32) {
                    names[count.*] = cd.name;
                    count.* += 1;
                }
            },
            .if_stmt => |if_stmt| {
                collectLocalClassDefinitions(if_stmt.body, names, count);
                collectLocalClassDefinitions(if_stmt.else_body, names, count);
            },
            .for_stmt => |for_stmt| {
                collectLocalClassDefinitions(for_stmt.body, names, count);
                if (for_stmt.orelse_body) |orelse_body| {
                    collectLocalClassDefinitions(orelse_body, names, count);
                }
            },
            .while_stmt => |while_stmt| {
                collectLocalClassDefinitions(while_stmt.body, names, count);
                if (while_stmt.orelse_body) |orelse_body| {
                    collectLocalClassDefinitions(orelse_body, names, count);
                }
            },
            .try_stmt => |try_stmt| {
                collectLocalClassDefinitions(try_stmt.body, names, count);
                for (try_stmt.handlers) |handler| {
                    collectLocalClassDefinitions(handler.body, names, count);
                }
                collectLocalClassDefinitions(try_stmt.else_body, names, count);
                collectLocalClassDefinitions(try_stmt.finalbody, names, count);
            },
            .with_stmt => |with_stmt| {
                collectLocalClassDefinitions(with_stmt.body, names, count);
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    collectLocalClassDefinitions(case.body, names, count);
                }
            },
            else => {},
        }
    }
}
