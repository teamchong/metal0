//! List comprehension code generation - SIMD, parallel, Metal, and scalar implementations
//! Split from comprehensions.zig for maintainability

const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const function_traits = @import("analysis.function_traits");
const zig_keywords = @import("utils.zig_keywords");

// MIGRATED TO ZIGBUILDER

// Trait imports for type checking
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../analysis/traits/string_traits.zig");

const comp_conditions = @import("comp_conditions.zig");
const comp_expr_subs = @import("comp_expr_subs.zig");
const comp_utils = @import("comp_utils.zig");

/// Generate list comprehension: [x * 2 for x in range(5)]
/// Generates as imperative loop that builds ArrayList (or Metal/SIMD/parallel when possible)
///
/// Dispatch priority (highest to lowest):
/// 1. Metal GPU (>10K elements on macOS) - massive parallelism
/// 2. Parallel (>1K elements) - multi-core CPU
/// 3. SIMD (16-1023 elements) - vectorized CPU
/// 4. Scalar (small arrays) - simple loop
pub fn genListComp(self: *NativeCodegen, listcomp: ast.Node.ListComp) CodegenError!void {
    // Check for SIMD vectorization opportunity
    const simd = function_traits.analyzeListCompForSimd(listcomp);
    if (simd.vectorizable and simd.is_range and simd.range_end != null) {
        const count = (simd.range_end orelse 0) - (simd.range_start orelse 0);

        // Check for Metal GPU acceleration (large workloads on macOS)
        // Metal dispatch is worth it for >10K elements due to GPU overhead
        const metal = function_traits.analyzeListCompForMetal(listcomp);
        if (metal.suitable and count >= 10000) {
            return genMetalListComp(self, listcomp, metal, simd);
        }

        // Check for parallelization opportunity (large workloads)
        const parallel = function_traits.analyzeListCompForParallel(listcomp);
        if (parallel.parallelizable and parallel.worth_parallelizing and count >= 1024) {
            return genParallelListComp(self, listcomp, parallel, simd);
        }

        // Use SIMD for medium arrays (16-1023 elements)
        if (count >= 16) {
            return genSimdListComp(self, listcomp, simd);
        }
    }

    return genListCompImpl(self, listcomp);
}

/// Generate SIMD-vectorized list comprehension when possible
/// Pattern: [x * 2 for x in range(N)] → SIMD vector operations
fn genSimdListComp(self: *NativeCodegen, listcomp: ast.Node.ListComp, simd: function_traits.SimdInfo) CodegenError!void {
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    const gen = listcomp.generators[0];
    const loop_var = gen.target.name.id;

    // Get range bounds
    const start = simd.range_start orelse 0;
    const end = simd.range_end orelse return genListCompImpl(self, listcomp); // Fallback if dynamic
    const count = end - start;
    if (count <= 0) return genListCompImpl(self, listcomp);

    const vec_width: i64 = simd.vector_width;

    // Generate SIMD block
    try self.emit(try std.fmt.allocPrint(self.allocator, "(simd_{d}: {{\n", .{label_id}));
    self.indent();

    // Allocate result array
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __result: [{d}]i64 = undefined;\n", .{count});

    // Generate constant vector if needed
    if (simd.op != .neg and simd.op != .square) {
        // Get the constant from the expression
        const c = getConstantFromExpr(listcomp.elt.*, loop_var) orelse 0;
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __c_vec: @Vector({d}, i64) = @splat({d});\n", .{ vec_width, c });
    }

    // Main vectorized loop
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __i: usize = 0;\n", .{});
    try self.emitIndent();
    try self.output.writer(self.allocator).print("while (__i + {d} <= {d}) : (__i += {d}) {{\n", .{ vec_width, count, vec_width });
    self.indent();

    // Load input vector (for range, it's just sequential indices)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const __base: @Vector({d}, i64) = .{{ ", .{vec_width});
    var i: i64 = 0;
    while (i < vec_width) : (i += 1) {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print("{d}", .{i});
    }
    try self.emit(" };\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const __idx: @Vector({d}, i64) = __base +% @as(@Vector({d}, i64), @splat(@as(i64, @intCast(__i)) + {d}));\n", .{ vec_width, vec_width, start });

    // Apply operation
    try self.emitIndent();
    const op_str = switch (simd.op) {
        .add => "const __r = __idx +% __c_vec;\n",
        .sub => "const __r = __idx -% __c_vec;\n",
        .mul => "const __r = __idx *% __c_vec;\n",
        .neg => try std.fmt.allocPrint(self.allocator, "const __r = -%__idx;\n", .{}),
        .square => "const __r = __idx *% __idx;\n",
        .bit_and => "const __r = __idx & __c_vec;\n",
        .bit_or => "const __r = __idx | __c_vec;\n",
        .bit_xor => "const __r = __idx ^ __c_vec;\n",
        .shl => "const __r = __idx << @intCast(__c_vec);\n",
        .shr => "const __r = __idx >> @intCast(__c_vec);\n",
        else => "const __r = __idx;\n",
    };
    try self.emit(op_str);

    // Store result
    try self.emitIndent();
    try self.output.writer(self.allocator).print("inline for (0..{d}) |__j| {{\n", .{vec_width});
    self.indent();
    try self.emitIndent();
    try self.emit("__result[__i + __j] = __r[__j];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Scalar cleanup for remaining elements
    try self.emitIndent();
    try self.output.writer(self.allocator).print("while (__i < {d}) : (__i += 1) {{\n", .{count});
    self.indent();
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s}: i64 = @as(i64, @intCast(__i)) + {d};\n", .{ loop_var, start });
    try self.emitIndent();
    // Generate native i64 expression based on SIMD op type
    const c = getConstantFromExpr(listcomp.elt.*, loop_var) orelse 0;
    const scalar_expr = switch (simd.op) {
        .add => try std.fmt.allocPrint(self.allocator, "__result[__i] = {s} +% {d};\n", .{ loop_var, c }),
        .sub => try std.fmt.allocPrint(self.allocator, "__result[__i] = {s} -% {d};\n", .{ loop_var, c }),
        .mul => try std.fmt.allocPrint(self.allocator, "__result[__i] = {s} *% {d};\n", .{ loop_var, c }),
        .neg => try std.fmt.allocPrint(self.allocator, "__result[__i] = -%{s};\n", .{loop_var}),
        .square => try std.fmt.allocPrint(self.allocator, "__result[__i] = {s} *% {s};\n", .{ loop_var, loop_var }),
        .bit_and => try std.fmt.allocPrint(self.allocator, "__result[__i] = {s} & {d};\n", .{ loop_var, c }),
        .bit_or => try std.fmt.allocPrint(self.allocator, "__result[__i] = {s} | {d};\n", .{ loop_var, c }),
        .bit_xor => try std.fmt.allocPrint(self.allocator, "__result[__i] = {s} ^ {d};\n", .{ loop_var, c }),
        .shl => try std.fmt.allocPrint(self.allocator, "__result[__i] = {s} << @intCast({d});\n", .{ loop_var, c }),
        .shr => try std.fmt.allocPrint(self.allocator, "__result[__i] = {s} >> @intCast({d});\n", .{ loop_var, c }),
        else => try std.fmt.allocPrint(self.allocator, "__result[__i] = {s};\n", .{loop_var}),
    };
    try self.emit(scalar_expr);
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Convert to ArrayList for compatibility
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __list = std.ArrayListUnmanaged(i64){{}};\n", .{});
    try self.emitIndent();
    try self.output.writer(self.allocator).print("try __list.appendSlice(__global_allocator, &__result);\n", .{});
    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :simd_{d} __list;\n", .{label_id});

    self.dedent();
    try self.emitIndent();
    try self.emit("})");
}

/// Get constant value from binop expression
fn getConstantFromExpr(expr: ast.Node, loop_var: []const u8) ?i64 {
    if (expr != .binop) return null;
    const b = expr.binop;
    const left_is_var = b.left.* == .name and std.mem.eql(u8, b.left.name.id, loop_var);
    const right_is_const = b.right.* == .constant and b.right.constant.value == .int;
    const left_is_const = b.left.* == .constant and b.left.constant.value == .int;

    if (left_is_var and right_is_const) return b.right.constant.value.int;
    if (left_is_const) return b.left.constant.value.int;
    return null;
}

/// Generate parallel list comprehension using runtime.parallel
fn genParallelListComp(self: *NativeCodegen, listcomp: ast.Node.ListComp, parallel: function_traits.ParallelInfo, simd: function_traits.SimdInfo) CodegenError!void {
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    const start = simd.range_start orelse 0;
    const end = simd.range_end orelse return genListCompImpl(self, listcomp);

    // Map SimdOp to runtime.parallel.ParallelOp
    const op_name: []const u8 = switch (parallel.op) {
        .add => "add",
        .sub => "sub",
        .mul => "mul",
        .div => "div",
        .neg => "neg",
        .square => "square",
        .bit_and => "bit_and",
        .bit_or => "bit_or",
        .bit_xor => "bit_xor",
        else => return genSimdListComp(self, listcomp, simd), // Fallback to SIMD
    };

    const gen = listcomp.generators[0];
    const loop_var = gen.target.name.id;
    const constant = getConstantFromExpr(listcomp.elt.*, loop_var) orelse 0;

    // Generate parallel execution block
    try self.emit(try std.fmt.allocPrint(self.allocator, "(parallel_{d}: {{\n", .{label_id}));
    self.indent();

    // Call runtime.parallel.parallelRangeMap
    try self.emitIndent();
    try self.output.writer(self.allocator).print(
        "const __slice = try runtime.parallel.parallelRangeMap({d}, {d}, .{s}, {d}, __global_allocator);\n",
        .{ start, end, op_name, constant },
    );

    // Convert to ArrayList for compatibility
    try self.emitIndent();
    try self.emit("var __list = std.ArrayListUnmanaged(i64){};\n");
    try self.emitIndent();
    try self.emit("__list.items = __slice;\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("__list.capacity = {d};\n", .{end - start});

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :parallel_{d} __list;\n", .{label_id});

    self.dedent();
    try self.emitIndent();
    try self.emit("})");
}

/// Generate Metal GPU-accelerated list comprehension
/// Pattern: [x * 2 for x in range(1_000_000)] → runtime.metal.vectorizedListCompToArrayList()
fn genMetalListComp(
    self: *NativeCodegen,
    listcomp: ast.Node.ListComp,
    metal: function_traits.MetalInfo,
    simd: function_traits.SimdInfo,
) CodegenError!void {
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Get range bounds
    const start = simd.range_start orelse 0;
    const end = simd.range_end orelse return genListCompImpl(self, listcomp);

    // Map SimdOp to Metal VectorOp string
    const op_name: []const u8 = switch (metal.op) {
        .add => ".add",
        .sub => ".sub",
        .mul => ".mul",
        .div => ".div",
        .neg => ".neg",
        .square => ".square",
        .bit_and => ".bit_and",
        .bit_or => ".bit_or",
        .bit_xor => ".bit_xor",
        .shl => ".shl",
        .shr => ".shr",
        .mul_add => ".mul_add",
        else => return genListCompImpl(self, listcomp), // Unsupported op, fall back
    };

    const constant = metal.constant orelse 0;

    // Generate Metal dispatch block
    try self.emit(try std.fmt.allocPrint(self.allocator, "(metal_{d}: {{\n", .{label_id}));
    self.indent();

    // Emit: break :metal_N try runtime.metal.vectorizedListCompToArrayList(__global_allocator, start, end, op, constant);
    try self.emitIndent();
    try self.emit("break :");
    try self.output.writer(self.allocator).print("metal_{d} try runtime.metal.vectorizedListCompToArrayList(__global_allocator, {d}, {d}, runtime.metal.VectorOp{s}, {d});\n", .{
        label_id,
        start,
        end,
        op_name,
        constant,
    });

    self.dedent();
    try self.emitIndent();
    try self.emit("})");
}

/// Internal list comprehension implementation (scalar)
pub fn genListCompImpl(self: *NativeCodegen, listcomp: ast.Node.ListComp) CodegenError!void {
    // Generate unique ID for this comprehension to avoid variable shadowing
    const comp_id = self.output.items.len;

    // Get unique block label to avoid nested block conflicts
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Build variable substitution map for this comprehension
    var subs = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer subs.deinit();

    // Track variables added to var_renames for cleanup at the end
    var renamed_vars: std.ArrayListUnmanaged([]const u8) = .{};
    defer renamed_vars.deinit(self.allocator);

    // Check if any generator iterates over PyValue - if so, skip the entire comprehension
    for (listcomp.generators) |gen| {
        const is_range = gen.iter.* == .call and gen.iter.call.func.* == .name and
            std.mem.eql(u8, gen.iter.call.func.name.id, "range");
        if (!is_range) {
            const iter_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
            if (iter_type == .pyvalue) {
                // PyValue iteration - emit empty PyValue list directly
                try self.emit("std.ArrayListUnmanaged(runtime.PyValue){}\n");
                return;
            }
        }
    }

    // Generate: (comp_N: { ... })
    try self.emit(try std.fmt.allocPrint(self.allocator, "(comp_{d}: {{\n", .{label_id}));
    self.indent();

    // Check if element is a lambda - requires special handling for closure type
    var lambda_closure_type_name: ?[]const u8 = null;
    var lambda_capture_var_name: ?[]const u8 = null;
    var lambda_capture_field_name: ?[]const u8 = null;

    if (listcomp.elt.* == .lambda) {
        const result = try genLambdaClosurePrelude(self, listcomp, label_id, comp_id, &subs);
        lambda_closure_type_name = result.closure_type_name;
        lambda_capture_var_name = result.capture_var_name;
        lambda_capture_field_name = result.capture_field_name;
    }

    // Determine element type from the expression
    const element_type: []const u8 = determineElementType(self, listcomp, lambda_closure_type_name);

    // Generate: var __comp_result_N = std.ArrayListUnmanaged(ElementType){};
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __comp_result_{d} = std.ArrayListUnmanaged(", .{label_id});
    try self.emit(element_type);
    try self.emit("){};\n");

    // Generate nested loops for each generator
    for (listcomp.generators, 0..) |gen, gen_idx| {
        try genListCompGenerator(self, gen, gen_idx, label_id, comp_id, &subs, &renamed_vars);
    }

    // Generate: try __comp_result_N.append(__global_allocator, <elt_expr>);
    try self.emitIndent();
    try self.output.writer(self.allocator).print("try __comp_result_{d}.append(__global_allocator, ", .{label_id});

    // For lambda elements with pre-defined closure type, generate instantiation
    if (lambda_closure_type_name != null and lambda_capture_var_name != null and lambda_capture_field_name != null) {
        try self.output.writer(self.allocator).print("{s}{{ .captures = .{{ .", .{lambda_closure_type_name.?});
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), lambda_capture_field_name.?);
        try self.output.writer(self.allocator).print(" = {s} }} }}", .{lambda_capture_var_name.?});
    } else {
        try comp_expr_subs.genExprWithSubs(self, listcomp.elt.*, &subs);
    }
    try self.emit(");\n");

    // Close all if conditions and for loops
    for (listcomp.generators) |gen| {
        for (gen.ifs) |_| {
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    // Generate: break :comp_N __comp_result_N;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :comp_{d} __comp_result_{d};\n", .{ label_id, label_id });

    self.dedent();
    try self.emitIndent();
    try self.emit("})");

    // Clean up var_renames so outer scope sees original variable names
    for (renamed_vars.items) |var_name| {
        _ = self.var_renames.swapRemove(var_name);
    }
}

/// Lambda closure prelude result
const LambdaPreludeResult = struct {
    closure_type_name: ?[]const u8,
    capture_var_name: ?[]const u8,
    capture_field_name: ?[]const u8,
};

/// Generate lambda closure type definitions if needed
fn genLambdaClosurePrelude(
    self: *NativeCodegen,
    listcomp: ast.Node.ListComp,
    label_id: usize,
    comp_id: usize,
    subs: *hashmap_helper.StringHashMap([]const u8),
) CodegenError!LambdaPreludeResult {
    const lambda = listcomp.elt.lambda;
    var result = LambdaPreludeResult{
        .closure_type_name = null,
        .capture_var_name = null,
        .capture_field_name = null,
    };

    if (listcomp.generators.len == 0) return result;

    const first_gen = listcomp.generators[0];
    if (first_gen.target.* != .name) return result;

    const orig_var = first_gen.target.name.id;

    // Check if this variable is used in the lambda (either default or body)
    var is_captured = false;
    var capture_name: []const u8 = orig_var;

    // Check default params (lambda i=i: i)
    if (lambda.args.len > 0 and lambda.args[0].default != null) {
        is_captured = true;
        capture_name = lambda.args[0].name;
    }

    // Check body for reference to loop variable (lambda: i)
    if (!is_captured and lambda.body.* == .name) {
        if (std.mem.eql(u8, lambda.body.name.id, orig_var)) {
            is_captured = true;
        }
    }

    if (!is_captured) return result;

    const mangled_var = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ orig_var, comp_id });

    // Pre-add to var_renames so lambda body generation can reference it
    try subs.put(orig_var, mangled_var);
    try self.var_renames.put(orig_var, mangled_var);

    result.capture_var_name = mangled_var;
    result.capture_field_name = capture_name;

    // Generate closure type definitions
    const closure_type_name = try std.fmt.allocPrint(self.allocator, "__ClosureType_{d}", .{label_id});
    result.closure_type_name = closure_type_name;

    // Generate: const __CaptureType_N = struct { <capture_name>: i64 };
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const __CaptureType_{d} = struct {{ ", .{label_id});
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), capture_name);
    try self.emit(": i64 };\n");

    // Generate impl function wrapped in struct
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const __ClosureImpl_{d} = struct {{ fn call(__cap: __CaptureType_{d}) i64 {{ return __cap.", .{ label_id, label_id });
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), capture_name);
    try self.emit("; } };\n");

    // Generate: const __ClosureType_N = runtime.Closure0(__CaptureType_N, i64, __ClosureImpl_N.call);
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = runtime.Closure0(__CaptureType_{d}, i64, __ClosureImpl_{d}.call);\n", .{ closure_type_name, label_id, label_id });

    return result;
}

/// Determine element type for list comprehension
fn determineElementType(self: *NativeCodegen, listcomp: ast.Node.ListComp, lambda_closure_type_name: ?[]const u8) []const u8 {
    // Check if we already have a lambda closure type
    if (lambda_closure_type_name) |closure_type| {
        return closure_type;
    }

    // Only access .tuple if it's actually a tuple AST node
    if (listcomp.elt.* == .tuple) {
        const tuple = listcomp.elt.tuple;
        var type_buf = std.ArrayListUnmanaged(u8){};
        const writer = type_buf.writer(self.allocator);
        writer.writeAll("struct { ") catch {};
        for (tuple.elts, 0..) |elt, idx| {
            if (idx > 0) writer.writeAll(", ") catch {};
            writer.print("@\"{d}\": ", .{idx}) catch {};
            const tuple_elt_type = self.type_inferrer.inferExpr(elt) catch .unknown;
            const type_str: []const u8 = if (string_traits.isString(tuple_elt_type))
                "[]const u8"
            else if (type_traits.isBoolean(tuple_elt_type))
                "bool"
            else if (type_traits.isFloating(tuple_elt_type))
                "f64"
            else if (tuple_elt_type == .pyvalue)
                "runtime.PyValue"
            else
                "i64";
            writer.writeAll(type_str) catch {};
        }
        writer.writeAll(" }") catch {};
        return type_buf.items;
    } else if (listcomp.elt.* == .call) {
        const call = listcomp.elt.call;
        if (call.func.* == .name) {
            const func_name = call.func.name.id;
            if (self.async_functions.contains(func_name)) {
                return "*runtime.GreenThread";
            }
        } else if (call.func.* == .attribute) {
            const method_name = call.func.attribute.attr;
            if (comp_utils.isStringReturningMethod(method_name)) {
                return "[]u8";
            }
        }
    } else if (listcomp.elt.* == .constant) {
        const const_type = self.type_inferrer.inferExpr(listcomp.elt.*) catch .unknown;
        if (string_traits.isString(const_type)) {
            return "[]const u8";
        } else if (string_traits.isBytes(const_type)) {
            return "runtime.builtins.PyBytes";
        } else if (type_traits.isBoolean(const_type)) {
            return "bool";
        } else if (type_traits.isFloating(const_type)) {
            return "f64";
        }
    } else if (listcomp.elt.* == .fstring) {
        return "[]u8";
    } else if (listcomp.elt.* == .binop) {
        // Check if binop produces a string (e.g., "prefix" + var)
        const elt_type = self.type_inferrer.inferExpr(listcomp.elt.*) catch .unknown;
        if (string_traits.isString(elt_type)) {
            return "[]u8"; // std.mem.concat returns []u8
        } else if (type_traits.isFloating(elt_type)) {
            return "f64";
        } else if (type_traits.isBoolean(elt_type)) {
            return "bool";
        }
    } else if (listcomp.elt.* == .if_expr) {
        const if_expr = listcomp.elt.if_expr;
        if (if_expr.body.* == .constant and if_expr.orelse_value.* == .constant) {
            const body_const_type = self.type_inferrer.inferExpr(if_expr.body.*) catch .unknown;
            const orelse_const_type = self.type_inferrer.inferExpr(if_expr.orelse_value.*) catch .unknown;
            if (type_traits.isBoolean(body_const_type) and type_traits.isBoolean(orelse_const_type)) {
                return "bool";
            }
        }
        const body_type = self.type_inferrer.inferExpr(if_expr.body.*) catch .unknown;
        if (type_traits.isBoolean(body_type)) {
            return "bool";
        } else if (string_traits.isString(body_type)) {
            return "[]const u8";
        } else if (type_traits.isFloating(body_type)) {
            return "f64";
        }
    }
    return "i64";
}

/// Generate a single generator (for loop) in list comprehension
fn genListCompGenerator(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    gen_idx: usize,
    label_id: usize,
    comp_id: usize,
    subs: *hashmap_helper.StringHashMap([]const u8),
    renamed_vars: *std.ArrayListUnmanaged([]const u8),
) CodegenError!void {
    // Check if this is a range() call
    const is_range = gen.iter.* == .call and gen.iter.call.func.* == .name and
        std.mem.eql(u8, gen.iter.call.func.name.id, "range");

    if (is_range) {
        try genRangeLoop(self, gen, comp_id, subs, renamed_vars);
    } else {
        try genIterLoop(self, gen, gen_idx, label_id, comp_id, subs, renamed_vars);
    }

    // Generate if conditions for this generator
    for (gen.ifs) |if_cond| {
        try self.emitIndent();
        try self.emit("if (");
        try comp_conditions.genComprehensionCondition(self, if_cond, subs);
        try self.emit(") {\n");
        self.indent();
    }
}

/// Generate range() loop for list comprehension
fn genRangeLoop(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    comp_id: usize,
    subs: *hashmap_helper.StringHashMap([]const u8),
    renamed_vars: *std.ArrayListUnmanaged([]const u8),
) CodegenError!void {
    const genExpr = @import("../expressions.zig").genExpr;

    const orig_var_name = gen.target.name.id;
    const args = gen.iter.call.args;

    // Create mangled name and add to substitution map
    const mangled_name = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ orig_var_name, comp_id });
    try subs.put(orig_var_name, mangled_name);
    try self.var_renames.put(orig_var_name, mangled_name);
    try renamed_vars.append(self.allocator, orig_var_name);

    // Parse range arguments
    const start_expr: ?ast.Node = if (args.len >= 2) args[0] else null;
    const stop_expr: ast.Node = if (args.len >= 2) args[1] else args[0];
    const step_val: i64 = 1;

    // Generate: var __comp_<orig>_<id>: i64 = <start>;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s}: i64 = ", .{mangled_name});
    if (start_expr) |start| {
        try genExpr(self, start);
    } else {
        try self.emit("0");
    }
    try self.emit(";\n");

    // Generate: while (__comp_<orig>_<id> < <stop>) {
    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s} < ", .{mangled_name});
    try genExpr(self, stop_expr);
    try self.emit(") {\n");
    self.indent();

    // Defer increment
    try self.emitIndent();
    try self.output.writer(self.allocator).print("defer {s} += {d};\n", .{ mangled_name, step_val });
}

/// Generate iterator loop for list comprehension
fn genIterLoop(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    gen_idx: usize,
    label_id: usize,
    _: usize, // comp_id - unused
    _: *hashmap_helper.StringHashMap([]const u8), // subs - unused
    renamed_vars: *std.ArrayListUnmanaged([]const u8),
) CodegenError!void {
    const genExpr = @import("../expressions.zig").genExpr;

    // Check if source is directly iterable (Zig arrays, not ArrayLists)
    const is_direct_iterable = blk: {
        if (gen.iter.* == .constant) {
            const iter_const_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
            if (string_traits.isString(iter_const_type)) break :blk true;
        }
        // List literals become Zig array literals, which are directly iterable
        if (gen.iter.* == .list) break :blk true;
        // Tuple literals also become Zig array-like structures
        if (gen.iter.* == .tuple) break :blk true;
        if (gen.iter.* == .name) {
            const var_name = gen.iter.name.id;
            if (self.isArrayVar(var_name)) break :blk true;
            if (self.anytype_params.contains(var_name)) break :blk true;
            if (self.getVarType(var_name)) |vt| {
                if (string_traits.isString(vt)) break :blk true;
            }
        }
        break :blk false;
    };

    try self.emitIndent();
    if (is_direct_iterable) {
        try self.output.writer(self.allocator).print("const __iter_{d}_{d} = ", .{ label_id, gen_idx });
        try genExpr(self, gen.iter.*);
        try self.emit(";\n");
    } else {
        try self.output.writer(self.allocator).print("const __list_{d}_{d} = ", .{ label_id, gen_idx });
        try genExpr(self, gen.iter.*);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __iter_{d}_{d} = __list_{d}_{d}.items;\n", .{ label_id, gen_idx, label_id, gen_idx });
    }

    try self.emitIndent();
    // Check if target is a tuple
    const is_tuple_target = switch (gen.target.*) {
        .tuple => true,
        .list => true,
        else => false,
    };

    if (is_tuple_target) {
        try genTupleUnpack(self, gen, gen_idx, label_id, renamed_vars);
    } else {
        try self.output.writer(self.allocator).print("for (__iter_{d}_{d}) |", .{ label_id, gen_idx });
        const unique_id = self.nextLabelId();
        const maybe_mangled = try comp_conditions.emitForLoopTarget(self, gen.target.*, unique_id);
        try self.emit("| {\n");
        self.indent();

        // If loop target shadows an imported module, register the rename mapping
        if (maybe_mangled) |mangled_name| {
            if (gen.target.* == .name) {
                const target_name = gen.target.name.id;
                try self.var_renames.put(target_name, mangled_name);
                try renamed_vars.append(self.allocator, target_name);
            }
        }

        // Check if iterator source is a closure list
        if (gen.target.* == .name) {
            const target_name = gen.target.name.id;
            var is_closure_list = false;
            if (gen.iter.* == .name) {
                const iter_var_name = gen.iter.name.id;
                if (self.closure_list_vars.contains(iter_var_name)) {
                    is_closure_list = true;
                } else if (self.var_renames.get(iter_var_name)) |renamed| {
                    if (self.closure_list_vars.contains(renamed)) {
                        is_closure_list = true;
                    }
                }
            }
            if (!is_closure_list) {
                const iter_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
                if (iter_type == .list) {
                    const elem_type = iter_type.list.*;
                    if (elem_type == .closure or elem_type == .function) {
                        is_closure_list = true;
                    }
                }
            }
            if (is_closure_list) {
                try self.closure_vars.put(target_name, {});
            }
        }
    }
}

/// Generate tuple unpacking for list comprehension
fn genTupleUnpack(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    gen_idx: usize,
    label_id: usize,
    renamed_vars: *std.ArrayListUnmanaged([]const u8),
) CodegenError!void {
    try self.output.writer(self.allocator).print("for (__iter_{d}_{d}) |__tuple_{d}_{d}__| {{\n", .{ label_id, gen_idx, label_id, gen_idx });
    self.indent();

    // Unpack tuple elements
    const elements = switch (gen.target.*) {
        .tuple => |t| t.elts,
        .list => |l| l.elts,
        else => &[_]ast.Node{},
    };
    for (elements, 0..) |elt, idx| {
        try self.emitIndent();
        if (elt == .name) {
            const var_name = elt.name.id;
            if (std.mem.eql(u8, var_name, "_")) {
                try self.output.writer(self.allocator).print("_ = __tuple_{d}_{d}__.@\"{d}\";\n", .{ label_id, gen_idx, idx });
            } else {
                if (self.isDeclared(var_name)) {
                    const renamed = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ var_name, label_id });
                    try self.var_renames.put(var_name, renamed);
                    try renamed_vars.append(self.allocator, var_name);
                    try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ renamed, label_id, gen_idx, idx });
                } else {
                    try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ var_name, label_id, gen_idx, idx });
                }
            }
        }
    }
}
