/// Async State Machine Transformation
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
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

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
    var points = std.ArrayList(AwaitPoint){};
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
    points: *std.ArrayList(AwaitPoint),
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
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |stmt| {
                try findAwaitPointsInNode(allocator, stmt, points, index);
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
    var vars = std.ArrayList([]const u8){};
    errdefer vars.deinit(allocator);

    for (body) |stmt| {
        try findVarsInNode(allocator, stmt, &vars);
    }

    return vars.toOwnedSlice(allocator);
}

fn findVarsInNode(allocator: std.mem.Allocator, node: ast.Node, vars: *std.ArrayList([]const u8)) !void {
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
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |stmt| {
                try findVarsInNode(allocator, stmt, vars);
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
    try self.emit("const ");
    try self.emit(name);
    try self.emit("_State = enum { start");
    for (await_points, 0..) |_, i| {
        try self.emit(", await_");
        try emitInt(self, i);
    }
    try self.emit(", done };\n\n");

    // 2. Generate Frame struct
    try self.emit("const ");
    try self.emit(name);
    try self.emit("_Frame = struct {\n");
    try self.emit("    state: ");
    try self.emit(name);
    try self.emit("_State = .start,\n");

    // Add parameters as fields
    for (func.args) |arg| {
        try self.emit("    ");
        try self.emit(arg.name);
        try self.emit(": i64,\n");
    }

    // Add timer_id for sleep awaits and child frames for task awaits
    for (await_points) |point| {
        if (point.await_type == .sleep) {
            try self.emit("    __timer_");
            try emitInt(self, point.index);
            try self.emit(": u64 = 0,\n");
        } else if (point.await_type == .task) {
            if (point.callee_name) |callee| {
                try self.emit("    __child_frame_");
                try emitInt(self, point.index);
                try self.emit(": ?*");
                try self.emit(callee);
                try self.emit("_Frame = null,\n");
            }
        }
    }

    // Add local variables for await results (except gather, handled separately)
    for (await_points) |point| {
        if (point.await_type != .gather) {
            if (point.target_var) |var_name| {
                try self.emit("    ");
                try self.emit(var_name);
                try self.emit(": i64 = 0,\n");
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
            try self.emit("    ");
            try self.emit(var_name);
            // Special handling for common async patterns
            if (std.mem.eql(u8, var_name, "tasks")) {
                // Use the actual callee name from list comprehension
                if (tasks_callee) |callee| {
                    try self.emit(": std.ArrayList(*");
                    try self.emit(callee);
                    try self.emit("_Frame) = .{},\n");
                } else {
                    try self.emit(": std.ArrayList(*anyopaque) = .{},\n");
                }
            } else if (std.mem.eql(u8, var_name, "start") or std.mem.eql(u8, var_name, "elapsed") or std.mem.eql(u8, var_name, "end")) {
                try self.emit(": f64 = 0,\n");
            } else {
                try self.emit(": i64 = 0,\n");
            }
        }
    }

    // Add gather result fields with proper list type
    for (await_points) |point| {
        if (point.await_type == .gather) {
            if (point.target_var) |var_name| {
                try self.emit("    ");
                try self.emit(var_name);
                try self.emit(": std.ArrayList(i64) = .{},\n");
            }
        }
    }

    // Add result field
    try self.emit("    __result: i64 = 0,\n");
    try self.emit("};\n\n");

    // 3. Generate poll function
    try self.emit("fn ");
    try self.emit(name);
    try self.emit("_poll(frame: *");
    try self.emit(name);
    try self.emit("_Frame) ?i64 {\n");
    try self.emit("    switch (frame.state) {\n");

    // Generate state handlers
    try genStateHandlers(self, func, await_points, local_vars, tasks_callee);

    try self.emit("    }\n");
    try self.emit("}\n\n");

    // 4. Generate spawn function that returns frame
    try self.emit("fn ");
    try self.emit(name);
    try self.emit("_async(");
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(arg.name);
        try self.emit(": i64");
    }
    try self.emit(") !*");
    try self.emit(name);
    try self.emit("_Frame {\n");
    try self.emit("    const frame = try __global_allocator.create(");
    try self.emit(name);
    try self.emit("_Frame);\n");
    try self.emit("    frame.* = .{\n");
    for (func.args) |arg| {
        try self.emit("        .");
        try self.emit(arg.name);
        try self.emit(" = ");
        try self.emit(arg.name);
        try self.emit(",\n");
    }
    try self.emit("    };\n");
    try self.emit("    return frame;\n");
    try self.emit("}\n\n");
}

fn genStateHandlers(self: *NativeCodegen, func: ast.Node.FunctionDef, await_points: []const AwaitPoint, local_vars: []const []const u8, tasks_callee: ?[]const u8) CodegenError!void {
    // Collect frame field names for variable remapping
    var frame_fields = std.ArrayList([]const u8){};
    defer frame_fields.deinit(self.allocator);

    // Parameters are frame fields
    for (func.args) |arg| {
        frame_fields.append(self.allocator, arg.name) catch {};
    }
    // Await results are frame fields
    for (await_points) |point| {
        if (point.target_var) |var_name| {
            frame_fields.append(self.allocator, var_name) catch {};
        }
    }
    // Local variables are frame fields
    for (local_vars) |var_name| {
        frame_fields.append(self.allocator, var_name) catch {};
    }

    // Start state - execute until first await
    try self.emit("        .start => {\n");

    var current_await: usize = 0;
    var ended_with_return = false;

    for (func.body, 0..) |stmt, stmt_idx| {
        ended_with_return = false;

        if (containsAwait(stmt)) {
            // Generate code to initiate the await, then transition
            try genCodeBeforeAwait(self, stmt, await_points[current_await]);
            try self.emit("            frame.state = .await_");
            try emitInt(self, current_await);
            try self.emit(";\n");
            try self.emit("            return null; // yield\n");
            try self.emit("        },\n");

            // Generate await state handler
            try self.emit("        .await_");
            try emitInt(self, current_await);
            try self.emit(" => {\n");
            try genAwaitCheck(self, await_points[current_await], await_points, tasks_callee);

            current_await += 1;
        } else if (stmt == .return_stmt) {
            try self.emit("            frame.__result = ");
            if (stmt.return_stmt.value) |val| {
                try genFrameExpr(self, val.*);
            } else {
                try self.emit("0");
            }
            try self.emit(";\n");
            try self.emit("            frame.state = .done;\n");
            try self.emit("            return frame.__result;\n");
            ended_with_return = true;
        } else {
            // Generate non-await statement with frame prefix for local vars
            try genStatementInFrame(self, stmt, frame_fields.items);
        }

        // After processing last statement, close the state if not a return
        if (stmt_idx == func.body.len - 1 and !ended_with_return) {
            try self.emit("            frame.state = .done;\n");
            try self.emit("            return frame.__result;\n");
        }
    }

    try self.emit("        },\n");

    // Done state
    try self.emit("        .done => return frame.__result,\n");
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
                        try self.emit("            ");
                        try self.emit("std.debug.print(\"{s}\\n\", .{");
                        if (call.args.len > 0) {
                            try genExprInFrame(self, call.args[0], frame_fields);
                        }
                        try self.emit("});\n");
                        return;
                    }
                }
            }
            // Fallback - generate using normal codegen (may have issues with frame vars)
            try self.emit("            ");
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
                try self.emit("            frame.");
                try self.emit(target_name.?);
                try self.emit(" = ");
                try genExprInFrame(self, assign.value.*, frame_fields);
                try self.emit(";\n");
            } else if (target_name != null) {
                // Local variable - emit with frame-aware expression
                try self.emit("            const ");
                try self.emit(target_name.?);
                try self.emit(" = ");
                try genExprInFrame(self, assign.value.*, frame_fields);
                try self.emit(";\n");
            } else {
                // Fallback to normal codegen
                try self.emit("            ");
                try self.generateStmt(stmt);
            }
        },
        .for_stmt => |for_stmt| {
            // Generate for loop with frame variable access
            try self.emit("            {\n");
            try self.emit("                var __i: i64 = 0;\n");
            try self.emit("                while (__i < ");
            // Extract range end
            if (for_stmt.iter.* == .call) {
                const call = for_stmt.iter.*.call;
                if (call.args.len > 0) {
                    try genExprInFrame(self, call.args[0], frame_fields);
                }
            }
            try self.emit(") : (__i += 1) {\n");
            // Bind loop variable
            if (for_stmt.target.* == .name) {
                try self.emit("                    const ");
                try self.emit(for_stmt.target.*.name.id);
                try self.emit(" = __i;\n");
            }
            // Generate body with frame prefix
            for (for_stmt.body) |body_stmt| {
                try genStatementInFrameNested(self, body_stmt, frame_fields);
            }
            try self.emit("                }\n");
            try self.emit("            }\n");
        },
        .aug_assign => |aug| {
            // Handle augmented assignment with frame prefix
            if (aug.target.* == .name) {
                const target_name = aug.target.*.name.id;
                // Check if target is a frame field
                var is_frame_field = false;
                for (frame_fields) |field| {
                    if (std.mem.eql(u8, field, target_name)) {
                        is_frame_field = true;
                        break;
                    }
                }
                try self.emit("            ");
                if (is_frame_field) {
                    try self.emit("frame.");
                }
                try self.emit(target_name);
                try self.emit(" = ");
                if (is_frame_field) {
                    try self.emit("frame.");
                }
                try self.emit(target_name);
                switch (aug.op) {
                    .Add => try self.emit(" + "),
                    .Sub => try self.emit(" - "),
                    .Mult => try self.emit(" * "),
                    .Div => try self.emit(" / "),
                    .Mod => try self.emit(" % "),
                    .BitAnd => try self.emit(" & "),
                    .BitOr => try self.emit(" | "),
                    .BitXor => try self.emit(" ^ "),
                    .LShift => try self.emit(" << "),
                    .RShift => try self.emit(" >> "),
                    else => try self.emit(" + "),
                }
                try self.emit("(");
                try genExprInFrame(self, aug.value.*, frame_fields);
                try self.emit(");\n");
            }
        },
        else => {
            try self.emit("            ");
            try self.generateStmt(stmt);
        },
    }
}

fn genStatementInFrameNested(self: *NativeCodegen, stmt: ast.Node, frame_fields: []const []const u8) CodegenError!void {
    switch (stmt) {
        .assign => |assign| {
            // Handle regular assignment in nested context
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const target_name = assign.targets[0].name.id;
                try self.emit("                    ");
                try self.emit(target_name);
                try self.emit(" = ");
                try genExprInFrameNested(self, assign.value.*, frame_fields);
                try self.emit(";\n");
            }
        },
        .aug_assign => |aug| {
            if (aug.target.* == .name) {
                const target_name = aug.target.*.name.id;
                // Check if target is a frame field
                var is_frame_field = false;
                for (frame_fields) |field| {
                    if (std.mem.eql(u8, field, target_name)) {
                        is_frame_field = true;
                        break;
                    }
                }
                try self.emit("                    ");
                if (is_frame_field) {
                    try self.emit("frame.");
                }
                try self.emit(target_name);
                try self.emit(" = ");
                if (is_frame_field) {
                    try self.emit("frame.");
                }
                try self.emit(target_name);
                switch (aug.op) {
                    .Add => try self.emit(" + "),
                    .Sub => try self.emit(" - "),
                    .Mult => try self.emit(" * "),
                    .Div => try self.emit(" / "),
                    .Mod => try self.emit(" % "),
                    .BitAnd => try self.emit(" & "),
                    .BitOr => try self.emit(" | "),
                    .BitXor => try self.emit(" ^ "),
                    .LShift => try self.emit(" << "),
                    .RShift => try self.emit(" >> "),
                    else => try self.emit(" + "),
                }
                try self.emit("(");
                try genExprInFrameNested(self, aug.value.*, frame_fields);
                try self.emit(");\n");
            }
        },
        else => {
            try self.emit("                    ");
            try self.generateStmt(stmt);
        },
    }
}

fn genExprInFrameNested(self: *NativeCodegen, node: ast.Node, frame_fields: []const []const u8) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Check if this is a frame field
            for (frame_fields) |field| {
                if (std.mem.eql(u8, n.id, field)) {
                    try self.emit("frame.");
                    try self.emit(n.id);
                    return;
                }
            }
            // Local variable - might be loop var, cast to i64
            if (std.mem.eql(u8, n.id, "i")) {
                try self.emit("@as(i64, @intCast(");
                try self.emit(n.id);
                try self.emit("))");
            } else {
                try self.emit(n.id);
            }
        },
        .constant => |c| {
            switch (c.value) {
                .int => |i| {
                    var buf: [32]u8 = undefined;
                    const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
                    try self.emit(slice);
                },
                else => try self.emit("0"),
            }
        },
        .binop => |bin| {
            try self.emit("(");
            try genExprInFrameNested(self, bin.left.*, frame_fields);
            switch (bin.op) {
                .Add => try self.emit(" + "),
                .Sub => try self.emit(" - "),
                .Mult => try self.emit(" * "),
                .Div => try self.emit(" / "),
                .Mod => try self.emit(" % "),
                .BitAnd => try self.emit(" & "),
                .BitOr => try self.emit(" | "),
                .BitXor => try self.emit(" ^ "),
                .LShift => try self.emit(" << "),
                .RShift => try self.emit(" >> "),
                else => try self.emit(" + "),
            }
            try genExprInFrameNested(self, bin.right.*, frame_fields);
            try self.emit(")");
        },
        else => try self.emit("0"),
    }
}

fn genExprInFrame(self: *NativeCodegen, node: ast.Node, frame_fields: []const []const u8) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Check if this is a frame field
            for (frame_fields) |field| {
                if (std.mem.eql(u8, n.id, field)) {
                    try self.emit("frame.");
                    try self.emit(n.id);
                    return;
                }
            }
            // Not a frame field, emit as-is
            try self.emit(n.id);
        },
        .fstring => |fs| {
            // Handle f-string with frame variable interpolation
            try self.emit("(std.fmt.allocPrint(__global_allocator, \"");
            for (fs.parts) |part| {
                switch (part) {
                    .literal => |lit| try self.emit(lit),
                    .expr, .format_expr, .conv_expr => try self.emit("{any}"),
                }
            }
            try self.emit("\", .{");
            var first = true;
            for (fs.parts) |part| {
                switch (part) {
                    .literal => {},
                    .expr => |e| {
                        if (!first) try self.emit(", ");
                        first = false;
                        try genExprInFrame(self, e.*, frame_fields);
                    },
                    .format_expr => |fe| {
                        if (!first) try self.emit(", ");
                        first = false;
                        try genExprInFrame(self, fe.expr.*, frame_fields);
                    },
                    .conv_expr => |ce| {
                        if (!first) try self.emit(", ");
                        first = false;
                        try genExprInFrame(self, ce.expr.*, frame_fields);
                    },
                }
            }
            try self.emit("}) catch \"\")");
        },
        .constant => |c| {
            try genConstantInFrame(self, c);
        },
        .binop => |bin| {
            // Handle binary operations with frame variable references
            // For division with mixed types, cast to f64
            const is_div = bin.op == .Div;
            try self.emit("(");
            if (is_div) try self.emit("@as(f64, @floatFromInt(");
            try genExprInFrame(self, bin.left.*, frame_fields);
            if (is_div) try self.emit("))");
            switch (bin.op) {
                .Add => try self.emit(" + "),
                .Sub => try self.emit(" - "),
                .Mult => try self.emit(" * "),
                .Div => try self.emit(" / "),
                .Mod => try self.emit(" % "),
                .BitAnd => try self.emit(" & "),
                .BitOr => try self.emit(" | "),
                .BitXor => try self.emit(" ^ "),
                .LShift => try self.emit(" << "),
                .RShift => try self.emit(" >> "),
                else => try self.emit(" + "),
            }
            try genExprInFrame(self, bin.right.*, frame_fields);
            try self.emit(")");
        },
        .call => |call| {
            // Handle function calls with frame variable arguments
            if (call.func.* == .name) {
                const func_name = call.func.*.name.id;
                if (std.mem.eql(u8, func_name, "sum")) {
                    // sum(list) -> blk: { var total = 0; for (list.items) |i| total += i; break :blk total; }
                    try self.emit("blk: {\nvar total: i64 = 0;\nfor (");
                    if (call.args.len > 0) {
                        try genExprInFrame(self, call.args[0], frame_fields);
                    }
                    try self.emit(".items) |item| { total += item; }\nbreak :blk total;\n}");
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
                try self.emit("comp_blk: {\n");
                try self.emit("    var __comp_result = std.ArrayList(*");
                try self.emit(fn_name);
                try self.emit("_Frame){};\n");
                // Generate for loop
                if (comp.generators.len > 0) {
                    const gen = comp.generators[0];
                    try self.emit("    var __comp_i: i64 = 0;\n");
                    try self.emit("    while (__comp_i < ");
                    // Extract range end
                    if (gen.iter.* == .call) {
                        const range_call = gen.iter.*.call;
                        if (range_call.args.len > 0) {
                            try genExprInFrame(self, range_call.args[0], frame_fields);
                        }
                    }
                    try self.emit(") : (__comp_i += 1) {\n");
                    // Generate element
                    try self.emit("        __comp_result.append(__global_allocator, ");
                    // comp.elt is the async function call
                    try self.emit(fn_name);
                    try self.emit("_async(__comp_i)");
                    try self.emit(" catch unreachable) catch unreachable;\n");
                    try self.emit("    }\n");
                }
                try self.emit("    break :comp_blk __comp_result;\n}");
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
        .int => |i| {
            var buf: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
            try self.emit(slice);
        },
        .float => |f| {
            var buf: [64]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.OutOfMemory;
            try self.emit(slice);
        },
        .string => |s| {
            try self.emit("\"");
            try self.emit(s);
            try self.emit("\"");
        },
        else => try self.emit("0"),
    }
}

fn containsAwait(node: ast.Node) bool {
    return switch (node) {
        .await_expr => true,
        .expr_stmt => |e| containsAwait(e.value.*),
        .assign => |a| containsAwait(a.value.*),
        else => false,
    };
}

fn genCodeBeforeAwait(self: *NativeCodegen, stmt: ast.Node, point: AwaitPoint) CodegenError!void {
    _ = stmt;
    switch (point.await_type) {
        .sleep => {
            // Register timer with netpoller
            try self.emit("            frame.__timer_");
            try emitInt(self, point.index);
            try self.emit(" = runtime.netpoller.addTimer(@as(u64, @intFromFloat(");

            // Extract sleep duration from the call
            if (point.expr == .call) {
                const call = point.expr.call;
                if (call.args.len > 0) {
                    try self.genExpr(call.args[0]);
                } else {
                    try self.emit("0");
                }
            }
            try self.emit(" * 1_000_000_000)));\n");
        },
        .task => {
            // Create child frame for the coroutine call
            if (point.callee_name) |callee| {
                try self.emit("            frame.__child_frame_");
                try emitInt(self, point.index);
                try self.emit(" = ");
                try self.emit(callee);
                try self.emit("_async(");
                // Pass arguments to the child frame
                if (point.expr == .call) {
                    const call = point.expr.call;
                    for (call.args, 0..) |arg, i| {
                        if (i > 0) try self.emit(", ");
                        try genFrameExpr(self, arg);
                    }
                }
                try self.emit(") catch unreachable;\n");
            }
        },
        else => {},
    }
}

fn genAwaitCheck(self: *NativeCodegen, point: AwaitPoint, await_points: []const AwaitPoint, tasks_callee: ?[]const u8) CodegenError!void {
    _ = await_points;
    switch (point.await_type) {
        .sleep => {
            try self.emit("            if (!runtime.netpoller.timerReady(frame.__timer_");
            try emitInt(self, point.index);
            try self.emit(")) return null; // still waiting\n");
        },
        .task => {
            // Poll child frame until complete
            if (point.callee_name) |callee| {
                try self.emit("            if (frame.__child_frame_");
                try emitInt(self, point.index);
                try self.emit(") |child| {\n");
                try self.emit("                if (");
                try self.emit(callee);
                try self.emit("_poll(child)) |result| {\n");
                // Store result if this is an assignment
                if (point.target_var) |var_name| {
                    try self.emit("                    frame.");
                    try self.emit(var_name);
                    try self.emit(" = result;\n");
                }
                try self.emit("                    __global_allocator.destroy(child);\n");
                try self.emit("                    frame.__child_frame_");
                try emitInt(self, point.index);
                try self.emit(" = null;\n");
                try self.emit("                } else return null; // child still running\n");
                try self.emit("            }\n");
            }
        },
        .gather => {
            // Poll all frames in the tasks list concurrently
            try self.emit("            var __remaining = frame.tasks.items.len;\n");
            try self.emit("            var __done = __global_allocator.alloc(bool, frame.tasks.items.len) catch unreachable;\n");
            try self.emit("            defer __global_allocator.free(__done);\n");
            try self.emit("            @memset(__done, false);\n");
            if (point.target_var) |var_name| {
                try self.emit("            frame.");
                try self.emit(var_name);
                try self.emit(" = std.ArrayList(i64){};\n");
                try self.emit("            frame.");
                try self.emit(var_name);
                try self.emit(".ensureTotalCapacity(__global_allocator, frame.tasks.items.len) catch unreachable;\n");
                try self.emit("            for (0..frame.tasks.items.len) |_| frame.");
                try self.emit(var_name);
                try self.emit(".append(__global_allocator, 0) catch unreachable;\n");
            }
            try self.emit("            while (__remaining > 0) {\n");
            try self.emit("                std.Thread.yield() catch {};\n");
            try self.emit("                for (frame.tasks.items, 0..) |__frame, __idx| {\n");
            try self.emit("                    if (!__done[__idx]) {\n");
            try self.emit("                        if (");
            if (tasks_callee) |callee| {
                try self.emit(callee);
            } else {
                try self.emit("worker");
            }
            try self.emit("_poll(__frame)) |__r| {\n");
            if (point.target_var) |var_name| {
                try self.emit("                            frame.");
                try self.emit(var_name);
                try self.emit(".items[__idx] = __r;\n");
            }
            try self.emit("                            __done[__idx] = true;\n");
            try self.emit("                            __remaining -= 1;\n");
            try self.emit("                            __global_allocator.destroy(__frame);\n");
            try self.emit("                        }\n");
            try self.emit("                    }\n");
            try self.emit("                }\n");
            try self.emit("            }\n");
        },
        else => {
            try self.emit("            // Generic await - not yet implemented\n");
        },
    }
}

fn genFrameExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    switch (node) {
        .name => |n| {
            try self.emit("frame.");
            try self.emit(n.id);
        },
        .constant => |c| {
            switch (c.value) {
                .int => |i| {
                    var buf: [32]u8 = undefined;
                    const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
                    try self.emit(slice);
                },
                else => try self.emit("0"),
            }
        },
        .binop => |bin| {
            try self.emit("(");
            try genFrameExpr(self, bin.left.*);
            switch (bin.op) {
                .Add => try self.emit(" + "),
                .Sub => try self.emit(" - "),
                .Mult => try self.emit(" * "),
                .Div => try self.emit(" / "),
                .Mod => try self.emit(" % "),
                else => try self.emit(" ? "),
            }
            try genFrameExpr(self, bin.right.*);
            try self.emit(")");
        },
        else => try self.emit("0"),
    }
}

fn genSyncFunction(self: *NativeCodegen, func: ast.Node.FunctionDef) CodegenError!void {
    // Generate Frame for async def without awaits (Option 2: uniform Frame generation)
    // The poll function executes body and returns immediately in .start state
    const name = func.name;

    // 1. Generate State enum (just start and done)
    try self.emit("const ");
    try self.emit(name);
    try self.emit("_State = enum { start, done };\n\n");

    // 2. Generate Frame struct
    try self.emit("const ");
    try self.emit(name);
    try self.emit("_Frame = struct {\n");
    try self.emit("    state: ");
    try self.emit(name);
    try self.emit("_State = .start,\n");

    // Add parameters as fields
    for (func.args) |arg| {
        try self.emit("    ");
        try self.emit(arg.name);
        try self.emit(": i64,\n");
    }

    try self.emit("    __result: i64 = 0,\n");
    try self.emit("};\n\n");

    // 3. Generate poll function - executes synchronously and returns immediately
    try self.emit("fn ");
    try self.emit(name);
    try self.emit("_poll(frame: *");
    try self.emit(name);
    try self.emit("_Frame) ?i64 {\n");
    try self.emit("    switch (frame.state) {\n");
    try self.emit("        .start => {\n");

    // Enter a scope so that codegen uses __global_allocator instead of allocator
    try self.symbol_table.pushScope();
    defer self.symbol_table.popScope();

    // Find mutated variables for proper var/const determination
    const mutated_vars = findMutatedVars(self.allocator, func.body) catch &[_][]const u8{};
    defer self.allocator.free(mutated_vars);

    // Generate function body - local vars stay local (not in frame)
    for (func.body) |stmt| {
        if (stmt == .return_stmt) {
            try self.emit("            frame.__result = ");
            if (stmt.return_stmt.value) |val| {
                // Use genSyncExprInFrame - it checks if var is param (frame field) or local
                try genSyncExprInFrame(self, val.*, func.args);
            } else {
                try self.emit("0");
            }
            try self.emit(";\n");
        } else {
            // Generate statement with frame variable access for params only
            try genSyncStatementInFrame(self, stmt, func.args, mutated_vars);
        }
    }

    try self.emit("            frame.state = .done;\n");
    try self.emit("            return frame.__result;\n");
    try self.emit("        },\n");
    try self.emit("        .done => return frame.__result,\n");
    try self.emit("    }\n");
    try self.emit("}\n\n");

    // 4. Generate async spawn function
    try self.emit("fn ");
    try self.emit(name);
    try self.emit("_async(");
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(arg.name);
        try self.emit(": i64");
    }
    try self.emit(") !*");
    try self.emit(name);
    try self.emit("_Frame {\n");
    try self.emit("    const frame = try __global_allocator.create(");
    try self.emit(name);
    try self.emit("_Frame);\n");
    try self.emit("    frame.* = .{\n");
    for (func.args) |arg| {
        try self.emit("        .");
        try self.emit(arg.name);
        try self.emit(" = ");
        try self.emit(arg.name);
        try self.emit(",\n");
    }
    try self.emit("    };\n");
    try self.emit("    return frame;\n");
    try self.emit("}\n\n");
}

/// Find variables that are mutated in the function body
/// A variable is mutated if it has method calls on it or augmented assignments
fn findMutatedVars(allocator: std.mem.Allocator, body: []ast.Node) ![]const []const u8 {
    var mutated = std.ArrayList([]const u8){};
    errdefer mutated.deinit(allocator);

    for (body) |stmt| {
        try findMutatedInNode(allocator, stmt, &mutated);
    }

    return mutated.toOwnedSlice(allocator);
}

fn findMutatedInNode(allocator: std.mem.Allocator, node: ast.Node, mutated: *std.ArrayList([]const u8)) !void {
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
                    try self.emit("            frame.");
                    try self.emit(target_name);
                    try self.emit(" = ");
                    try genSyncExprInFrame(self, assign.value.*, args);
                    try self.emit(";\n");
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
                    try self.emit("            ");
                    try self.emit(if (is_mutated) "var " else "const ");
                    try self.emit(target_name);
                    try self.emit(" = ");
                    try genSyncExprInFrame(self, assign.value.*, args);
                    try self.emit(";\n");
                }
            }
        },
        .for_stmt => |for_stmt| {
            // Generate for loop with frame variable access
            try self.emit("            {\n");
            try self.emit("                var __i: i64 = 0;\n");
            try self.emit("                while (__i < ");
            // Extract range end
            if (for_stmt.iter.* == .call) {
                const call = for_stmt.iter.*.call;
                if (call.args.len > 0) {
                    try genSyncExprInFrame(self, call.args[0], args);
                }
            }
            try self.emit(") : (__i += 1) {\n");
            // Bind loop variable
            if (for_stmt.target.* == .name) {
                try self.emit("                    const ");
                try self.emit(for_stmt.target.*.name.id);
                try self.emit(" = __i;\n");
            }
            // Generate body
            for (for_stmt.body) |body_stmt| {
                try genSyncStatementInFrame(self, body_stmt, args, mutated_vars);
            }
            try self.emit("                }\n");
            try self.emit("            }\n");
        },
        .aug_assign => |aug| {
            if (aug.target.* == .name) {
                const target_name = aug.target.*.name.id;
                try self.emit("            ");
                try self.emit(target_name);
                try self.emit(" = ");
                try self.emit(target_name);
                switch (aug.op) {
                    .Add => try self.emit(" + "),
                    .Sub => try self.emit(" - "),
                    .Mult => try self.emit(" * "),
                    else => try self.emit(" + "),
                }
                try self.emit("(");
                try genSyncExprInFrameWithLoopVar(self, aug.value.*, args, "__i");
                try self.emit(");\n");
            }
        },
        .expr_stmt => |expr| {
            // Skip docstrings
            if (expr.value.* == .constant) {
                const c = expr.value.*.constant;
                if (c.value == .string) return;
            }
            try self.emit("            _ = ");
            try genSyncExprInFrame(self, expr.value.*, args);
            try self.emit(";\n");
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
                    try self.emit("frame.");
                    try self.emit(n.id);
                    return;
                }
            }
            // Check if it's the loop variable (needs cast)
            if (std.mem.eql(u8, n.id, "i") or std.mem.eql(u8, n.id, loop_var)) {
                try self.emit("@as(i64, @intCast(");
                try self.emit(n.id);
                try self.emit("))");
                return;
            }
            // Local variable
            try self.emit(n.id);
        },
        .constant => |c| {
            switch (c.value) {
                .int => |i| {
                    var buf: [32]u8 = undefined;
                    const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
                    try self.emit(slice);
                },
                else => try self.emit("0"),
            }
        },
        .binop => |bin| {
            try self.emit("(");
            try genSyncExprInFrameWithLoopVar(self, bin.left.*, args, loop_var);
            switch (bin.op) {
                .Add => try self.emit(" + "),
                .Sub => try self.emit(" - "),
                .Mult => try self.emit(" * "),
                .Div => try self.emit(" / "),
                .Mod => try self.emit(" % "),
                else => try self.emit(" ? "),
            }
            try genSyncExprInFrameWithLoopVar(self, bin.right.*, args, loop_var);
            try self.emit(")");
        },
        .call => {
            // Delegate to genSyncExprInFrame for function calls
            try genSyncExprInFrame(self, node, args);
        },
        else => try self.emit("0"),
    }
}

fn genSyncExprInFrame(self: *NativeCodegen, node: ast.Node, args: []ast.Arg) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Check if this is a parameter (frame field)
            for (args) |arg| {
                if (std.mem.eql(u8, arg.name, n.id)) {
                    try self.emit("frame.");
                    try self.emit(n.id);
                    return;
                }
            }
            // Local variable
            try self.emit(n.id);
        },
        .constant => |c| {
            switch (c.value) {
                .int => |i| {
                    var buf: [32]u8 = undefined;
                    const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.OutOfMemory;
                    try self.emit(slice);
                },
                else => try self.emit("0"),
            }
        },
        .binop => |bin| {
            try self.emit("(");
            try genSyncExprInFrame(self, bin.left.*, args);
            switch (bin.op) {
                .Add => try self.emit(" + "),
                .Sub => try self.emit(" - "),
                .Mult => try self.emit(" * "),
                .Div => try self.emit(" / "),
                .Mod => try self.emit(" % "),
                else => try self.emit(" ? "),
            }
            try genSyncExprInFrame(self, bin.right.*, args);
            try self.emit(")");
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
                        try self.emit("hashlib.");
                        try self.emit(method);
                        try self.emit("(");
                        for (call.args, 0..) |arg_expr, idx| {
                            if (idx > 0) try self.emit(", ");
                            try genSyncExprInFrame(self, arg_expr, args);
                        }
                        try self.emit(")");
                        return;
                    }

                    // It's a method call on a local variable (h.update(), h.hexdigest())
                    // Handle specific methods that need special treatment
                    if (std.mem.eql(u8, method, "hexdigest") or std.mem.eql(u8, method, "digest")) {
                        // These return error unions - poll can't return errors, use catch
                        try self.emit("(");
                        try self.emit(obj_name);
                        try self.emit(".");
                        try self.emit(method);
                        try self.emit("(__global_allocator) catch unreachable)");
                        return;
                    }

                    // Regular method call: obj.method(args)
                    try self.emit(obj_name);
                    try self.emit(".");
                    try self.emit(method);
                    try self.emit("(");
                    for (call.args, 0..) |arg_expr, idx| {
                        if (idx > 0) try self.emit(", ");
                        try genSyncExprInFrame(self, arg_expr, args);
                    }
                    try self.emit(")");
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
                    try self.emit(".");
                    try self.emit(method);
                    try self.emit("(");
                    for (call.args, 0..) |arg_expr, idx| {
                        if (idx > 0) try self.emit(", ");
                        try genSyncExprInFrame(self, arg_expr, args);
                    }
                    try self.emit(")");
                    return;
                }
            }
            // Function call like str(), len(), etc.
            if (call.func.* == .name) {
                const func_name = call.func.*.name.id;

                if (std.mem.eql(u8, func_name, "str")) {
                    // str(x) -> std.fmt.allocPrint(__global_allocator, "{d}", .{x}) catch unreachable
                    try self.emit("(std.fmt.allocPrint(__global_allocator, \"{d}\", .{");
                    if (call.args.len > 0) {
                        try genSyncExprInFrame(self, call.args[0], args);
                    }
                    try self.emit("}) catch unreachable)");
                    return;
                }
                if (std.mem.eql(u8, func_name, "len")) {
                    // len(x) -> x.len or x.items.len
                    try self.emit("@as(i64, @intCast(");
                    if (call.args.len > 0) {
                        try genSyncExprInFrame(self, call.args[0], args);
                    }
                    try self.emit(".len))");
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
                try self.emit(func_name);
                try self.emit("(");
                for (call.args, 0..) |arg_expr, idx| {
                    if (idx > 0) try self.emit(", ");
                    try genSyncExprInFrame(self, arg_expr, args);
                }
                try self.emit(")");
                return;
            }
            // Fallback to regular codegen (shouldn't reach here)
            try self.genExpr(node);
        },
        else => try self.emit("0"),
    }
}

fn emitInt(self: *NativeCodegen, val: usize) CodegenError!void {
    var buf: [32]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return error.OutOfMemory;
    try self.emit(slice);
}
