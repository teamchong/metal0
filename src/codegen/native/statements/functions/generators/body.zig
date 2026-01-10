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
pub fn methodMutatesSelf(method: ast.Node.FunctionDef) bool {
    _ = method;
    return false; // Query via pass_analysis_result.methodMutatesSelf()
}
pub fn usesTypeAttribute(_: ast.Node.FunctionDef) bool {
    return false;
}
pub fn usesRegularSelf(_: ast.Node.FunctionDef) bool {
    return true;
}

/// Analyze a function's local mutations and store in passes system
/// This handles class methods that aren't in the IR - analyzes during codegen
pub fn analyzeFunctionLocalMutations(self: *NativeCodegen, func: ast.Node.FunctionDef) !void {
    // Only analyze if we have a passes result and function isn't already analyzed
    if (self.pass_analysis_result) |result| {
        // Check if already analyzed
        if (result.function_scopes.contains(func.name)) return;

        // Create function scope
        var scope = pass_analysis.FunctionScope.init(self.allocator);
        errdefer scope.deinit();

        // Track assignment counts to determine mutations
        var assignment_counts = hashmap_helper.StringHashMap(usize).init(self.allocator);
        defer assignment_counts.deinit();

        // Analyze function body
        for (func.body) |stmt| {
            try analyzeStmtMutations(stmt, &scope, &assignment_counts, self.allocator);
        }

        // Convert assignment counts > 1 to mutations
        var iter = assignment_counts.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* > 1) {
                try scope.mutations.put(entry.key_ptr.*, {});
            }
        }

        // Store in passes system
        try result.function_scopes.put(func.name, scope);
    }
}

/// Analyze a statement for mutations and aug_assigns
/// Recursively traverses nested blocks
fn analyzeStmtMutations(
    stmt: ast.Node,
    scope: *pass_analysis.FunctionScope,
    assignment_counts: *hashmap_helper.StringHashMap(usize),
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
                    try scope.uses.put(name, {});
                }
            }
        },
        .ann_assign => |a| {
            if (a.target.* == .name) {
                const name = a.target.name.id;
                const count = assignment_counts.get(name) orelse 0;
                try assignment_counts.put(name, count + 1);
                try scope.uses.put(name, {});
            }
        },
        .aug_assign => |a| {
            // Aug_assign is both mutation and use
            if (a.target.* == .name) {
                const name = a.target.name.id;
                try scope.aug_assigns.put(name, {});
                try scope.mutations.put(name, {});
                try scope.uses.put(name, {});
            }
        },
        .for_stmt => |f| {
            // Loop variable is mutated (each iteration)
            if (f.target.* == .name) {
                const name = f.target.name.id;
                try scope.mutations.put(name, {});
                try scope.uses.put(name, {});
            }
            // Recurse into body
            for (f.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, allocator);
            if (f.orelse_body) |ob| for (ob) |s| try analyzeStmtMutations(s, scope, assignment_counts, allocator);
        },
        .if_stmt => |i| {
            for (i.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, allocator);
            for (i.else_body) |s| try analyzeStmtMutations(s, scope, assignment_counts, allocator);
        },
        .while_stmt => |w| {
            for (w.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, allocator);
            if (w.orelse_body) |ob| for (ob) |s| try analyzeStmtMutations(s, scope, assignment_counts, allocator);
        },
        .try_stmt => |t| {
            for (t.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, allocator);
            for (t.handlers) |h| {
                for (h.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, allocator);
            }
            for (t.else_body) |s| try analyzeStmtMutations(s, scope, assignment_counts, allocator);
            for (t.finalbody) |s| try analyzeStmtMutations(s, scope, assignment_counts, allocator);
        },
        .with_stmt => |w| {
            for (w.body) |s| try analyzeStmtMutations(s, scope, assignment_counts, allocator);
        },
        else => {},
    }
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
