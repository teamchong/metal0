/// Async State Machine Transformation
/// MIGRATED TO ZIGBUILDER
///
/// Transforms Python async functions into Zig state machines for true non-blocking I/O.
///
/// Python:
///   async def worker(task_id):
///       await asyncio.sleep(0.001)
///       return task_id
///
/// Becomes:
///   const WorkerState = enum { start, await_0, done };
///   const WorkerFrame = struct { state: WorkerState, task_id: i64, timer_id: u64 };
///   fn worker_poll(frame: *WorkerFrame) ?i64 { ... }
///
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const shared = @import("shared_maps.zig");
const BinOpStrings = shared.BinOpStrings;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}


/// Emit binary operator string (DRY helper)
/// NOTE: Only use for operators that have direct Zig equivalents!
/// Pow, Mod, FloorDiv need special handling (std.math.pow, @mod, @divFloor)
fn emitBinOp(self: *NativeCodegen, op: ast.Operator) CodegenError!void {
    try emitConst(self,BinOpStrings.get(@tagName(op)) orelse " ? ");
}

/// Check if name is a frame field (DRY helper)
fn isFrameField(name: []const u8, frame_fields: []const []const u8) bool {
    for (frame_fields) |field| if (std.mem.eql(u8, field, name)) return true;
    return false;
}

/// Emit integer literal (DRY helper)
fn emitInt(self: *NativeCodegen, val: anytype) CodegenError!void {
    var buf: [32]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return error.OutOfMemory;
    try emitConst(self,slice);
}

/// Emit float literal (DRY helper)
fn emitFloat(self: *NativeCodegen, f: f64) CodegenError!void {
    var buf: [64]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.OutOfMemory;
    try emitConst(self,slice);
}

/// Get Zig type string for a variable in async function context (Two-Flow aware)
/// Returns "runtime.PyValue" for uncertain types, otherwise the inferred Zig type
fn getAsyncVarType(self: *NativeCodegen, func_name: []const u8, var_name: []const u8) []const u8 {
    // Check if type is uncertain - use PyValue for safety
    if (self.type_inferrer.isUncertain(var_name)) {
        return "runtime.PyValue";
    }

    // Try scoped lookup first (function-local)
    if (self.getVarTypeInScope(func_name, var_name)) |var_type| {
        return self.nativeTypeToZigType(var_type) catch "i64";
    }

    // Try global lookup
    if (self.getVarType(var_name)) |var_type| {
        return self.nativeTypeToZigType(var_type) catch "i64";
    }

    // Default to i64 for untracked variables
    return "i64";
}

/// Get Zig return type string for an async function (Two-Flow aware)
/// Returns "runtime.PyValue" for uncertain returns, otherwise the inferred Zig type
fn getAsyncReturnType(self: *NativeCodegen, func: ast.Node.FunctionDef) []const u8 {
    // Check if function has explicit return annotation
    if (func.return_type) |type_name| {
        if (std.mem.eql(u8, type_name, "int")) return "i64";
        if (std.mem.eql(u8, type_name, "float")) return "f64";
        if (std.mem.eql(u8, type_name, "str")) return "[]const u8";
        if (std.mem.eql(u8, type_name, "bool")) return "bool";
        if (std.mem.eql(u8, type_name, "None")) return "void";
    }

    // Try to get inferred return type from type inferrer
    if (self.type_inferrer.func_return_types.get(func.name)) |return_type| {
        return self.nativeTypeToZigType(return_type) catch "i64";
    }

    // Default to i64 for async functions without annotation
    return "i64";
}

/// Information about an await point in an async function
const AwaitPoint = struct {
    index: usize,              // Sequential index (0, 1, 2, ...)
    await_type: AwaitType,     // What kind of await
    expr: ast.Node,            // The awaited expression
    target_var: ?[]const u8,   // Variable to store result (for assignments)
    callee_name: ?[]const u8,  // Name of called function (for task awaits)
};

const AwaitType = enum {
    sleep,      // asyncio.sleep(duration)
    gather,     // asyncio.gather(*tasks)
    task,       // await some_coroutine()
    other,      // Generic await
};

/// Analyze an async function to find all await points
pub fn findAwaitPoints(allocator: std.mem.Allocator, body: []ast.Node) ![]AwaitPoint {
    var points = std.ArrayListUnmanaged(AwaitPoint){};
    errdefer points.deinit(allocator);

    var index: usize = 0;
    for (body) |stmt| {
        try findAwaitPointsInNode(allocator, stmt, &points, &index);
    }

    return points.toOwnedSlice(allocator);
}

fn findAwaitPointsInNode(
    allocator: std.mem.Allocator,
    node: ast.Node,
    points: *std.ArrayListUnmanaged(AwaitPoint),
    index: *usize,
) !void {
    switch (node) {
        .await_expr => |await_node| {
            const await_type = classifyAwait(await_node.value.*);
            try points.append(allocator, .{
                .index = index.*,
                .await_type = await_type,
                .expr = await_node.value.*,
                .target_var = null,
                .callee_name = getCalleeName(await_node.value.*),
            });
            index.* += 1;
        },
        .expr_stmt => |expr| {
            try findAwaitPointsInNode(allocator, expr.value.*, points, index);
        },
        .assign => |assign| {
            // Check if assigning from await
            if (assign.value.* == .await_expr) {
                const await_node = assign.value.*.await_expr;
                const await_type = classifyAwait(await_node.value.*);
                const target_var = getAssignTarget(assign.targets);
                try points.append(allocator, .{
                    .index = index.*,
                    .await_type = await_type,
                    .expr = await_node.value.*,
                    .target_var = target_var,
                    .callee_name = getCalleeName(await_node.value.*),
                });
                index.* += 1;
            } else {
                try findAwaitPointsInNode(allocator, assign.value.*, points, index);
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |stmt| {
                try findAwaitPointsInNode(allocator, stmt, points, index);
            }
            for (if_stmt.else_body) |stmt| {
                try findAwaitPointsInNode(allocator, stmt, points, index);
            }
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |stmt| {
                try findAwaitPointsInNode(allocator, stmt, points, index);
            }
            if (for_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |stmt| {
                    try findAwaitPointsInNode(allocator, stmt, points, index);
                }
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |stmt| {
                try findAwaitPointsInNode(allocator, stmt, points, index);
            }
            if (while_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |stmt| {
                    try findAwaitPointsInNode(allocator, stmt, points, index);
                }
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |stmt| {
                try findAwaitPointsInNode(allocator, stmt, points, index);
            }
            for (try_stmt.handlers) |handler| {
                for (handler.body) |stmt| {
                    try findAwaitPointsInNode(allocator, stmt, points, index);
                }
            }
            for (try_stmt.else_body) |stmt| {
                try findAwaitPointsInNode(allocator, stmt, points, index);
            }
            for (try_stmt.finalbody) |stmt| {
                try findAwaitPointsInNode(allocator, stmt, points, index);
            }
        },
        .with_stmt => |with_stmt| {
            for (with_stmt.body) |stmt| {
                try findAwaitPointsInNode(allocator, stmt, points, index);
            }
        },
        .match_stmt => |match_stmt| {
            for (match_stmt.cases) |case| {
                for (case.body) |stmt| {
                    try findAwaitPointsInNode(allocator, stmt, points, index);
                }
            }
        },
        else => {},
    }
}

fn classifyAwait(expr: ast.Node) AwaitType {
    if (expr == .call) {
        const call = expr.call;
        if (call.func.* == .attribute) {
            const attr = call.func.*.attribute;
            if (attr.value.* == .name) {
                const mod = attr.value.*.name.id;
                if (std.mem.eql(u8, mod, "asyncio")) {
                    if (std.mem.eql(u8, attr.attr, "sleep")) return .sleep;
                    if (std.mem.eql(u8, attr.attr, "gather")) return .gather;
                }
            }
        }
        // Regular coroutine call
        return .task;
    }
    return .other;
}

fn getCalleeName(expr: ast.Node) ?[]const u8 {
    if (expr == .call) {
        const call = expr.call;
        if (call.func.* == .name) {
            return call.func.*.name.id;
        }
    }
    return null;
}

fn getAssignTarget(targets: []ast.Node) ?[]const u8 {
    if (targets.len > 0) {
        if (targets[0] == .name) {
            return targets[0].name.id;
        }
    }
    return null;
}

/// Find all local variable assignments in function body
fn findLocalVariables(allocator: std.mem.Allocator, body: []ast.Node) ![]const []const u8 {
    var vars = std.ArrayListUnmanaged([]const u8){};
    errdefer vars.deinit(allocator);

    for (body) |stmt| {
        try findVarsInNode(allocator, stmt, &vars);
    }

    return vars.toOwnedSlice(allocator);
}

fn findVarsInNode(allocator: std.mem.Allocator, node: ast.Node, vars: *std.ArrayListUnmanaged([]const u8)) !void {
    switch (node) {
        .assign => |assign| {
            // Don't include await results - those are handled separately
            if (assign.value.* != .await_expr) {
                if (getAssignTarget(assign.targets)) |var_name| {
                    // Check if already in list
                    var found = false;
                    for (vars.items) |v| {
                        if (std.mem.eql(u8, v, var_name)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        try vars.append(allocator, var_name);
                    }
                }
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |stmt| {
                try findVarsInNode(allocator, stmt, vars);
            }
            for (if_stmt.else_body) |stmt| {
                try findVarsInNode(allocator, stmt, vars);
            }
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |stmt| {
                try findVarsInNode(allocator, stmt, vars);
            }
            if (for_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |stmt| {
                    try findVarsInNode(allocator, stmt, vars);
                }
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |stmt| {
                try findVarsInNode(allocator, stmt, vars);
            }
            if (while_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |stmt| {
                    try findVarsInNode(allocator, stmt, vars);
                }
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |stmt| {
                try findVarsInNode(allocator, stmt, vars);
            }
            for (try_stmt.handlers) |handler| {
                for (handler.body) |stmt| {
                    try findVarsInNode(allocator, stmt, vars);
                }
            }
            for (try_stmt.else_body) |stmt| {
                try findVarsInNode(allocator, stmt, vars);
            }
            for (try_stmt.finalbody) |stmt| {
                try findVarsInNode(allocator, stmt, vars);
            }
        },
        .with_stmt => |with_stmt| {
            for (with_stmt.body) |stmt| {
                try findVarsInNode(allocator, stmt, vars);
            }
        },
        .match_stmt => |match_stmt| {
            for (match_stmt.cases) |case| {
                for (case.body) |stmt| {
                    try findVarsInNode(allocator, stmt, vars);
                }
            }
        },
        else => {},
    }
}

/// Find async callee name from tasks list comprehension (e.g., tasks = [worker(i) for i in ...])
fn findTasksCalleeName(body: []ast.Node) ?[]const u8 {
    for (body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (getAssignTarget(assign.targets)) |target| {
                if (std.mem.eql(u8, target, "tasks")) {
                    // Check if value is listcomp
                    if (assign.value.* == .listcomp) {
                        const listcomp = assign.value.*.listcomp;
                        // Check if element is a call
                        if (listcomp.elt.* == .call) {
                            const call = listcomp.elt.*.call;
                            if (call.func.* == .name) {
                                return call.func.*.name.id;
                            }
                        }
                    }
                }
            }
        }
    }
    return null;
}

/// Generate a state machine async function
/// This replaces the old spawn-based approach with pollable frames
pub fn genAsyncStateMachine(self: *NativeCodegen, func: ast.Node.FunctionDef) CodegenError!void {
    // Rename "main" to "__user_main" to avoid conflict with entry point
    const name = if (std.mem.eql(u8, func.name, "main")) "__user_main" else func.name;
    const allocator = self.allocator;

    // Find all await points
    const await_points = findAwaitPoints(allocator, func.body) catch return error.OutOfMemory;
    defer allocator.free(await_points);

    // Find all local variables that need to be stored in frame
    const local_vars = findLocalVariables(allocator, func.body) catch return error.OutOfMemory;
    defer allocator.free(local_vars);

    // Find the async function called in tasks = [...] comprehension
    const tasks_callee = findTasksCalleeName(func.body);

    // If no await points, generate simple sync function
    if (await_points.len == 0) {
        try genSyncFunction(self, func);
        return;
    }

    // 1. Generate State enum
    try emitConst(self,"const ");
    try emitConst(self,name);
    try emitConst(self,"_State = enum { start");
    for (await_points, 0..) |_, i| {
        try emitConst(self,", await_");
        try emitInt(self, i);
    }
    try emitConst(self,", done };\n\n");

    // 2. Generate Frame struct
    try emitConst(self,"const ");
    try emitConst(self,name);
    try emitConst(self,"_Frame = struct {\n");
    try emitConst(self,"    state: ");
    try emitConst(self,name);
    try emitConst(self,"_State = .start,\n");

    // Add parameters as fields (Two-Flow: use inferred types)
    for (func.args) |arg| {
        try emitConst(self,"    ");
        try emitConst(self,arg.name);
        try emitConst(self,": ");
        try emitConst(self,getAsyncVarType(self, name, arg.name));
        try emitConst(self,",\n");
    }

    // Add timer_id for sleep awaits and child frames for task awaits
    for (await_points) |point| {
        if (point.await_type == .sleep) {
            try emitConst(self,"    __timer_");
            try emitInt(self, point.index);
            try emitConst(self,": u64 = 0,\n");
        } else if (point.await_type == .task) {
            if (point.callee_name) |callee| {
                try emitConst(self,"    __child_frame_");
                try emitInt(self, point.index);
                try emitConst(self,": ?*");
                try emitConst(self,callee);
                try emitConst(self,"_Frame = null,\n");
            }
        }
    }

    // Add local variables for await results (except gather, handled separately)
    // Two-Flow: use inferred types for await results
    for (await_points) |point| {
        if (point.await_type != .gather) {
            if (point.target_var) |var_name| {
                try emitConst(self,"    ");
                try emitConst(self,var_name);
                try emitConst(self,": ");
                try emitConst(self,getAsyncVarType(self, name, var_name));
                try emitConst(self," = ");
                // Default value based on type
                const var_type = getAsyncVarType(self, name, var_name);
                if (std.mem.eql(u8, var_type, "runtime.PyValue")) {
                    try emitConst(self,"runtime.PyValue.none()");
                } else if (std.mem.eql(u8, var_type, "f64")) {
                    try emitConst(self,"0.0");
                } else if (std.mem.eql(u8, var_type, "bool")) {
                    try emitConst(self,"false");
                } else {
                    try emitConst(self,"0");
                }
                try emitConst(self,",\n");
            }
        }
    }

    // Add ALL local variables as frame fields (they span await points)
    for (local_vars) |var_name| {
        // Skip if already added as await result
        var already_added = false;
        for (await_points) |point| {
            if (point.target_var) |target| {
                if (std.mem.eql(u8, target, var_name)) {
                    already_added = true;
                    break;
                }
            }
        }
        if (!already_added) {
            try emitConst(self,"    ");
            try emitConst(self,var_name);
            // Special handling for common async patterns
            if (std.mem.eql(u8, var_name, "tasks")) {
                // Use the actual callee name from list comprehension
                if (tasks_callee) |callee| {
                    try emitConst(self,": std.ArrayListUnmanaged(*");
                    try emitConst(self,callee);
                    try emitConst(self,"_Frame) = .{},\n");
                } else {
                    try emitConst(self,": std.ArrayListUnmanaged(*anyopaque) = .{},\n");
                }
            } else if (std.mem.eql(u8, var_name, "start") or std.mem.eql(u8, var_name, "elapsed") or std.mem.eql(u8, var_name, "end")) {
                try emitConst(self,": f64 = 0,\n");
            } else {
                // Two-Flow: use inferred type for local variables
                try emitConst(self,": ");
                const var_type = getAsyncVarType(self, name, var_name);
                try emitConst(self,var_type);
                try emitConst(self," = ");
                // Default value based on type
                if (std.mem.eql(u8, var_type, "runtime.PyValue")) {
                    try emitConst(self,"runtime.PyValue.none()");
                } else if (std.mem.eql(u8, var_type, "f64")) {
                    try emitConst(self,"0.0");
                } else if (std.mem.eql(u8, var_type, "bool")) {
                    try emitConst(self,"false");
                } else {
                    try emitConst(self,"0");
                }
                try emitConst(self,",\n");
            }
        }
    }

    // Add gather result fields with proper list type
    // Two-Flow: use inferred element type for gather results
    for (await_points) |point| {
        if (point.await_type == .gather) {
            if (point.target_var) |var_name| {
                try emitConst(self,"    ");
                try emitConst(self,var_name);
                // For gather, the result is a list - use element type from inference
                const elem_type = getAsyncVarType(self, name, var_name);
                if (std.mem.eql(u8, elem_type, "runtime.PyValue")) {
                    try emitConst(self,": std.ArrayListUnmanaged(runtime.PyValue) = .{},\n");
                } else {
                    try emitConst(self,": std.ArrayListUnmanaged(i64) = .{},\n");
                }
            }
        }
    }

    // Add result field - Two-Flow: use inferred return type
    const result_type = getAsyncReturnType(self, func);
    try emitConst(self,"    __result: ");
    try emitConst(self,result_type);
    try emitConst(self," = ");
    if (std.mem.eql(u8, result_type, "runtime.PyValue")) {
        try emitConst(self,"runtime.PyValue.none()");
    } else if (std.mem.eql(u8, result_type, "f64")) {
        try emitConst(self,"0.0");
    } else if (std.mem.eql(u8, result_type, "bool")) {
        try emitConst(self,"false");
    } else {
        try emitConst(self,"0");
    }
    try emitConst(self,",\n");
    try emitConst(self,"};\n\n");

    // 3. Generate poll function - Two-Flow: use inferred return type
    try emitConst(self,"fn ");
    try emitConst(self,name);
    try emitConst(self,"_poll(frame: *");
    try emitConst(self,name);
    try emitConst(self,"_Frame) ?");
    try emitConst(self,result_type);
    try emitConst(self," {\n");
    try emitConst(self,"    switch (frame.state) {\n");

    // Generate state handlers
    try genStateHandlers(self, func, await_points, local_vars, tasks_callee);

    try emitConst(self,"    }\n");
    try emitConst(self,"}\n\n");

    // 4. Generate spawn function that returns frame (Two-Flow: use inferred types)
    try emitConst(self,"fn ");
    try emitConst(self,name);
    try emitConst(self,"_async(");
    for (func.args, 0..) |arg, i| {
        if (i > 0) try emitConst(self,", ");
        try emitConst(self,arg.name);
        try emitConst(self,": ");
        try emitConst(self,getAsyncVarType(self, name, arg.name));
    }
    try emitConst(self,") !*");
    try emitConst(self,name);
    try emitConst(self,"_Frame {\n");
    try emitConst(self,"    const frame = try __global_allocator.create(");
    try emitConst(self,name);
    try emitConst(self,"_Frame);\n");
    try emitConst(self,"    frame.* = .{\n");
    for (func.args) |arg| {
        try emitConst(self,"        .");
        try emitConst(self,arg.name);
        try emitConst(self," = ");
        try emitConst(self,arg.name);
        try emitConst(self,",\n");
    }
    try emitConst(self,"    };\n");
    try emitConst(self,"    return frame;\n");
    try emitConst(self,"}\n\n");
}

fn genStateHandlers(self: *NativeCodegen, func: ast.Node.FunctionDef, await_points: []const AwaitPoint, local_vars: []const []const u8, tasks_callee: ?[]const u8) CodegenError!void {
    // Collect frame field names for variable remapping
    var frame_fields = std.ArrayListUnmanaged([]const u8){};
    defer frame_fields.deinit(self.allocator);

    // Parameters are frame fields
    for (func.args) |arg| {
        try frame_fields.append(self.allocator, arg.name);
    }
    // Await results are frame fields
    for (await_points) |point| {
        if (point.target_var) |var_name| {
            try frame_fields.append(self.allocator, var_name);
        }
    }
    // Local variables are frame fields
    for (local_vars) |var_name| {
        try frame_fields.append(self.allocator, var_name);
    }

    // Start state - execute until first await
    try emitConst(self,"        .start => {\n");

    var current_await: usize = 0;
    var ended_with_return = false;

    for (func.body, 0..) |stmt, stmt_idx| {
        ended_with_return = false;

        if (containsAwait(stmt)) {
            // Generate code to initiate the await, then transition
            try genCodeBeforeAwait(self, stmt, await_points[current_await]);
            try emitConst(self,"            frame.state = .await_");
            try emitInt(self, current_await);
            try emitConst(self,";\n");
            try emitConst(self,"            return null; // yield\n");
            try emitConst(self,"        },\n");

            // Generate await state handler
            try emitConst(self,"        .await_");
            try emitInt(self, current_await);
            try emitConst(self," => {\n");
            try genAwaitCheck(self, await_points[current_await], await_points, tasks_callee);

            current_await += 1;
        } else if (stmt == .return_stmt) {
            try emitConst(self,"            frame.__result = ");
            if (stmt.return_stmt.value) |val| {
                try genFrameExpr(self, val.*);
            } else {
                try emitConst(self,"0");
            }
            try emitConst(self,";\n");
            try emitConst(self,"            frame.state = .done;\n");
            try emitConst(self,"            return frame.__result;\n");
            ended_with_return = true;
        } else {
            // Generate non-await statement with frame prefix for local vars
            try genStatementInFrame(self, stmt, frame_fields.items);
        }

        // After processing last statement, close the state if not a return
        if (stmt_idx == func.body.len - 1 and !ended_with_return) {
            try emitConst(self,"            frame.state = .done;\n");
            try emitConst(self,"            return frame.__result;\n");
        }
    }

    try emitConst(self,"        },\n");

    // Done state
    try emitConst(self,"        .done => return frame.__result,\n");
}

fn genStatementInFrame(self: *NativeCodegen, stmt: ast.Node, frame_fields: []const []const u8) CodegenError!void {
    switch (stmt) {
        .expr_stmt => |expr| {
            // Handle print calls with frame variable references
            if (expr.value.* == .call) {
                const call = expr.value.*.call;
                if (call.func.* == .name) {
                    const func_name = call.func.*.name.id;
                    if (std.mem.eql(u8, func_name, "print")) {
                        try emitConst(self,"            ");
                        try emitConst(self,"runtime.print(\"{s}\\n\", .{");
                        if (call.args.len > 0) {
                            try genExprInFrame(self, call.args[0], frame_fields);
                        }
                        try emitConst(self,"});\n");
                        return;
                    }
                }
            }
            // Fallback - generate using normal codegen (may have issues with frame vars)
            try emitConst(self,"            ");
            try self.generateStmt(stmt);
        },
        .assign => |assign| {
            // Check if target is a frame field or a local variable
            var is_frame_field = false;
            var target_name: ?[]const u8 = null;
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                target_name = assign.targets[0].name.id;
                for (frame_fields) |field| {
                    if (std.mem.eql(u8, target_name.?, field)) {
                        is_frame_field = true;
                        break;
                    }
                }
            }

            if (is_frame_field) {
                // Assignment to frame field
                try emitConst(self,"            frame.");
                try emitConst(self,target_name.?);
                try emitConst(self," = ");
                try genExprInFrame(self, assign.value.*, frame_fields);
                try emitConst(self,";\n");
            } else if (target_name != null) {
                // Local variable - emit with frame-aware expression
                try emitConst(self,"            const ");
                try emitConst(self,target_name.?);
                try emitConst(self," = ");
                try genExprInFrame(self, assign.value.*, frame_fields);
                try emitConst(self,";\n");
            } else {
                // Fallback to normal codegen
                try emitConst(self,"            ");
                try self.generateStmt(stmt);
            }
        },
        .for_stmt => |for_stmt| {
            // Generate for loop with frame variable access
            try emitConst(self,"            {\n");
            try emitConst(self,"                var __i: i64 = 0;\n");
            try emitConst(self,"                while (__i < ");
            // Extract range end
            if (for_stmt.iter.* == .call) {
                const call = for_stmt.iter.*.call;
                if (call.args.len > 0) {
                    try genExprInFrame(self, call.args[0], frame_fields);
                }
            }
            try emitConst(self,") : (__i += 1) {\n");
            // Bind loop variable
            if (for_stmt.target.* == .name) {
                try emitConst(self,"                    const ");
                try emitConst(self,for_stmt.target.*.name.id);
                try emitConst(self," = __i;\n");
            }
            // Generate body with frame prefix
            for (for_stmt.body) |body_stmt| {
                try genStatementInFrameNested(self, body_stmt, frame_fields);
            }
            try emitConst(self,"                }\n");
            try emitConst(self,"            }\n");
        },
        .aug_assign => |aug| {
            if (aug.target.* == .name) {
                const target_name = aug.target.*.name.id;
                const is_field = isFrameField(target_name, frame_fields);
                const prefix: []const u8 = if (is_field) "frame." else "";
                try emitConst(self,"            ");
                try emitConst(self,prefix);
                try emitConst(self,target_name);
                try emitConst(self," = ");
                // Handle special operators that need function calls
                if (aug.op == .Pow) {
                    try emitConst(self,"std.math.pow(i64, ");
                    try emitConst(self,prefix);
                    try emitConst(self,target_name);
                    try emitConst(self,", ");
                    try genExprInFrame(self, aug.value.*, frame_fields);
                    try emitConst(self,");\n");
                } else if (aug.op == .Mod) {
                    // Use runtime.OperatorMod for proper Python modulo semantics (floored)
                    try emitConst(self,"runtime.OperatorMod{}.call(");
                    try emitConst(self,prefix);
                    try emitConst(self,target_name);
                    try emitConst(self,", ");
                    try genExprInFrame(self, aug.value.*, frame_fields);
                    try emitConst(self,");\n");
                } else if (aug.op == .FloorDiv) {
                    // Use runtime.OperatorFloordiv for proper Python floor division
                    try emitConst(self,"runtime.OperatorFloordiv{}.call(");
                    try emitConst(self,prefix);
                    try emitConst(self,target_name);
                    try emitConst(self,", ");
                    try genExprInFrame(self, aug.value.*, frame_fields);
                    try emitConst(self,");\n");
                } else {
                    try emitConst(self,prefix);
                    try emitConst(self,target_name);
                    try emitBinOp(self, aug.op);
                    try emitConst(self,"(");
                    try genExprInFrame(self, aug.value.*, frame_fields);
                    try emitConst(self,");\n");
                }
            }
        },
        else => {
            try emitConst(self,"            ");
            try self.generateStmt(stmt);
        },
    }
}

/// Wrapper for nested context (uses deeper indent)
fn genStatementInFrameNested(self: *NativeCodegen, stmt: ast.Node, frame_fields: []const []const u8) CodegenError!void {
    try genStatementInFrameWithIndent(self, stmt, frame_fields, "                    ");
}

/// Unified statement generator with configurable indent
fn genStatementInFrameWithIndent(self: *NativeCodegen, stmt: ast.Node, frame_fields: []const []const u8, indent: []const u8) CodegenError!void {
    switch (stmt) {
        .assign => |assign| {
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const target_name = assign.targets[0].name.id;
                try emitConst(self,indent);
                try emitConst(self,target_name);
                try emitConst(self," = ");
                try genExprInFrame(self, assign.value.*, frame_fields);
                try emitConst(self,";\n");
            }
        },
        .aug_assign => |aug| {
            if (aug.target.* == .name) {
                const target_name = aug.target.*.name.id;
                const is_field = isFrameField(target_name, frame_fields);
                const prefix: []const u8 = if (is_field) "frame." else "";
                try emitConst(self,indent);
                try emitConst(self,prefix);
                try emitConst(self,target_name);
                try emitConst(self," = ");
                // Handle special operators that need function calls
                if (aug.op == .Pow) {
                    try emitConst(self,"std.math.pow(i64, ");
                    try emitConst(self,prefix);
                    try emitConst(self,target_name);
                    try emitConst(self,", ");
                    try genExprInFrame(self, aug.value.*, frame_fields);
                    try emitConst(self,");\n");
                } else if (aug.op == .Mod) {
                    // Use runtime.OperatorMod for proper Python modulo semantics (floored)
                    try emitConst(self,"runtime.OperatorMod{}.call(");
                    try emitConst(self,prefix);
                    try emitConst(self,target_name);
                    try emitConst(self,", ");
                    try genExprInFrame(self, aug.value.*, frame_fields);
                    try emitConst(self,");\n");
                } else if (aug.op == .FloorDiv) {
                    // Use runtime.OperatorFloordiv for proper Python floor division
                    try emitConst(self,"runtime.OperatorFloordiv{}.call(");
                    try emitConst(self,prefix);
                    try emitConst(self,target_name);
                    try emitConst(self,", ");
                    try genExprInFrame(self, aug.value.*, frame_fields);
                    try emitConst(self,");\n");
                } else {
                    try emitConst(self,prefix);
                    try emitConst(self,target_name);
                    try emitBinOp(self, aug.op);
                    try emitConst(self,"(");
                    try genExprInFrame(self, aug.value.*, frame_fields);
                    try emitConst(self,");\n");
                }
            }
        },
        else => {
            try emitConst(self,indent);
            try self.generateStmt(stmt);
        },
    }
}

fn genExprInFrame(self: *NativeCodegen, node: ast.Node, frame_fields: []const []const u8) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Check if this is a frame field
            for (frame_fields) |field| {
                if (std.mem.eql(u8, n.id, field)) {
                    try emitConst(self,"frame.");
                    try emitConst(self,n.id);
                    return;
                }
            }
            // Not a frame field, emit as-is
            try emitConst(self,n.id);
        },
        .fstring => |fs| {
            // Handle f-string with frame variable interpolation
            try emitConst(self,"(std.fmt.allocPrint(__global_allocator, \"");
            for (fs.parts) |part| {
                switch (part) {
                    .literal => |lit| try emitConst(self,lit),
                    .expr, .format_expr, .conv_expr => try emitConst(self,"{any}"),
                }
            }
            try emitConst(self,"\", .{");
            var first = true;
            for (fs.parts) |part| {
                switch (part) {
                    .literal => {},
                    .expr => |e| {
                        if (!first) try emitConst(self,", ");
                        first = false;
                        try genExprInFrame(self, e.node.*, frame_fields);
                    },
                    .format_expr => |fe| {
                        if (!first) try emitConst(self,", ");
                        first = false;
                        try genExprInFrame(self, fe.expr.*, frame_fields);
                    },
                    .conv_expr => |ce| {
                        if (!first) try emitConst(self,", ");
                        first = false;
                        try genExprInFrame(self, ce.expr.*, frame_fields);
                    },
                }
            }
            try emitConst(self,"}) catch \"\")");
        },
        .constant => |c| {
            try genConstantInFrame(self, c);
        },
        .binop => |bin| {
            // Handle binary operations with frame variable references
            // Use runtime.OperatorMod for modulo - handles both int and float correctly
            if (bin.op == .Mod) {
                try emitConst(self,"runtime.OperatorMod{}.call(");
                try genExprInFrame(self, bin.left.*, frame_fields);
                try emitConst(self,", ");
                try genExprInFrame(self, bin.right.*, frame_fields);
                try emitConst(self,")");
            } else if (bin.op == .Pow) {
                // Zig doesn't have ** operator, use std.math.pow
                try emitConst(self,"std.math.pow(i64, ");
                try genExprInFrame(self, bin.left.*, frame_fields);
                try emitConst(self,", ");
                try genExprInFrame(self, bin.right.*, frame_fields);
                try emitConst(self,")");
            } else if (bin.op == .FloorDiv) {
                // Use runtime.OperatorFloordiv for proper Python floor division
                try emitConst(self,"runtime.OperatorFloordiv{}.call(");
                try genExprInFrame(self, bin.left.*, frame_fields);
                try emitConst(self,", ");
                try genExprInFrame(self, bin.right.*, frame_fields);
                try emitConst(self,")");
            } else {
                // For division with mixed types, cast to f64
                const is_div = bin.op == .Div;
                try emitConst(self,"(");
                if (is_div) try emitConst(self,"@as(f64, @floatFromInt(");
                try genExprInFrame(self, bin.left.*, frame_fields);
                if (is_div) try emitConst(self,"))");
                try emitBinOp(self, bin.op);
                try genExprInFrame(self, bin.right.*, frame_fields);
                try emitConst(self,")");
            }
        },
        .call => |call| {
            // Handle function calls with frame variable arguments
            if (call.func.* == .name) {
                const func_name = call.func.*.name.id;
                if (std.mem.eql(u8, func_name, "sum")) {
                    const label = try self.emitInlineBlockStart("sum");
                    try emitConst(self,"\nvar total: i64 = 0;\nfor (");
                    if (call.args.len > 0) {
                        try genExprInFrame(self, call.args[0], frame_fields);
                    }
                    try emitFmtConst(self, ".items) |item| {{ total += item; }}\nbreak :{s} total;\n", .{label});
                    try self.emitInlineBlockEnd();
                    return;
                }
            }
            // Fallback to regular call generation
            try self.genExpr(node);
        },
        .listcomp => |comp| {
            // Check if calling an async function (has _async suffix)
            var is_async_call = false;
            if (comp.elt.* == .call) {
                const elem_call = comp.elt.*.call;
                if (elem_call.func.* == .name) {
                    // Check if this function name exists as a frame type
                    // For simplicity, check if we're in a context with awaits (bench_io vs bench_fanout)
                    is_async_call = true; // Assume async for now
                }
            }

            if (is_async_call) {
                // Handle list comprehension with catch unreachable (poll function can't use try)
                // Extract function name from the call
                var fn_name: []const u8 = "worker";
                if (comp.elt.* == .call) {
                    const elem_call = comp.elt.*.call;
                    if (elem_call.func.* == .name) {
                        fn_name = elem_call.func.*.name.id;
                    }
                }
                const label = try self.emitInlineBlockStart("comp");
                try emitConst(self,"\n    var __comp_result = std.ArrayListUnmanaged(*");
                try emitConst(self,fn_name);
                try emitConst(self,"_Frame){{}};\n");
                // Generate for loop
                if (comp.generators.len > 0) {
                    const gen = comp.generators[0];
                    try emitConst(self,"    var __comp_i: i64 = 0;\n");
                    try emitConst(self,"    while (__comp_i < ");
                    // Extract range end
                    if (gen.iter.* == .call) {
                        const range_call = gen.iter.*.call;
                        if (range_call.args.len > 0) {
                            try genExprInFrame(self, range_call.args[0], frame_fields);
                        }
                    }
                    try emitConst(self,") : (__comp_i += 1) {\n");
                    // Generate element
                    try emitConst(self,"        __comp_result.append(__global_allocator, ");
                    // comp.elt is the async function call
                    try emitConst(self,fn_name);
                    try emitConst(self,"_async(__comp_i)");
                    try emitConst(self," catch unreachable) catch unreachable;\n");
                    try emitConst(self,"    }\n");
                }
                try emitFmtConst(self, "    break :{s} __comp_result;\n", .{label});
                try self.emitInlineBlockEnd();
            } else {
                // Fallback to regular list comp
                try self.genExpr(node);
            }
        },
        else => {
            // Fallback to regular expression generation
            try self.genExpr(node);
        },
    }
}

fn genConstantInFrame(self: *NativeCodegen, c: ast.Node.Constant) CodegenError!void {
    switch (c.value) {
        .int => |i| try emitInt(self, i),
        .float => |f| try emitFloat(self, f),
        .string => |s| {
            try emitConst(self,"\"");
            try emitConst(self,s);
            try emitConst(self,"\"");
        },
        else => try emitConst(self,"0"),
    }
}

fn containsAwait(node: ast.Node) bool {
    return switch (node) {
        .await_expr => true,
        .expr_stmt => |e| containsAwait(e.value.*),
        .assign => |a| blk: {
            if (containsAwait(a.value.*)) break :blk true;
            for (a.targets) |t| if (containsAwait(t)) break :blk true;
            break :blk false;
        },
        .aug_assign => |a| containsAwait(a.target.*) or containsAwait(a.value.*),
        .call => |c| blk: {
            if (containsAwait(c.func.*)) break :blk true;
            for (c.args) |arg| if (containsAwait(arg)) break :blk true;
            for (c.keyword_args) |kw| if (containsAwait(kw.value)) break :blk true;
            break :blk false;
        },
        .binop => |b| containsAwait(b.left.*) or containsAwait(b.right.*),
        .unaryop => |u| containsAwait(u.operand.*),
        .boolop => |bo| blk: {
            for (bo.values) |v| if (containsAwait(v)) break :blk true;
            break :blk false;
        },
        .compare => |cmp| blk: {
            if (containsAwait(cmp.left.*)) break :blk true;
            for (cmp.comparators) |c| if (containsAwait(c)) break :blk true;
            break :blk false;
        },
        .subscript => |s| blk: {
            if (containsAwait(s.value.*)) break :blk true;
            switch (s.slice) {
                .index => |idx| break :blk containsAwait(idx.*),
                .slice => |range| {
                    if (range.lower) |l| if (containsAwait(l.*)) break :blk true;
                    if (range.upper) |u| if (containsAwait(u.*)) break :blk true;
                    if (range.step) |st| if (containsAwait(st.*)) break :blk true;
                    break :blk false;
                },
            }
        },
        .attribute => |a| containsAwait(a.value.*),
        .if_expr => |ie| containsAwait(ie.condition.*) or containsAwait(ie.body.*) or containsAwait(ie.orelse_value.*),
        .list => |l| blk: {
            for (l.elts) |e| if (containsAwait(e)) break :blk true;
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |e| if (containsAwait(e)) break :blk true;
            break :blk false;
        },
        .dict => |d| blk: {
            for (d.keys) |k| if (containsAwait(k)) break :blk true;
            for (d.values) |v| if (containsAwait(v)) break :blk true;
            break :blk false;
        },
        .fstring => |fstr| blk: {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| if (containsAwait(e.node.*)) break :blk true,
                    .format_expr => |fe| if (containsAwait(fe.expr.*)) break :blk true,
                    .conv_expr => |ce| if (containsAwait(ce.expr.*)) break :blk true,
                    .literal => {},
                }
            }
            break :blk false;
        },
        .listcomp => |lc| blk: {
            if (containsAwait(lc.elt.*)) break :blk true;
            for (lc.generators) |gen| {
                if (containsAwait(gen.iter.*)) break :blk true;
                for (gen.ifs) |cond| if (containsAwait(cond)) break :blk true;
            }
            break :blk false;
        },
        .dictcomp => |dc| blk: {
            if (containsAwait(dc.key.*) or containsAwait(dc.value.*)) break :blk true;
            for (dc.generators) |gen| {
                if (containsAwait(gen.iter.*)) break :blk true;
                for (gen.ifs) |cond| if (containsAwait(cond)) break :blk true;
            }
            break :blk false;
        },
        .genexp => |ge| blk: {
            if (containsAwait(ge.elt.*)) break :blk true;
            for (ge.generators) |gen| {
                if (containsAwait(gen.iter.*)) break :blk true;
                for (gen.ifs) |cond| if (containsAwait(cond)) break :blk true;
            }
            break :blk false;
        },
        .lambda => |lam| containsAwait(lam.body.*),
        .starred => |s| containsAwait(s.value.*),
        .return_stmt => |r| if (r.value) |v| containsAwait(v.*) else false,
        .if_stmt => |i| blk: {
            if (containsAwait(i.condition.*)) break :blk true;
            for (i.body) |s| if (containsAwait(s)) break :blk true;
            for (i.else_body) |s| if (containsAwait(s)) break :blk true;
            break :blk false;
        },
        .for_stmt => |f| blk: {
            if (containsAwait(f.iter.*)) break :blk true;
            for (f.body) |s| if (containsAwait(s)) break :blk true;
            if (f.orelse_body) |ob| for (ob) |s| if (containsAwait(s)) break :blk true;
            break :blk false;
        },
        .while_stmt => |w| blk: {
            if (containsAwait(w.condition.*)) break :blk true;
            for (w.body) |s| if (containsAwait(s)) break :blk true;
            if (w.orelse_body) |ob| for (ob) |s| if (containsAwait(s)) break :blk true;
            break :blk false;
        },
        .match_stmt => |m| blk: {
            if (containsAwait(m.subject.*)) break :blk true;
            for (m.cases) |case| {
                if (case.guard) |g| if (containsAwait(g.*)) break :blk true;
                for (case.body) |s| if (containsAwait(s)) break :blk true;
            }
            break :blk false;
        },
        .ann_assign => |a| if (a.value) |v| containsAwait(v.*) else false,
        .assert_stmt => |a| containsAwait(a.condition.*) or (if (a.msg) |m| containsAwait(m.*) else false),
        .raise_stmt => |r| (if (r.exc) |e| containsAwait(e.*) else false) or (if (r.cause) |c| containsAwait(c.*) else false),
        .yield_stmt => |y| if (y.value) |v| containsAwait(v.*) else false,
        .yield_from_stmt => |y| containsAwait(y.value.*),
        .function_def => |f| blk: {
            for (f.body) |s| if (containsAwait(s)) break :blk true;
            break :blk false;
        },
        .class_def => |c| blk: {
            for (c.body) |s| if (containsAwait(s)) break :blk true;
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| if (containsAwait(s)) break :blk true;
            for (t.handlers) |h| for (h.body) |s| if (containsAwait(s)) break :blk true;
            for (t.else_body) |s| if (containsAwait(s)) break :blk true;
            for (t.finalbody) |s| if (containsAwait(s)) break :blk true;
            break :blk false;
        },
        .with_stmt => |wth| blk: {
            if (containsAwait(wth.context_expr.*)) break :blk true;
            for (wth.body) |s| if (containsAwait(s)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

fn genCodeBeforeAwait(self: *NativeCodegen, stmt: ast.Node, point: AwaitPoint) CodegenError!void {
    _ = stmt;
    switch (point.await_type) {
        .sleep => {
            // Register timer with netpoller
            try emitConst(self,"            frame.__timer_");
            try emitInt(self, point.index);
            try emitConst(self," = runtime.netpoller.addTimer(@as(u64, @intFromFloat(");

            // Extract sleep duration from the call
            if (point.expr == .call) {
                const call = point.expr.call;
                if (call.args.len > 0) {
                    try self.genExpr(call.args[0]);
                } else {
                    try emitConst(self,"0");
                }
            }
            try emitConst(self," * 1_000_000_000)));\n");
        },
        .task => {
            // Create child frame for the coroutine call
            if (point.callee_name) |callee| {
                try emitConst(self,"            frame.__child_frame_");
                try emitInt(self, point.index);
                try emitConst(self," = ");
                try emitConst(self,callee);
                try emitConst(self,"_async(");
                // Pass arguments to the child frame
                if (point.expr == .call) {
                    const call = point.expr.call;
                    for (call.args, 0..) |arg, i| {
                        if (i > 0) try emitConst(self,", ");
                        try genFrameExpr(self, arg);
                    }
                }
                try emitConst(self,") catch unreachable;\n");
            }
        },
        else => {},
    }
}

fn genAwaitCheck(self: *NativeCodegen, point: AwaitPoint, await_points: []const AwaitPoint, tasks_callee: ?[]const u8) CodegenError!void {
    _ = await_points;
    switch (point.await_type) {
        .sleep => {
            try emitConst(self,"            if (!runtime.netpoller.timerReady(frame.__timer_");
            try emitInt(self, point.index);
            try emitConst(self,")) return null; // still waiting\n");
        },
        .task => {
            // Poll child frame until complete
            if (point.callee_name) |callee| {
                try emitConst(self,"            if (frame.__child_frame_");
                try emitInt(self, point.index);
                try emitConst(self,") |child| {\n");
                try emitConst(self,"                if (");
                try emitConst(self,callee);
                try emitConst(self,"_poll(child)) |result| {\n");
                // Store result if this is an assignment
                if (point.target_var) |var_name| {
                    try emitConst(self,"                    frame.");
                    try emitConst(self,var_name);
                    try emitConst(self," = result;\n");
                }
                try emitConst(self,"                    __global_allocator.destroy(child);\n");
                try emitConst(self,"                    frame.__child_frame_");
                try emitInt(self, point.index);
                try emitConst(self," = null;\n");
                try emitConst(self,"                } else return null; // child still running\n");
                try emitConst(self,"            }\n");
            }
        },
        .gather => {
            // Poll all frames in the tasks list concurrently
            try emitConst(self,"            var __remaining = frame.tasks.items.len;\n");
            try emitConst(self,"            var __done = __global_allocator.alloc(bool, frame.tasks.items.len) catch unreachable;\n");
            try emitConst(self,"            defer __global_allocator.free(__done);\n");
            try emitConst(self,"            @memset(__done, false);\n");
            if (point.target_var) |var_name| {
                try emitConst(self,"            frame.");
                try emitConst(self,var_name);
                try emitConst(self," = std.ArrayListUnmanaged(i64){};\n");
                try emitConst(self,"            frame.");
                try emitConst(self,var_name);
                try emitConst(self,".ensureTotalCapacity(__global_allocator, frame.tasks.items.len) catch unreachable;\n");
                try emitConst(self,"            for (0..frame.tasks.items.len) |_| frame.");
                try emitConst(self,var_name);
                try emitConst(self,".append(__global_allocator, 0) catch unreachable;\n");
            }
            try emitConst(self,"            while (__remaining > 0) {\n");
            try emitConst(self,"                std.Thread.yield() catch {};\n");
            try emitConst(self,"                for (frame.tasks.items, 0..) |__frame, __idx| {\n");
            try emitConst(self,"                    if (!__done[__idx]) {\n");
            try emitConst(self,"                        if (");
            if (tasks_callee) |callee| {
                try emitConst(self,callee);
            } else {
                try emitConst(self,"worker");
            }
            try emitConst(self,"_poll(__frame)) |__r| {\n");
            if (point.target_var) |var_name| {
                try emitConst(self,"                            frame.");
                try emitConst(self,var_name);
                try emitConst(self,".items[__idx] = __r;\n");
            }
            try emitConst(self,"                            __done[__idx] = true;\n");
            try emitConst(self,"                            __remaining -= 1;\n");
            try emitConst(self,"                            __global_allocator.destroy(__frame);\n");
            try emitConst(self,"                        }\n");
            try emitConst(self,"                    }\n");
            try emitConst(self,"                }\n");
            try emitConst(self,"            }\n");
        },
        else => {
            try emitConst(self,"            // Generic await - not yet implemented\n");
        },
    }
}

fn genFrameExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    switch (node) {
        .name => |n| {
            try emitConst(self,"frame.");
            try emitConst(self,n.id);
        },
        .constant => |c| switch (c.value) {
            .int => |i| try emitInt(self, i),
            else => try emitConst(self,"0"),
        },
        .binop => |bin| {
            // Use runtime.OperatorMod for proper Python modulo semantics (floored)
            if (bin.op == .Mod) {
                try emitConst(self,"runtime.OperatorMod{}.call(");
                try genFrameExpr(self, bin.left.*);
                try emitConst(self,", ");
                try genFrameExpr(self, bin.right.*);
                try emitConst(self,")");
            } else if (bin.op == .Pow) {
                // Zig doesn't have ** operator, use std.math.pow
                try emitConst(self,"std.math.pow(i64, ");
                try genFrameExpr(self, bin.left.*);
                try emitConst(self,", ");
                try genFrameExpr(self, bin.right.*);
                try emitConst(self,")");
            } else if (bin.op == .FloorDiv) {
                // Use runtime.OperatorFloordiv for proper Python floor division
                try emitConst(self,"runtime.OperatorFloordiv{}.call(");
                try genFrameExpr(self, bin.left.*);
                try emitConst(self,", ");
                try genFrameExpr(self, bin.right.*);
                try emitConst(self,")");
            } else {
                try emitConst(self,"(");
                try genFrameExpr(self, bin.left.*);
                try emitBinOp(self, bin.op);
                try genFrameExpr(self, bin.right.*);
                try emitConst(self,")");
            }
        },
        else => try emitConst(self,"0"),
    }
}

fn genSyncFunction(self: *NativeCodegen, func: ast.Node.FunctionDef) CodegenError!void {
    // Generate Frame for async def without awaits (Option 2: uniform Frame generation)
    // The poll function executes body and returns immediately in .start state
    const name = func.name;

    // 1. Generate State enum (just start and done)
    try emitConst(self,"const ");
    try emitConst(self,name);
    try emitConst(self,"_State = enum { start, done };\n\n");

    // 2. Generate Frame struct
    try emitConst(self,"const ");
    try emitConst(self,name);
    try emitConst(self,"_Frame = struct {\n");
    try emitConst(self,"    state: ");
    try emitConst(self,name);
    try emitConst(self,"_State = .start,\n");

    // Add parameters as fields (Two-Flow: use inferred types)
    for (func.args) |arg| {
        try emitConst(self,"    ");
        try emitConst(self,arg.name);
        try emitConst(self,": ");
        try emitConst(self,getAsyncVarType(self, name, arg.name));
        try emitConst(self,",\n");
    }

    // Two-Flow: use inferred return type
    const result_type = getAsyncReturnType(self, func);
    try emitConst(self,"    __result: ");
    try emitConst(self,result_type);
    try emitConst(self," = ");
    if (std.mem.eql(u8, result_type, "runtime.PyValue")) {
        try emitConst(self,"runtime.PyValue.none()");
    } else if (std.mem.eql(u8, result_type, "f64")) {
        try emitConst(self,"0.0");
    } else if (std.mem.eql(u8, result_type, "bool")) {
        try emitConst(self,"false");
    } else {
        try emitConst(self,"0");
    }
    try emitConst(self,",\n");
    try emitConst(self,"};\n\n");

    // 3. Generate poll function - executes synchronously and returns immediately
    // Two-Flow: use inferred return type
    try emitConst(self,"fn ");
    try emitConst(self,name);
    try emitConst(self,"_poll(frame: *");
    try emitConst(self,name);
    try emitConst(self,"_Frame) ?");
    try emitConst(self,result_type);
    try emitConst(self," {\n");
    try emitConst(self,"    switch (frame.state) {\n");
    try emitConst(self,"        .start => {\n");

    // Enter a scope so that codegen uses __global_allocator instead of allocator
    try self.symbol_table.pushScope();
    defer self.symbol_table.popScope();

    // Find mutated variables for proper var/const determination
    const mutated_vars = findMutatedVars(self.allocator, func.body) catch &[_][]const u8{};
    defer self.allocator.free(mutated_vars);

    // Generate function body - local vars stay local (not in frame)
    for (func.body) |stmt| {
        if (stmt == .return_stmt) {
            try emitConst(self,"            frame.__result = ");
            if (stmt.return_stmt.value) |val| {
                // Use genSyncExprInFrame - it checks if var is param (frame field) or local
                try genSyncExprInFrame(self, val.*, func.args);
            } else {
                try emitConst(self,"0");
            }
            try emitConst(self,";\n");
        } else {
            // Generate statement with frame variable access for params only
            try genSyncStatementInFrame(self, stmt, func.args, mutated_vars);
        }
    }

    try emitConst(self,"            frame.state = .done;\n");
    try emitConst(self,"            return frame.__result;\n");
    try emitConst(self,"        },\n");
    try emitConst(self,"        .done => return frame.__result,\n");
    try emitConst(self,"    }\n");
    try emitConst(self,"}\n\n");

    // 4. Generate async spawn function (Two-Flow: use inferred types)
    try emitConst(self,"fn ");
    try emitConst(self,name);
    try emitConst(self,"_async(");
    for (func.args, 0..) |arg, i| {
        if (i > 0) try emitConst(self,", ");
        try emitConst(self,arg.name);
        try emitConst(self,": ");
        try emitConst(self,getAsyncVarType(self, name, arg.name));
    }
    try emitConst(self,") !*");
    try emitConst(self,name);
    try emitConst(self,"_Frame {\n");
    try emitConst(self,"    const frame = try __global_allocator.create(");
    try emitConst(self,name);
    try emitConst(self,"_Frame);\n");
    try emitConst(self,"    frame.* = .{\n");
    for (func.args) |arg| {
        try emitConst(self,"        .");
        try emitConst(self,arg.name);
        try emitConst(self," = ");
        try emitConst(self,arg.name);
        try emitConst(self,",\n");
    }
    try emitConst(self,"    };\n");
    try emitConst(self,"    return frame;\n");
    try emitConst(self,"}\n\n");
}

/// Find variables that are mutated in the function body
/// A variable is mutated if it has method calls on it or augmented assignments
fn findMutatedVars(allocator: std.mem.Allocator, body: []ast.Node) ![]const []const u8 {
    var mutated = std.ArrayListUnmanaged([]const u8){};
    errdefer mutated.deinit(allocator);

    for (body) |stmt| {
        try findMutatedInNode(allocator, stmt, &mutated);
    }

    return mutated.toOwnedSlice(allocator);
}

fn findMutatedInNode(allocator: std.mem.Allocator, node: ast.Node, mutated: *std.ArrayListUnmanaged([]const u8)) !void {
    switch (node) {
        .expr_stmt => |expr| {
            // Check for method calls: var.method()
            if (expr.value.* == .call) {
                const call = expr.value.*.call;
                if (call.func.* == .attribute) {
                    const attr = call.func.*.attribute;
                    if (attr.value.* == .name) {
                        const var_name = attr.value.*.name.id;
                        // Add if not already in list
                        var found = false;
                        for (mutated.items) |v| {
                            if (std.mem.eql(u8, v, var_name)) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            try mutated.append(allocator, var_name);
                        }
                    }
                }
            }
        },
        .aug_assign => |aug| {
            if (aug.target.* == .name) {
                const var_name = aug.target.*.name.id;
                var found = false;
                for (mutated.items) |v| {
                    if (std.mem.eql(u8, v, var_name)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    try mutated.append(allocator, var_name);
                }
            }
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |stmt| {
                try findMutatedInNode(allocator, stmt, mutated);
            }
            if (for_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |stmt| {
                    try findMutatedInNode(allocator, stmt, mutated);
                }
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |stmt| {
                try findMutatedInNode(allocator, stmt, mutated);
            }
            for (if_stmt.else_body) |stmt| {
                try findMutatedInNode(allocator, stmt, mutated);
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |stmt| {
                try findMutatedInNode(allocator, stmt, mutated);
            }
            if (while_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |stmt| {
                    try findMutatedInNode(allocator, stmt, mutated);
                }
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |stmt| {
                try findMutatedInNode(allocator, stmt, mutated);
            }
            for (try_stmt.handlers) |handler| {
                for (handler.body) |stmt| {
                    try findMutatedInNode(allocator, stmt, mutated);
                }
            }
            for (try_stmt.else_body) |stmt| {
                try findMutatedInNode(allocator, stmt, mutated);
            }
            for (try_stmt.finalbody) |stmt| {
                try findMutatedInNode(allocator, stmt, mutated);
            }
        },
        .with_stmt => |with_stmt| {
            for (with_stmt.body) |stmt| {
                try findMutatedInNode(allocator, stmt, mutated);
            }
        },
        .match_stmt => |match_stmt| {
            for (match_stmt.cases) |case| {
                for (case.body) |stmt| {
                    try findMutatedInNode(allocator, stmt, mutated);
                }
            }
        },
        else => {},
    }
}

fn genSyncStatementInFrame(self: *NativeCodegen, stmt: ast.Node, args: []ast.Arg, mutated_vars: []const []const u8) CodegenError!void {
    switch (stmt) {
        .assign => |assign| {
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const target_name = assign.targets[0].name.id;
                // Check if this is a parameter (frame field)
                var is_param = false;
                for (args) |arg| {
                    if (std.mem.eql(u8, arg.name, target_name)) {
                        is_param = true;
                        break;
                    }
                }
                if (is_param) {
                    try emitConst(self,"            frame.");
                    try emitConst(self,target_name);
                    try emitConst(self," = ");
                    try genSyncExprInFrame(self, assign.value.*, args);
                    try emitConst(self,";\n");
                } else {
                    // Check if variable is mutated later (method calls, aug assign)
                    var is_mutated = false;
                    for (mutated_vars) |mv| {
                        if (std.mem.eql(u8, mv, target_name)) {
                            is_mutated = true;
                            break;
                        }
                    }
                    // Use var for mutated variables, const for immutable
                    try emitConst(self,"            ");
                    try emitConst(self,if (is_mutated) "var " else "const ");
                    try emitConst(self,target_name);
                    try emitConst(self," = ");
                    try genSyncExprInFrame(self, assign.value.*, args);
                    try emitConst(self,";\n");
                }
            }
        },
        .for_stmt => |for_stmt| {
            // Generate for loop with frame variable access
            try emitConst(self,"            {\n");
            try emitConst(self,"                var __i: i64 = 0;\n");
            try emitConst(self,"                while (__i < ");
            // Extract range end
            if (for_stmt.iter.* == .call) {
                const call = for_stmt.iter.*.call;
                if (call.args.len > 0) {
                    try genSyncExprInFrame(self, call.args[0], args);
                }
            }
            try emitConst(self,") : (__i += 1) {\n");
            // Bind loop variable
            if (for_stmt.target.* == .name) {
                try emitConst(self,"                    const ");
                try emitConst(self,for_stmt.target.*.name.id);
                try emitConst(self," = __i;\n");
            }
            // Generate body
            for (for_stmt.body) |body_stmt| {
                try genSyncStatementInFrame(self, body_stmt, args, mutated_vars);
            }
            try emitConst(self,"                }\n");
            try emitConst(self,"            }\n");
        },
        .aug_assign => |aug| {
            if (aug.target.* == .name) {
                const target_name = aug.target.*.name.id;
                try emitConst(self,"            ");
                try emitConst(self,target_name);
                try emitConst(self," = ");
                // Handle special operators that need function calls
                if (aug.op == .Pow) {
                    try emitConst(self,"std.math.pow(i64, ");
                    try emitConst(self,target_name);
                    try emitConst(self,", ");
                    try genSyncExprInFrameWithLoopVar(self, aug.value.*, args, "__i");
                    try emitConst(self,");\n");
                } else if (aug.op == .Mod) {
                    // Use runtime.OperatorMod for proper Python modulo semantics (floored)
                    try emitConst(self,"runtime.OperatorMod{}.call(");
                    try emitConst(self,target_name);
                    try emitConst(self,", ");
                    try genSyncExprInFrameWithLoopVar(self, aug.value.*, args, "__i");
                    try emitConst(self,");\n");
                } else if (aug.op == .FloorDiv) {
                    // Use runtime.OperatorFloordiv for proper Python floor division
                    try emitConst(self,"runtime.OperatorFloordiv{}.call(");
                    try emitConst(self,target_name);
                    try emitConst(self,", ");
                    try genSyncExprInFrameWithLoopVar(self, aug.value.*, args, "__i");
                    try emitConst(self,");\n");
                } else {
                    try emitConst(self,target_name);
                    try emitBinOp(self, aug.op);
                    try emitConst(self,"(");
                    try genSyncExprInFrameWithLoopVar(self, aug.value.*, args, "__i");
                    try emitConst(self,");\n");
                }
            }
        },
        .expr_stmt => |expr| {
            // Skip docstrings
            if (expr.value.* == .constant) {
                const c = expr.value.*.constant;
                if (c.value == .string) return;
            }
            try emitConst(self,"            _ = ");
            try genSyncExprInFrame(self, expr.value.*, args);
            try emitConst(self,";\n");
        },
        else => {},
    }
}

fn genSyncExprInFrameWithLoopVar(self: *NativeCodegen, node: ast.Node, args: []ast.Arg, loop_var: []const u8) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Check if this is a parameter (frame field)
            for (args) |arg| {
                if (std.mem.eql(u8, arg.name, n.id)) {
                    try emitConst(self,"frame.");
                    try emitConst(self,n.id);
                    return;
                }
            }
            // Check if it's the loop variable (needs cast)
            if (std.mem.eql(u8, n.id, "i") or std.mem.eql(u8, n.id, loop_var)) {
                try emitConst(self,"@as(i64, @intCast(");
                try emitConst(self,n.id);
                try emitConst(self,"))");
                return;
            }
            // Local variable
            try emitConst(self,n.id);
        },
        .constant => |c| switch (c.value) {
            .int => |i| try emitInt(self, i),
            else => try emitConst(self,"0"),
        },
        .binop => |bin| {
            // Use runtime.OperatorMod for proper Python modulo semantics (floored)
            if (bin.op == .Mod) {
                try emitConst(self,"runtime.OperatorMod{}.call(");
                try genSyncExprInFrameWithLoopVar(self, bin.left.*, args, loop_var);
                try emitConst(self,", ");
                try genSyncExprInFrameWithLoopVar(self, bin.right.*, args, loop_var);
                try emitConst(self,")");
            } else if (bin.op == .Pow) {
                try emitConst(self,"std.math.pow(i64, ");
                try genSyncExprInFrameWithLoopVar(self, bin.left.*, args, loop_var);
                try emitConst(self,", ");
                try genSyncExprInFrameWithLoopVar(self, bin.right.*, args, loop_var);
                try emitConst(self,")");
            } else if (bin.op == .FloorDiv) {
                // Use runtime.OperatorFloordiv for proper Python floor division
                try emitConst(self,"runtime.OperatorFloordiv{}.call(");
                try genSyncExprInFrameWithLoopVar(self, bin.left.*, args, loop_var);
                try emitConst(self,", ");
                try genSyncExprInFrameWithLoopVar(self, bin.right.*, args, loop_var);
                try emitConst(self,")");
            } else {
                try emitConst(self,"(");
                try genSyncExprInFrameWithLoopVar(self, bin.left.*, args, loop_var);
                try emitBinOp(self, bin.op);
                try genSyncExprInFrameWithLoopVar(self, bin.right.*, args, loop_var);
                try emitConst(self,")");
            }
        },
        .call => {
            // Delegate to genSyncExprInFrame for function calls
            try genSyncExprInFrame(self, node, args);
        },
        else => try emitConst(self,"0"),
    }
}

fn genSyncExprInFrame(self: *NativeCodegen, node: ast.Node, args: []ast.Arg) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Check if this is a parameter (frame field)
            for (args) |arg| {
                if (std.mem.eql(u8, arg.name, n.id)) {
                    try emitConst(self,"frame.");
                    try emitConst(self,n.id);
                    return;
                }
            }
            // Local variable
            try emitConst(self,n.id);
        },
        .constant => |c| switch (c.value) {
            .int => |i| try emitInt(self, i),
            else => try emitConst(self,"0"),
        },
        .binop => |bin| {
            // Use runtime.OperatorMod for proper Python modulo semantics (floored)
            if (bin.op == .Mod) {
                try emitConst(self,"runtime.OperatorMod{}.call(");
                try genSyncExprInFrame(self, bin.left.*, args);
                try emitConst(self,", ");
                try genSyncExprInFrame(self, bin.right.*, args);
                try emitConst(self,")");
            } else if (bin.op == .Pow) {
                try emitConst(self,"std.math.pow(i64, ");
                try genSyncExprInFrame(self, bin.left.*, args);
                try emitConst(self,", ");
                try genSyncExprInFrame(self, bin.right.*, args);
                try emitConst(self,")");
            } else if (bin.op == .FloorDiv) {
                // Use runtime.OperatorFloordiv for proper Python floor division
                try emitConst(self,"runtime.OperatorFloordiv{}.call(");
                try genSyncExprInFrame(self, bin.left.*, args);
                try emitConst(self,", ");
                try genSyncExprInFrame(self, bin.right.*, args);
                try emitConst(self,")");
            } else {
                try emitConst(self,"(");
                try genSyncExprInFrame(self, bin.left.*, args);
                try emitBinOp(self, bin.op);
                try genSyncExprInFrame(self, bin.right.*, args);
                try emitConst(self,")");
            }
        },
        .call => |call| {
            // Handle function calls with frame-aware argument generation
            if (call.func.* == .attribute) {
                const attr = call.func.*.attribute;
                // Module call like hashlib.sha256() or method call like h.update()
                if (attr.value.* == .name) {
                    const obj_name = attr.value.*.name.id;
                    const method = attr.attr;

                    // Check if it's a module (hashlib, time, etc.)
                    if (std.mem.eql(u8, obj_name, "hashlib")) {
                        try emitConst(self,"hashlib.");
                        try emitConst(self,method);
                        try emitConst(self,"(");
                        for (call.args, 0..) |arg_expr, idx| {
                            if (idx > 0) try emitConst(self,", ");
                            try genSyncExprInFrame(self, arg_expr, args);
                        }
                        try emitConst(self,")");
                        return;
                    }

                    // It's a method call on a local variable (h.update(), h.hexdigest())
                    // Handle specific methods that need special treatment
                    if (std.mem.eql(u8, method, "hexdigest") or std.mem.eql(u8, method, "digest")) {
                        // These return error unions - poll can't return errors, use catch
                        try emitConst(self,"(");
                        try emitConst(self,obj_name);
                        try emitConst(self,".");
                        try emitConst(self,method);
                        try emitConst(self,"(__global_allocator) catch unreachable)");
                        return;
                    }

                    // Regular method call: obj.method(args)
                    try emitConst(self,obj_name);
                    try emitConst(self,".");
                    try emitConst(self,method);
                    try emitConst(self,"(");
                    for (call.args, 0..) |arg_expr, idx| {
                        if (idx > 0) try emitConst(self,", ");
                        try genSyncExprInFrame(self, arg_expr, args);
                    }
                    try emitConst(self,")");
                    return;
                }
                // Chained method call like str(x).encode()
                if (attr.value.* == .call) {
                    const method = attr.attr;
                    // Skip .encode() on strings - Zig strings are already bytes
                    if (std.mem.eql(u8, method, "encode")) {
                        // Just generate the inner call, skip .encode()
                        try genSyncExprInFrame(self, attr.value.*, args);
                        return;
                    }
                    // Generate the inner call first
                    try genSyncExprInFrame(self, attr.value.*, args);
                    // Then the method
                    try emitConst(self,".");
                    try emitConst(self,method);
                    try emitConst(self,"(");
                    for (call.args, 0..) |arg_expr, idx| {
                        if (idx > 0) try emitConst(self,", ");
                        try genSyncExprInFrame(self, arg_expr, args);
                    }
                    try emitConst(self,")");
                    return;
                }
            }
            // Function call like str(), len(), etc.
            if (call.func.* == .name) {
                const func_name = call.func.*.name.id;

                if (std.mem.eql(u8, func_name, "str")) {
                    // str(x) -> std.fmt.allocPrint(__global_allocator, "{d}", .{x}) catch unreachable
                    try emitConst(self,"(std.fmt.allocPrint(__global_allocator, \"{d}\", .{");
                    if (call.args.len > 0) {
                        try genSyncExprInFrame(self, call.args[0], args);
                    }
                    try emitConst(self,"}) catch unreachable)");
                    return;
                }
                if (std.mem.eql(u8, func_name, "len")) {
                    // len(x) -> x.len or x.items.len
                    try emitConst(self,"@as(i64, @intCast(");
                    if (call.args.len > 0) {
                        try genSyncExprInFrame(self, call.args[0], args);
                    }
                    try emitConst(self,".len))");
                    return;
                }
                if (std.mem.eql(u8, func_name, "range")) {
                    // range(n) -> just emit the argument for use in loop bounds
                    if (call.args.len > 0) {
                        try genSyncExprInFrame(self, call.args[0], args);
                    }
                    return;
                }

                // Generic function call
                try emitConst(self,func_name);
                try emitConst(self,"(");
                for (call.args, 0..) |arg_expr, idx| {
                    if (idx > 0) try emitConst(self,", ");
                    try genSyncExprInFrame(self, arg_expr, args);
                }
                try emitConst(self,")");
                return;
            }
            // Fallback to regular codegen (shouldn't reach here)
            try self.genExpr(node);
        },
        else => try emitConst(self,"0"),
    }
}
