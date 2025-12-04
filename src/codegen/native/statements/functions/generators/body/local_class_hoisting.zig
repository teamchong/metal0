/// Local class hoisting utilities - hoist locally-defined classes from method bodies to struct level
/// This is needed because Zig requires all const declarations to appear before pub fn declarations.
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const generators = @import("../../generators.zig");

/// Hoist ALL locally-defined classes from ALL method bodies to struct level.
/// This MUST be called at the START of class generation, BEFORE any fields or methods.
/// Zig requires all const declarations to appear before pub fn declarations.
pub fn hoistAllLocalClassesFromMethods(self: *NativeCodegen, class: ast.Node.ClassDef) CodegenError!void {
    for (class.body) |stmt| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            try hoistLocalClassesFromMethod(self, method);
        }
    }
}

/// Hoist locally-defined classes from a method body to struct level.
/// This allows the method's return type to reference the class name.
/// The hoisted class is generated before the method, and the class definition
/// in the method body will be skipped during body generation.
fn hoistLocalClassesFromMethod(self: *NativeCodegen, method: ast.Node.FunctionDef) CodegenError!void {
    // First, check if this method returns a locally-defined class
    const returned_class_name = getReturnedLocalClassName(method.body) orelse return;

    // Find the class definition in the method body
    const class_def = findClassDefInBody(method.body, returned_class_name) orelse return;

    // Check if already hoisted or known - but only skip if it's in the CURRENT parent class scope
    // Note: nested_class_names check should NOT be used here because it contains classes from
    // sibling scopes that were added during their own genClassDef. Each parent class needs its
    // own copy of locally-defined classes hoisted.
    // Instead, only check hoisted_local_classes which is cleared for each new parent class.
    if (self.class_registry.getClass(returned_class_name) != null) return;
    if (self.hoisted_local_classes.contains(returned_class_name)) return;

    // Mark as hoisted BEFORE generating (so genClassDef knows to skip _ = &Name;)
    // Store with original name initially - genClassDef will update if renamed
    try self.hoisted_local_classes.put(returned_class_name, returned_class_name);

    // Generate the class at struct level (before the method)
    // genClassDef will update hoisted_local_classes with the actual name if renamed
    try generators.genClassDef(self, class_def);
}

/// Check if a method body returns a locally-defined class constructor call
/// Returns the class name if found, null otherwise
fn getReturnedLocalClassName(stmts: []const ast.Node) ?[]const u8 {
    // First, collect all locally-defined class names
    var local_class_names: [32][]const u8 = undefined;
    var local_class_count: usize = 0;
    collectLocalClasses(stmts, &local_class_names, &local_class_count);

    // Now find return statements that return a constructor call to a local class
    for (stmts) |stmt| {
        const class_name = checkStmtForLocalClassReturn(stmt, local_class_names[0..local_class_count]);
        if (class_name != null) return class_name;
    }
    return null;
}

fn checkStmtForLocalClassReturn(stmt: ast.Node, local_classes: []const []const u8) ?[]const u8 {
    switch (stmt) {
        .return_stmt => |ret| {
            if (ret.value) |val| {
                if (val.* == .call and val.call.func.* == .name) {
                    const func_name = val.call.func.name.id;
                    for (local_classes) |local_name| {
                        if (std.mem.eql(u8, func_name, local_name)) {
                            return local_name;
                        }
                    }
                }
            }
        },
        .if_stmt => |if_stmt| {
            if (checkStmtsForLocalClassReturn(if_stmt.body, local_classes)) |found| return found;
            if (checkStmtsForLocalClassReturn(if_stmt.else_body, local_classes)) |found| return found;
        },
        .for_stmt => |for_stmt| {
            if (checkStmtsForLocalClassReturn(for_stmt.body, local_classes)) |found| return found;
        },
        .while_stmt => |while_stmt| {
            if (checkStmtsForLocalClassReturn(while_stmt.body, local_classes)) |found| return found;
        },
        .try_stmt => |try_stmt| {
            if (checkStmtsForLocalClassReturn(try_stmt.body, local_classes)) |found| return found;
            for (try_stmt.handlers) |handler| {
                if (checkStmtsForLocalClassReturn(handler.body, local_classes)) |found| return found;
            }
        },
        else => {},
    }
    return null;
}

fn checkStmtsForLocalClassReturn(stmts: []const ast.Node, local_classes: []const []const u8) ?[]const u8 {
    for (stmts) |stmt| {
        if (checkStmtForLocalClassReturn(stmt, local_classes)) |found| return found;
    }
    return null;
}

/// Collect class definition names from statements
fn collectLocalClasses(stmts: []const ast.Node, names: *[32][]const u8, count: *usize) void {
    for (stmts) |stmt| {
        switch (stmt) {
            .class_def => |cd| {
                if (count.* < 32) {
                    names[count.*] = cd.name;
                    count.* += 1;
                }
            },
            .if_stmt => |if_stmt| {
                collectLocalClasses(if_stmt.body, names, count);
                collectLocalClasses(if_stmt.else_body, names, count);
            },
            .for_stmt => |for_stmt| {
                collectLocalClasses(for_stmt.body, names, count);
            },
            .while_stmt => |while_stmt| {
                collectLocalClasses(while_stmt.body, names, count);
            },
            .try_stmt => |try_stmt| {
                collectLocalClasses(try_stmt.body, names, count);
                for (try_stmt.handlers) |handler| {
                    collectLocalClasses(handler.body, names, count);
                }
            },
            else => {},
        }
    }
}

/// Find a class definition by name in a body
fn findClassDefInBody(stmts: []const ast.Node, class_name: []const u8) ?ast.Node.ClassDef {
    for (stmts) |stmt| {
        switch (stmt) {
            .class_def => |cd| {
                if (std.mem.eql(u8, cd.name, class_name)) {
                    return cd;
                }
            },
            .if_stmt => |if_stmt| {
                if (findClassDefInBody(if_stmt.body, class_name)) |found| return found;
                if (findClassDefInBody(if_stmt.else_body, class_name)) |found| return found;
            },
            .for_stmt => |for_stmt| {
                if (findClassDefInBody(for_stmt.body, class_name)) |found| return found;
            },
            .while_stmt => |while_stmt| {
                if (findClassDefInBody(while_stmt.body, class_name)) |found| return found;
            },
            .try_stmt => |try_stmt| {
                if (findClassDefInBody(try_stmt.body, class_name)) |found| return found;
                for (try_stmt.handlers) |handler| {
                    if (findClassDefInBody(handler.body, class_name)) |found| return found;
                }
            },
            else => {},
        }
    }
    return null;
}

/// Check if a statement (or its children) contains self.attr assignments
pub fn hasSelfAttrAssign(stmt: ast.Node) bool {
    return hasSelfAttrAssignImpl(stmt);
}

fn hasSelfAttrAssignImpl(node: ast.Node) bool {
    switch (node) {
        .assign => |assign| {
            for (assign.targets) |target| {
                if (isSelfAttrTarget(target)) return true;
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |s| {
                if (hasSelfAttrAssignImpl(s)) return true;
            }
            for (if_stmt.else_body) |s| {
                if (hasSelfAttrAssignImpl(s)) return true;
            }
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |s| {
                if (hasSelfAttrAssignImpl(s)) return true;
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |s| {
                if (hasSelfAttrAssignImpl(s)) return true;
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |s| {
                if (hasSelfAttrAssignImpl(s)) return true;
            }
            for (try_stmt.handlers) |handler| {
                for (handler.body) |s| {
                    if (hasSelfAttrAssignImpl(s)) return true;
                }
            }
        },
        else => {},
    }
    return false;
}

/// Check if target is self.attr (direct attribute) or tuple/list containing self.attr
fn isSelfAttrTarget(target: ast.Node) bool {
    switch (target) {
        .attribute => |attr| {
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                return true;
            }
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                if (isSelfAttrTarget(elem)) return true;
            }
        },
        .list => |list| {
            for (list.elts) |elem| {
                if (isSelfAttrTarget(elem)) return true;
            }
        },
        else => {},
    }
    return false;
}
