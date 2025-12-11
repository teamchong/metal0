/// Variable mutation analysis - Determine var vs const for local variables
/// Zig 0.15 requires `const` for variables that are never mutated.
/// A variable needs `var` if:
/// 1. It's reassigned after initial declaration (multiple assignments)
/// 2. It's used in augmented assignment (+=, -=, etc.)
/// 3. It's an iterator (mutated by .next() calls)
///
/// Note: Dict/list method calls (.put(), .append()) don't require `var` -
/// these methods take *Self and mutate through the pointer.
const std = @import("std");
const ast = @import("analysis.ast");

/// Set of mutated variable names (up to 64 variables)
pub const MutatedVarSet = struct {
    names: [64][]const u8 = undefined,
    count: usize = 0,

    pub fn add(self: *MutatedVarSet, name: []const u8) void {
        // Don't add duplicates
        for (self.names[0..self.count]) |existing| {
            if (std.mem.eql(u8, existing, name)) return;
        }
        if (self.count < 64) {
            self.names[self.count] = name;
            self.count += 1;
        }
    }

    pub fn contains(self: *const MutatedVarSet, name: []const u8) bool {
        for (self.names[0..self.count]) |existing| {
            if (std.mem.eql(u8, existing, name)) return true;
        }
        return false;
    }
};

/// Analyze a function body for variable mutations
/// Returns a set of variable names that are mutated (need `var`)
pub fn analyzeMutatedVars(body: []const ast.Node) MutatedVarSet {
    var result = MutatedVarSet{};
    collectMutatedVars(body, &result, null);
    return result;
}

/// Collect mutated variables from function body
/// first_assign tracks which variables have been seen (for detecting reassignment)
fn collectMutatedVars(body: []const ast.Node, result: *MutatedVarSet, first_assign: ?*MutatedVarSet) void {
    var seen = if (first_assign) |fa| fa.* else MutatedVarSet{};

    for (body) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                // Check for reassignment (variable assigned more than once)
                for (assign.targets) |target| {
                    if (target == .name) {
                        const name = target.name.id;
                        if (seen.contains(name)) {
                            // Reassigned - needs var
                            result.add(name);
                        } else {
                            seen.add(name);
                        }
                    }
                }
            },
            .aug_assign => |aug| {
                // Augmented assignment always needs var
                if (aug.target.* == .name) {
                    result.add(aug.target.name.id);
                }
            },
            .for_stmt => |for_stmt| {
                // Loop variable is reassigned each iteration
                if (for_stmt.target.* == .name) {
                    result.add(for_stmt.target.name.id);
                }
                // Recurse into body with current seen state
                collectMutatedVars(for_stmt.body, result, &seen);
                if (for_stmt.orelse_body) |orelse_body| {
                    collectMutatedVars(orelse_body, result, &seen);
                }
            },
            .while_stmt => |while_stmt| {
                collectMutatedVars(while_stmt.body, result, &seen);
                if (while_stmt.orelse_body) |orelse_body| {
                    collectMutatedVars(orelse_body, result, &seen);
                }
            },
            .if_stmt => |if_stmt| {
                collectMutatedVars(if_stmt.body, result, &seen);
                collectMutatedVars(if_stmt.else_body, result, &seen);
            },
            .try_stmt => |try_stmt| {
                collectMutatedVars(try_stmt.body, result, &seen);
                collectMutatedVars(try_stmt.else_body, result, &seen);
                collectMutatedVars(try_stmt.finalbody, result, &seen);
            },
            .with_stmt => |with_stmt| {
                collectMutatedVars(with_stmt.body, result, &seen);
            },
            .function_def => {
                // Don't recurse into nested function definitions -
                // they have their own scope
            },
            .class_def => {
                // Don't recurse into class definitions
            },
            else => {},
        }
    }
}

/// Check if a variable is mutated in a function body
pub fn isVarMutatedInBody(body: []const ast.Node, var_name: []const u8) bool {
    const mutated = analyzeMutatedVars(body);
    return mutated.contains(var_name);
}

/// Track which variables are actually used (read) in a function body
/// This is for determining if `_ = var;` discard is needed
pub const UsedVarsSet = struct {
    names: [128][]const u8 = undefined,
    count: usize = 0,

    pub fn add(self: *UsedVarsSet, name: []const u8) void {
        if (!self.contains(name) and self.count < 128) {
            self.names[self.count] = name;
            self.count += 1;
        }
    }

    pub fn contains(self: *const UsedVarsSet, name: []const u8) bool {
        for (self.names[0..self.count]) |n| {
            if (std.mem.eql(u8, n, name)) return true;
        }
        return false;
    }
};

/// Analyze which variables are actually read (used) in a function body
/// Excludes LHS of assignments (those are writes, not reads)
pub fn analyzeUsedVars(body: []const ast.Node) UsedVarsSet {
    var result = UsedVarsSet{};
    for (body) |stmt| {
        collectUsedVars(stmt, &result);
    }
    return result;
}

fn collectUsedVars(node: ast.Node, result: *UsedVarsSet) void {
    switch (node) {
        .name => |name| result.add(name.id),
        .attribute => |attr| collectUsedVars(attr.value.*, result),
        .subscript => |sub| {
            collectUsedVars(sub.value.*, result);
            collectUsedVars(sub.slice.*, result);
        },
        .call => |call| {
            collectUsedVars(call.func.*, result);
            for (call.args) |arg| collectUsedVars(arg, result);
            for (call.keywords) |kw| {
                if (kw.value) |v| collectUsedVars(v.*, result);
            }
        },
        .binop => |binop| {
            collectUsedVars(binop.left.*, result);
            collectUsedVars(binop.right.*, result);
        },
        .unaryop => |unary| collectUsedVars(unary.operand.*, result),
        .compare => |cmp| {
            collectUsedVars(cmp.left.*, result);
            for (cmp.comparators) |c| collectUsedVars(c, result);
        },
        .boolop => |boolop| {
            for (boolop.values) |v| collectUsedVars(v, result);
        },
        .ifexp => |ifexp| {
            collectUsedVars(ifexp.condition.*, result);
            collectUsedVars(ifexp.body.*, result);
            collectUsedVars(ifexp.@"orelse".*, result);
        },
        .list => |list| {
            for (list.elts) |e| collectUsedVars(e, result);
        },
        .tuple => |tuple| {
            for (tuple.elts) |e| collectUsedVars(e, result);
        },
        .dict => |dict| {
            for (dict.keys) |k| collectUsedVars(k, result);
            for (dict.values) |v| collectUsedVars(v, result);
        },
        .set => |set| {
            for (set.elts) |e| collectUsedVars(e, result);
        },
        .listcomp => |lc| {
            collectUsedVars(lc.elt.*, result);
            for (lc.generators) |gen| {
                collectUsedVars(gen.iter.*, result);
                for (gen.ifs) |cond| collectUsedVars(cond, result);
            }
        },
        .dictcomp => |dc| {
            collectUsedVars(dc.key.*, result);
            collectUsedVars(dc.value.*, result);
            for (dc.generators) |gen| {
                collectUsedVars(gen.iter.*, result);
                for (gen.ifs) |cond| collectUsedVars(cond, result);
            }
        },
        .setcomp => |sc| {
            collectUsedVars(sc.elt.*, result);
            for (sc.generators) |gen| {
                collectUsedVars(gen.iter.*, result);
                for (gen.ifs) |cond| collectUsedVars(cond, result);
            }
        },
        .genexp => |ge| {
            collectUsedVars(ge.elt.*, result);
            for (ge.generators) |gen| {
                collectUsedVars(gen.iter.*, result);
                for (gen.ifs) |cond| collectUsedVars(cond, result);
            }
        },
        .lambda => |lambda| collectUsedVars(lambda.body.*, result),
        .slice => |slice| {
            if (slice.lower) |l| collectUsedVars(l.*, result);
            if (slice.upper) |u| collectUsedVars(u.*, result);
            if (slice.step) |s| collectUsedVars(s.*, result);
        },
        .starred => |starred| collectUsedVars(starred.value.*, result),
        .await_expr => |await_e| collectUsedVars(await_e.value.*, result),
        .joined_str => |js| {
            for (js.values) |v| collectUsedVars(v, result);
        },
        .formatted_value => |fv| collectUsedVars(fv.value.*, result),
        // Statements - recurse into their expression parts
        .assign => |assign| {
            // Only collect from RHS (value), not LHS (targets)
            collectUsedVars(assign.value.*, result);
        },
        .ann_assign => |ann| {
            if (ann.value) |v| collectUsedVars(v.*, result);
        },
        .aug_assign => |aug| {
            // Both target and value are used for aug_assign (target is read AND written)
            collectUsedVars(aug.target.*, result);
            collectUsedVars(aug.value.*, result);
        },
        .expr_stmt => |expr| collectUsedVars(expr.value.*, result),
        .return_stmt => |ret| {
            if (ret.value) |v| collectUsedVars(v.*, result);
        },
        .delete_stmt => |del| {
            for (del.targets) |t| collectUsedVars(t, result);
        },
        .raise_stmt => |raise| {
            if (raise.exc) |e| collectUsedVars(e.*, result);
            if (raise.cause) |c| collectUsedVars(c.*, result);
        },
        .assert_stmt => |assert| {
            collectUsedVars(assert.@"test".*, result);
            if (assert.msg) |m| collectUsedVars(m.*, result);
        },
        .if_stmt => |if_stmt| {
            collectUsedVars(if_stmt.condition.*, result);
            for (if_stmt.body) |s| collectUsedVars(s, result);
            for (if_stmt.else_body) |s| collectUsedVars(s, result);
        },
        .while_stmt => |while_stmt| {
            collectUsedVars(while_stmt.condition.*, result);
            for (while_stmt.body) |s| collectUsedVars(s, result);
            if (while_stmt.orelse_body) |else_body| {
                for (else_body) |s| collectUsedVars(s, result);
            }
        },
        .for_stmt => |for_stmt| {
            collectUsedVars(for_stmt.iter.*, result);
            for (for_stmt.body) |s| collectUsedVars(s, result);
            if (for_stmt.orelse_body) |else_body| {
                for (else_body) |s| collectUsedVars(s, result);
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |s| collectUsedVars(s, result);
            for (try_stmt.handlers) |handler| {
                for (handler.body) |s| collectUsedVars(s, result);
            }
            for (try_stmt.else_body) |s| collectUsedVars(s, result);
            for (try_stmt.finalbody) |s| collectUsedVars(s, result);
        },
        .with_stmt => |with_stmt| {
            collectUsedVars(with_stmt.context_expr.*, result);
            for (with_stmt.body) |s| collectUsedVars(s, result);
        },
        .match_stmt => |match_stmt| {
            collectUsedVars(match_stmt.subject.*, result);
            for (match_stmt.cases) |case| {
                for (case.body) |s| collectUsedVars(s, result);
            }
        },
        else => {},
    }
}

/// Check if a variable is actually used (read) in a body after being assigned
/// This helps avoid "pointless discard" errors
pub fn isVarActuallyUsed(body: []const ast.Node, var_name: []const u8) bool {
    const used = analyzeUsedVars(body);
    return used.contains(var_name);
}
