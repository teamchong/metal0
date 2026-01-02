/// Try/except/finally statement code generation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const NativeType = @import("../../../analysis/native_types.zig").NativeType;
const variable_usage = @import("../analysis/variable_usage.zig");
const expressions = @import("../expressions.zig");
const shared = @import("../shared_maps.zig");
const zig_keywords = @import("utils.zig_keywords");
const signature_utils = @import("functions/generators/signature.zig");
const string_traits = @import("../../../analysis/traits/string_traits.zig");
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const module_functions = @import("../dispatch/module_functions.zig");

const FnvVoidMap = hashmap_helper.StringHashMap(void);

// Re-use shared implementations
const isSuperMethodCallExpr = variable_usage.isSuperMethodCall;
const isCapturedByCurrentClass = expressions.isCapturedByCurrentClass;

/// Check if a call expression is a super() method call (wrapper for ast.Node.Call)
fn isSuperMethodCall(call: ast.Node.Call) bool {
    return isSuperMethodCallExpr(ast.Node{ .call = call });
}

/// Detect try/except import pattern: try: import X except: X = None
/// Returns the module name if pattern matches and module is unavailable
pub fn detectOptionalImportPattern(try_node: ast.Node.Try, codegen: *NativeCodegen) ?[]const u8 {
    // Check if try body has exactly one import statement
    if (try_node.body.len != 1) return null;
    const try_stmt = try_node.body[0];
    if (try_stmt != .import_stmt) return null;
    const module_name = try_stmt.import_stmt.module;

    // Check if there's an except handler that assigns the same name to None
    for (try_node.handlers) |handler| {
        // Must be ImportError or bare except
        if (handler.type) |exc_type| {
            if (!std.mem.eql(u8, exc_type, "ImportError")) continue;
        }
        // Check handler body for: X = None
        for (handler.body) |stmt| {
            if (stmt == .assign) {
                if (stmt.assign.targets.len > 0 and stmt.assign.targets[0] == .name) {
                    const var_name = stmt.assign.targets[0].name.id;
                    // Check if assigning to the module name and value is None
                    if (std.mem.eql(u8, var_name, module_name)) {
                        const is_none = if (stmt.assign.value.* == .constant)
                            stmt.assign.value.constant.value == .none
                        else
                            false;
                        if (is_none) {
                            // Pattern matches! Check if module has VALID implementation
                            const stdlib_gen = @import("../stdlib_modules_gen.zig");
                            const in_stdlib = stdlib_gen.hasModule(module_name);

                            // Check if module is in registry AND has valid implementation
                            const has_valid_impl = blk: {
                                if (codegen.import_registry.lookup(module_name)) |info| {
                                    // Check if strategy is supported and has implementation paths
                                    switch (info.strategy) {
                                        .unsupported => break :blk false, // Explicitly marked as unsupported
                                        .zig_runtime, .c_library => {
                                            // Must have either direct_import or zig_import path OR codegen dispatch
                                            const has_path = info.direct_import != null or info.zig_import != null;
                                            const has_codegen_dispatch = module_functions.hasCodegenDispatch(module_name);
                                            if (!has_path and !has_codegen_dispatch) {
                                                // FAIL FAST: Module in registry but no implementation!
                                                std.debug.print("\n[FATAL] Module '{s}' in import_registry with strategy={s} but NO implementation paths!\n", .{ module_name, @tagName(info.strategy) });
                                                std.debug.print("  direct_import = {any}\n", .{info.direct_import});
                                                std.debug.print("  zig_import = {any}\n", .{info.zig_import});
                                                std.debug.print("  has_codegen_dispatch = {}\n", .{has_codegen_dispatch});
                                                std.debug.print("  This indicates registry corruption or missing module implementation.\n", .{});
                                                std.debug.print("  Either implement the module or mark it as .unsupported in registry.\n\n", .{});
                                                @panic("Import registry has module without valid implementation!");
                                            }
                                            break :blk has_path or has_codegen_dispatch;
                                        },
                                        .compile_python => break :blk true, // Will be compiled
                                    }
                                } else {
                                    break :blk false; // Not in registry
                                }
                            };

                            if (!in_stdlib and !has_valid_impl) {
                                // Module is genuinely unavailable - mark as optional
                                return module_name;
                            }
                        }
                    }
                }
            }
        }
    }
    return null;
}

/// Detect try/except from-import pattern: try: from X import a, b, ... except ImportError: fallback
/// This handles the pattern where multiple names are imported and the except block provides fallbacks.
/// Returns the module name if pattern matches and module is unavailable
fn detectOptionalFromImportPattern(try_node: ast.Node.Try, codegen: *NativeCodegen) ?[]const u8 {
    // Check if try body has exactly one from-import statement
    if (try_node.body.len != 1) return null;
    const try_stmt = try_node.body[0];
    if (try_stmt != .import_from) return null;
    const module_name = try_stmt.import_from.module;
    // Empty module name means relative import like "from . import X" - skip
    if (module_name.len == 0) return null;

    // Check if there's an ImportError handler
    for (try_node.handlers) |handler| {
        if (handler.type) |exc_type| {
            if (!std.mem.eql(u8, exc_type, "ImportError")) continue;
        }
        // Found an ImportError handler - check if module is available
        const stdlib_gen = @import("../stdlib_modules_gen.zig");
        const in_stdlib = stdlib_gen.hasModule(module_name);
        const in_registry = codegen.import_registry.lookup(module_name) != null;
        if (!in_stdlib and !in_registry) {
            // Module is not in stdlib or registry - it's unavailable
            return module_name;
        }
    }
    return null;
}

// Use shared Python builtin names for DCE optimization
const BuiltinFuncs = shared.PythonBuiltinNames;

/// Python exception types mapped to Zig error names
/// Complete list of Python built-in exceptions
const ExceptionMap = std.StaticStringMap([]const u8).initComptime(.{
    // Base exceptions
    .{ "BaseException", "BaseException" },
    .{ "Exception", "Exception" },
    .{ "GeneratorExit", "GeneratorExit" },
    .{ "KeyboardInterrupt", "KeyboardInterrupt" },
    .{ "SystemExit", "SystemExit" },

    // Arithmetic errors
    .{ "ArithmeticError", "ArithmeticError" },
    .{ "FloatingPointError", "FloatingPointError" },
    .{ "OverflowError", "OverflowError" },
    .{ "ZeroDivisionError", "ZeroDivisionError" },

    // Lookup errors
    .{ "LookupError", "LookupError" },
    .{ "IndexError", "IndexError" },
    .{ "KeyError", "KeyError" },

    // Value/Type errors
    .{ "ValueError", "ValueError" },
    .{ "TypeError", "TypeError" },
    .{ "UnicodeError", "UnicodeError" },
    .{ "UnicodeDecodeError", "UnicodeDecodeError" },
    .{ "UnicodeEncodeError", "UnicodeEncodeError" },
    .{ "UnicodeTranslateError", "UnicodeTranslateError" },

    // Attribute/Name errors
    .{ "AttributeError", "AttributeError" },
    .{ "NameError", "NameError" },
    .{ "UnboundLocalError", "UnboundLocalError" },

    // Import errors
    .{ "ImportError", "ImportError" },
    .{ "ModuleNotFoundError", "ModuleNotFoundError" },

    // OS/IO errors
    .{ "OSError", "OSError" },
    .{ "IOError", "IOError" },
    .{ "FileNotFoundError", "FileNotFoundError" },
    .{ "FileExistsError", "FileExistsError" },
    .{ "IsADirectoryError", "IsADirectoryError" },
    .{ "NotADirectoryError", "NotADirectoryError" },
    .{ "PermissionError", "PermissionError" },
    .{ "TimeoutError", "TimeoutError" },
    .{ "ConnectionError", "ConnectionError" },
    .{ "BrokenPipeError", "BrokenPipeError" },
    .{ "ConnectionAbortedError", "ConnectionAbortedError" },
    .{ "ConnectionRefusedError", "ConnectionRefusedError" },
    .{ "ConnectionResetError", "ConnectionResetError" },
    .{ "BlockingIOError", "BlockingIOError" },
    .{ "ChildProcessError", "ChildProcessError" },
    .{ "InterruptedError", "InterruptedError" },
    .{ "ProcessLookupError", "ProcessLookupError" },

    // Runtime errors
    .{ "RuntimeError", "RuntimeError" },
    .{ "NotImplementedError", "NotImplementedError" },
    .{ "RecursionError", "RecursionError" },

    // Syntax errors
    .{ "SyntaxError", "SyntaxError" },
    .{ "IndentationError", "IndentationError" },
    .{ "TabError", "TabError" },

    // System errors
    .{ "SystemError", "SystemError" },
    .{ "MemoryError", "MemoryError" },
    .{ "BufferError", "BufferError" },

    // EOF/Stop iteration
    .{ "EOFError", "EOFError" },
    .{ "StopIteration", "StopIteration" },
    .{ "StopAsyncIteration", "StopAsyncIteration" },

    // Assertion/Reference
    .{ "AssertionError", "AssertionError" },
    .{ "ReferenceError", "ReferenceError" },

    // Warnings (can be raised as exceptions)
    .{ "Warning", "Warning" },
    .{ "UserWarning", "UserWarning" },
    .{ "DeprecationWarning", "DeprecationWarning" },
    .{ "PendingDeprecationWarning", "PendingDeprecationWarning" },
    .{ "SyntaxWarning", "SyntaxWarning" },
    .{ "RuntimeWarning", "RuntimeWarning" },
    .{ "FutureWarning", "FutureWarning" },
    .{ "ImportWarning", "ImportWarning" },
    .{ "UnicodeWarning", "UnicodeWarning" },
    .{ "BytesWarning", "BytesWarning" },
    .{ "ResourceWarning", "ResourceWarning" },
    .{ "EncodingWarning", "EncodingWarning" },
});

/// Check if any handler in the try block catches NameError (or a base class like Exception)
/// Returns true for:
///   - except NameError:
///   - except NameError as e:
///   - except:  (bare except catches everything)
///   - except BaseException:  (catches everything)
///   - except Exception:  (catches NameError since it's a subclass)
/// Note: handler.type is ?[]const u8 (just the exception type name as string)
fn catchesNameError(handlers: []const ast.Node.ExceptHandler) bool {
    for (handlers) |handler| {
        // Bare except catches everything
        if (handler.type == null) return true;

        const type_name = handler.type.?;
        // NameError, BaseException, Exception all catch NameError
        if (std.mem.eql(u8, type_name, "NameError") or
            std.mem.eql(u8, type_name, "BaseException") or
            std.mem.eql(u8, type_name, "Exception"))
        {
            return true;
        }
    }
    return false;
}

/// Check if a variable name is used in any statement within a list of statements
fn isNameUsedInStmts(stmts: []ast.Node, name: []const u8, allocator: std.mem.Allocator) bool {
    var vars = FnvVoidMap.init(allocator);
    defer vars.deinit();
    findReferencedVarsInStmts(stmts, &vars, allocator) catch return false;
    return vars.contains(name);
}

// Re-use shared implementation for finding referenced vars in expressions
const findReferencedVarsInExpr = variable_usage.collectReferencedVarsInExpr;

/// Find all variable names that are assigned (written) in statements
/// Methods that mutate collections (dict.put, list.append, etc.)
const MutatingMethods = std.StaticStringMap(void).initComptime(.{
    .{ "put", {} },
    .{ "append", {} },
    .{ "extend", {} },
    .{ "insert", {} },
    .{ "pop", {} },
    .{ "remove", {} },
    .{ "clear", {} },
    .{ "update", {} },
    .{ "setdefault", {} },
    .{ "add", {} },
    .{ "discard", {} },
    .{ "reverse", {} },
    .{ "sort", {} },
});

fn findWrittenVarsInStmts(stmts: []ast.Node, vars: *FnvVoidMap) !void {
    for (stmts) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                for (assign.targets) |target| {
                    if (target == .name) {
                        try vars.put(target.name.id, {});
                    } else if (target == .subscript) {
                        // x[key] = value mutates x
                        if (target.subscript.value.* == .name) {
                            try vars.put(target.subscript.value.name.id, {});
                        }
                    } else if (target == .tuple) {
                        // Tuple unpacking: (a, b, c) = expr or a, b, c = expr
                        for (target.tuple.elts) |elt| {
                            if (elt == .name) {
                                // Skip Python's discard pattern
                                if (std.mem.eql(u8, elt.name.id, "_")) continue;
                                try vars.put(elt.name.id, {});
                            }
                        }
                    } else if (target == .list) {
                        // List unpacking: [a, b, c] = expr
                        for (target.list.elts) |elt| {
                            if (elt == .name) {
                                // Skip Python's discard pattern
                                if (std.mem.eql(u8, elt.name.id, "_")) continue;
                                try vars.put(elt.name.id, {});
                            }
                        }
                    }
                }
            },
            .aug_assign => |aug| {
                if (aug.target.* == .name) {
                    try vars.put(aug.target.name.id, {});
                } else if (aug.target.* == .subscript) {
                    // x[key] += value mutates x
                    if (aug.target.subscript.value.* == .name) {
                        try vars.put(aug.target.subscript.value.name.id, {});
                    }
                }
            },
            .expr_stmt => |expr| {
                // Check for mutating method calls: x.put(...), x.append(...), etc.
                try findMutatingMethodCalls(expr.value.*, vars);
            },
            .if_stmt => |if_stmt| {
                try findWrittenVarsInStmts(if_stmt.body, vars);
                try findWrittenVarsInStmts(if_stmt.else_body, vars);
            },
            .while_stmt => |while_stmt| {
                try findWrittenVarsInStmts(while_stmt.body, vars);
                if (while_stmt.orelse_body) |orelse_body| {
                    try findWrittenVarsInStmts(orelse_body, vars);
                }
            },
            .for_stmt => |for_stmt| {
                try findWrittenVarsInStmts(for_stmt.body, vars);
                if (for_stmt.orelse_body) |orelse_body| {
                    try findWrittenVarsInStmts(orelse_body, vars);
                }
            },
            .try_stmt => |try_stmt| {
                try findWrittenVarsInStmts(try_stmt.body, vars);
                // Also check else block and except handlers
                try findWrittenVarsInStmts(try_stmt.else_body, vars);
                for (try_stmt.handlers) |handler| {
                    // NOTE: Don't add exception names from NESTED try handlers here.
                    // Exception names (the "as e" in "except E as e:") are local to
                    // their own try block and should be handled by that block's TryHelper,
                    // not captured as outer variables by enclosing try blocks.
                    // See findLocallyDeclaredVars which marks them as local.
                    try findWrittenVarsInStmts(handler.body, vars);
                }
                try findWrittenVarsInStmts(try_stmt.finalbody, vars);
            },
            .with_stmt => |with_stmt| {
                try findWrittenVarsInStmts(with_stmt.body, vars);
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    try findWrittenVarsInStmts(case.body, vars);
                }
            },
            else => {},
        }
    }
}

/// Find variables that are assigned from exception variables (e.g., `e = exc` where `exc` is from `except X as exc:`)
/// This is needed for proper type propagation - these variables should also be typed as PyException
fn findExceptionAssignedVars(stmts: []ast.Node, exception_vars: *FnvVoidMap, result: *FnvVoidMap) !void {
    for (stmts) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                // Check if RHS is a name that's an exception variable
                if (assign.value.* == .name) {
                    const rhs_name = assign.value.name.id;
                    if (exception_vars.contains(rhs_name)) {
                        // Mark all LHS targets as exception-assigned
                        for (assign.targets) |target| {
                            if (target == .name) {
                                try result.put(target.name.id, {});
                            }
                        }
                    }
                }
            },
            .if_stmt => |if_stmt| {
                try findExceptionAssignedVars(if_stmt.body, exception_vars, result);
                try findExceptionAssignedVars(if_stmt.else_body, exception_vars, result);
            },
            .while_stmt => |while_stmt| {
                try findExceptionAssignedVars(while_stmt.body, exception_vars, result);
                if (while_stmt.orelse_body) |orelse_body| {
                    try findExceptionAssignedVars(orelse_body, exception_vars, result);
                }
            },
            .for_stmt => |for_stmt| {
                try findExceptionAssignedVars(for_stmt.body, exception_vars, result);
                if (for_stmt.orelse_body) |orelse_body| {
                    try findExceptionAssignedVars(orelse_body, exception_vars, result);
                }
            },
            .try_stmt => |try_stmt| {
                try findExceptionAssignedVars(try_stmt.body, exception_vars, result);
                try findExceptionAssignedVars(try_stmt.else_body, exception_vars, result);
                for (try_stmt.handlers) |handler| {
                    try findExceptionAssignedVars(handler.body, exception_vars, result);
                }
                try findExceptionAssignedVars(try_stmt.finalbody, exception_vars, result);
            },
            .with_stmt => |with_stmt| {
                try findExceptionAssignedVars(with_stmt.body, exception_vars, result);
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    try findExceptionAssignedVars(case.body, exception_vars, result);
                }
            },
            else => {},
        }
    }
}

fn findMutatingMethodCalls(expr: ast.Node, vars: *FnvVoidMap) !void {
    switch (expr) {
        .call => |call| {
            // Check if this is a method call on a variable: x.method(...)
            if (call.func.* == .attribute) {
                const attr = call.func.attribute;
                if (attr.value.* == .name) {
                    // Check if this is a mutating method
                    if (MutatingMethods.has(attr.attr)) {
                        try vars.put(attr.value.name.id, {});
                    }
                }
            }
        },
        else => {},
    }
}

/// Helper to recursively add all variable names from an unpacking target (name, tuple, list, starred)
fn addTargetVarsToLocals(target: ast.Node, vars: *FnvVoidMap) !void {
    switch (target) {
        .name => |name| {
            try vars.put(name.id, {});
        },
        .tuple => |tuple| {
            // Handle tuple unpacking: for a, b in items
            for (tuple.elts) |elt| {
                try addTargetVarsToLocals(elt, vars);
            }
        },
        .list => |list| {
            // Handle list unpacking: for [a, b] in items
            for (list.elts) |elt| {
                try addTargetVarsToLocals(elt, vars);
            }
        },
        .starred => |starred| {
            // Handle starred: for *rest in items or for a, *rest in items
            try addTargetVarsToLocals(starred.value.*, vars);
        },
        else => {},
    }
}

/// Find all variables locally declared within statements (for-loop targets, imports)
/// These are variables that should NOT be captured from outer scope
/// NOTE: We only track for-loop targets and imports here, NOT assignment targets,
/// because assignments might be reassigning outer variables
fn findLocallyDeclaredVars(stmts: []ast.Node, vars: *FnvVoidMap) !void {
    for (stmts) |stmt| {
        switch (stmt) {
            // NOTE: Don't include .assign targets here - assignments might be
            // reassigning variables from outer scope, not declaring new ones.
            // The declared_var_set handles first-time declarations separately.
            .for_stmt => |for_stmt| {
                // For-loop target variables are locally declared
                try addTargetVarsToLocals(for_stmt.target.*, vars);
                try findLocallyDeclaredVars(for_stmt.body, vars);
                if (for_stmt.orelse_body) |orelse_body| {
                    try findLocallyDeclaredVars(orelse_body, vars);
                }
            },
            .if_stmt => |if_stmt| {
                try findLocallyDeclaredVars(if_stmt.body, vars);
                try findLocallyDeclaredVars(if_stmt.else_body, vars);
            },
            .while_stmt => |while_stmt| {
                try findLocallyDeclaredVars(while_stmt.body, vars);
                if (while_stmt.orelse_body) |orelse_body| {
                    try findLocallyDeclaredVars(orelse_body, vars);
                }
            },
            .try_stmt => |try_stmt| {
                try findLocallyDeclaredVars(try_stmt.body, vars);
                for (try_stmt.handlers) |handler| {
                    // Exception names from nested try handlers are locally declared
                    // within this scope - they should NOT be captured as outer variables
                    // by enclosing try blocks.
                    if (handler.name) |exc_name| {
                        try vars.put(exc_name, {});
                    }
                    try findLocallyDeclaredVars(handler.body, vars);
                }
                try findLocallyDeclaredVars(try_stmt.else_body, vars);
                try findLocallyDeclaredVars(try_stmt.finalbody, vars);
            },
            .with_stmt => |with_stmt| {
                // Add context manager variable as locally declared (e.g., 'f' in 'with open(...) as f:')
                // This variable is created inside the try block by the with statement,
                // not captured from outer scope
                if (with_stmt.optional_vars) |target| {
                    try addTargetVarsToLocals(target.*, vars);
                }
                try findLocallyDeclaredVars(with_stmt.body, vars);
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    try findLocallyDeclaredVars(case.body, vars);
                }
            },
            // Import statements introduce new variables - they're locally declared
            // e.g., `import numpy` creates variable `numpy`
            // e.g., `from os import path` creates variable `path`
            // e.g., `import numpy as np` creates variable `np`
            .import_stmt => |import_stmt| {
                // Use asname if present, otherwise module name
                const var_name = import_stmt.asname orelse import_stmt.module;
                try vars.put(var_name, {});
            },
            .import_from => |import_from| {
                // Each imported name creates a variable
                for (import_from.names, 0..) |name, i| {
                    // Use asname if present, otherwise the imported name
                    const var_name = if (i < import_from.asnames.len and import_from.asnames[i] != null)
                        import_from.asnames[i].?
                    else
                        name;
                    try vars.put(var_name, {});
                }
            },
            else => {},
        }
    }
}

// Re-use shared implementation for finding referenced vars in statements
const findReferencedVarsInStmts = variable_usage.collectReferencedVars;

/// Check if statements contain break or continue (for try block control flow handling)
fn containsBreakOrContinue(stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        switch (stmt) {
            .break_stmt => return true,
            .continue_stmt => return true,
            .if_stmt => |if_stmt| {
                if (containsBreakOrContinue(if_stmt.body)) return true;
                if (containsBreakOrContinue(if_stmt.else_body)) return true;
            },
            // Don't recurse into nested loops/functions - their break/continue is local
            else => {},
        }
    }
    return false;
}

/// Check if statements contain a raise statement (for finally block handling)
/// When finally contains raise, we can't use defer because defer can't return errors
fn containsRaise(stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        switch (stmt) {
            .raise_stmt => return true,
            .if_stmt => |if_stmt| {
                if (containsRaise(if_stmt.body)) return true;
                if (containsRaise(if_stmt.else_body)) return true;
            },
            .for_stmt => |for_stmt| {
                if (containsRaise(for_stmt.body)) return true;
                if (for_stmt.orelse_body) |orelse_body| {
                    if (containsRaise(orelse_body)) return true;
                }
            },
            .while_stmt => |while_stmt| {
                if (containsRaise(while_stmt.body)) return true;
                if (while_stmt.orelse_body) |orelse_body| {
                    if (containsRaise(orelse_body)) return true;
                }
            },
            .with_stmt => |with_stmt| {
                if (containsRaise(with_stmt.body)) return true;
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    if (containsRaise(case.body)) return true;
                }
            },
            // Don't recurse into nested try/functions - their raise is local
            else => {},
        }
    }
    return false;
}

/// Check if statements contain control flow (break, continue, return) that is illegal in defer
/// Zig error: "cannot break/continue/return out of defer expression"
fn containsControlFlow(stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        switch (stmt) {
            .break_stmt, .continue_stmt, .return_stmt => return true,
            .if_stmt => |if_stmt| {
                if (containsControlFlow(if_stmt.body)) return true;
                if (containsControlFlow(if_stmt.else_body)) return true;
            },
            .for_stmt => |for_stmt| {
                // Don't recurse into loop body - break/continue there is for the inner loop
                // But DO check orelse_body since that's not part of the loop
                if (for_stmt.orelse_body) |orelse_body| {
                    if (containsControlFlow(orelse_body)) return true;
                }
            },
            .while_stmt => |while_stmt| {
                // Same - don't recurse into loop body, but check orelse_body
                if (while_stmt.orelse_body) |orelse_body| {
                    if (containsControlFlow(orelse_body)) return true;
                }
            },
            .with_stmt => |with_stmt| {
                if (containsControlFlow(with_stmt.body)) return true;
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    if (containsControlFlow(case.body)) return true;
                }
            },
            // Don't recurse into nested try/functions - their control flow is local
            else => {},
        }
    }
    return false;
}

/// Check if a statement list always terminates (raise or return on all paths).
/// Used to determine if code after try-except is unreachable.
fn stmtListAlwaysTerminates(stmts: []ast.Node) bool {
    if (stmts.len == 0) return false;

    // Check if last statement is a terminator
    const last_stmt = stmts[stmts.len - 1];
    switch (last_stmt) {
        .raise_stmt => return true,
        .return_stmt => return true,
        .if_stmt => |if_stmt| {
            // Both branches must terminate
            if (if_stmt.else_body.len == 0) return false; // No else = may fall through
            return stmtListAlwaysTerminates(if_stmt.body) and
                stmtListAlwaysTerminates(if_stmt.else_body);
        },
        .try_stmt => |try_stmt| {
            // Try body must terminate AND all handlers must terminate
            if (!stmtListAlwaysTerminates(try_stmt.body)) return false;
            for (try_stmt.handlers) |handler| {
                if (!stmtListAlwaysTerminates(handler.body)) return false;
            }
            return true;
        },
        .match_stmt => |match_stmt| {
            // All cases must terminate
            for (match_stmt.cases) |case| {
                if (!stmtListAlwaysTerminates(case.body)) return false;
            }
            return match_stmt.cases.len > 0;
        },
        // Loops don't guarantee termination (may run 0 times)
        else => return false,
    }
}

/// Recursively collect all exception names from nested try-except handlers.
/// This ensures that when hoisting variables like `raised = exc`, we know
/// `exc` is an exception variable even if it's from a nested inner handler.
///
/// Problem: `raised = exc` gets hoisted at OUTER try level, but `exc` comes from
/// an INNER `except Exception as exc:`. Without pre-scanning, `raised` gets
/// hoisted as PyValue instead of PyException, causing `raised.__context__` to fail.
fn collectNestedExceptionNames(self: *NativeCodegen, stmts: []ast.Node) !void {
    for (stmts) |stmt| {
        switch (stmt) {
            .try_stmt => |try_stmt| {
                // Collect exception names from THIS try statement's handlers
                for (try_stmt.handlers) |handler| {
                    if (handler.name) |exc_name| {
                        try self.exception_vars.put(exc_name, {});
                    }
                    // Recursively scan handler body for deeper nesting
                    try collectNestedExceptionNames(self, handler.body);
                }
                // Also scan try body, else body, and finally body
                try collectNestedExceptionNames(self, try_stmt.body);
                try collectNestedExceptionNames(self, try_stmt.else_body);
                try collectNestedExceptionNames(self, try_stmt.finalbody);
            },
            .if_stmt => |if_stmt| {
                try collectNestedExceptionNames(self, if_stmt.body);
                try collectNestedExceptionNames(self, if_stmt.else_body);
            },
            .for_stmt => |for_stmt| {
                try collectNestedExceptionNames(self, for_stmt.body);
                if (for_stmt.orelse_body) |orelse_body| {
                    try collectNestedExceptionNames(self, orelse_body);
                }
            },
            .while_stmt => |while_stmt| {
                try collectNestedExceptionNames(self, while_stmt.body);
                if (while_stmt.orelse_body) |orelse_body| {
                    try collectNestedExceptionNames(self, orelse_body);
                }
            },
            .with_stmt => |with_stmt| {
                try collectNestedExceptionNames(self, with_stmt.body);
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    try collectNestedExceptionNames(self, case.body);
                }
            },
            // Don't recurse into function_def - those have their own scope
            else => {},
        }
    }
}

pub fn genTry(self: *NativeCodegen, try_node: ast.Node.Try) CodegenError!void {
    // Detect optional import pattern: try: import X except: X = None
    // If module X is unavailable, mark it as skipped so functions using it are skipped
    if (detectOptionalImportPattern(try_node, self)) |unavailable_module| {
        try self.markSkippedModule(unavailable_module);
        // Generate: const X: ?*void = null; _ = X; (module is not available)
        // This allows code like `if X is None:` and `@unittest.skipIf(X is None, ...)`
        // The _ = X; suppresses "unused constant" warning
        try self.emitIndent();
        try self.emit("const ");
        try self.emit(unavailable_module);
        try self.emit(": ?*void = null; _ = ");
        try self.emit(unavailable_module);
        try self.emit("; // Optional import: module not available\n");
        return; // Skip generating the full try/except structure
    }

    // Detect try/except from-import pattern: try: from X import ... except ImportError: fallback
    // When module is unavailable, generate the except block contents at module level
    // This handles function definitions that can't be inside struct initializers
    if (detectOptionalFromImportPattern(try_node, self)) |unavailable_module| {
        try self.markSkippedModule(unavailable_module);
        // Generate comment to mark the pattern
        try self.emitIndent();
        try self.emit("// Optional from-import: module '");
        try self.emit(unavailable_module);
        try self.emit("' not available, using fallback definitions\n");

        // Find the ImportError handler and generate its body at module level
        for (try_node.handlers) |handler| {
            if (handler.type) |exc_type| {
                if (!std.mem.eql(u8, exc_type, "ImportError")) continue;
            }
            // Generate each statement in the handler body at module level
            for (handler.body) |stmt| {
                try self.generateStmt(stmt);
            }
            break; // Only generate the first matching handler
        }
        return; // Skip generating the full try/except structure
    }

    // NOTE: Function definitions from except handlers are hoisted during Phase 5.1 in generator.zig
    // This ensures they're at module level before main() is generated, not inside catch blocks.
    // The handler body generation below will skip function_def statements that were hoisted.

    // First pass: collect variables declared in try block AND except handlers that need hoisting
    // Only hoist variables that aren't already declared in the current scope
    // Store both name and the assignment expression value for type inference
    const HoistedVar = struct {
        name: []const u8,
        value: ast.Node, // The RHS expression for type inference
        is_exception_name: bool = false, // true if this is an "except X as name" variable
    };
    var declared_vars = std.ArrayListUnmanaged(HoistedVar){};
    defer declared_vars.deinit(self.allocator);

    // Helper to add variable if not already declared
    const addVarIfNeeded = struct {
        fn add(list: *std.ArrayListUnmanaged(HoistedVar), codegen: *NativeCodegen, var_name: []const u8, value: ast.Node) !void {
            // Only hoist if not already declared in scope or previously hoisted
            if (!codegen.isDeclared(var_name) and !codegen.hoisted_vars.contains(var_name)) {
                // Check if already in list
                for (list.items) |existing| {
                    if (std.mem.eql(u8, existing.name, var_name)) return;
                }
                // Skip if variable name matches a nested function definition in the current function
                // e.g., `def recurser(): ...; finally: recurser = None` - don't hoist 'recurser'
                // because it's already defined as a struct
                if (codegen.current_function_body) |func_body| {
                    for (func_body) |stmt| {
                        if (stmt == .function_def) {
                            if (std.mem.eql(u8, stmt.function_def.name, var_name)) {
                                return; // Skip - this is a nested function, not a regular variable
                            }
                        }
                    }
                }
                try list.append(codegen.allocator, .{ .name = var_name, .value = value });
            }
        }
    }.add;

    // Recursively collect assigned variables from try body (including nested if/for/while)
    const collectAssignedVarsRecursive = struct {
        fn collect(stmts: []ast.Node, list: *std.ArrayListUnmanaged(HoistedVar), codegen: *NativeCodegen, addFn: anytype) !void {
            for (stmts) |stmt| {
                switch (stmt) {
                    .assign => |assign| {
                        for (assign.targets) |target| {
                            if (target == .name) {
                                try addFn(list, codegen, target.name.id, assign.value.*);
                            } else if (target == .tuple) {
                                // Tuple unpacking: (a, b, c) = expr - each element needs hoisting
                                // Use None as value since we can't determine individual element types
                                for (target.tuple.elts) |elt| {
                                    if (elt == .name) {
                                        // Skip Python's discard pattern - no need to hoist _
                                        if (std.mem.eql(u8, elt.name.id, "_")) continue;
                                        try addFn(list, codegen, elt.name.id, .{ .constant = .{ .value = .{ .none = {} } } });
                                    }
                                }
                            } else if (target == .list) {
                                // List unpacking: [a, b, c] = expr - each element needs hoisting
                                for (target.list.elts) |elt| {
                                    if (elt == .name) {
                                        // Skip Python's discard pattern - no need to hoist _
                                        if (std.mem.eql(u8, elt.name.id, "_")) continue;
                                        try addFn(list, codegen, elt.name.id, .{ .constant = .{ .value = .{ .none = {} } } });
                                    }
                                }
                            }
                        }
                    },
                    .if_stmt => |if_stmt| {
                        try collect(if_stmt.body, list, codegen, addFn);
                        try collect(if_stmt.else_body, list, codegen, addFn);
                    },
                    .for_stmt => |for_stmt| {
                        try collect(for_stmt.body, list, codegen, addFn);
                        if (for_stmt.orelse_body) |orelse_body| {
                            try collect(orelse_body, list, codegen, addFn);
                        }
                    },
                    .while_stmt => |while_stmt| {
                        try collect(while_stmt.body, list, codegen, addFn);
                        if (while_stmt.orelse_body) |orelse_body| {
                            try collect(orelse_body, list, codegen, addFn);
                        }
                    },
                    .try_stmt => |try_stmt| {
                        try collect(try_stmt.body, list, codegen, addFn);
                        for (try_stmt.handlers) |handler| {
                            try collect(handler.body, list, codegen, addFn);
                        }
                        try collect(try_stmt.else_body, list, codegen, addFn);
                        try collect(try_stmt.finalbody, list, codegen, addFn);
                    },
                    .with_stmt => |with_stmt| {
                        try collect(with_stmt.body, list, codegen, addFn);
                    },
                    .match_stmt => |match_stmt| {
                        for (match_stmt.cases) |case| {
                            try collect(case.body, list, codegen, addFn);
                        }
                    },
                    else => {},
                }
            }
        }
    }.collect;

    // CRITICAL: Pre-scan ALL nested try-except handlers to collect exception names FIRST.
    // This must happen BEFORE hoisting type inference because:
    //   - Outer try hoists `raised = exc` where `exc` is from an INNER handler
    //   - Without pre-scan, `exc` isn't in exception_vars yet when hoisting decides types
    //   - Result: `raised` becomes PyValue instead of PyException
    //   - Causes: `raised.__context__` fails (PyValue has no __context__)
    for (try_node.handlers) |handler| {
        try collectNestedExceptionNames(self, handler.body);
    }
    try collectNestedExceptionNames(self, try_node.body);
    try collectNestedExceptionNames(self, try_node.else_body);
    try collectNestedExceptionNames(self, try_node.finalbody);

    // Collect from try body recursively
    try collectAssignedVarsRecursive(try_node.body, &declared_vars, self, addVarIfNeeded);

    // CRITICAL: Also collect from except handlers!
    // Pattern: try: import X except: X = None
    // The X = None is in the except handler, needs hoisting too
    for (try_node.handlers) |handler| {
        try collectAssignedVarsRecursive(handler.body, &declared_vars, self, addVarIfNeeded);
    }

    // Also collect from else_body - variables assigned there need hoisting too
    // Pattern: try/except/else where else clause assigns module-level vars
    // Example: try: import ctypes except: ctypes=None else: c_forward_pointer = ...
    try collectAssignedVarsRecursive(try_node.else_body, &declared_vars, self, addVarIfNeeded);

    // Also collect from finalbody for completeness
    try collectAssignedVarsRecursive(try_node.finalbody, &declared_vars, self, addVarIfNeeded);

    // Also hoist exception variable names (the "as name" in "except Exception as name")
    // Python allows these variables to be accessed after the try/except block
    for (try_node.handlers) |handler| {
        if (handler.name) |exc_name| {
            // Only hoist if not already declared in scope or previously hoisted
            if (!self.isDeclared(exc_name) and !self.hoisted_vars.contains(exc_name)) {
                // Check if already in declared_vars
                const already_declared = blk: {
                    for (declared_vars.items) |dv| {
                        if (std.mem.eql(u8, dv.name, exc_name)) break :blk true;
                    }
                    break :blk false;
                };
                if (!already_declared) {
                    // Create a dummy node for the exception name - it's a string type
                    try declared_vars.append(self.allocator, .{
                        .name = exc_name,
                        .value = .{ .constant = .{ .value = .{ .string = "" } } }, // dummy string value
                        .is_exception_name = true, // marker that this is an exception name
                    });
                }
            }
            // Pre-populate exception_vars so type inference during hoisting can detect
            // assignments from exception variables (e.g., `exc1 = e` where `e` is exception var)
            try self.exception_vars.put(exc_name, {});
        }
    }

    // Find variables assigned from exception variables (e.g., `e = exc` where `exc` is exception var)
    // These need to be typed as PyException even though they're not directly exception names
    var exception_assigned_vars = FnvVoidMap.init(self.allocator);
    defer exception_assigned_vars.deinit();
    for (try_node.handlers) |handler| {
        try findExceptionAssignedVars(handler.body, &self.exception_vars, &exception_assigned_vars);
    }
    try findExceptionAssignedVars(try_node.else_body, &self.exception_vars, &exception_assigned_vars);

    // Hoist variable declarations BEFORE the block (so they're accessible after try)
    for (declared_vars.items) |hoisted| {
        const var_name = hoisted.name;

        // Exception names (from "except X as name") use PyException for full Python semantics
        // (including __traceback__, __context__, __cause__ attributes)
        // For regular variables, infer type from the RHS expression
        var zig_type: []const u8 = undefined;
        var needs_free = false;
        var var_type: ?NativeType = null;
        if (hoisted.is_exception_name) {
            zig_type = "runtime.PyException";
        } else if (hoisted.value == .name and self.exception_vars.contains(hoisted.value.name.id)) {
            // Assigning from an exception variable - propagate PyException type
            // e.g., `exc1 = e` where `e` is from `except X as e:`
            zig_type = "runtime.PyException";
        } else if (exception_assigned_vars.contains(var_name)) {
            // This variable is assigned from an exception variable somewhere in the handlers
            // e.g., `e = exc` where `exc` is from `except ValueError as exc:`
            zig_type = "runtime.PyException";
        } else {
            var_type = self.type_inferrer.inferExpr(hoisted.value) catch null;
            if (var_type) |vt| {
                // If the inferred type is 'none' (from assigning None), use PyValue
                // because None assignments typically mean the variable can hold other types too
                // e.g., cdll = None followed by cdll = load_library(...)
                if (vt == .none) {
                    zig_type = "runtime.PyValue";
                    // Mark this variable so assignments wrap values in PyValue.from()
                    try self.pyvalue_hoisted_vars.put(var_name, {});
                } else {
                    zig_type = try self.nativeTypeToZigType(vt);
                    needs_free = true;
                }
            } else {
                zig_type = "i64";
            }
        }
        defer if (needs_free) self.allocator.free(zig_type);

        // If it's a class instance type, check if the class was renamed (e.g., duplicate S classes)
        if (var_type) |vt| {
            if (type_traits.isClassInstance(vt)) {
                const class_name = vt.class_instance;
                if (self.var_renames.get(class_name)) |renamed| {
                    self.allocator.free(zig_type);
                    zig_type = try self.arena.allocator().dupe(u8, renamed);
                }
            }
        }

        // Check if var_name would shadow a module-level import, function, or variable
        // If so, use NameGen for consistent unique naming
        var actual_var_name = var_name;
        const shadows_module_level = self.imported_modules.contains(var_name) or
            self.module_level_funcs.contains(var_name) or
            self.module_level_vars.contains(var_name) or
            self.module_level_from_imports.contains(var_name);
        if (shadows_module_level and !self.var_renames.contains(var_name)) {
            const prefixed_name = try self.name_gen.local(var_name);
            try self.var_renames.put(var_name, prefixed_name);
            actual_var_name = prefixed_name;
        } else if (self.var_renames.get(var_name)) |renamed| {
            actual_var_name = renamed;
        }

        // If rename ends with ".*", this variable is already a pointer parameter in an enclosing
        // TryHelper. Skip local declaration - it will be accessed through the pointer.
        if (std.mem.endsWith(u8, actual_var_name, ".*")) {
            continue;
        }

        // Strip ".*" suffix if present - the rename is for pointer access, not declaration.
        // e.g., "p_sys_exception.*" should become "p_sys_exception" for declaration.
        const decl_var_name = if (std.mem.endsWith(u8, actual_var_name, ".*"))
            actual_var_name[0 .. actual_var_name.len - 2]
        else
            actual_var_name;

        try self.emitIndent();
        try self.emit("var ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), decl_var_name);
        try self.emit(": ");
        try self.emit(zig_type);
        try self.emit(" = undefined;\n");

        // Suppress "local variable is never mutated" warning for hoisted vars.
        // The variable may be assigned in a branch that doesn't execute at runtime
        // (e.g., else: hit_else = True when exception IS raised, else never runs).
        try self.emitIndent();
        try self.emit("_ = &");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), decl_var_name);
        try self.emit(";\n");

        // Mark as hoisted so assignment generation skips declaration
        try self.hoisted_vars.put(var_name, {});

        // Mark exception variables for type-aware assignment generation
        // This includes both direct exception vars (from "except X as name:") and
        // propagated exception vars (from "exc1 = e" where e is exception var)
        if (hoisted.is_exception_name) {
            try self.exception_vars.put(var_name, {});
        } else if (hoisted.value == .name and self.exception_vars.contains(hoisted.value.name.id)) {
            // Variable assigned from exception var - also track it as exception type
            try self.exception_vars.put(var_name, {});
        }
    }

    // Get unique ID for this try block (used for variable names)
    const helper_id = self.try_helper_counter;
    self.try_helper_counter += 1;

    // Wrap in block for scope
    try self.emitIndent();
    try self.emit("{\n");
    self.indent();

    // If we have a finally block, declare pending exception variable
    // This tracks exceptions that need to be re-thrown after finally runs
    const has_finally = try_node.finalbody.len > 0;
    if (has_finally) {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var __pending_exception_{d}: ?anyerror = null;\n", .{helper_id});
        // Suppress "never mutated" warning - may not be mutated if all exceptions are caught
        try self.emitIndent();
        try self.output.writer(self.allocator).print("_ = &__pending_exception_{d};\n", .{helper_id});
    }

    // Generate try block with exception handling
    if (try_node.handlers.len > 0) {
        // Collect read-only captured variables (not written in try block)
        var read_only_vars = std.ArrayListUnmanaged([]const u8){};
        defer read_only_vars.deinit(self.allocator);

        // Collect written variables from outer scope (need pointers)
        var written_outer_vars = std.ArrayListUnmanaged([]const u8){};
        defer written_outer_vars.deinit(self.allocator);

        var declared_var_set = FnvVoidMap.init(self.allocator);
        defer declared_var_set.deinit();
        for (declared_vars.items) |hoisted| {
            try declared_var_set.put(hoisted.name, {});
        }

        // Find variables that are WRITTEN in try block body AND handlers
        // (handlers run inside the TryHelper struct too, so their writes need params)
        var written_vars = FnvVoidMap.init(self.allocator);
        defer written_vars.deinit();
        try findWrittenVarsInStmts(try_node.body, &written_vars);
        // Also check handlers - e.g., "except E as e: x = foo()" writes to x
        // NOTE: Don't add the current try block's exception names here - they're already hoisted
        // via declared_vars (lines 448-471). Only check the handler BODIES for additional writes.
        for (try_node.handlers) |handler| {
            try findWrittenVarsInStmts(handler.body, &written_vars);
        }
        // Also check else_body and finalbody
        try findWrittenVarsInStmts(try_node.else_body, &written_vars);
        try findWrittenVarsInStmts(try_node.finalbody, &written_vars);

        // Find variables actually referenced in try block body (and nested try handlers)
        // NOTE: Do NOT include try_node.handlers here! The handler body is generated in the
        // outer catch block, NOT inside the TryHelper.run() function. Only the try body
        // (which may contain nested try blocks with their own handlers) runs inside run().
        // Similarly for else_body and finalbody - they run outside the TryHelper struct.
        var referenced_vars = FnvVoidMap.init(self.allocator);
        defer referenced_vars.deinit();
        try findReferencedVarsInStmts(try_node.body, &referenced_vars, self.allocator);

        // Find locally declared variables (including for-loop targets) - these should NOT be captured
        var locally_declared = FnvVoidMap.init(self.allocator);
        defer locally_declared.deinit();
        try findLocallyDeclaredVars(try_node.body, &locally_declared);
        // Also check handlers, else_body, and finalbody for local declarations
        for (try_node.handlers) |handler| {
            try findLocallyDeclaredVars(handler.body, &locally_declared);
        }
        try findLocallyDeclaredVars(try_node.else_body, &locally_declared);
        try findLocallyDeclaredVars(try_node.finalbody, &locally_declared);

        // Categorize variables:
        // 1. declared_vars: first declared in try block (hoisted, passed as pointer)
        // 2. written_outer_vars: from outer scope, written in try block (passed as pointer)
        // 3. read_only_vars: from outer scope, only read in try block (passed by value)
        var ref_iter = referenced_vars.iterator();
        while (ref_iter.next()) |entry| {
            const name = entry.key_ptr.*;

            // Skip if declared in try block (already in declared_vars)
            if (declared_var_set.contains(name)) continue;

            // Skip locally declared variables (for-loop targets, etc.) - they don't exist outside try
            if (locally_declared.contains(name)) continue;

            // Skip built-in functions - but NOT 'self'/'__self' which are method parameters
            // (PythonBuiltinNames includes "self" as a special name, but we need to capture it)
            if (BuiltinFuncs.has(name) and !std.mem.eql(u8, name, "self") and !std.mem.eql(u8, name, "__self")) continue;

            // NOTE: Do NOT skip 'self' - inside TryHelper struct, self is NOT available
            // because TryHelper is a separate struct with its own scope. self needs to be
            // captured like any other read-only variable when used in try body.

            // Skip user-defined functions (they're module-level, accessible directly)
            if (self.function_signatures.contains(name)) continue;
            if (self.functions_needing_allocator.contains(name)) continue;

            // Skip imported modules (they're module-level constants, no need to capture)
            if (self.imported_modules.contains(name)) continue;

            // Check if this variable is from outer scope
            // If the variable is written in the try block, it's definitely an outer variable
            // (otherwise it would be in declared_var_set or locally_declared)
            // If it's only read, we need to verify it exists in some tracking mechanism
            if (written_vars.contains(name)) {
                // Variable is written in try block and not locally declared
                // Check if it actually exists in outer scope - if not, it needs to be hoisted
                // Also check var_renames - if variable has a rename, it exists (from outer helper)
                // Note: var_types and lifetimes are NOT checked here because they contain semantic info
                // but don't guarantee the variable was actually declared (e.g., unused var optimization may skip it)
                // Note: Do NOT check func_local_vars - it contains variables that WILL be declared anywhere
                // in the function, including inside this try block. We only care about variables that
                // already EXIST before the try block.
                const exists_in_outer = self.isDeclared(name) or
                    self.hoisted_vars.contains(name) or
                    self.forward_declared_vars.contains(name) or
                    self.var_renames.contains(name);

                if (exists_in_outer) {
                    // Variable exists in outer scope - pass as pointer
                    // Skip Python's discard pattern - _ is not a real variable
                    if (std.mem.eql(u8, name, "_")) continue;
                    // Skip 'self' in __init__ methods - self doesn't exist yet (struct created at end)
                    const is_self_in_init_written = (std.mem.eql(u8, name, "self") or std.mem.eql(u8, name, "__self")) and
                        self.current_function_name != null and
                        (std.mem.eql(u8, self.current_function_name.?, "__init__") or std.mem.eql(u8, self.current_function_name.?, "init"));
                    if (is_self_in_init_written) continue;
                    try written_outer_vars.append(self.allocator, name);
                } else {
                    // Variable doesn't exist yet - needs to be hoisted/declared
                    // Add to declared_vars so it gets declared before the try block
                    // Check if not already in declared_var_set to avoid duplicates
                    // Skip Python's discard pattern - no need to hoist _
                    if (std.mem.eql(u8, name, "_")) continue;
                    if (!declared_var_set.contains(name)) {
                        try declared_vars.append(self.allocator, .{
                            .name = name,
                            // Use a None constant as the value - type will be inferred as optional
                            .value = .{ .constant = .{ .value = .{ .none = {} } } },
                            .is_exception_name = false,
                        });
                        try declared_var_set.put(name, {});
                    }
                }
            } else if (self.isDeclared(name) or self.semantic_info.lifetimes.contains(name) or self.type_inferrer.var_types.contains(name) or self.type_inferrer.getScopedVar(name) != null or self.nested_class_names.contains(name) or self.hoisted_vars.contains(name) or self.forward_declared_vars.contains(name) or std.mem.eql(u8, name, "self") or std.mem.eql(u8, name, "__self")) {
                // Variable is only read and we can verify it exists - capture as read-only
                // Note: nested_class_names tracks classes defined inside methods (like for-loop bodies)
                // Note: hoisted_vars tracks variables that were hoisted for scope escaping
                // Note: forward_declared_vars tracks variables forward declared for scope escaping
                // Note: getScopedVar checks for loop-local variables stored in scoped_var_types
                // Note: 'self' and '__self' are method parameters - always available when referenced
                // NOTE: Do NOT include func_local_vars - those are variables that WILL be declared
                // later in the function, not variables that are already available
                // Skip Python's discard pattern - _ is not a real variable
                // Skip 'self' in __init__ methods - self doesn't exist yet (struct created at end)
                const is_self_in_init = (std.mem.eql(u8, name, "self") or std.mem.eql(u8, name, "__self")) and
                    self.current_function_name != null and
                    (std.mem.eql(u8, self.current_function_name.?, "__init__") or std.mem.eql(u8, self.current_function_name.?, "init"));
                if (!std.mem.eql(u8, name, "_") and !is_self_in_init) {
                    try read_only_vars.append(self.allocator, name);
                }
            }

            // If this is a nested class with captured variables, also capture those variables
            // Example: class A captures badval, try block uses A() -> need to pass badval too
            if (self.nested_class_captures.get(name)) |captured_vars| {
                for (captured_vars) |cap_var| {
                    // Add captured var if not already tracked and exists in outer scope
                    var already_tracked = false;
                    for (read_only_vars.items) |existing| {
                        if (std.mem.eql(u8, existing, cap_var)) {
                            already_tracked = true;
                            break;
                        }
                    }
                    if (!already_tracked) {
                        for (written_outer_vars.items) |existing| {
                            if (std.mem.eql(u8, existing, cap_var)) {
                                already_tracked = true;
                                break;
                            }
                        }
                    }
                    if (!already_tracked and (self.isDeclared(cap_var) or self.semantic_info.lifetimes.contains(cap_var) or self.type_inferrer.var_types.contains(cap_var) or self.func_local_vars.contains(cap_var))) {
                        try read_only_vars.append(self.allocator, cap_var);
                    }
                }
            }
        }

        // Track if this try block has __gen_result passed as pointer (for yield inside try)
        var has_gen_result_param = false;
        // If we're inside a generator function and try block contains yield statements,
        // we need to pass __gen_result as a pointer parameter to the TryHelper
        // so that yield statements inside can append to it
        if (self.in_generator_function and signature_utils.hasYieldStatement(try_node.body)) {
            try written_outer_vars.append(self.allocator, "__gen_result");
            has_gen_result_param = true;
        }

        // Create helper function with unique name to avoid shadowing in nested try blocks
        // Note: helper_id is already declared at the start of genTry

        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __TryHelper_{d} = struct {{\n", .{helper_id});
        self.indent();
        try self.emitIndent();
        try self.emit("fn run(");

        // Parameters:
        // - read_only_vars: passed by value (anytype)
        // - written_outer_vars: passed as pointer (*i64)
        // - declared_vars: passed as pointer (*i64)
        var param_count: usize = 0;
        // Parameters use helper_id suffix to avoid shadowing in nested try blocks
        for (read_only_vars.items) |var_name| {
            if (param_count > 0) try self.emit(", ");
            // For heterogeneous loop variables, use concrete runtime.PyValue type
            // These variables are wrapped in PyValue in for_basic.zig to ensure type consistency
            // across inline for iterations (fixes "anytype can't reconcile multiple types" error)
            if (self.heterogeneous_loop_vars.contains(var_name)) {
                try self.output.writer(self.allocator).print("p_{s}_{d}: runtime.PyValue", .{ var_name, helper_id });
            } else {
                try self.output.writer(self.allocator).print("p_{s}_{d}: anytype", .{ var_name, helper_id });
            }
            param_count += 1;
        }
        for (written_outer_vars.items) |var_name| {
            if (param_count > 0) try self.emit(", ");
            try self.output.writer(self.allocator).print("p_{s}_{d}", .{ var_name, helper_id });
            // Special case: __gen_result is always std.ArrayListUnmanaged(runtime.PyValue)
            // This is a codegen-generated variable, not user-defined, so type inference won't find it
            if (std.mem.eql(u8, var_name, "__gen_result")) {
                try self.emit(": *std.ArrayListUnmanaged(runtime.PyValue)");
                param_count += 1;
                continue;
            }
            // Get actual type from type inference (local scope first, then global)
            const var_type = self.getVarType(var_name);
            // For class instances, use the class name directly (not *runtime.PyObject)
            // because user-defined classes like Rat should be passed as *Rat, not **runtime.PyObject
            if (var_type) |vt| {
                if (type_traits.isClassInstance(vt)) {
                    // Use renamed class name if available (e.g., metal0_main.Rat)
                    const class_name = self.var_renames.get(vt.class_instance) orelse vt.class_instance;
                    try self.emit(": *");
                    try self.emit(class_name);
                    param_count += 1;
                    continue;
                }
            }
            // For non-class types, use the standard type conversion
            // Special case: None type variables (x = None) should use runtime.PyValue
            // because Python allows reassigning None-initialized vars to other types
            if (var_type) |vt| {
                if (vt == .none) {
                    try self.emit(": *runtime.PyValue");
                    param_count += 1;
                    continue;
                }
            }
            const zig_type = if (var_type) |vt| blk: {
                break :blk try self.nativeTypeToZigType(vt);
            } else "i64";
            defer if (var_type != null) self.allocator.free(zig_type);
            try self.emit(": *");
            try self.emit(zig_type); // Pointer for mutable access
            param_count += 1;
        }
        for (declared_vars.items) |hoisted| {
            // Exception names are ALWAYS passed as parameters because they are assigned
            // in the catch block which is INSIDE the helper struct's run() function.
            // The assignment `e = runtime.getExceptionFull()` happens in the catch handler,
            // which requires the pointer parameter to access the outer variable.
            if (hoisted.is_exception_name) {
                if (param_count > 0) try self.emit(", ");
                try self.output.writer(self.allocator).print("p_{s}_{d}: *runtime.PyException", .{ hoisted.name, helper_id });
                param_count += 1;
                continue;
            }
            // Check if this variable is assigned from an exception variable (e.g., exc1 = e)
            // In that case, it should also be typed as PyException
            if (hoisted.value == .name and self.exception_vars.contains(hoisted.value.name.id)) {
                if (param_count > 0) try self.emit(", ");
                try self.output.writer(self.allocator).print("p_{s}_{d}: *runtime.PyException", .{ hoisted.name, helper_id });
                param_count += 1;
                continue;
            }
            if (param_count > 0) try self.emit(", ");
            try self.output.writer(self.allocator).print("p_{s}_{d}", .{ hoisted.name, helper_id });
            const var_type = self.type_inferrer.inferExpr(hoisted.value) catch null;
            // For class instances, use the class name directly (not *runtime.PyObject)
            // because user-defined classes like Rat should be passed as *Rat, not **runtime.PyObject
            if (var_type) |vt| {
                if (type_traits.isClassInstance(vt)) {
                    // Use renamed class name if available (e.g., metal0_main.Rat)
                    const class_name = self.var_renames.get(vt.class_instance) orelse vt.class_instance;
                    try self.emit(": *");
                    try self.emit(class_name);
                    param_count += 1;
                    continue;
                }
            }
            // For non-class types, use the standard type conversion
            // Special case: None type variables (x = None) should use runtime.PyValue
            // because Python allows reassigning None-initialized vars to other types
            if (var_type) |vt| {
                if (vt == .none) {
                    try self.emit(": *runtime.PyValue");
                    param_count += 1;
                    continue;
                }
            }
            const zig_type2 = if (var_type) |vt| blk: {
                break :blk try self.nativeTypeToZigType(vt);
            } else "i64";
            defer if (var_type != null) self.allocator.free(zig_type2);
            try self.emit(": *");
            try self.emit(zig_type2); // Pointer for mutable access
            param_count += 1;
        }

        try self.emit(") !void {\n");
        self.indent();

        // Save any existing renames for read_only_vars before overwriting
        // (e.g., function param `x` -> `__p_x_0` needs to be restored after try block)
        var saved_read_only_renames = std.ArrayListUnmanaged(struct { name: []const u8, rename: []const u8 }){};
        defer saved_read_only_renames.deinit(self.allocator);
        for (read_only_vars.items) |var_name| {
            if (self.var_renames.get(var_name)) |existing_rename| {
                try saved_read_only_renames.append(self.allocator, .{
                    .name = var_name,
                    .rename = try self.arena.allocator().dupe(u8, existing_rename),
                });
            }
        }

        // Create aliases for read-only captured variables (by value)
        // Always use 'const' - read-only vars don't need mutation, and some types
        // like null and type references require const in Zig
        for (read_only_vars.items) |var_name| {
            try self.emitIndent();
            // Check if this is a class type (for skipping discard)
            const is_nested_class = self.nested_class_names.contains(var_name);
            const is_toplevel_class = self.class_registry.getClass(var_name) != null;
            const is_class_type = is_nested_class or is_toplevel_class;
            try self.output.writer(self.allocator).print("const __local_{s}_{d}: @TypeOf(p_{s}_{d}) = p_{s}_{d};\n", .{ var_name, helper_id, var_name, helper_id, var_name, helper_id });

            // Emit discard to mark as used
            try self.emitIndent();
            if (is_class_type) {
                // For class types, use runtime.discard - can't take address of comptime type
                try self.output.writer(self.allocator).print("runtime.discard(&__local_{s}_{d});\n", .{ var_name, helper_id });
            } else {
                // For regular values, use _ = &var to prevent mutation errors
                try self.output.writer(self.allocator).print("_ = &__local_{s}_{d};\n", .{ var_name, helper_id });
            }

            // Add to rename map
            var buf = std.ArrayListUnmanaged(u8){};
            try buf.writer(self.allocator).print("__local_{s}_{d}", .{ var_name, helper_id });
            const renamed = try buf.toOwnedSlice(self.allocator);
            try self.var_renames.put(var_name, renamed);
            // Remove from func_local_vars so var_renames lookup is used in expressions.zig
            // This ensures starred unpacking (*instances) uses __local_instances_N instead
            _ = self.func_local_vars.swapRemove(var_name);
            // CRITICAL: Also add the RENAMED name to func_local_vars so isNameDefined can find it.
            // When in_nameerror_context=true, expressions.zig checks isNameDefined(name_to_use)
            // where name_to_use is the renamed value (e.g., "__local_self_26"). Without this,
            // isNameDefined fails and emits "return error.NameError" incorrectly.
            try self.func_local_vars.put(renamed, {});
        }

        // Save any existing renames for written_outer_vars before overwriting
        // This is critical for nested try blocks - the outer try's renames must be preserved
        var saved_written_outer_renames = std.ArrayListUnmanaged(struct { name: []const u8, rename: []const u8 }){};
        defer saved_written_outer_renames.deinit(self.allocator);
        for (written_outer_vars.items) |var_name| {
            if (self.var_renames.get(var_name)) |existing_rename| {
                try saved_written_outer_renames.append(self.allocator, .{
                    .name = var_name,
                    .rename = try self.arena.allocator().dupe(u8, existing_rename),
                });
            }
        }

        // Create aliases for written outer variables (dereference pointers)
        // Check if each variable is used in the try body OR in the finally block
        // If not used in either, suppress the unused parameter warning
        for (written_outer_vars.items) |var_name| {
            // Special case: __gen_result is always used by yield statements in generators
            // It's a codegen-generated variable not visible in the AST, so skip usage check
            if (std.mem.eql(u8, var_name, "__gen_result")) {
                // Add to rename map to use dereferenced pointer (no discard needed)
                var buf = std.ArrayListUnmanaged(u8){};
                try buf.writer(self.allocator).print("p_{s}_{d}.*", .{ var_name, helper_id });
                const renamed = try buf.toOwnedSlice(self.allocator);
                try self.var_renames.put(var_name, renamed);
                // Remove from func_local_vars so var_renames lookup is used
                _ = self.func_local_vars.swapRemove(var_name);
                continue;
            }
            // ALWAYS emit discard for written_outer_vars parameters.
            // When nested try body always terminates (raise on all paths), we add unreachable; after catch,
            // which makes code that would use these parameters unreachable. Without unconditional
            // discard, we get "unused function parameter" errors.
            // Use runtime.discard() to suppress both "unused" and "pointless discard" errors.
            try self.emitIndent();
            try self.output.writer(self.allocator).print("runtime.discard(p_{s}_{d});\n", .{ var_name, helper_id });

            // Add to rename map to use dereferenced pointer
            var buf = std.ArrayListUnmanaged(u8){};
            try buf.writer(self.allocator).print("p_{s}_{d}.*", .{ var_name, helper_id });
            const renamed = try buf.toOwnedSlice(self.allocator);
            try self.var_renames.put(var_name, renamed);
            // Remove from func_local_vars so var_renames lookup is used
            _ = self.func_local_vars.swapRemove(var_name);
            // CRITICAL: Also add the RENAMED name to func_local_vars so isNameDefined can find it.
            try self.func_local_vars.put(renamed, {});
        }

        // Save any existing import-shadowing renames for hoisted vars before overwriting
        // (we'll restore them after generating the helper body)
        var saved_hoisted_renames = std.ArrayListUnmanaged(struct { name: []const u8, rename: []const u8 }){};
        defer saved_hoisted_renames.deinit(self.allocator);
        for (declared_vars.items) |hoisted| {
            if (self.var_renames.get(hoisted.name)) |existing_rename| {
                // Don't save if it's a p_* rename from a previous helper
                if (!std.mem.startsWith(u8, existing_rename, "p_")) {
                    try saved_hoisted_renames.append(self.allocator, .{
                        .name = hoisted.name,
                        .rename = try self.arena.allocator().dupe(u8, existing_rename),
                    });
                }
            }
        }

        // Create aliases for declared variables (dereference pointers)
        // Also suppress unused parameter warnings since these vars may only be set in except block
        for (declared_vars.items) |hoisted| {
            // ALWAYS emit discard for hoisted parameters.
            // When try body always terminates (raise on all paths), we add unreachable; after catch,
            // which makes code that would use these parameters unreachable. Without unconditional
            // discard, we get "unused function parameter" errors.
            try self.emitIndent();
            try self.output.writer(self.allocator).print("runtime.discard(p_{s}_{d});\n", .{ hoisted.name, helper_id });

            // Add to rename map to use dereferenced pointer
            var buf = std.ArrayListUnmanaged(u8){};
            try buf.writer(self.allocator).print("p_{s}_{d}.*", .{ hoisted.name, helper_id });
            const renamed = try buf.toOwnedSlice(self.allocator);
            try self.var_renames.put(hoisted.name, renamed);
            // Remove from func_local_vars so var_renames lookup is used
            _ = self.func_local_vars.swapRemove(hoisted.name);
            // CRITICAL: Also add the RENAMED name to func_local_vars so isNameDefined can find it.
            try self.func_local_vars.put(renamed, {});
        }

        // Check if try body contains break/continue for special handling
        const has_break_continue = containsBreakOrContinue(try_node.body);
        const saved_break_helper_id = self.try_break_helper_id;
        if (has_break_continue) {
            self.try_break_helper_id = helper_id;
        }
        defer self.try_break_helper_id = saved_break_helper_id;

        // Save and reset control_flow_terminated for try body scope.
        // The try body is inside a helper function, so raise/return there should NOT
        // terminate control flow in the outer scope. Code after the try block should
        // still be generated (e.g., self.assertTrue(hit_except) after try/except).
        const saved_control_flow_terminated = self.control_flow_terminated;
        self.control_flow_terminated = false;

        // Set inside_try_body = true so that error-returning builtins (like float())
        // use 'try' instead of 'catch 0.0', allowing errors to propagate to handlers
        const saved_inside_try_body = self.inside_try_body;
        self.inside_try_body = true;

        // CRITICAL: Reset in_assert_raises_context inside TryHelper function body.
        // When we're inside a TryHelper, we're in a separate Zig function - labeled breaks
        // cannot cross function boundaries. If raise happens here, it must use `return error.X`
        // (not `break :__ar_blk_N`) so the catch handler outside can handle it properly.
        const saved_in_assert_raises = self.in_assert_raises_context;
        self.in_assert_raises_context = false;

        // CRITICAL: Reset current_function_returns_pyvalue inside TryHelper function body.
        // The TryHelper function returns !void (not PyValue), so constructor calls
        // must use (try ...) to propagate errors, not (... catch unreachable).
        const saved_returns_pyvalue = self.current_function_returns_pyvalue;
        self.current_function_returns_pyvalue = false;

        // Set in_nameerror_context if this try block catches NameError (or bare except/Exception)
        // This enables emitting runtime.raiseNameError() for undefined variables
        const saved_in_nameerror_context = self.in_nameerror_context;
        if (catchesNameError(try_node.handlers)) {
            self.in_nameerror_context = true;
        }

        // Generate try block body with renamed variables
        for (try_node.body) |stmt| {
            try self.generateStmt(stmt);
        }

        // Restore in_nameerror_context, inside_try_body, current_function_returns_pyvalue, and control_flow_terminated
        // IMMEDIATELY after try body. Must do this before generating else/finally/handlers.
        // NOTE: in_assert_raises_context is NOT restored here - it must stay false until
        // the TryHelper struct closes, because except handlers run inside the struct and
        // labeled breaks cannot cross function boundaries in Zig.
        self.in_nameerror_context = saved_in_nameerror_context;
        self.inside_try_body = saved_inside_try_body;
        // self.in_assert_raises_context restored AFTER TryHelper closes (see below)
        self.current_function_returns_pyvalue = saved_returns_pyvalue;
        self.control_flow_terminated = saved_control_flow_terminated;

        // Clear rename map after generating body and free allocated strings
        // Also remove the renamed entries from func_local_vars that we added earlier
        for (read_only_vars.items) |var_name| {
            if (self.var_renames.fetchSwapRemove(var_name)) |entry| {
                // Also remove the renamed entry from func_local_vars
                _ = self.func_local_vars.swapRemove(entry.value);
                self.allocator.free(entry.value);
            }
        }
        for (written_outer_vars.items) |var_name| {
            if (self.var_renames.fetchSwapRemove(var_name)) |entry| {
                // Also remove the renamed entry from func_local_vars
                _ = self.func_local_vars.swapRemove(entry.value);
                self.allocator.free(entry.value);
            }
        }
        for (declared_vars.items) |hoisted| {
            if (self.var_renames.fetchSwapRemove(hoisted.name)) |entry| {
                // Also remove the renamed entry from func_local_vars
                _ = self.func_local_vars.swapRemove(entry.value);
                self.allocator.free(entry.value);
            }
        }

        // Restore import-shadowing renames for hoisted vars (needed for helper call)
        for (saved_hoisted_renames.items) |saved| {
            try self.var_renames.put(saved.name, saved.rename);
        }

        // Restore saved read_only_vars renames (e.g., function param x -> __p_x_0)
        // These are needed for the TryHelper call to use the correct parameter name
        for (saved_read_only_renames.items) |saved| {
            try self.var_renames.put(saved.name, saved.rename);
        }

        // Restore saved written_outer_vars renames (needed for nested try blocks)
        // This ensures outer try's renames are preserved when inner try clears its own
        for (saved_written_outer_renames.items) |saved| {
            try self.var_renames.put(saved.name, saved.rename);
        }

        // CRITICAL: Add written_outer_vars and declared_vars back to func_local_vars AND var_renames
        // These are outer scope variables that will be assigned in exception handlers.
        // Without this, the assignment codegen treats them as first assignments and
        // applies shadowing renames (e.g., stop -> stop_) which causes undeclared identifier errors.
        // The var_renames entry maps the Python name to itself, indicating the variable is already
        // declared and shouldn't have shadowing rename applied.
        for (written_outer_vars.items) |var_name| {
            try self.func_local_vars.put(var_name, {});
            // Add to var_renames so assignment uses the actual declared name
            if (!self.var_renames.contains(var_name)) {
                try self.var_renames.put(var_name, var_name);
            }
        }
        for (declared_vars.items) |hoisted| {
            try self.func_local_vars.put(hoisted.name, {});
            // Add to var_renames so assignment uses the actual declared name
            if (!self.var_renames.contains(hoisted.name)) {
                try self.var_renames.put(hoisted.name, hoisted.name);
            }
        }

        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");

        // If there's an else block, declare a flag to track whether exception was caught
        const has_else_block = try_node.else_body.len > 0;
        if (has_else_block) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var __exception_caught_{d}: bool = false;\n", .{helper_id});
        }

        // Call helper with:
        // - read_only_vars: by value
        // - written_outer_vars: as pointer (&)
        // - declared_vars: as pointer (&)
        try self.emitIndent();
        try self.output.writer(self.allocator).print("__TryHelper_{d}.run(", .{helper_id});
        var call_param_count: usize = 0;
        for (read_only_vars.items) |var_name| {
            if (call_param_count > 0) try self.emit(", ");
            // Check if variable has been renamed (e.g., function param x -> __p_x_0)
            const actual_name = self.var_renames.get(var_name) orelse var_name;
            // Check if this is a captured variable in the current nested class
            if (isCapturedByCurrentClass(self, var_name)) {
                // Access via __self.__captured_var.* for captured variables
                const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
                try self.output.writer(self.allocator).print("{s}.__captured_{s}.*", .{ self_name, var_name });
            } else {
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), actual_name);
            }
            call_param_count += 1;
        }
        for (written_outer_vars.items) |var_name| {
            if (call_param_count > 0) try self.emit(", ");
            // Check if variable has been renamed (e.g., function param a -> a__mut)
            const actual_name = self.var_renames.get(var_name) orelse var_name;
            // Check if this is a captured variable in the current nested class
            if (isCapturedByCurrentClass(self, var_name)) {
                // Access via __self.__captured_var for captured variables (already a pointer, no & needed)
                const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
                try self.output.writer(self.allocator).print("{s}.__captured_{s}", .{ self_name, var_name });
            } else {
                try self.emit("&");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), actual_name);
            }
            call_param_count += 1;
        }
        for (declared_vars.items) |hoisted| {
            // Exception names are ALWAYS passed as parameter since they're assigned in catch handlers
            // The assignment `e = runtime.getExceptionFull()` needs the pointer to work
            // Don't skip exception names - they need the parameter for the assignment
            if (call_param_count > 0) try self.emit(", ");
            try self.emit("&");
            // Use renamed name if variable was renamed to avoid shadowing imports
            const actual_name = self.var_renames.get(hoisted.name) orelse hoisted.name;
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), actual_name);
            call_param_count += 1;
        }

        // Check if we need to capture err (if there are specific exception handlers OR exception var names OR break/continue)
        const needs_err_capture = blk: {
            if (has_break_continue) break :blk true;
            for (try_node.handlers) |handler| {
                if (handler.type != null or handler.name != null) break :blk true;
            }
            break :blk false;
        };

        // Use unique error variable name to avoid shadowing in nested try blocks
        var err_var_buf: [32]u8 = undefined;
        const err_var = std.fmt.bufPrint(&err_var_buf, "__err_{d}", .{helper_id}) catch "__err";

        if (needs_err_capture) {
            try self.output.writer(self.allocator).print(") catch |{s}| {{\n", .{err_var});
        } else {
            try self.emit(") catch {\n");
        }
        self.indent();

        // Set exception caught flag for else block tracking (must be first in catch)
        if (has_else_block) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("__exception_caught_{d} = true;\n", .{helper_id});
        }

        // Handle break/continue from try body - must come first before exception handlers
        if (has_break_continue) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("if ({s} == error.BreakRequested) break;\n", .{err_var});
        }

        // Generate exception handlers
        var generated_handler = false;
        for (try_node.handlers, 0..) |handler, i| {
            if (i > 0) {
                try self.emitIndent();
                try self.emit("} else ");
            } else if (handler.type != null) {
                try self.emitIndent();
            }

            if (handler.type) |exc_type| {
                // Exception and BaseException are catch-all - they catch any error
                const is_catch_all = std.mem.eql(u8, exc_type, "Exception") or
                    std.mem.eql(u8, exc_type, "BaseException");

                if (is_catch_all) {
                    // Catch-all: just enter the handler block without checking specific error
                    try self.emit("{\n");
                    // Suppress unused error variable warning (can't use _ for error sets)
                    self.indent();
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("_ = @errorName({s});\n", .{err_var});
                    self.dedent();
                } else {
                    const zig_err = pythonExceptionToZigError(exc_type);
                    try self.output.writer(self.allocator).print("if ({s} == error.", .{err_var});
                    try self.emit(zig_err);
                    try self.emit(") {\n");
                }
                self.indent();
                // If handler has "as name", always assign the exception variable
                // It might be used in the handler body OR after the try/except block
                if (handler.name) |exc_name| {
                    // Check if this name was already hoisted as a var (this try block)
                    const is_hoisted_this_block = blk: {
                        for (declared_vars.items) |hoisted| {
                            if (std.mem.eql(u8, hoisted.name, exc_name)) break :blk true;
                        }
                        break :blk false;
                    };
                    // Also check if already declared from a previous try block or other scope
                    // BUT: if we're inside a TryHelper (nested try) and the variable was declared
                    // OUTSIDE the TryHelper, we can't access it due to Zig namespace boundaries.
                    // In that case, treat it as a new local variable.
                    const was_declared_elsewhere = self.hoisted_vars.contains(exc_name) or self.isDeclared(exc_name);

                    // Check if we can actually access this variable:
                    // - is_hoisted_this_block: hoisted by THIS try block, passed as pointer param - ACCESSIBLE
                    // - was_declared_elsewhere: if we have a rename (p_X_N.*), it was passed as pointer - ACCESSIBLE
                    //   otherwise, it's outside our TryHelper namespace - NOT ACCESSIBLE
                    const has_pointer_rename = if (self.var_renames.get(exc_name)) |renamed| std.mem.endsWith(u8, renamed, ".*") else false;
                    const is_accessible = is_hoisted_this_block or (was_declared_elsewhere and has_pointer_rename);

                    // Only emit if used in handler body OR hoisted (used elsewhere)
                    if (is_accessible or isNameUsedInStmts(handler.body, exc_name, self.allocator)) {
                        try self.emitIndent();
                        // Use runtime.getExceptionFull() to get full PyException with
                        // __traceback__, __context__, __cause__ attributes
                        if (is_accessible) {
                            // Assign to the existing hoisted variable
                            // Check for rename (e.g., p_e.* for hoisted exception names passed as pointers)
                            if (self.var_renames.get(exc_name)) |renamed| {
                                try self.emit(renamed);
                            } else {
                                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), exc_name);
                            }
                            try self.emit(" = runtime.getExceptionFull();\n");
                        } else {
                            // Declare new const - either not declared elsewhere, or declared but not accessible
                            // Use scoped name to avoid shadowing outer variables with the same name
                            const scoped_name = try std.fmt.allocPrint(self.allocator, "__exc_{s}_{d}", .{ exc_name, helper_id });
                            try self.emit("const ");
                            try self.emit(scoped_name);
                            try self.emit(": runtime.PyException = runtime.getExceptionFull();\n");
                            // Suppress "unused local constant" error - variable may be used or just declared for Python compat
                            try self.emitIndent();
                            try self.emit("_ = &");
                            try self.emit(scoped_name);
                            try self.emit(";\n");
                            // Add to var_renames so handler body references use the scoped name
                            try self.var_renames.put(exc_name, scoped_name);
                        }
                    }
                }
                // Push exception onto stack for bare raise support (use defer to ensure pop on any exit)
                try self.emitIndent();
                try self.emit("{\n");
                self.indent();
                try self.emitIndent();
                try self.emit("runtime.exceptions.pushException(\"");
                try self.emit(exc_type);
                try self.emit("\", runtime.exceptions.getExceptionMessage());\n");
                try self.emitIndent();
                try self.emit("defer runtime.exceptions.popException();\n");

                for (handler.body) |stmt| {
                    // Skip function_def if it was already hoisted during Phase 5.1
                    // (function definitions in except handlers are hoisted to module level)
                    if (stmt == .function_def) {
                        if (self.module_level_vars.contains(stmt.function_def.name)) continue;
                    }
                    try self.generateStmt(stmt);
                }

                self.dedent();
                try self.emitIndent();
                try self.emit("}\n");

                // If inside assertRaises context, break out of the __ar_blk block
                // to indicate the exception was successfully caught (test passes)
                if (self.in_assert_raises_context and !self.control_flow_terminated) {
                    try self.emitIndent();
                    try self.emitFmt("break :__ar_blk_{d} {{}}; // Exception caught by except handler\n", .{self.current_assert_raises_block_id});
                }
                self.dedent();
                // For catch-all handlers (Exception/BaseException), close the block
                if (is_catch_all) {
                    try self.emitIndent();
                    try self.emit("}\n");
                }
                generated_handler = true;
            } else {
                if (i > 0) {
                    try self.emit("{\n");
                } else {
                    try self.emitIndent();
                    try self.emit("{\n");
                }
                self.indent();
                // If handler has "as name", always assign the exception variable
                // It might be used in the handler body OR after the try/except block
                if (handler.name) |exc_name| {
                    // Check if this name was already hoisted as a var (this try block)
                    const is_hoisted_this_block = blk: {
                        for (declared_vars.items) |hoisted| {
                            if (std.mem.eql(u8, hoisted.name, exc_name)) break :blk true;
                        }
                        break :blk false;
                    };
                    // Also check if already declared from a previous try block or other scope
                    // BUT: if we're inside a TryHelper (nested try) and the variable was declared
                    // OUTSIDE the TryHelper, we can't access it due to Zig namespace boundaries.
                    // In that case, treat it as a new local variable.
                    const was_declared_elsewhere = self.hoisted_vars.contains(exc_name) or self.isDeclared(exc_name);

                    // Check if we can actually access this variable:
                    // - is_hoisted_this_block: hoisted by THIS try block, passed as pointer param - ACCESSIBLE
                    // - was_declared_elsewhere: if we have a rename (p_X_N.*), it was passed as pointer - ACCESSIBLE
                    //   otherwise, it's outside our TryHelper namespace - NOT ACCESSIBLE
                    const has_pointer_rename = if (self.var_renames.get(exc_name)) |renamed| std.mem.endsWith(u8, renamed, ".*") else false;
                    const is_accessible = is_hoisted_this_block or (was_declared_elsewhere and has_pointer_rename);

                    // Only emit if used in handler body OR hoisted (used elsewhere)
                    if (is_accessible or isNameUsedInStmts(handler.body, exc_name, self.allocator)) {
                        try self.emitIndent();
                        // Use runtime.getExceptionFull() to get full PyException with
                        // __traceback__, __context__, __cause__ attributes
                        if (is_accessible) {
                            // Assign to the existing hoisted variable
                            // Check for rename (e.g., p_e.* for hoisted exception names passed as pointers)
                            if (self.var_renames.get(exc_name)) |renamed| {
                                try self.emit(renamed);
                            } else {
                                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), exc_name);
                            }
                            try self.emit(" = runtime.getExceptionFull();\n");
                        } else {
                            // Declare new const - either not declared elsewhere, or declared but not accessible
                            // Use scoped name to avoid shadowing outer variables with the same name
                            const scoped_name = try std.fmt.allocPrint(self.allocator, "__exc_{s}_{d}", .{ exc_name, helper_id });
                            try self.emit("const ");
                            try self.emit(scoped_name);
                            try self.emit(": runtime.PyException = runtime.getExceptionFull();\n");
                            // Suppress "unused local constant" error - variable may be used or just declared for Python compat
                            try self.emitIndent();
                            try self.emit("_ = &");
                            try self.emit(scoped_name);
                            try self.emit(";\n");
                            // Add to var_renames so handler body references use the scoped name
                            try self.var_renames.put(exc_name, scoped_name);
                        }
                    }
                }
                // Push exception onto stack for bare raise support (use defer to ensure pop on any exit)
                try self.emitIndent();
                try self.emit("{\n");
                self.indent();
                try self.emitIndent();
                try self.emit("runtime.exceptions.pushException(runtime.exceptions.getExceptionType(), runtime.exceptions.getExceptionMessage());\n");
                try self.emitIndent();
                try self.emit("defer runtime.exceptions.popException();\n");

                for (handler.body) |stmt| {
                    // Skip function_def if it was already hoisted during Phase 5.1
                    // (function definitions in except handlers are hoisted to module level)
                    if (stmt == .function_def) {
                        if (self.module_level_vars.contains(stmt.function_def.name)) continue;
                    }
                    try self.generateStmt(stmt);
                }

                self.dedent();
                try self.emitIndent();
                try self.emit("}\n");

                // If inside assertRaises context, break out of the __ar_blk block
                // to indicate the exception was successfully caught (test passes)
                if (self.in_assert_raises_context and !self.control_flow_terminated) {
                    try self.emitIndent();
                    try self.emitFmt("break :__ar_blk_{d} {{}}; // Exception caught by except handler\n", .{self.current_assert_raises_block_id});
                }
                self.dedent();
                try self.emitIndent();
                try self.emit("}\n");
                generated_handler = true;
            }
        }

        // Generate `else { return err; }` only if the last handler is NOT a catch-all
        // Exception and BaseException are catch-all handlers that handle all errors
        if (generated_handler and try_node.handlers[try_node.handlers.len - 1].type != null) {
            const last_exc_type = try_node.handlers[try_node.handlers.len - 1].type.?;
            const is_catch_all = std.mem.eql(u8, last_exc_type, "Exception") or
                std.mem.eql(u8, last_exc_type, "BaseException");

            if (!is_catch_all) {
                try self.emitIndent();
                try self.emit("} else {\n");
                self.indent();
                try self.emitIndent();
                // If there's a finally block, store exception instead of returning immediately
                // This allows finally to run before the exception is propagated
                if (has_finally) {
                    try self.output.writer(self.allocator).print("__pending_exception_{d} = {s};\n", .{ helper_id, err_var });
                } else if (self.inside_defer) {
                    // Cannot return from defer - just re-raise the error
                    // The defer will complete and error will propagate naturally
                    // Note: We don't emit _ = err_var because the error is already used
                    // in the if condition check above
                    try self.output.writer(self.allocator).print("// Cannot return {s} from defer - error propagates after defer\n", .{err_var});
                } else {
                    try self.output.writer(self.allocator).print("return {s};\n", .{err_var});
                }
                self.dedent();
                try self.emitIndent();
                try self.emit("}\n");
            }
        }

        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");

        // If try body always terminates (raise/return on all paths) AND all except handlers
        // also terminate, the code after catch is unreachable.
        // The TryHelper.run() will never return successfully - it always returns an error.
        // AND the catch block will never fall through - it always returns/re-raises.
        const try_body_always_terminates = stmtListAlwaysTerminates(try_node.body);
        var all_handlers_terminate = true;
        if (try_body_always_terminates) {
            for (try_node.handlers) |handler| {
                if (!stmtListAlwaysTerminates(handler.body)) {
                    all_handlers_terminate = false;
                    break;
                }
            }
        }
        if (try_body_always_terminates and all_handlers_terminate and try_node.handlers.len > 0) {
            try self.emitIndent();
            try self.emit("unreachable;\n");
            // Mark control flow as terminated - skip else block, it's unreachable
            self.control_flow_terminated = true;
        }

        // NOW restore in_assert_raises_context - TryHelper struct is closed, so labeled breaks
        // in the outer scope (else block, finally block, etc.) can reach their targets.
        self.in_assert_raises_context = saved_in_assert_raises;

        // Generate else block (runs only if NO exception was raised)
        // In Python's try/except/else, the else block executes only when no exception occurred.
        // We track this via __exception_caught_N flag set in the catch block.
        // Skip if try body always terminates - else is unreachable.
        if (try_node.else_body.len > 0 and !try_body_always_terminates) {
            // Reset control_flow_terminated - raise in except handlers shouldn't skip else generation
            // The else block is runtime-conditional (only runs if no exception), but code must be generated
            self.control_flow_terminated = false;

            try self.emitIndent();
            try self.output.writer(self.allocator).print("if (!__exception_caught_{d}) {{\n", .{helper_id});
            self.indent();
            for (try_node.else_body) |stmt| {
                try self.generateStmt(stmt);
            }
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }
    } else {
        // No exception handlers - just try/finally or try/else/finally
        // When there's a finally block, use defer to ensure it runs even if try body returns
        // BUT: Can't use defer if:
        // 1. finally contains break/continue/return (Zig doesn't allow control flow in defer)
        // 2. try body contains break/continue/return (defer won't run before these exit)
        // In case 2, we use Nuitka-style inline code duplication instead
        const finally_has_control_flow = has_finally and containsControlFlow(try_node.finalbody);
        const try_body_has_control_flow = containsControlFlow(try_node.body);
        const can_use_defer = has_finally and !finally_has_control_flow and !containsRaise(try_node.finalbody) and !try_body_has_control_flow;

        // Track if we need special handling for raise in try body
        // When finally can't use defer, raise must store exception instead of returning directly
        const needs_try_finally_tracking = has_finally and !can_use_defer;

        if (can_use_defer) {
            // Generate finally code as defer BEFORE try body
            // defer runs when scope exits (including on return), ensuring cleanup always happens
            try self.emitIndent();
            try self.emit("defer {\n");
            self.indent();

            // Generate finally body inline in the defer
            for (try_node.finalbody) |stmt| {
                // Temporarily disable finally block markers since we're using defer
                const saved_inside_finally = self.inside_finally_block;
                const saved_finally_id = self.current_finally_id;
                const saved_inside_defer = self.inside_defer;
                self.inside_finally_block = false;  // Don't use break :__finally_blk pattern
                self.inside_defer = true;
                self.current_finally_id = @intCast(helper_id);

                try self.generateStmt(stmt);

                self.inside_finally_block = saved_inside_finally;
                self.current_finally_id = saved_finally_id;
                self.inside_defer = saved_inside_defer;
            }

            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }

        // NOTE: __pending_exception_N is already declared at line 687 for all try blocks with finally
        // No need to declare it again here

        // Push finally context for Nuitka-style code duplication
        // When return/break/continue/raise is encountered inside the try body,
        // the finally code will be duplicated inline BEFORE the control flow statement
        if (has_finally) {
            _ = self.pushFinallyContext(try_node.finalbody, can_use_defer);
        }

        // Generate try body
        const saved_inside_try_body = self.inside_try_body;
        const saved_inside_try_with_finally = self.inside_try_with_finally;
        const saved_try_finally_id = self.current_try_finally_id;
        const saved_in_nameerror_context = self.in_nameerror_context;
        self.inside_try_body = true;
        if (needs_try_finally_tracking) {
            self.inside_try_with_finally = true;
            self.current_try_finally_id = @intCast(helper_id);
        }
        // Set in_nameerror_context if this try block catches NameError
        if (catchesNameError(try_node.handlers)) {
            self.in_nameerror_context = true;
        }

        for (try_node.body) |stmt| {
            try self.generateStmt(stmt);
        }

        self.inside_try_body = saved_inside_try_body;
        self.inside_try_with_finally = saved_inside_try_with_finally;
        self.current_try_finally_id = saved_try_finally_id;
        self.in_nameerror_context = saved_in_nameerror_context;

        // Pop finally context BEFORE generating inline finally code
        // CRITICAL: This must happen before inline finally generation to avoid infinite recursion.
        // If the finally block contains a `raise`, that raise's handler calls emitAllFinallyBlocks
        // which would emit this same finally again if we haven't popped it yet.
        if (has_finally) {
            self.popFinallyContext();
        }

        // Emit finally code at end of try body for normal fallthrough
        // (when try body doesn't terminate with break/continue/return)
        // The inline duplication before control flow handles early exits;
        // this handles the normal path where execution falls through
        if (has_finally and !can_use_defer and !self.control_flow_terminated) {
            // Emit finally code inline at end of try body
            try self.emitIndent();
            try self.emit("{ // finally (normal path)\n");
            self.indent();
            for (try_node.finalbody) |stmt| {
                try self.generateStmt(stmt);
            }
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            // Pop the exception that was pushed for finally (if any was raised in try body)
            // This is safe because we only push when storing to __pending_exception_N
            try self.emitIndent();
            try self.output.writer(self.allocator).print("if (__pending_exception_{d} != null) runtime.exceptions.popException();\n", .{helper_id});
            // Propagate pending exception after finally completes
            try self.emitIndent();
            try self.output.writer(self.allocator).print("if (__pending_exception_{d}) |pe| return pe;\n", .{helper_id});
        }

        // Also handle else_body when there are no exception handlers
        // (try/else/finally without except)
        if (try_node.else_body.len > 0) {
            for (try_node.else_body) |stmt| {
                try self.generateStmt(stmt);
            }
        }

    }

    // Generate finally block (always executes after try/except/else)
    // Uses a labeled block to allow raise statements to break out with an error
    // SKIP this if we already generated it as defer (no exception handlers + no control flow in finally or try body)
    const used_defer_for_finally = try_node.handlers.len == 0 and has_finally and !containsControlFlow(try_node.finalbody) and !containsRaise(try_node.finalbody) and !containsControlFlow(try_node.body);

    // Also skip when using inline duplication (no exception handlers + try body has control flow)
    // In this case, we already emitted finally code:
    // 1. Inline before control flow statements (break/continue/return)
    // 2. At end of try body for normal path
    const used_inline_duplication = try_node.handlers.len == 0 and has_finally and containsControlFlow(try_node.body);

    // Also skip if try body terminated with control flow (break/continue/return)
    // In this case, the finally block code after try body is unreachable
    // The finally code was already duplicated inline BEFORE the control flow statement
    const try_body_terminated = self.control_flow_terminated;

    if (has_finally and !used_defer_for_finally and !used_inline_duplication and !try_body_terminated) {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __finally_err_{d}: ?anyerror = __finally_blk_{d}: {{\n", .{ helper_id, helper_id });
        self.indent();

        // Save and set finally block context
        const saved_inside_finally = self.inside_finally_block;
        const saved_finally_id = self.current_finally_id;
        const saved_inside_defer = self.inside_defer;
        self.inside_finally_block = true;
        self.current_finally_id = @intCast(helper_id);
        self.inside_defer = true; // Still suppress 'try' in finally (use catch {} for non-raise calls)

        // Reset control_flow_terminated before generating finally body
        const saved_control_flow = self.control_flow_terminated;
        self.control_flow_terminated = false;

        for (try_node.finalbody) |stmt| {
            try self.generateStmt(stmt);
        }

        // Check if finally body terminated (e.g., via raise)
        const finally_terminated = self.control_flow_terminated;

        // Restore context
        self.inside_finally_block = saved_inside_finally;
        self.current_finally_id = saved_finally_id;
        self.inside_defer = saved_inside_defer;
        self.control_flow_terminated = saved_control_flow;

        // Default: no exception raised in finally
        // Only emit break if finally didn't already terminate with control flow
        // If finally_terminated is true, the finally body already contains a break/return/raise
        // that exits the labeled block, so we don't need to emit anything extra
        if (!finally_terminated) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("break :__finally_blk_{d} null;\n", .{helper_id});
        }
        // Note: Don't emit unreachable when finally_terminated - the finally body already
        // handled the exit (e.g., break :__finally_blk_N null from return, or error from raise)
        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");

        // Propagate exceptions: finally exception takes precedence over pending exception
        try self.emitIndent();
        try self.output.writer(self.allocator).print("if (__finally_err_{d}) |fe| return fe;\n", .{helper_id});
        try self.emitIndent();
        try self.output.writer(self.allocator).print("if (__pending_exception_{d}) |pe| return pe;\n", .{helper_id});
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // NOTE: Do NOT clear hoisted_vars here - keep tracking them for the entire function
    // so subsequent try blocks with the same variable name don't re-hoist them.
    // hoisted_vars will be cleared when the function ends or via function reset.
}

fn pythonExceptionToZigError(exc_type: []const u8) []const u8 {
    return ExceptionMap.get(exc_type) orelse "GenericError";
}
