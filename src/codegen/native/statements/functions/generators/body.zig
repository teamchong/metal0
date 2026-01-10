/// Function and class body generation - Thin facade that re-exports from submodules
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const pass_analysis = @import("../../../../passes/analysis.zig");

// Import submodules
const class_fields = @import("body/class_fields.zig");
const class_methods = @import("body/class_methods.zig");
const nested_captures = @import("body/nested_captures.zig");
const function_gen = @import("body/function_gen.zig");
const returned_vars_analysis = @import("body/returned_vars_analysis.zig");

// Re-export class field functions
pub const genClassFields = class_fields.genClassFields;
pub const genClassFieldsNoDict = class_fields.genClassFieldsNoDict;
pub const genClassAttributeFields = class_fields.genClassAttributeFields;
pub const genClassLevelFields = class_fields.genClassLevelFields;
pub const inferParamType = class_fields.inferParamType;

// Re-export class method functions
pub const genDefaultInitMethod = class_methods.genDefaultInitMethod;
pub const genDefaultInitMethodWithBuiltinBase = class_methods.genDefaultInitMethodWithBuiltinBase;
pub const genInitMethod = class_methods.genInitMethod;
pub const genInitMethodWithBuiltinBase = class_methods.genInitMethodWithBuiltinBase;
pub const genInitMethodFromNew = class_methods.genInitMethodFromNew;
pub const genClassMethods = class_methods.genClassMethods;
pub const genInheritedMethods = class_methods.genInheritedMethods;
pub const genPolymorphicReturnHelpers = class_methods.genPolymorphicReturnHelpers;
pub const genABCDefaultMethods = class_methods.genABCDefaultMethods;
pub const hoistAllLocalClassesFromMethods = class_methods.hoistAllLocalClassesFromMethods;

// Mutation/usage analysis - populates passes system for functions not in IR (e.g., class methods)
pub fn methodMutatesSelf(self: *NativeCodegen, method: ast.Node.FunctionDef) bool {
    // Build a unique key including class name if inside a class
    const key = if (self.current_class_name) |class_name| blk: {
        break :blk std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, method.name }) catch method.name;
    } else method.name;

    // Query the passes system for mutates_self flag
    if (self.pass_analysis_result) |result| {
        return result.methodMutatesSelf(key);
    }
    // Fallback: analyze directly (conservative approach)
    return analyzeMethodMutatesSelfDirect(method);
}

/// Direct analysis of whether a method mutates self (fallback when passes system unavailable)
fn analyzeMethodMutatesSelfDirect(method: ast.Node.FunctionDef) bool {
    for (method.body) |stmt| {
        if (stmtMutatesSelf(stmt)) return true;
    }
    return false;
}

/// Check if a statement mutates self or returns self
/// "return self" also counts as mutation because it requires a mutable pointer return type
fn stmtMutatesSelf(stmt: ast.Node) bool {
    switch (stmt) {
        .assign => |a| {
            for (a.targets) |target| {
                if (target == .attribute and target.attribute.value.* == .name) {
                    if (std.mem.eql(u8, target.attribute.value.name.id, "self")) return true;
                }
            }
        },
        .ann_assign => |a| {
            if (a.target.* == .attribute and a.target.attribute.value.* == .name) {
                if (std.mem.eql(u8, a.target.attribute.value.name.id, "self")) return true;
            }
        },
        .aug_assign => |a| {
            if (a.target.* == .attribute and a.target.attribute.value.* == .name) {
                if (std.mem.eql(u8, a.target.attribute.value.name.id, "self")) return true;
            }
        },
        .return_stmt => |r| {
            // "return self" requires mutable self pointer for the return type
            if (r.value) |val| {
                if (val.* == .name and std.mem.eql(u8, val.name.id, "self")) return true;
            }
        },
        .for_stmt => |f| {
            for (f.body) |s| if (stmtMutatesSelf(s)) return true;
            if (f.orelse_body) |ob| for (ob) |s| if (stmtMutatesSelf(s)) return true;
        },
        .if_stmt => |i| {
            for (i.body) |s| if (stmtMutatesSelf(s)) return true;
            for (i.else_body) |s| if (stmtMutatesSelf(s)) return true;
        },
        .while_stmt => |w| {
            for (w.body) |s| if (stmtMutatesSelf(s)) return true;
            if (w.orelse_body) |ob| for (ob) |s| if (stmtMutatesSelf(s)) return true;
        },
        .try_stmt => |t| {
            for (t.body) |s| if (stmtMutatesSelf(s)) return true;
            for (t.handlers) |h| {
                for (h.body) |s| if (stmtMutatesSelf(s)) return true;
            }
            for (t.else_body) |s| if (stmtMutatesSelf(s)) return true;
            for (t.finalbody) |s| if (stmtMutatesSelf(s)) return true;
        },
        .with_stmt => |w| {
            for (w.body) |s| if (stmtMutatesSelf(s)) return true;
        },
        else => {},
    }
    return false;
}
pub fn usesTypeAttribute(_: ast.Node.FunctionDef) bool {
    return false;
}
pub fn usesRegularSelf(_: ast.Node.FunctionDef) bool {
    return true;
}

/// Analyze a function's local mutations and store in passes system
/// This handles class methods that aren't in the IR - analyzes during codegen
/// Also populates func_local_mutations for var_hoisting compatibility
pub fn analyzeFunctionLocalMutations(self: *NativeCodegen, func: ast.Node.FunctionDef) !void {
    // Build a unique key including class name if inside a class
    const key = if (self.current_class_name) |class_name| blk: {
        break :blk std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, func.name }) catch func.name;
    } else func.name;
    // Check if passes system already has this function analyzed
    const already_analyzed = if (self.pass_analysis_result) |result|
        result.function_scopes.contains(key)
    else
        false;

    // If already analyzed in passes system, copy mutations to func_local_mutations
    if (already_analyzed) {
        if (self.pass_analysis_result) |result| {
            if (result.function_scopes.get(key)) |existing_scope| {
                // Copy mutations to func_local_mutations
                var mut_iter = existing_scope.mutations.iterator();
                while (mut_iter.next()) |entry| {
                    try self.func_local_mutations.put(entry.key_ptr.*, {});
                }
                // Copy aug_assigns too
                var aug_iter = existing_scope.aug_assigns.iterator();
                while (aug_iter.next()) |entry| {
                    try self.func_local_mutations.put(entry.key_ptr.*, {});
                }
            }
        }
        return;
    }

    // Track assignment counts to determine mutations
    var assignment_counts = hashmap_helper.StringHashMap(usize).init(self.allocator);
    defer assignment_counts.deinit();

    // Track aug_assigns separately for func_local_mutations
    var aug_assigns = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer aug_assigns.deinit();

    // Create scope for passes system (if available)
    var scope: ?pass_analysis.FunctionScope = if (self.pass_analysis_result != null)
        pass_analysis.FunctionScope.init(self.allocator)
    else
        null;
    errdefer if (scope) |*s| s.deinit();

    // Analyze function body
    for (func.body) |stmt| {
        try analyzeStmtMutations(stmt, if (scope) |*s| s else null, &assignment_counts, &aug_assigns, self.allocator);
    }

    // Convert assignment counts > 1 to mutations
    var iter = assignment_counts.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* > 1) {
            // Add to passes system scope
            if (scope) |*s| {
                try s.mutations.put(entry.key_ptr.*, {});
            }
            // Also populate func_local_mutations for var_hoisting compatibility
            try self.func_local_mutations.put(entry.key_ptr.*, {});
        }
    }

    // Store aug_assigns in func_local_mutations
    var aug_iter = aug_assigns.iterator();
    while (aug_iter.next()) |entry| {
        try self.func_local_mutations.put(entry.key_ptr.*, {});
    }

    // Store in passes system
    if (scope) |s| {
        if (self.pass_analysis_result) |result| {
            try result.function_scopes.put(key, s);
        }
    }
}

/// Analyze a statement for mutations and aug_assigns
/// Recursively traverses nested blocks
fn analyzeStmtMutations(
    stmt: ast.Node,
    scope: ?*pass_analysis.FunctionScope,
    assignment_counts: *hashmap_helper.StringHashMap(usize),
    aug_assigns: *hashmap_helper.StringHashMap(void),
    allocator: std.mem.Allocator,
) !void {
    switch (stmt) {
        .assign => |a| {
            // Track assignments for mutation detection
            for (a.targets) |target| {
                if (target == .name) {
                    const name = target.name.id;
                    const count = assignment_counts.get(name) orelse 0;
                    try assignment_counts.put(name, count + 1);
                    // Also mark as used since it appears in code
                    if (scope) |s| try s.uses.put(name, {});
                } else if (target == .attribute) {
                    // Check if assigning to self.xxx - note: target is already dereferenced
                    if (isSelfAttribute(target.attribute)) {
                        if (scope) |s| s.mutates_self = true;
                    }
                }
            }
        },
        .ann_assign => |a| {
            if (a.target.* == .name) {
                const name = a.target.name.id;
                const count = assignment_counts.get(name) orelse 0;
                try assignment_counts.put(name, count + 1);
                if (scope) |s| try s.uses.put(name, {});
            } else if (a.target.* == .attribute) {
                // Check if annotated assignment to self.xxx
                if (isSelfAttribute(a.target.attribute)) {
                    if (scope) |s| s.mutates_self = true;
                }
            }
        },
        .aug_assign => |a| {
            // Aug_assign is both mutation and use
            if (a.target.* == .name) {
                const name = a.target.name.id;
                // Track in aug_assigns for func_local_mutations
                try aug_assigns.put(name, {});
                if (scope) |s| {
                    try s.aug_assigns.put(name, {});
                    try s.mutations.put(name, {});
                    try s.uses.put(name, {});
                }
            } else if (a.target.* == .attribute) {
                // Check if aug_assign to self.xxx
                if (isSelfAttribute(a.target.attribute)) {
                    if (scope) |s| s.mutates_self = true;
                }
            }
        },
        .return_stmt => |r| {
            // "return self" requires mutable self pointer for the return type
            if (r.value) |val| {
                if (val.* == .name and std.mem.eql(u8, val.name.id, "self")) {
                    if (scope) |s| s.mutates_self = true;
                }
            }
        },
        .for_stmt => |f| {
            // Loop variable is mutated (each iteration)
            if (f.target.* == .name) {
                const name = f.target.name.id;
                // For loop variable is mutated each iteration
                try aug_assigns.put(name, {}); // Treat as mutation
                if (scope) |s| {
                    try s.mutations.put(name, {});
                    try s.uses.put(name, {});
                }
            }
            // Recurse into body
            for (f.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, aug_assigns, allocator);
            if (f.orelse_body) |ob| for (ob) |s_| try analyzeStmtMutations(s_, scope, assignment_counts, aug_assigns, allocator);
        },
        .if_stmt => |i| {
            for (i.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, aug_assigns, allocator);
            for (i.else_body) |s| try analyzeStmtMutations(s, scope, assignment_counts, aug_assigns, allocator);
        },
        .while_stmt => |w| {
            for (w.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, aug_assigns, allocator);
            if (w.orelse_body) |ob| for (ob) |s_| try analyzeStmtMutations(s_, scope, assignment_counts, aug_assigns, allocator);
        },
        .try_stmt => |t| {
            for (t.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, aug_assigns, allocator);
            for (t.handlers) |h| {
                for (h.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, aug_assigns, allocator);
            }
            for (t.else_body) |s| try analyzeStmtMutations(s, scope, assignment_counts, aug_assigns, allocator);
            for (t.finalbody) |s| try analyzeStmtMutations(s, scope, assignment_counts, aug_assigns, allocator);
        },
        .with_stmt => |w| {
            for (w.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, aug_assigns, allocator);
        },
        else => {},
    }
}

/// Check if an attribute access is on 'self' (e.g., self.count)
fn isSelfAttribute(attr: ast.Node.Attribute) bool {
    // Check if the value is a Name node with id "self"
    return attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self");
}

pub fn analyzeModuleLevelMutations(_: *NativeCodegen, _: []const ast.Node) !void {
    // No-op: passes system already analyzed mutations at module level
}
pub fn countAssignmentsWithScope(_: []const ast.Node, _: []const u8, _: usize) usize {
    return 0;
}

/// Analyze a function's local uses and store in passes system
pub fn analyzeFunctionLocalUses(self: *NativeCodegen, func: ast.Node.FunctionDef) !void {
    // Use the unified analyzeFunctionLocalMutations which handles both
    try analyzeFunctionLocalMutations(self, func);
}
pub fn collectUsesInNode(_: *NativeCodegen, _: ast.Node) !void {
    // No-op: analyzeFunctionLocalMutations handles this
}

// Re-export nested capture functions
pub const analyzeNestedClassCaptures = nested_captures.analyzeNestedClassCaptures;
pub const collectLocalVarsInStmts = nested_captures.collectLocalVarsInStmts;
pub const findNestedClassCaptures = nested_captures.findNestedClassCaptures;
pub const findCapturedVarsInClass = nested_captures.findCapturedVarsInClass;
pub const findOuterRefsInStmts = nested_captures.findOuterRefsInStmts;
pub const findOuterRefsInNode = nested_captures.findOuterRefsInNode;
pub const isBuiltinName = nested_captures.isBuiltinName;

// Re-export function generation functions
pub const genFunctionBody = function_gen.genFunctionBody;
pub const genAsyncFunctionBody = function_gen.genAsyncFunctionBody;
pub const genMethodBody = function_gen.genMethodBody;
pub const genMethodBodyWithAllocatorInfo = function_gen.genMethodBodyWithAllocatorInfo;
pub const genMethodBodyWithContext = function_gen.genMethodBodyWithContext;
pub const hasSuperCall = function_gen.hasSuperCall;

// Re-export returned vars analysis functions
pub const analyzeReturnedVars = returned_vars_analysis.analyzeReturnedVars;
pub const analyzeModuleLevelReturnedVars = returned_vars_analysis.analyzeModuleLevelReturnedVars;
