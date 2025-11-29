/// Analyze whether a function needs an allocator parameter
/// Functions need allocator if they perform operations that allocate memory
const std = @import("std");
const ast = @import("ast");

// ComptimeStringMaps for O(1) lookup + DCE optimization

/// Methods that use allocator param (string/list mutations)
const AllocatorMethods = std.StaticStringMap(void).initComptime(.{
    .{ "upper", {} },
    .{ "lower", {} },
    .{ "strip", {} },
    .{ "split", {} },
    .{ "replace", {} },
    .{ "join", {} },
    .{ "format", {} },
    .{ "append", {} },
    .{ "extend", {} },
    .{ "insert", {} },
    // StringIO/BytesIO methods
    .{ "write", {} },
    .{ "getvalue", {} },
});

/// unittest assertion methods - these don't need allocator
const UnittestAssertions = std.StaticStringMap(void).initComptime(.{
    .{ "assertEqual", {} },
    .{ "assertTrue", {} },
    .{ "assertFalse", {} },
    .{ "assertIsNone", {} },
    .{ "assertGreater", {} },
    .{ "assertLess", {} },
    .{ "assertGreaterEqual", {} },
    .{ "assertLessEqual", {} },
    .{ "assertNotEqual", {} },
    .{ "assertIs", {} },
    .{ "assertIsNot", {} },
    .{ "assertIsNotNone", {} },
    .{ "assertIn", {} },
    .{ "assertNotIn", {} },
    .{ "assertAlmostEqual", {} },
    .{ "assertNotAlmostEqual", {} },
    .{ "assertCountEqual", {} },
    .{ "assertRaises", {} },
    .{ "assertRegex", {} },
    .{ "assertNotRegex", {} },
    .{ "assertIsInstance", {} },
    .{ "assertNotIsInstance", {} },
    .{ "subTest", {} },
});

/// Built-in functions that use allocator param
const AllocatorBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "str", {} },
    .{ "list", {} },
    .{ "dict", {} },
    .{ "format", {} },
    .{ "input", {} },
    .{ "StringIO", {} },
    .{ "BytesIO", {} },
    // collections module
    .{ "Counter", {} },
    .{ "deque", {} },
    .{ "defaultdict", {} },
    .{ "OrderedDict", {} },
});

/// Functions that return strings (for mightBeString)
const StringReturningFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "str", {} },
    .{ "input", {} },
});

/// String methods (for mightBeString)
const StringMethods = std.StaticStringMap(void).initComptime(.{
    .{ "upper", {} },
    .{ "lower", {} },
    .{ "strip", {} },
    .{ "lstrip", {} },
    .{ "rstrip", {} },
    .{ "split", {} },
    .{ "join", {} },
    .{ "replace", {} },
    .{ "format", {} },
    .{ "capitalize", {} },
    .{ "title", {} },
    .{ "swapcase", {} },
    .{ "center", {} },
    .{ "ljust", {} },
    .{ "rjust", {} },
    .{ "encode", {} },
    .{ "decode", {} },
});

/// Check if a function needs an allocator parameter (for error union return type)
pub fn functionNeedsAllocator(func: ast.Node.FunctionDef) bool {
    // First, collect names of nested classes defined in this function
    var nested_classes: [32][]const u8 = undefined;
    var nested_class_count: usize = 0;
    collectNestedClassNames(func.body, &nested_classes, &nested_class_count);

    // If there are nested classes, check if they're instantiated
    if (nested_class_count > 0) {
        if (hasNestedClassCalls(func.body, nested_classes[0..nested_class_count])) {
            return true;
        }
    }

    for (func.body) |stmt| {
        if (stmtNeedsAllocator(stmt)) return true;
    }
    return false;
}

/// Check if statements contain calls to any nested class constructors
fn hasNestedClassCalls(stmts: []ast.Node, nested_classes: []const []const u8) bool {
    for (stmts) |stmt| {
        if (stmtHasNestedClassCall(stmt, nested_classes)) return true;
    }
    return false;
}

fn stmtHasNestedClassCall(stmt: ast.Node, nested_classes: []const []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprHasNestedClassCall(e.value.*, nested_classes),
        .assign => |a| exprHasNestedClassCall(a.value.*, nested_classes),
        .aug_assign => |a| exprHasNestedClassCall(a.value.*, nested_classes),
        .return_stmt => |r| if (r.value) |v| exprHasNestedClassCall(v.*, nested_classes) else false,
        .if_stmt => |i| {
            if (exprHasNestedClassCall(i.condition.*, nested_classes)) return true;
            if (hasNestedClassCalls(i.body, nested_classes)) return true;
            if (hasNestedClassCalls(i.else_body, nested_classes)) return true;
            return false;
        },
        .while_stmt => |w| {
            if (exprHasNestedClassCall(w.condition.*, nested_classes)) return true;
            return hasNestedClassCalls(w.body, nested_classes);
        },
        .for_stmt => |f| {
            if (exprHasNestedClassCall(f.iter.*, nested_classes)) return true;
            return hasNestedClassCalls(f.body, nested_classes);
        },
        .try_stmt => |t| {
            if (hasNestedClassCalls(t.body, nested_classes)) return true;
            for (t.handlers) |h| {
                if (hasNestedClassCalls(h.body, nested_classes)) return true;
            }
            return false;
        },
        .with_stmt => |w| {
            if (exprHasNestedClassCall(w.context_expr.*, nested_classes)) return true;
            return hasNestedClassCalls(w.body, nested_classes);
        },
        else => false,
    };
}

fn exprHasNestedClassCall(expr: ast.Node, nested_classes: []const []const u8) bool {
    return switch (expr) {
        .call => |c| {
            // Check if this is a call to a nested class
            if (c.func.* == .name) {
                const called_name = c.func.name.id;
                for (nested_classes) |class_name| {
                    if (std.mem.eql(u8, called_name, class_name)) return true;
                }
            }
            // Check call arguments recursively
            for (c.args) |arg| {
                if (exprHasNestedClassCall(arg, nested_classes)) return true;
            }
            // Check function expression
            return exprHasNestedClassCall(c.func.*, nested_classes);
        },
        .binop => |b| exprHasNestedClassCall(b.left.*, nested_classes) or exprHasNestedClassCall(b.right.*, nested_classes),
        .unaryop => |u| exprHasNestedClassCall(u.operand.*, nested_classes),
        .attribute => |a| exprHasNestedClassCall(a.value.*, nested_classes),
        .subscript => |s| {
            if (exprHasNestedClassCall(s.value.*, nested_classes)) return true;
            return switch (s.slice) {
                .index => |idx| exprHasNestedClassCall(idx.*, nested_classes),
                .slice => |rng| {
                    if (rng.lower) |l| if (exprHasNestedClassCall(l.*, nested_classes)) return true;
                    if (rng.upper) |u| if (exprHasNestedClassCall(u.*, nested_classes)) return true;
                    if (rng.step) |st| if (exprHasNestedClassCall(st.*, nested_classes)) return true;
                    return false;
                },
            };
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                if (exprHasNestedClassCall(elt, nested_classes)) return true;
            }
            return false;
        },
        .list => |l| {
            for (l.elts) |elt| {
                if (exprHasNestedClassCall(elt, nested_classes)) return true;
            }
            return false;
        },
        .compare => |co| {
            if (exprHasNestedClassCall(co.left.*, nested_classes)) return true;
            for (co.comparators) |comp| {
                if (exprHasNestedClassCall(comp, nested_classes)) return true;
            }
            return false;
        },
        else => false,
    };
}

/// Check if function actually uses the 'allocator' param (not just __global_allocator)
/// Dict literals use __global_allocator so they don't actually use the param
/// Also returns true for recursive calls since they pass allocator to self
pub fn functionActuallyUsesAllocatorParam(func: ast.Node.FunctionDef) bool {
    // First, collect names of nested classes defined in this function
    var nested_classes: [32][]const u8 = undefined;
    var nested_class_count: usize = 0;
    collectNestedClassNames(func.body, &nested_classes, &nested_class_count);

    for (func.body) |stmt| {
        if (stmtUsesAllocatorParamWithClasses(stmt, func.name, nested_classes[0..nested_class_count])) return true;
    }
    return false;
}

/// Collect names of nested class definitions in statements
fn collectNestedClassNames(stmts: []ast.Node, names: *[32][]const u8, count: *usize) void {
    for (stmts) |stmt| {
        switch (stmt) {
            .class_def => |c| {
                if (count.* < 32) {
                    names[count.*] = c.name;
                    count.* += 1;
                }
            },
            .if_stmt => |i| {
                collectNestedClassNames(i.body, names, count);
                collectNestedClassNames(i.else_body, names, count);
            },
            .for_stmt => |f| {
                collectNestedClassNames(f.body, names, count);
            },
            .while_stmt => |w| {
                collectNestedClassNames(w.body, names, count);
            },
            .try_stmt => |t| {
                collectNestedClassNames(t.body, names, count);
                for (t.handlers) |h| {
                    collectNestedClassNames(h.body, names, count);
                }
            },
            .with_stmt => |w| {
                collectNestedClassNames(w.body, names, count);
            },
            else => {},
        }
    }
}

/// Check if a call is to a nested class constructor
fn isNestedClassCall(call: ast.Node.Call, nested_classes: []const []const u8) bool {
    if (call.func.* == .name) {
        const called_name = call.func.name.id;
        for (nested_classes) |class_name| {
            if (std.mem.eql(u8, called_name, class_name)) return true;
        }
    }
    return false;
}

/// Check if a statement uses the allocator parameter
/// func_name is passed to detect recursive calls
fn stmtUsesAllocatorParam(stmt: ast.Node, func_name: []const u8) bool {
    return stmtUsesAllocatorParamWithClasses(stmt, func_name, &[_][]const u8{});
}

/// Check if a statement uses the allocator parameter (with nested class tracking)
fn stmtUsesAllocatorParamWithClasses(stmt: ast.Node, func_name: []const u8, nested_classes: []const []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprUsesAllocatorParamWithClasses(e.value.*, func_name, nested_classes),
        .assign => |a| exprUsesAllocatorParamWithClasses(a.value.*, func_name, nested_classes),
        .aug_assign => |a| exprUsesAllocatorParamWithClasses(a.value.*, func_name, nested_classes),
        .return_stmt => |r| if (r.value) |v| exprUsesAllocatorParamWithClasses(v.*, func_name, nested_classes) else false,
        .if_stmt => |i| {
            if (exprUsesAllocatorParamWithClasses(i.condition.*, func_name, nested_classes)) return true;
            for (i.body) |s| {
                if (stmtUsesAllocatorParamWithClasses(s, func_name, nested_classes)) return true;
            }
            for (i.else_body) |s| {
                if (stmtUsesAllocatorParamWithClasses(s, func_name, nested_classes)) return true;
            }
            return false;
        },
        .while_stmt => |w| {
            if (exprUsesAllocatorParamWithClasses(w.condition.*, func_name, nested_classes)) return true;
            for (w.body) |s| {
                if (stmtUsesAllocatorParamWithClasses(s, func_name, nested_classes)) return true;
            }
            return false;
        },
        .for_stmt => |f| {
            if (exprUsesAllocatorParamWithClasses(f.iter.*, func_name, nested_classes)) return true;
            for (f.body) |s| {
                if (stmtUsesAllocatorParamWithClasses(s, func_name, nested_classes)) return true;
            }
            return false;
        },
        .try_stmt => |t| {
            for (t.body) |s| {
                if (stmtUsesAllocatorParamWithClasses(s, func_name, nested_classes)) return true;
            }
            for (t.handlers) |h| {
                for (h.body) |s| {
                    if (stmtUsesAllocatorParamWithClasses(s, func_name, nested_classes)) return true;
                }
            }
            return false;
        },
        .class_def => |c| {
            // Check if the class body itself uses allocator param
            for (c.body) |s| {
                if (stmtUsesAllocatorParamWithClasses(s, func_name, nested_classes)) return true;
            }
            return false;
        },
        .with_stmt => |w| {
            if (exprUsesAllocatorParamWithClasses(w.context_expr.*, func_name, nested_classes)) return true;
            for (w.body) |s| {
                if (stmtUsesAllocatorParamWithClasses(s, func_name, nested_classes)) return true;
            }
            return false;
        },
        else => false,
    };
}

/// Check if an expression actually uses the allocator param
/// func_name is passed to detect recursive calls
fn exprUsesAllocatorParam(expr: ast.Node, func_name: []const u8) bool {
    return exprUsesAllocatorParamWithClasses(expr, func_name, &[_][]const u8{});
}

/// Check if an expression actually uses the allocator param (with nested class tracking)
fn exprUsesAllocatorParamWithClasses(expr: ast.Node, func_name: []const u8, nested_classes: []const []const u8) bool {
    return switch (expr) {
        .binop => |b| {
            // String concatenation uses __global_allocator, not the function's allocator param
            // So we don't mark it as using allocator param
            return exprUsesAllocatorParamWithClasses(b.left.*, func_name, nested_classes) or exprUsesAllocatorParamWithClasses(b.right.*, func_name, nested_classes);
        },
        .call => |c| callUsesAllocatorParamWithClasses(c, func_name, nested_classes),
        // F-strings use __global_allocator, not the function's allocator param
        .fstring => false,
        .listcomp => true,
        .dictcomp => true,
        .list => |l| {
            // List literals use __global_allocator, not the passed allocator param
            // (same as dict and fstring)
            for (l.elts) |elt| {
                if (exprUsesAllocatorParamWithClasses(elt, func_name, nested_classes)) return true;
            }
            return false;
        },
        // Dict uses __global_allocator, not the passed allocator param
        .dict => false,
        .tuple => |t| {
            for (t.elts) |elt| {
                if (exprUsesAllocatorParamWithClasses(elt, func_name, nested_classes)) return true;
            }
            return false;
        },
        .subscript => |s| {
            if (exprUsesAllocatorParamWithClasses(s.value.*, func_name, nested_classes)) return true;
            return switch (s.slice) {
                .index => |idx| exprUsesAllocatorParamWithClasses(idx.*, func_name, nested_classes),
                .slice => |rng| {
                    if (rng.lower) |l| if (exprUsesAllocatorParamWithClasses(l.*, func_name, nested_classes)) return true;
                    if (rng.upper) |u| if (exprUsesAllocatorParamWithClasses(u.*, func_name, nested_classes)) return true;
                    if (rng.step) |st| if (exprUsesAllocatorParamWithClasses(st.*, func_name, nested_classes)) return true;
                    return false;
                },
            };
        },
        .attribute => |a| exprUsesAllocatorParamWithClasses(a.value.*, func_name, nested_classes),
        .compare => |c| {
            if (exprUsesAllocatorParamWithClasses(c.left.*, func_name, nested_classes)) return true;
            for (c.comparators) |comp| {
                if (exprUsesAllocatorParamWithClasses(comp, func_name, nested_classes)) return true;
            }
            return false;
        },
        .boolop => |b| {
            for (b.values) |val| {
                if (exprUsesAllocatorParamWithClasses(val, func_name, nested_classes)) return true;
            }
            return false;
        },
        .unaryop => |u| exprUsesAllocatorParamWithClasses(u.operand.*, func_name, nested_classes),
        .name => |n| {
            // Check if this is a reference to 'allocator' param
            return std.mem.eql(u8, n.id, "allocator");
        },
        .if_expr => |ie| {
            return exprUsesAllocatorParamWithClasses(ie.body.*, func_name, nested_classes) or
                exprUsesAllocatorParamWithClasses(ie.orelse_value.*, func_name, nested_classes) or
                exprUsesAllocatorParamWithClasses(ie.condition.*, func_name, nested_classes);
        },
        else => false,
    };
}

/// Builtins that use __global_allocator instead of param (don't count as using param)
const GlobalAllocatorBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "str", {} }, // str() uses __global_allocator in codegen
    .{ "print", {} }, // print with string concat uses __global_allocator
    .{ "eval", {} }, // runtime.eval() uses __global_allocator
    .{ "exec", {} }, // exec() uses __global_allocator
    .{ "compile", {} }, // compile() uses __global_allocator
});

/// Module functions that use the allocator param in generated code
/// These module.function() calls generate code using `allocator` variable
const ModuleFunctionsUsingAllocator = std.StaticStringMap(void).initComptime(.{
    // json module
    .{ "dumps", {} },
    .{ "loads", {} },
    // re module
    .{ "match", {} },
    .{ "search", {} },
    .{ "findall", {} },
    .{ "sub", {} },
    .{ "split", {} },
    .{ "compile", {} },
    // gzip module
    .{ "compress", {} },
    .{ "decompress", {} },
    // zlib module
    .{ "crc32", {} },
    .{ "adler32", {} },
});

/// Builtin classes/constructors that use allocator in generated code
const AllocatorConstructors = std.StaticStringMap(void).initComptime(.{
    // collections module
    .{ "Counter", {} },
    .{ "deque", {} },
    .{ "defaultdict", {} },
    .{ "OrderedDict", {} },
    // io module
    .{ "StringIO", {} },
    .{ "BytesIO", {} },
});

/// Check if a call uses allocator param
/// func_name is the current function name to detect recursive calls
fn callUsesAllocatorParam(call: ast.Node.Call, func_name: []const u8) bool {
    return callUsesAllocatorParamWithClasses(call, func_name, &[_][]const u8{});
}

/// Check if a call uses allocator param (with nested class tracking)
fn callUsesAllocatorParamWithClasses(call: ast.Node.Call, func_name: []const u8, nested_classes: []const []const u8) bool {
    // ALWAYS check arguments first - even unittest assertions may have args that use allocator
    for (call.args) |arg| {
        if (exprUsesAllocatorParamWithClasses(arg, func_name, nested_classes)) return true;
    }

    if (call.func.* == .attribute) {
        const method_name = call.func.attribute.attr;
        if (AllocatorMethods.has(method_name)) return true;

        // unittest assertion methods don't use allocator themselves
        if (UnittestAssertions.has(method_name)) return false;

        // Check if this is a module function that uses allocator param
        if (call.func.attribute.value.* == .name) {
            const obj_name = call.func.attribute.value.name.id;
            // json.dumps(), json.loads(), re.match(), etc. use allocator param
            if (ModuleFunctionsUsingAllocator.has(method_name) and
                !std.mem.eql(u8, obj_name, "self"))
            {
                return true;
            }
            // Other module.function() calls use __global_allocator, not the param
            return false;
        }
    }
    if (call.func.* == .name) {
        const called_name = call.func.name.id;
        // Skip builtins that use __global_allocator instead of the param
        if (GlobalAllocatorBuiltins.has(called_name)) return false;
        // Recursive call: function calls itself, allocator will be passed
        if (std.mem.eql(u8, called_name, func_name)) return true;
        if (AllocatorBuiltins.has(called_name)) return true;
        // Constructor calls that use allocator (Counter, deque, etc.)
        if (AllocatorConstructors.has(called_name)) return true;
        // Nested class constructor calls: Foo() where Foo is a class defined in this function
        for (nested_classes) |class_name| {
            if (std.mem.eql(u8, called_name, class_name)) return true;
        }
    }
    return false;
}

/// Check if a statement needs allocator
fn stmtNeedsAllocator(stmt: ast.Node) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprNeedsAllocator(e.value.*),
        .assign => |a| {
            // Check if target is self.attr (becomes __dict__.put which can fail)
            for (a.targets) |target| {
                if (target == .attribute) {
                    const attr = target.attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        return true; // self.attr = value uses __dict__.put() which can fail
                    }
                }
            }
            return exprNeedsAllocator(a.value.*);
        },
        .aug_assign => |a| exprNeedsAllocator(a.value.*),
        .return_stmt => |r| if (r.value) |v| exprNeedsAllocator(v.*) else false,
        .if_stmt => |i| {
            // Check condition
            if (exprNeedsAllocator(i.condition.*)) return true;
            // Check body
            for (i.body) |s| {
                if (stmtNeedsAllocator(s)) return true;
            }
            // Check else body
            for (i.else_body) |s| {
                if (stmtNeedsAllocator(s)) return true;
            }
            return false;
        },
        .while_stmt => |w| {
            // Check condition
            if (exprNeedsAllocator(w.condition.*)) return true;
            // Check body
            for (w.body) |s| {
                if (stmtNeedsAllocator(s)) return true;
            }
            return false;
        },
        .for_stmt => |f| {
            // Check iterator
            if (exprNeedsAllocator(f.iter.*)) return true;
            // Check body
            for (f.body) |s| {
                if (stmtNeedsAllocator(s)) return true;
            }
            return false;
        },
        .try_stmt => |t| {
            // Check body
            for (t.body) |s| {
                if (stmtNeedsAllocator(s)) return true;
            }
            // Check handlers
            for (t.handlers) |h| {
                for (h.body) |s| {
                    if (stmtNeedsAllocator(s)) return true;
                }
            }
            return false;
        },
        .class_def => |c| {
            // Check if the class body itself needs allocator
            // Don't automatically mark as needing allocator just because there's a class
            for (c.body) |s| {
                if (stmtNeedsAllocator(s)) return true;
            }
            return false;
        },
        .with_stmt => |w| {
            // Check context expression
            if (exprNeedsAllocator(w.context_expr.*)) return true;
            // Check body
            for (w.body) |s| {
                if (stmtNeedsAllocator(s)) return true;
            }
            return false;
        },
        else => false,
    };
}

/// Check if an expression needs allocator (or is otherwise fallible)
fn exprNeedsAllocator(expr: ast.Node) bool {
    return switch (expr) {
        .binop => |b| {
            // String concatenation needs allocator
            if (b.op == .Add) {
                // Check if operands might be strings
                if (mightBeString(b.left.*) or mightBeString(b.right.*)) {
                    return true;
                }
            }
            // Division can fail with ZeroDivisionError
            if (b.op == .Div or b.op == .FloorDiv or b.op == .Mod) {
                return true;
            }
            // Check nested expressions
            return exprNeedsAllocator(b.left.*) or exprNeedsAllocator(b.right.*);
        },
        .call => |c| callNeedsAllocator(c),
        .fstring => true, // F-strings always need allocator
        .listcomp => true, // List comprehensions need allocator
        .dictcomp => true, // Dict comprehensions need allocator
        .list => |l| {
            // List literals with elements need allocator for ArrayList creation
            if (l.elts.len > 0) return true;
            // Check if any elements need allocator
            for (l.elts) |elt| {
                if (exprNeedsAllocator(elt)) return true;
            }
            return false;
        },
        .dict => true, // Dict literals need error union return type (HashMap.put can fail)
        .tuple => |t| {
            // Check if any elements need allocator
            for (t.elts) |elt| {
                if (exprNeedsAllocator(elt)) return true;
            }
            return false;
        },
        .subscript => |s| {
            // Check object
            if (exprNeedsAllocator(s.value.*)) return true;
            // Check slice/index
            return switch (s.slice) {
                .index => |idx| exprNeedsAllocator(idx.*),
                .slice => |rng| {
                    if (rng.lower) |l| if (exprNeedsAllocator(l.*)) return true;
                    if (rng.upper) |u| if (exprNeedsAllocator(u.*)) return true;
                    if (rng.step) |st| if (exprNeedsAllocator(st.*)) return true;
                    return false;
                },
            };
        },
        .attribute => |a| exprNeedsAllocator(a.value.*),
        .compare => |c| {
            // Check left side
            if (exprNeedsAllocator(c.left.*)) return true;
            // Check comparators
            for (c.comparators) |comp| {
                if (exprNeedsAllocator(comp)) return true;
            }
            return false;
        },
        .boolop => |b| {
            for (b.values) |val| {
                if (exprNeedsAllocator(val)) return true;
            }
            return false;
        },
        .unaryop => |u| exprNeedsAllocator(u.operand.*),
        else => false,
    };
}

/// Check if a call needs allocator
fn callNeedsAllocator(call: ast.Node.Call) bool {
    // Check if this is a method call that needs allocator
    if (call.func.* == .attribute) {
        const method_name = call.func.attribute.attr;
        if (AllocatorMethods.has(method_name)) return true;

        // Module function call (e.g., test_utils.double(x))
        // Codegen passes allocator to imported module functions
        // But NOT self.method() calls - those are instance method calls
        if (call.func.attribute.value.* == .name) {
            const obj_name = call.func.attribute.value.name.id;
            // Any module.function() call (except self.) will receive allocator param in codegen
            if (!std.mem.eql(u8, obj_name, "self")) return true;
        }
    }

    // Check if this is a built-in that needs allocator
    if (call.func.* == .name) {
        const fn_name = call.func.name.id;
        if (AllocatorBuiltins.has(fn_name)) return true;
    }

    // Check arguments recursively - even unittest assertions may have fallible args (e.g., division)
    for (call.args) |arg| {
        if (exprNeedsAllocator(arg)) return true;
    }

    return false;
}

/// Check if an expression might be a string
/// Conservative: only returns true if we're CERTAIN it's a string
fn mightBeString(expr: ast.Node) bool {
    return switch (expr) {
        .constant => |c| c.value == .string,
        .fstring => true,
        .name => false, // Be conservative - don't assume names are strings
        .call => |ca| {
            // Check if this is str() or a string method
            if (ca.func.* == .name) {
                const fn_name = ca.func.name.id;
                if (StringReturningFuncs.has(fn_name)) return true;
            }
            if (ca.func.* == .attribute) {
                const method_name = ca.func.attribute.attr;
                if (StringMethods.has(method_name)) return true;
            }
            return false;
        },
        .binop => |b| {
            // If it's addition and either side might be string, result might be string
            if (b.op == .Add) {
                return mightBeString(b.left.*) or mightBeString(b.right.*);
            }
            return false;
        },
        .subscript => false, // Be conservative
        .attribute => false, // Be conservative
        else => false,
    };
}
