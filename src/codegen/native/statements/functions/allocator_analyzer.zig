/// Analyze whether a function needs an allocator parameter
/// Functions need allocator if they perform operations that allocate memory
const std = @import("std");
const ast = @import("../../../../ast.zig");

/// Check if a function needs an allocator parameter (for error union return type)
pub fn functionNeedsAllocator(func: ast.Node.FunctionDef) bool {
    for (func.body) |stmt| {
        if (stmtNeedsAllocator(stmt)) return true;
    }
    return false;
}

/// Check if function actually uses the 'allocator' param (not just __global_allocator)
/// Dict literals use __global_allocator so they don't actually use the param
pub fn functionActuallyUsesAllocatorParam(func: ast.Node.FunctionDef) bool {
    for (func.body) |stmt| {
        if (stmtUsesAllocatorParam(stmt)) return true;
    }
    return false;
}

/// Check if a statement uses the allocator parameter
fn stmtUsesAllocatorParam(stmt: ast.Node) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprUsesAllocatorParam(e.value.*),
        .assign => |a| exprUsesAllocatorParam(a.value.*),
        .aug_assign => |a| exprUsesAllocatorParam(a.value.*),
        .return_stmt => |r| if (r.value) |v| exprUsesAllocatorParam(v.*) else false,
        .if_stmt => |i| {
            if (exprUsesAllocatorParam(i.condition.*)) return true;
            for (i.body) |s| {
                if (stmtUsesAllocatorParam(s)) return true;
            }
            for (i.else_body) |s| {
                if (stmtUsesAllocatorParam(s)) return true;
            }
            return false;
        },
        .while_stmt => |w| {
            if (exprUsesAllocatorParam(w.condition.*)) return true;
            for (w.body) |s| {
                if (stmtUsesAllocatorParam(s)) return true;
            }
            return false;
        },
        .for_stmt => |f| {
            if (exprUsesAllocatorParam(f.iter.*)) return true;
            for (f.body) |s| {
                if (stmtUsesAllocatorParam(s)) return true;
            }
            return false;
        },
        .try_stmt => |t| {
            for (t.body) |s| {
                if (stmtUsesAllocatorParam(s)) return true;
            }
            for (t.handlers) |h| {
                for (h.body) |s| {
                    if (stmtUsesAllocatorParam(s)) return true;
                }
            }
            return false;
        },
        else => false,
    };
}

/// Check if an expression actually uses the allocator param
fn exprUsesAllocatorParam(expr: ast.Node) bool {
    return switch (expr) {
        .binop => |b| {
            // String concatenation uses allocator param
            if (b.op == .Add) {
                if (mightBeString(b.left.*) or mightBeString(b.right.*)) {
                    return true;
                }
            }
            return exprUsesAllocatorParam(b.left.*) or exprUsesAllocatorParam(b.right.*);
        },
        .call => |c| callUsesAllocatorParam(c),
        .fstring => true,
        .listcomp => true,
        .dictcomp => true,
        .list => |l| {
            for (l.elts) |elt| {
                if (exprUsesAllocatorParam(elt)) return true;
            }
            return false;
        },
        // Dict uses __global_allocator, not the passed allocator param
        .dict => false,
        .tuple => |t| {
            for (t.elts) |elt| {
                if (exprUsesAllocatorParam(elt)) return true;
            }
            return false;
        },
        .subscript => |s| {
            if (exprUsesAllocatorParam(s.value.*)) return true;
            return switch (s.slice) {
                .index => |idx| exprUsesAllocatorParam(idx.*),
                .slice => |rng| {
                    if (rng.lower) |l| if (exprUsesAllocatorParam(l.*)) return true;
                    if (rng.upper) |u| if (exprUsesAllocatorParam(u.*)) return true;
                    if (rng.step) |st| if (exprUsesAllocatorParam(st.*)) return true;
                    return false;
                },
            };
        },
        .attribute => |a| exprUsesAllocatorParam(a.value.*),
        .compare => |c| {
            if (exprUsesAllocatorParam(c.left.*)) return true;
            for (c.comparators) |comp| {
                if (exprUsesAllocatorParam(comp)) return true;
            }
            return false;
        },
        .boolop => |b| {
            for (b.values) |val| {
                if (exprUsesAllocatorParam(val)) return true;
            }
            return false;
        },
        .unaryop => |u| exprUsesAllocatorParam(u.operand.*),
        else => false,
    };
}

/// Check if a call uses allocator param
fn callUsesAllocatorParam(call: ast.Node.Call) bool {
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;
        const method_name = attr.attr;
        if (std.mem.eql(u8, method_name, "upper") or
            std.mem.eql(u8, method_name, "lower") or
            std.mem.eql(u8, method_name, "strip") or
            std.mem.eql(u8, method_name, "split") or
            std.mem.eql(u8, method_name, "replace") or
            std.mem.eql(u8, method_name, "join") or
            std.mem.eql(u8, method_name, "format") or
            std.mem.eql(u8, method_name, "append") or
            std.mem.eql(u8, method_name, "extend") or
            std.mem.eql(u8, method_name, "insert"))
        {
            return true;
        }
    }
    if (call.func.* == .name) {
        const func_name = call.func.name.id;
        if (std.mem.eql(u8, func_name, "str") or
            std.mem.eql(u8, func_name, "list") or
            std.mem.eql(u8, func_name, "dict") or
            std.mem.eql(u8, func_name, "format") or
            std.mem.eql(u8, func_name, "input"))
        {
            return true;
        }
    }
    for (call.args) |arg| {
        if (exprUsesAllocatorParam(arg)) return true;
    }
    return false;
}

/// Check if a statement needs allocator
fn stmtNeedsAllocator(stmt: ast.Node) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprNeedsAllocator(e.value.*),
        .assign => |a| exprNeedsAllocator(a.value.*),
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
        else => false,
    };
}

/// Check if an expression needs allocator
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
            // Check nested expressions
            return exprNeedsAllocator(b.left.*) or exprNeedsAllocator(b.right.*);
        },
        .call => |c| callNeedsAllocator(c),
        .fstring => true, // F-strings always need allocator
        .listcomp => true, // List comprehensions need allocator
        .dictcomp => true, // Dict comprehensions need allocator
        .list => |l| {
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
        const attr = call.func.attribute;
        const method_name = attr.attr;

        // String methods that return new strings
        if (std.mem.eql(u8, method_name, "upper") or
            std.mem.eql(u8, method_name, "lower") or
            std.mem.eql(u8, method_name, "strip") or
            std.mem.eql(u8, method_name, "split") or
            std.mem.eql(u8, method_name, "replace") or
            std.mem.eql(u8, method_name, "join") or
            std.mem.eql(u8, method_name, "format"))
        {
            return true;
        }

        // List methods that mutate (need allocator for ArrayList)
        if (std.mem.eql(u8, method_name, "append") or
            std.mem.eql(u8, method_name, "extend") or
            std.mem.eql(u8, method_name, "insert"))
        {
            return true;
        }
    }

    // Check if this is a built-in that needs allocator
    if (call.func.* == .name) {
        const func_name = call.func.name.id;

        // Built-ins that need allocator
        if (std.mem.eql(u8, func_name, "str") or
            std.mem.eql(u8, func_name, "list") or
            std.mem.eql(u8, func_name, "dict") or
            std.mem.eql(u8, func_name, "format") or
            std.mem.eql(u8, func_name, "input"))
        {
            return true;
        }
    }

    // Check arguments recursively
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
                const func_name = ca.func.name.id;
                if (std.mem.eql(u8, func_name, "str") or
                    std.mem.eql(u8, func_name, "input"))
                {
                    return true;
                }
            }
            if (ca.func.* == .attribute) {
                // String methods return strings
                const method_name = ca.func.attribute.attr;
                // Only flag known string methods
                const string_methods = [_][]const u8{
                    "upper",    "lower",  "strip",   "lstrip", "rstrip",
                    "split",    "join",   "replace", "format", "capitalize",
                    "title",    "swapcase", "center", "ljust", "rjust",
                    "encode",   "decode",
                };
                for (string_methods) |method| {
                    if (std.mem.eql(u8, method_name, method)) return true;
                }
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
